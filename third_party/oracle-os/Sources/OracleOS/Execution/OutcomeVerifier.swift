import Foundation

public struct OutcomeVerifier: Sendable {
    public init() {}

    public func verify(
        command: Command,
        snapshotBeforeExecution: WorldModelSnapshot,
        routedResult: RoutedExecutionResult,
        observedAfterExecution: PostExecutionObservation,
        policyDecision: PolicyDecision,
        preconditionsPassed: Bool
    ) -> VerifierReport {
        var notes = routedResult.evidence.notes + observedAfterExecution.notes
        var postconditionsPassed = true

        for expectation in routedResult.evidence.expectedPostconditions {
            if !matches(
                expectation,
                command: command,
                snapshotBeforeExecution: snapshotBeforeExecution,
                routedResult: routedResult,
                observedAfterExecution: observedAfterExecution,
                notes: &notes
            ) {
                postconditionsPassed = false
            }
        }

        if routedResult.status != .success && routedResult.status != .partialSuccess {
            postconditionsPassed = false
            if notes.isEmpty {
                notes.append("router returned \(routedResult.status.rawValue)")
            }
        }

        if routedResult.evidence.expectedPostconditions.isEmpty,
           routedResult.status == .success,
           !notes.contains("no_expected_postconditions")
        {
            notes.append("no_expected_postconditions")
        }

        return VerifierReport(
            commandID: command.id,
            preconditionsPassed: preconditionsPassed,
            policyDecision: policyDecision.allowed ? "approved" : "blocked",
            postconditionsPassed: postconditionsPassed,
            notes: notes
        )
    }

    private func matches(
        _ expectation: ExpectedPostcondition,
        command: Command,
        snapshotBeforeExecution: WorldModelSnapshot,
        routedResult: RoutedExecutionResult,
        observedAfterExecution: PostExecutionObservation,
        notes: inout [String]
    ) -> Bool {
        switch expectation {
        case .activeApplication(let value):
            if observedAfterExecution.activeApplication?.localizedCaseInsensitiveContains(value) == true {
                return true
            }
            notes.append("active app missing: \(value)")
            return false

        case .windowTitleContains(let value):
            if observedAfterExecution.windowTitle?.localizedCaseInsensitiveContains(value) == true {
                return true
            }
            notes.append("window title missing: \(value)")
            return false

        case .urlContains(let value):
            if observedAfterExecution.url?.localizedCaseInsensitiveContains(value) == true {
                return true
            }
            notes.append("url missing: \(value)")
            return false

        case .fileExists(let path):
            if observedAfterExecution.fileExistsByPath[path] == true {
                return true
            }
            notes.append("file missing: \(path)")
            return false

        case .fileContentsChanged(let path):
            guard observedAfterExecution.fileExistsByPath[path] == true else {
                notes.append("file missing for content check: \(path)")
                return false
            }

            if let expected = expectedFileContents(for: path, command: command, routedResult: routedResult),
               let actual = observedAfterExecution.fileContentsByPath[path]
            {
                if actual == expected {
                    return true
                }
                notes.append("file contents mismatch: \(path)")
                return false
            }

            if let actual = observedAfterExecution.fileContentsByPath[path], !actual.isEmpty {
                return true
            }

            notes.append("file content unavailable: \(path)")
            return false

        case .buildSucceeded:
            if observedAfterExecution.buildSucceeded == true {
                return true
            }
            notes.append("build did not succeed")
            return false

        case .testsCompleted:
            if observedAfterExecution.testsSucceeded == true || observedAfterExecution.failingTestCount != nil {
                return true
            }
            notes.append("tests did not produce verifiable result")
            return false
        }
    }

    private func expectedFileContents(
        for path: String,
        command: Command,
        routedResult: RoutedExecutionResult
    ) -> String? {
        if case .code(let action) = command.payload,
           let patch = action.patch,
           let resolvedPath = resolvePath(filePath: action.filePath, workspacePath: action.workspacePath)?.path,
           resolvedPath == path
        {
            return patch
        }

        if let artifact = routedResult.evidence.artifacts.first(where: { $0.identifier == path }),
           let data = artifact.data,
           let string = String(data: data, encoding: .utf8)
        {
            return string
        }

        return nil
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
