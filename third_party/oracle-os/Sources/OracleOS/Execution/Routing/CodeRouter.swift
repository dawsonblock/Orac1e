import Foundation

public struct CodeRouter: @unchecked Sendable {
    private let workspaceRunner: WorkspaceRunner?
    private let repositoryIndexer: RepositoryIndexer

    /// Truncate potentially large outputs before embedding them in observations
    private func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<endIndex]) + "\n...[truncated]"
    }

    init(
        workspaceRunner: WorkspaceRunner?,
        repositoryIndexer: RepositoryIndexer
    ) {
        self.workspaceRunner = workspaceRunner
        self.repositoryIndexer = repositoryIndexer
    }

    public func execute(
        _ command: Command,
        policyDecision: PolicyDecision
    ) async throws -> RoutedExecutionResult {
        guard command.type == .code else {
            throw RouterError.invalidRoute(expected: .code, actual: command.type)
        }

        switch command.payload {
        case .shell(let spec):
            guard let workspaceRunner else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Workspace runner unavailable",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

            let result = try workspaceRunner.execute(spec: spec)
            let maxLogLength = 2000
            let truncatedStdout = truncated(result.stdout, limit: maxLogLength)
            let truncatedStderr = truncated(result.stderr, limit: maxLogLength)
            let observations = [
                ObservationPayload(
                    kind: "code.shell",
                    content: "\(result.summary)\nstdout:\n\(truncatedStdout)\nstderr:\n\(truncatedStderr)"
                ),
            ]
            if result.succeeded {
                return CommandRouter.successOutcome(
                    command: command,
                    observations: observations,
                    artifacts: [],
                    policyDecision: policyDecision,
                    router: "code",
                    emittedEvents: successEvents(for: command, spec: spec, result: result),
                    expectedPostconditions: expectedPostconditions(for: spec, result: result)
                )
            }

            let failureOutput = result.stderr.isEmpty ? result.stdout : result.stderr
            let truncatedFailureOutput = truncated(failureOutput, limit: maxLogLength)
            return CommandRouter.failureOutcome(
                command: command,
                reason: truncatedFailureOutput,
                policyDecision: policyDecision,
                router: "code",
                emittedEvents: successEvents(for: command, spec: spec, result: result)
            )

        case .code(let action):
            return try executeCodeAction(
                action,
                command: command,
                policyDecision: policyDecision
            )

        case .ui:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Invalid code payload",
                policyDecision: policyDecision,
                router: "code"
            )
        }
    }

    private func executeCodeAction(
        _ action: CodeAction,
        command: Command,
        policyDecision: PolicyDecision
    ) throws -> ExecutionOutcome {
        switch action.name {
        case "searchRepository":
            let workspaceRoot = action.workspacePath ?? FileManager.default.currentDirectoryPath
            let snapshot = repositoryIndexer.indexIfNeeded(
                workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
            )
            let matches = CodeSearch().search(query: action.query ?? "", in: snapshot)
            let content = matches
                .prefix(10)
                .map { "\($0.path) (\(String(format: "%.2f", $0.score)))" }
                .joined(separator: "\n")
            return CommandRouter.successOutcome(
                command: command,
                observations: [
                    ObservationPayload(
                        kind: "searchResult",
                        content: content.isEmpty ? "no matches" : content
                    ),
                ],
                artifacts: [],
                policyDecision: policyDecision,
                router: "code",
                emittedEvents: [
                    repositoryObservedEvent(command: command, snapshot: snapshot),
                ],
                expectedPostconditions: []
            )

        case "readFile":
            guard let resolvedPath = try resolvePath(filePath: action.filePath, workspacePath: action.workspacePath),
                  let data = FileManager.default.contents(atPath: resolvedPath.path),
                  let text = String(data: data, encoding: .utf8)
            else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Unable to read \(action.filePath ?? "file")",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }

            var emittedEvents = [
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.fileRead,
                    payload: FileReadPayload(path: resolvedPath.path)
                ),
            ]
            if let snapshot = repositorySnapshot(forWorkspacePath: action.workspacePath) {
                emittedEvents.insert(repositoryObservedEvent(command: command, snapshot: snapshot), at: 0)
            }

            return CommandRouter.successOutcome(
                command: command,
                observations: [ObservationPayload(kind: "fileContent", content: text)],
                artifacts: [ArtifactPayload(kind: "file", identifier: resolvedPath.path, data: data)],
                policyDecision: policyDecision,
                router: "code",
                emittedEvents: emittedEvents,
                expectedPostconditions: [.fileExists(resolvedPath.path)]
            )

        case "modifyFile":
            guard let resolvedPath = try resolvePath(filePath: action.filePath, workspacePath: action.workspacePath) else {
                return CommandRouter.failureOutcome(
                    command: command,
                    reason: "Unable to resolve \(action.filePath ?? "file")",
                    policyDecision: policyDecision,
                    router: "code"
                )
            }
            let existing = FileManager.default.contents(atPath: resolvedPath.path)
                .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let newContent = action.patch ?? existing
            try newContent.write(to: resolvedPath, atomically: true, encoding: .utf8)

            var emittedEvents = [
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.fileModified,
                    payload: FileModifiedPayload(path: resolvedPath.path, bytesWritten: newContent.lengthOfBytes(using: .utf8))
                ),
            ]
            if let snapshot = repositorySnapshot(forWorkspacePath: action.workspacePath) {
                emittedEvents.insert(repositoryObservedEvent(command: command, snapshot: snapshot), at: 0)
            }

            return CommandRouter.successOutcome(
                command: command,
                observations: [
                    ObservationPayload(
                        kind: "fileModified",
                        content: "modified \(resolvedPath.path): \(existing.count)->\(newContent.count) chars"
                    ),
                ],
                artifacts: [ArtifactPayload(kind: "patch", identifier: resolvedPath.path, data: newContent.data(using: .utf8))],
                policyDecision: policyDecision,
                router: "code",
                emittedEvents: emittedEvents,
                expectedPostconditions: [.fileExists(resolvedPath.path), .fileContentsChanged(resolvedPath.path)]
            )

        default:
            return CommandRouter.failureOutcome(
                command: command,
                reason: "Unsupported code action: \(action.name)",
                policyDecision: policyDecision,
                router: "code"
            )
        }
    }

    private func successEvents(
        for command: Command,
        spec: CommandSpec,
        result: CommandResult
    ) -> [EventEnvelope] {
        var events = [repositoryObservedEvent(command: command, workspaceRoot: spec.workspaceRoot)]

        switch spec.category {
        case .build:
            events.append(
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.buildCompleted,
                    payload: BuildCompletedPayload(succeeded: result.succeeded)
                )
            )
        case .test:
            events.append(
                CommandRouter.makeEvent(
                    command: command,
                    eventType: EventKinds.testsCompleted,
                    payload: TestsCompletedPayload(
                        succeeded: result.succeeded,
                        failingTestCount: parseFailingTestCount(from: result.stdout + "\n" + result.stderr)
                    )
                )
            )
        default:
            break
        }

        return events
    }

    private func expectedPostconditions(for spec: CommandSpec, result: CommandResult) -> [ExpectedPostcondition] {
        switch spec.category {
        case .build:
            return [.buildSucceeded]
        case .test:
            return [.testsCompleted]
        default:
            return []
        }
    }

    private func parseFailingTestCount(from text: String) -> Int? {
        let patterns = [
            #"(\d+)\s+failures?"#,
            #"(\d+)\s+tests?,\s+(\d+)\s+failures?"#,
            #"failed\s*:\s*(\d+)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range) else {
                continue
            }

            let captureIndex = match.numberOfRanges > 2 ? 2 : 1
            let captureRange = match.range(at: captureIndex)
            guard let stringRange = Range(captureRange, in: text) else {
                continue
            }
            return Int(text[stringRange])
        }

        return resultSucceededMarker(in: text) ? 0 : nil
    }

    private func resultSucceededMarker(in text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("0 failures") || lowered.contains("0 failed") || lowered.contains("passed")
    }

    private func repositorySnapshot(forWorkspacePath workspacePath: String?) -> RepositorySnapshot? {
        guard let workspacePath, !workspacePath.isEmpty else { return nil }
        return repositoryIndexer.indexIfNeeded(
            workspaceRoot: URL(fileURLWithPath: workspacePath, isDirectory: true)
        )
    }

    private func repositoryObservedEvent(command: Command, workspaceRoot: String) -> EventEnvelope {
        let snapshot = repositoryIndexer.indexIfNeeded(
            workspaceRoot: URL(fileURLWithPath: workspaceRoot, isDirectory: true)
        )
        return repositoryObservedEvent(command: command, snapshot: snapshot)
    }

    private func repositoryObservedEvent(command: Command, snapshot: RepositorySnapshot) -> EventEnvelope {
        CommandRouter.makeEvent(
            command: command,
            eventType: EventKinds.repositoryObserved,
            payload: RepositoryObservedPayload(
                repositoryRoot: snapshot.workspaceRoot,
                activeBranch: snapshot.activeBranch,
                isGitDirty: snapshot.isGitDirty,
                openFileCount: snapshot.files.filter { !$0.isDirectory }.count
            )
        )
    }

    private func resolvePath(filePath: String?, workspacePath: String?) throws -> URL? {
        guard let filePath, !filePath.isEmpty else { return nil }
        guard let workspacePath, !filePath.hasPrefix("/") else {
            return URL(fileURLWithPath: filePath)
        }

        let scope = try WorkspaceScope(rootURL: URL(fileURLWithPath: workspacePath, isDirectory: true))
        return try scope.resolve(relativePath: filePath)
    }
}
