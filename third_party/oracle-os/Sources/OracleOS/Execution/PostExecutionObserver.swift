import Foundation

public struct PostExecutionObservation: Sendable {
    public let activeApplication: String?
    public let windowTitle: String?
    public let url: String?
    public let fileExistsByPath: [String: Bool]
    public let fileContentsByPath: [String: String]
    public let buildSucceeded: Bool?
    public let testsSucceeded: Bool?
    public let failingTestCount: Int?
    public let notes: [String]

    public init(
        activeApplication: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        fileExistsByPath: [String: Bool] = [:],
        fileContentsByPath: [String: String] = [:],
        buildSucceeded: Bool? = nil,
        testsSucceeded: Bool? = nil,
        failingTestCount: Int? = nil,
        notes: [String] = []
    ) {
        self.activeApplication = activeApplication
        self.windowTitle = windowTitle
        self.url = url
        self.fileExistsByPath = fileExistsByPath
        self.fileContentsByPath = fileContentsByPath
        self.buildSucceeded = buildSucceeded
        self.testsSucceeded = testsSucceeded
        self.failingTestCount = failingTestCount
        self.notes = notes
    }
}

public struct PostExecutionObserver: @unchecked Sendable {
    private let automationHost: AutomationHost?

    public init(automationHost: AutomationHost? = nil) {
        self.automationHost = automationHost
    }

    public func observe(
        command: Command,
        evidence: ExecutionEvidence,
        snapshotBeforeExecution: WorldModelSnapshot
    ) async -> PostExecutionObservation {
        var activeApplication: String?
        var windowTitle: String?
        var url: String?
        var fileExistsByPath: [String: Bool] = [:]
        var fileContentsByPath: [String: String] = [:]
        var buildSucceeded: Bool?
        var testsSucceeded: Bool?
        var failingTestCount: Int?
        var notes: [String] = []

        switch command.payload {
        case .ui(let action):
            let observed = await MainActor.run { ObservationBuilder.capture(appName: action.app) }
            activeApplication = observed.app
            windowTitle = observed.windowTitle
            url = observed.url
            notes.append("ui_readback")

        case .code(let action):
            for path in candidatePaths(for: command, evidence: evidence) {
                let exists = FileManager.default.fileExists(atPath: path)
                fileExistsByPath[path] = exists
                if exists,
                   let data = FileManager.default.contents(atPath: path),
                   let text = String(data: data, encoding: .utf8)
                {
                    fileContentsByPath[path] = text
                }
            }
            notes.append("code_readback")

        case .shell:
            break
        }

        for event in evidence.events {
            switch event.eventType {
            case EventKinds.buildCompleted:
                let payload = EventPayloadDecoder.decode(BuildCompletedPayload.self, from: event)
                buildSucceeded = payload?.succeeded
            case EventKinds.testsCompleted:
                let payload = EventPayloadDecoder.decode(TestsCompletedPayload.self, from: event)
                testsSucceeded = payload?.succeeded
                failingTestCount = payload?.failingTestCount
            default:
                break
            }
        }

        if activeApplication == nil { activeApplication = snapshotBeforeExecution.activeApplication }
        if windowTitle == nil { windowTitle = snapshotBeforeExecution.windowTitle }
        if url == nil { url = snapshotBeforeExecution.url }

        return PostExecutionObservation(
            activeApplication: activeApplication,
            windowTitle: windowTitle,
            url: url,
            fileExistsByPath: fileExistsByPath,
            fileContentsByPath: fileContentsByPath,
            buildSucceeded: buildSucceeded,
            testsSucceeded: testsSucceeded,
            failingTestCount: failingTestCount,
            notes: notes
        )
    }

    private func candidatePaths(for command: Command, evidence: ExecutionEvidence) -> [String] {
        var paths: [String] = []

        for postcondition in evidence.expectedPostconditions {
            switch postcondition {
            case .fileExists(let path), .fileContentsChanged(let path):
                paths.append(path)
            default:
                break
            }
        }

        if case .code(let action) = command.payload,
           let path = resolvePath(filePath: action.filePath, workspacePath: action.workspacePath)?.path
        {
            paths.append(path)
        }

        return Array(Set(paths)).sorted()
    }

    private func resolvePath(filePath: String?, workspacePath: String?) -> URL? {
        guard let filePath, !filePath.isEmpty else { return nil }
        guard let workspacePath, !filePath.hasPrefix("/") else {
            return URL(fileURLWithPath: filePath)
        }

        return URL(fileURLWithPath: workspacePath, isDirectory: true)
            .appendingPathComponent(filePath)
            .standardizedFileURL
    }
}
