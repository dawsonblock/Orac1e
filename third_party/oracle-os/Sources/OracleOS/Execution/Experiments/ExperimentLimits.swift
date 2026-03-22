/// Global safety limits for the experiment subsystem.
///
/// Prevents runaway search by bounding the number of candidates
/// generated and the number of iterations any experiment loop may run.
public enum ExperimentLimits {
    /// Maximum number of patch candidates per experiment run.
    public static let maxCandidates = 5

    /// Maximum number of experiment iterations before escalation.
    public static let maxIterations = 3
}
