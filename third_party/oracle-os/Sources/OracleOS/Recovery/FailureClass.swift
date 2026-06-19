public enum FailureClass: String, Codable, Sendable {

    case elementNotFound
    case elementAmbiguous
    case wrongFocus
    case actionFailed
    case navigationFailed
    case modalBlocking
    case verificationFailed
    case staleObservation
    case buildFailed
    case testFailed
    case patchApplyFailed
    case workspaceScopeViolation
    case gitPolicyBlocked
    case noRelevantFiles
    case ambiguousEditTarget
    case targetMissing
    case permissionBlocked
    case unexpectedDialog
    case environmentMismatch
    case workflowReplayFailure
    case loopStalled
}
