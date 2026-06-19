import Foundation
import OracleControllerShared
import OracleOS

enum HostClientError: LocalizedError {
    case hostBinaryNotFound
    case hostPipeUnavailable
    case hostExited
    case requestCancelled
    case noResponse

    var errorDescription: String? {
        switch self {
        case .hostBinaryNotFound:
            return "OracleControllerHost could not be found. Install the bundled app helper or set ORACLE_CONTROLLER_HOST_PATH for development."
        case .hostPipeUnavailable:
            return "OracleControllerHost pipes are unavailable."
        case .hostExited:
            return "OracleControllerHost stopped responding."
        case .requestCancelled:
            return "The request was cancelled before the host responded."
        case .noResponse:
            return "The host did not return an expected response."
        }
    }
}

actor HostProcessClient {
    typealias EventHandler = @MainActor @Sendable (ControllerHostEvent) -> Void

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let eventHandler: EventHandler

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var readTask: Task<Void, Never>?
    private var pendingResponses: [String: CheckedContinuation<ControllerHostResponse, any Error>] = [:]

    init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
        self.encoder = ControllerJSONCoding.makeEncoder(outputFormatting: [.sortedKeys])
        self.decoder = ControllerJSONCoding.makeDecoder()
    }

    deinit {
        readTask?.cancel()
        process?.terminate()
    }

    func send(_ request: ControllerHostRequest) async throws -> ControllerHostResponse {
        try launchIfNeeded()
        guard let stdinHandle else {
            throw HostClientError.hostPipeUnavailable
        }

        let payload = try encodedLine(for: request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingResponses[request.id] = continuation
                do {
                    try stdinHandle.write(contentsOf: payload)
                } catch {
                    pendingResponses.removeValue(forKey: request.id)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task {
                await self.cancelPending(requestID: request.id)
            }
        }
    }

    // MARK: - Coding Run Methods
    
    func listCodingRuns() async throws -> [ControllerCodingRun] {
        let request = ControllerHostRequest(command: .listCodingRuns)
        let response = try await send(request)
        return response.codingRuns ?? []
    }
    
    func loadCodingRun(id: String) async throws -> ControllerCodingRunDetail? {
        let request = ControllerHostRequest(command: .loadCodingRun, codingRunID: id)
        let response = try await send(request)
        return response.codingRunDetail
    }
    
    func startCodingRun(_ submission: ControllerCodingRunSubmission) async throws -> ControllerCodingRunDetail {
        let request = ControllerHostRequest(command: .startCodingRun, codingRunSubmission: submission)
        let response = try await send(request)
        guard let detail = response.codingRunDetail else {
            throw HostClientError.noResponse
        }
        return detail
    }
    
    func approveCodingRun(id: String, reason: String) async throws -> ControllerCodingRunDetail {
        let request = ControllerHostRequest(command: .approveCodingRun, codingRunID: id, codingRunReason: reason)
        let response = try await send(request)
        guard let detail = response.codingRunDetail else {
            throw HostClientError.noResponse
        }
        return detail
    }
    
    func rejectCodingRun(id: String, reason: String) async throws -> ControllerCodingRunDetail {
        let request = ControllerHostRequest(command: .rejectCodingRun, codingRunID: id, codingRunReason: reason)
        let response = try await send(request)
        guard let detail = response.codingRunDetail else {
            throw HostClientError.noResponse
        }
        return detail
    }

    private func encodedLine(for request: ControllerHostRequest) throws -> Data {
        var data = try encoder.encode(request)
        data.append(0x0A)
        return data
    }

    private func launchIfNeeded() throws {
        if process?.isRunning == true {
            return
        }

        let hostURL = try resolveHostURL()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        let process = Process()
        process.executableURL = hostURL
        process.currentDirectoryURL = OracleProductPaths.runningFromAppBundle
            ? OracleProductPaths.dataRootDirectory
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        self.process = process
        self.stdinHandle = inputPipe.fileHandleForWriting
        self.stdoutHandle = outputPipe.fileHandleForReading
        startReadLoop(outputPipe.fileHandleForReading)
    }

    private func resolveHostURL() throws -> URL {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["ORACLE_CONTROLLER_HOST_PATH"],
           !override.isEmpty
        {
            let url = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        if let bundledHelperURL = OracleProductPaths.bundledHelperURL,
           fileManager.isExecutableFile(atPath: bundledHelperURL.path)
        {
            return bundledHelperURL
        }

        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let currentDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let candidates = [
            executableURL.deletingLastPathComponent().appendingPathComponent("OracleControllerHost"),
            currentDirectory.appendingPathComponent(".build/debug/OracleControllerHost"),
            currentDirectory.appendingPathComponent(".build/arm64-apple-macosx/debug/OracleControllerHost"),
            currentDirectory.appendingPathComponent(".build/x86_64-apple-macosx/debug/OracleControllerHost"),
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw HostClientError.hostBinaryNotFound
    }

    private func startReadLoop(_ handle: FileHandle) {
        readTask?.cancel()
        readTask = Task {
            do {
                for try await line in handle.bytes.lines {
                    guard let data = line.data(using: .utf8), !data.isEmpty else {
                        continue
                    }
                    let envelope = try decoder.decode(ControllerHostEnvelope.self, from: data)
                    await route(envelope)
                }
                failPendingResponses(with: HostClientError.hostExited)
            } catch {
                failPendingResponses(with: error)
            }
        }
    }

    private func route(_ envelope: ControllerHostEnvelope) async {
        if let response = envelope.response,
           let continuation = pendingResponses.removeValue(forKey: response.requestID)
        {
            continuation.resume(returning: response)
            return
        }

        if let event = envelope.event {
            await MainActor.run {
                eventHandler(event)
            }
        }
    }

    private func cancelPending(requestID: String) {
        guard let continuation = pendingResponses.removeValue(forKey: requestID) else {
            return
        }
        continuation.resume(throwing: HostClientError.requestCancelled)
    }

    private func failPendingResponses(with error: any Error) {
        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}
