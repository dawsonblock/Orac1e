import Foundation

public struct OracleCodingRuntimeConfiguration: Sendable {
    public let workspaceRoot: URL
    public let retrievalBaseURL: URL
    public let workerEndpoints: CodingWorkerEndpoints
    public let toolsRootURL: URL?
    public let runServerBaseURL: URL
    public let repoRoot: URL?

    public init(
        workspaceRoot: URL,
        retrievalBaseURL: URL,
        workerEndpoints: CodingWorkerEndpoints,
        toolsRootURL: URL? = nil,
        runServerBaseURL: URL,
        repoRoot: URL? = nil
    ) {
        self.workspaceRoot = workspaceRoot
        self.retrievalBaseURL = retrievalBaseURL
        self.workerEndpoints = workerEndpoints
        self.toolsRootURL = toolsRootURL
        self.runServerBaseURL = runServerBaseURL
        self.repoRoot = repoRoot
    }

    public static func fromEnvironment() -> OracleCodingRuntimeConfiguration {
        let env = ProcessInfo.processInfo.environment
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let repoRoot = resolveRepoRoot(environment: env, currentDirectory: currentDirectory)
        let workspaceRoot = resolveWorkspaceRoot(environment: env, currentDirectory: currentDirectory, repoRoot: repoRoot)
        let retrievalBaseURL = URL(string: env["ORACLE_CODING_RETRIEVAL_URL"] ?? "http://127.0.0.1:8787")
            ?? URL(string: "http://127.0.0.1:8787")!
        let aiderURL = URL(string: env["ORACLE_CODING_AIDER_URL"] ?? "http://127.0.0.1:8788")
            ?? URL(string: "http://127.0.0.1:8788")!
        let hardenedURL = URL(string: env["ORACLE_CODING_HARDENED_URL"] ?? "http://127.0.0.1:8789")
            ?? URL(string: "http://127.0.0.1:8789")!
        let runServerBaseURL = URL(string: env["ORACLE_CODING_RUN_SERVER_URL"] ?? "http://127.0.0.1:8790")
            ?? URL(string: "http://127.0.0.1:8790")!
        return OracleCodingRuntimeConfiguration(
            workspaceRoot: workspaceRoot,
            retrievalBaseURL: retrievalBaseURL,
            workerEndpoints: CodingWorkerEndpoints(aider: aiderURL, hardened: hardenedURL),
            toolsRootURL: CodingToolBootstrap.resolveToolsRoot(environment: env, currentDirectory: currentDirectory),
            runServerBaseURL: runServerBaseURL,
            repoRoot: repoRoot
        )
    }

    private static func resolveRepoRoot(environment: [String: String], currentDirectory: URL) -> URL? {
        if let explicit = environment["ORACLE_CODING_REPO_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }

        let fileManager = FileManager.default
        var cursor = currentDirectory.standardizedFileURL
        for _ in 0..<8 {
            let scriptPath = cursor.appendingPathComponent("scripts/coding_run_promotion.py", isDirectory: false)
            if fileManager.fileExists(atPath: scriptPath.path) {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        return nil
    }

    private static func resolveWorkspaceRoot(environment: [String: String], currentDirectory: URL, repoRoot: URL?) -> URL {
        if let explicit = environment["ORACLE_CODING_WORKSPACE_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return URL(fileURLWithPath: explicit, isDirectory: true)
        }
        if let repoRoot {
            return repoRoot.appendingPathComponent("workspace", isDirectory: true)
        }

        let fileManager = FileManager.default
        var cursor = currentDirectory.standardizedFileURL
        for _ in 0..<8 {
            let candidate = cursor.appendingPathComponent("workspace", isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            cursor.deleteLastPathComponent()
        }
        return currentDirectory.appendingPathComponent("workspace", isDirectory: true)
    }
}

public struct OracleCodingRunSubmission: Sendable {
    public let repoPath: String
    public let task: String
    public let mode: CodingRunMode
    public let retrievalQuery: String
    public let allowedPaths: [String]
    public let validationCommands: [String]
    public let preferredRetrievalToolID: String?
    public let preferredWorkerToolID: String?

    public init(
        repoPath: String,
        task: String,
        mode: CodingRunMode = .interactive,
        retrievalQuery: String? = nil,
        allowedPaths: [String] = [""],
        validationCommands: [String] = [],
        preferredRetrievalToolID: String? = nil,
        preferredWorkerToolID: String? = nil
    ) {
        self.repoPath = repoPath
        self.task = task
        self.mode = mode
        self.retrievalQuery = retrievalQuery ?? task
        self.allowedPaths = allowedPaths.isEmpty ? [""] : allowedPaths
        self.validationCommands = validationCommands
        self.preferredRetrievalToolID = preferredRetrievalToolID
        self.preferredWorkerToolID = preferredWorkerToolID
    }
}

public struct OracleCodingRunSummary: Sendable {
    public let record: CodingRunRecord
    public let approvalRequired: Bool
    public let pendingApprovalReasons: [String]

    public init(record: CodingRunRecord, approvalRequired: Bool, pendingApprovalReasons: [String]) {
        self.record = record
        self.approvalRequired = approvalRequired
        self.pendingApprovalReasons = pendingApprovalReasons
    }
}

public struct OracleCodingPendingProposal: Sendable {
    public let worker: String
    public let summary: String
    public let diff: String
    public let touchedPaths: [String]
    public let changedLines: Int
    public let warnings: [String]
    public let commandsRequested: [String]
    public let approvalReasons: [String]

    public init(
        worker: String,
        summary: String,
        diff: String,
        touchedPaths: [String],
        changedLines: Int,
        warnings: [String],
        commandsRequested: [String],
        approvalReasons: [String]
    ) {
        self.worker = worker
        self.summary = summary
        self.diff = diff
        self.touchedPaths = touchedPaths
        self.changedLines = changedLines
        self.warnings = warnings
        self.commandsRequested = commandsRequested
        self.approvalReasons = approvalReasons
    }
}

public struct OracleCodingRunEvent: Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let type: String
    public let timestamp: Date
    public let payload: [String: String]

    public init(id: String, runID: String, type: String, timestamp: Date, payload: [String: String]) {
        self.id = id
        self.runID = runID
        self.type = type
        self.timestamp = timestamp
        self.payload = payload
    }
}

public struct OracleCodingApprovalDecision: Sendable, Identifiable {
    public let id: String
    public let runID: String
    public let approved: Bool
    public let reason: String?
    public let actor: String?
    public let timestamp: Date

    public init(id: String, runID: String, approved: Bool, reason: String?, actor: String?, timestamp: Date) {
        self.id = id
        self.runID = runID
        self.approved = approved
        self.reason = reason
        self.actor = actor
        self.timestamp = timestamp
    }
}

public struct OracleCodingRunDetail: Sendable {
    public let summary: OracleCodingRunSummary
    public let pendingProposal: OracleCodingPendingProposal?
    public let events: [OracleCodingRunEvent]
    public let approvals: [OracleCodingApprovalDecision]
    public let artifactPaths: [String]

    public init(
        summary: OracleCodingRunSummary,
        pendingProposal: OracleCodingPendingProposal?,
        events: [OracleCodingRunEvent],
        approvals: [OracleCodingApprovalDecision],
        artifactPaths: [String]
    ) {
        self.summary = summary
        self.pendingProposal = pendingProposal
        self.events = events
        self.approvals = approvals
        self.artifactPaths = artifactPaths
    }
}

public actor OracleCodingRuntime {
    private let config: OracleCodingRuntimeConfiguration
    private let service: IntegratedCodingRunService
    private let decoder = JSONDecoder()

    public init(
        config: OracleCodingRuntimeConfiguration = .fromEnvironment(),
        service: IntegratedCodingRunService = IntegratedCodingRunService()
    ) {
        self.config = config
        self.service = service
        decoder.dateDecodingStrategy = .iso8601
    }

    public func start(_ submission: OracleCodingRunSubmission) async throws -> OracleCodingRunDetail {
        try FileManager.default.createDirectory(at: config.workspaceRoot, withIntermediateDirectories: true, attributes: nil)
        let repoURL = URL(fileURLWithPath: NSString(string: submission.repoPath).expandingTildeInPath, isDirectory: true)
        let request = IntegratedCodingRunRequest(
            repoName: repoURL.lastPathComponent,
            repoURL: repoURL,
            task: submission.task,
            mode: submission.mode,
            retrievalQuery: submission.retrievalQuery,
            retrievalBaseURL: config.retrievalBaseURL,
            workerEndpoints: config.workerEndpoints,
            workspaceRoot: config.workspaceRoot,
            allowedPaths: submission.allowedPaths,
            validationCommands: submission.validationCommands,
            validationConfigRootURL: config.repoRoot,
            toolsRootURL: config.toolsRootURL,
            preferredRetrievalToolID: submission.preferredRetrievalToolID,
            preferredWorkerToolID: submission.preferredWorkerToolID
        )
        let outcome = try await service.execute(request)
        return try loadRun(id: outcome.record.id) ?? OracleCodingRunDetail(
            summary: OracleCodingRunSummary(
                record: outcome.record,
                approvalRequired: outcome.record.status == .awaitingApproval,
                pendingApprovalReasons: outcome.record.status == .awaitingApproval ? ["Awaiting operator approval"] : []
            ),
            pendingProposal: nil,
            events: [],
            approvals: [],
            artifactPaths: []
        )
    }

    @discardableResult
    public func approve(runID: String, reason: String? = nil) async throws -> OracleCodingRunDetail? {
        guard try loadRun(id: runID) != nil else {
            return nil
        }
        try await postDecision(runID: runID, endpoint: "approve", reason: reason)
        return try loadRun(id: runID)
    }

    @discardableResult
    public func reject(runID: String, reason: String? = nil) async throws -> OracleCodingRunDetail? {
        guard try loadRun(id: runID) != nil else {
            return nil
        }
        try await postDecision(runID: runID, endpoint: "reject", reason: reason)
        return try loadRun(id: runID)
    }

    public func listRuns() throws -> [OracleCodingRunSummary] {
        try loadRecords()
            .sorted { $0.createdAt > $1.createdAt }
            .map { record in
                OracleCodingRunSummary(
                    record: record,
                    approvalRequired: record.status == .awaitingApproval,
                    pendingApprovalReasons: record.status == .awaitingApproval ? ["Awaiting operator approval"] : []
                )
            }
    }

    public func loadRun(id: String) throws -> OracleCodingRunDetail? {
        guard let record = try loadRecords().first(where: { $0.id == id }) else {
            return nil
        }
        let summary = OracleCodingRunSummary(
            record: record,
            approvalRequired: record.status == .awaitingApproval,
            pendingApprovalReasons: record.status == .awaitingApproval ? ["Awaiting operator approval"] : []
        )
        let events = try loadEvents(runID: id)
        let approvals = try loadApprovals(runID: id)
        let metadata = try loadMetadata(runID: id)
        let pendingProposal = try loadPendingProposal(for: record, metadata: metadata)
        let artifactPaths = artifactPathsForRun(id: id)
        return OracleCodingRunDetail(
            summary: summary,
            pendingProposal: pendingProposal,
            events: events,
            approvals: approvals,
            artifactPaths: artifactPaths
        )
    }

    private func loadRecords() throws -> [CodingRunRecord] {
        let fileURL = runsRoot().appendingPathComponent("runs.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([CodingRunRecord].self, from: Data(contentsOf: fileURL))
    }

    private func loadMetadata(runID: String) throws -> CodingRunMetadata? {
        let fileURL = runsRoot()
            .appendingPathComponent("metadata", isDirectory: true)
            .appendingPathComponent("\(runID).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try decoder.decode(CodingRunMetadata.self, from: Data(contentsOf: fileURL))
    }

    private func loadEvents(runID: String) throws -> [OracleCodingRunEvent] {
        let fileURL = runsRoot().appendingPathComponent("events.jsonl")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try readJSONLines(fileURL)
            .compactMap { item in
                let normalizedRunID = string(item["runID"]) ?? string(item["run_id"])
                guard normalizedRunID == runID else { return nil }
                let id = string(item["id"]) ?? UUID().uuidString
                let type = string(item["type"]) ?? "unknown"
                let timestamp = parseDate(item["ts"]) ?? parseDate(item["timestamp"]) ?? Date.distantPast
                let payloadAny = item["payload"] as? [String: Any] ?? [:]
                let payload = payloadAny.reduce(into: [String: String]()) { result, pair in
                    result[pair.key] = stringify(pair.value)
                }
                return OracleCodingRunEvent(id: id, runID: runID, type: type, timestamp: timestamp, payload: payload)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func loadApprovals(runID: String) throws -> [OracleCodingApprovalDecision] {
        let fileURL = runsRoot().appendingPathComponent("approvals.jsonl")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try readJSONLines(fileURL)
            .compactMap { item in
                let normalizedRunID = string(item["runID"]) ?? string(item["run_id"])
                guard normalizedRunID == runID else { return nil }
                let id = string(item["id"]) ?? "\(runID):approval:\(UUID().uuidString)"
                let approved: Bool
                if let direct = item["approved"] as? Bool {
                    approved = direct
                } else if let decision = string(item["decision"]) {
                    approved = decision == "approved"
                } else {
                    approved = false
                }
                let reason = string(item["reason"]) ?? string(item["note"])
                let actor = string(item["actor"])
                let timestamp = parseDate(item["at"]) ?? parseDate(item["timestamp"]) ?? Date.distantPast
                return OracleCodingApprovalDecision(
                    id: id,
                    runID: runID,
                    approved: approved,
                    reason: reason,
                    actor: actor,
                    timestamp: timestamp
                )
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func loadPendingProposal(for record: CodingRunRecord, metadata: CodingRunMetadata?) throws -> OracleCodingPendingProposal? {
        guard record.status == .awaitingApproval else { return nil }
        guard let worktreePath = metadata?.worktreePath else { return nil }
        let worktreeURL = URL(fileURLWithPath: worktreePath, isDirectory: true)
        guard FileManager.default.fileExists(atPath: worktreeURL.path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", worktreeURL.path, "diff", "--binary"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let diffData = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let diff = String(data: diffData, encoding: .utf8), !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return OracleCodingPendingProposal(
            worker: "pending-patch",
            summary: "Patch staged in disposable worktree",
            diff: diff,
            touchedPaths: parseTouchedPaths(diffText: diff),
            changedLines: parseChangedLines(diffText: diff),
            warnings: [],
            commandsRequested: [],
            approvalReasons: ["Awaiting operator approval"]
        )
    }

    private func artifactPathsForRun(id: String) -> [String] {
        let fileManager = FileManager.default
        let runs = runsRoot()
        let candidates = [
            runs.appendingPathComponent("approvals", isDirectory: true).appendingPathComponent("\(id).json"),
            runs.appendingPathComponent("promotions", isDirectory: true).appendingPathComponent("\(id).json"),
            runs.appendingPathComponent("validation", isDirectory: true).appendingPathComponent("\(id).worktree.json"),
            runs.appendingPathComponent("validation", isDirectory: true).appendingPathComponent("\(id).canonical.json"),
            runs.appendingPathComponent("artifacts", isDirectory: true).appendingPathComponent("\(id).patch")
        ]
        return candidates.filter { fileManager.fileExists(atPath: $0.path) }.map(\.path)
    }

    private func runsRoot() -> URL {
        config.workspaceRoot.appendingPathComponent("runs", isDirectory: true)
    }

    private func postDecision(runID: String, endpoint: String, reason: String?) async throws {
        let success = try await tryRunServerDecision(runID: runID, endpoint: endpoint, reason: reason)
        guard success else {
            throw NSError(
                domain: "OracleCodingRuntime",
                code: 42,
                userInfo: [NSLocalizedDescriptionKey: "Run server unavailable; approval actions are disabled"]
            )
        }
    }

    private func tryRunServerDecision(runID: String, endpoint: String, reason: String?) async throws -> Bool {
        var request = URLRequest(url: config.runServerBaseURL.appendingPathComponent("runs/\(runID)/\(endpoint)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        let body = ["actor": "oracle-cli", "note": reason ?? ""]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            switch http.statusCode {
            case 200 ..< 300:
                return true
            case 404:
                return false
            default:
                throw NSError(
                    domain: "OracleCodingRuntime",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Run server decision failed with status \(http.statusCode)"]
                )
            }
        } catch {
            return false
        }
    }

    private func runLocalPromotionScript(runID: String, reject: Bool, reason: String?) throws {
        guard let repoRoot = config.repoRoot else {
            throw NSError(
                domain: "OracleCodingRuntime",
                code: 40,
                userInfo: [NSLocalizedDescriptionKey: "Run server unavailable and repo root could not be resolved for local promotion fallback"]
            )
        }

        let scriptURL = repoRoot.appendingPathComponent("scripts/coding_run_promotion.py", isDirectory: false)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw NSError(
                domain: "OracleCodingRuntime",
                code: 41,
                userInfo: [NSLocalizedDescriptionKey: "Promotion script missing at \(scriptURL.path)"]
            )
        }

        let process = Process()
        process.currentDirectoryURL = repoRoot
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var arguments = ["python3", scriptURL.path, runID, "--actor", "oracle-cli"]
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--note", reason])
        }
        if reject {
            arguments.append("--reject")
        }
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "OracleCodingRuntime",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: stderrText.isEmpty ? stdoutText : stderrText]
            )
        }
    }

    private func readJSONLines(_ fileURL: URL) throws -> [[String: Any]] {
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        return try contents
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { line in
                let data = Data(line.utf8)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw NSError(
                        domain: "OracleCodingRuntime",
                        code: 50,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid JSONL item in \(fileURL.lastPathComponent)"]
                    )
                }
                return object
            }
    }

    private func parseTouchedPaths(diffText: String) -> [String] {
        let lines = diffText.split(separator: "\n", omittingEmptySubsequences: false)
        var paths: [String] = []
        for line in lines {
            if line.hasPrefix("+++ b/") {
                let path = String(line.dropFirst(6))
                if path != "/dev/null" {
                    paths.append(path)
                }
            }
        }
        return Array(Set(paths)).sorted()
    }

    private func parseChangedLines(diffText: String) -> Int {
        diffText.split(separator: "\n", omittingEmptySubsequences: false).reduce(into: 0) { count, line in
            guard let first = line.first else { return }
            if first == "+" || first == "-" {
                if !line.hasPrefix("+++") && !line.hasPrefix("---") {
                    count += 1
                }
            }
        }
    }

    private func stringify(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let array = value as? [Any] { return array.map(stringify).joined(separator: ",") }
        if let dictionary = value as? [String: Any] {
            return dictionary.map { "\($0.key)=\(stringify($0.value))" }.sorted().joined(separator: ",")
        }
        return String(describing: value)
    }

    private func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func parseDate(_ value: Any?) -> Date? {
        guard let string = string(value) else { return nil }
        return Self.iso8601WithFractionalSeconds.date(from: string) ?? Self.iso8601.date(from: string)
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
