import Foundation

/// Validates preconditions before command execution.
/// Throws when required committed-state conditions are not met.
public struct PreconditionsValidator: Sendable {
    public init() {}

    public func validate(_ command: Command, snapshot: WorldModelSnapshot) throws {
        switch command.payload {
        case .ui(let action):
            try validateUI(action, snapshot: snapshot)
        case .code(let action):
            try validateCode(action, snapshot: snapshot)
        case .shell(let spec):
            try validateShell(spec, snapshot: snapshot)
        }

        let zeroUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        guard command.metadata.intentID != zeroUUID else {
            throw PreconditionError.invalidIntentID
        }

        guard command.metadata.confidence >= 0.5 else {
            throw PreconditionError.lowConfidence(command.metadata.confidence)
        }
    }

    private func validateUI(_ action: UIAction, snapshot: WorldModelSnapshot) throws {
        let requiresActiveApplication: Set<String> = [
            "clickElement",
            "typeText",
            "focusWindow",
            "readElement",
            "click",
            "type",
            "focus",
            "read",
        ]

        if requiresActiveApplication.contains(action.name) {
            guard snapshot.activeApplication != nil else {
                throw PreconditionError.noActiveApplication
            }
        }

        if requiresActiveApplication.contains(action.name) || action.windowTitle != nil {
            guard !snapshot.modalPresent else {
                throw PreconditionError.modalPresent
            }
        }
    }

    private func validateCode(_ action: CodeAction, snapshot: WorldModelSnapshot) throws {
        let requiresRepository: Set<String> = [
            "searchRepository",
            "modifyFile",
            "runBuild",
            "runTests",
            "readFile",
            "search",
            "editFile",
            "writeFile",
        ]

        if requiresRepository.contains(action.name) {
            guard snapshot.repositoryRoot != nil else {
                throw PreconditionError.noRepositoryContext
            }
        }

        if action.name == "modifyFile" && snapshot.isGitDirty {
            throw PreconditionError.gitDirty
        }
    }

    private func validateShell(_ spec: CommandSpec, snapshot: WorldModelSnapshot) throws {
        let requiresRepository: Set<CodeCommandCategory> = [
            .build,
            .test,
            .formatter,
            .linter,
            .gitStatus,
            .gitBranch,
            .gitCommit,
            .gitPush,
        ]

        if requiresRepository.contains(spec.category) {
            guard snapshot.repositoryRoot != nil else {
                throw PreconditionError.noRepositoryContext
            }
        }
    }
}

/// Errors thrown by PreconditionsValidator
public enum PreconditionError: Error, CustomStringConvertible {
    case noActiveApplication
    case modalPresent
    case noRepositoryContext
    case gitDirty
    case invalidIntentID
    case lowConfidence(Double)

    public var description: String {
        switch self {
        case .noActiveApplication: return "No active application context"
        case .modalPresent: return "Modal dialog present - cannot execute"
        case .noRepositoryContext: return "No repository context for code command"
        case .gitDirty: return "Git working directory is dirty"
        case .invalidIntentID: return "Invalid or missing intent ID in metadata"
        case .lowConfidence(let confidence): return "Confidence \(confidence) below threshold 0.5"
        }
    }
}
