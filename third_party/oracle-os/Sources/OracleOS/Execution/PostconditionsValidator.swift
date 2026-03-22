import Foundation

/// Validates final outcome consistency after command execution.
/// This validator does not determine whether an action succeeded in the world;
/// OutcomeVerifier owns that decision. This layer only checks that the final
/// report and status agree with each other.
public struct PostconditionsValidator: Sendable {
    public init() {}

    public func validate(_ command: Command, outcome: ExecutionOutcome) throws -> Bool {
        guard outcome.verifierReport.commandID == command.id else {
            throw PostconditionError.commandIDMismatch
        }

        switch outcome.status {
        case .failed:
            throw PostconditionError.executionFailed

        case .preconditionFailed:
            guard outcome.verifierReport.preconditionsPassed == false else {
                throw PostconditionError.preconditionsNotVerified
            }

        case .policyBlocked:
            guard outcome.verifierReport.policyDecision == "blocked" else {
                throw PostconditionError.invalidPolicyDecision(outcome.verifierReport.policyDecision)
            }

        case .postconditionFailed:
            guard outcome.verifierReport.postconditionsPassed == false else {
                throw PostconditionError.postconditionsNotMet
            }

        case .success, .partialSuccess:
            guard outcome.verifierReport.preconditionsPassed else {
                throw PostconditionError.preconditionsNotVerified
            }
            guard outcome.verifierReport.policyDecision == "approved" else {
                throw PostconditionError.invalidPolicyDecision(outcome.verifierReport.policyDecision)
            }
            guard outcome.verifierReport.postconditionsPassed else {
                throw PostconditionError.postconditionsNotMet
            }
        }

        return true
    }
}

/// Errors thrown by PostconditionsValidator
public enum PostconditionError: Error, CustomStringConvertible {
    case executionFailed
    case preconditionsNotMet
    case policyNotApproved
    case commandIDMismatch
    case preconditionsNotVerified
    case invalidPolicyDecision(String)
    case policyBlocked(String)
    case postconditionsNotMet
    case observationCaptureFailed

    public var description: String {
        switch self {
        case .executionFailed: return "Command execution failed"
        case .preconditionsNotMet: return "Preconditions were not met"
        case .policyNotApproved: return "Policy decision was not approved"
        case .commandIDMismatch: return "Command ID mismatch in verifier report"
        case .preconditionsNotVerified: return "Preconditions were not verified"
        case .invalidPolicyDecision(let decision): return "Invalid policy decision: \(decision)"
        case .policyBlocked(let reason): return "Policy blocked: \(reason)"
        case .postconditionsNotMet: return "Postconditions were not met"
        case .observationCaptureFailed: return "Failed to capture observations"
        }
    }
}
