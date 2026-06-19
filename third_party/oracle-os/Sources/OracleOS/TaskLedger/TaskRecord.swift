import Foundation

/// Represents a meaningful task state in the task graph.
///
/// ``TaskRecord`` captures *task-relevant* state abstractions rather than raw UI
/// noise. The planner navigates the graph by moving between nodes, so each
/// node must describe a recognisable planning position such as ``repo_loaded``,
/// ``tests_running``, or ``permission_dialog_active``.
public final class TaskRecord: @unchecked Sendable {
    public let id: String
    public let abstractState: AbstractTaskState
    public let planningStateID: PlanningStateID
    public private(set) var worldSnapshotRef: String?
    public let createdByAction: String?
    public let timestamp: TimeInterval
    public private(set) var attachedMemoryRefs: [String]
    public private(set) var workflowMatches: [String]
    public private(set) var confidence: Double
    public private(set) var visitCount: Int

    public init(
        id: String = UUID().uuidString,
        abstractState: AbstractTaskState,
        planningStateID: PlanningStateID,
        worldSnapshotRef: String? = nil,
        createdByAction: String? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        attachedMemoryRefs: [String] = [],
        workflowMatches: [String] = [],
        confidence: Double = 1.0,
        visitCount: Int = 0
    ) {
        self.id = id
        self.abstractState = abstractState
        self.planningStateID = planningStateID
        self.worldSnapshotRef = worldSnapshotRef
        self.createdByAction = createdByAction
        self.timestamp = timestamp
        self.attachedMemoryRefs = attachedMemoryRefs
        self.workflowMatches = workflowMatches
        self.confidence = confidence
        self.visitCount = visitCount
    }

    public func recordVisit() {
        visitCount += 1
    }

    public func attachMemoryRef(_ ref: String) {
        if !attachedMemoryRefs.contains(ref) {
            attachedMemoryRefs.append(ref)
        }
    }

    public func attachWorkflowMatch(_ workflowID: String) {
        if !workflowMatches.contains(workflowID) {
            workflowMatches.append(workflowID)
        }
    }

    public func updateConfidence(_ newConfidence: Double) {
        confidence = max(0, min(1, newConfidence))
    }

    public func updateWorldSnapshotRef(_ ref: String) {
        worldSnapshotRef = ref
    }

    /// A stable signature combining the abstract state and planning state,
    /// used to determine if the task position has meaningfully changed.
    public var stateSignature: String {
        "\(abstractState.rawValue)|\(planningStateID.rawValue)"
    }
}

/// Task-relevant state abstraction.
///
/// Each case represents a meaningful planning position that the planner can
/// reason about. Raw UI noise (scroll offsets, focus rings, minor DOM
/// mutations) must **not** create distinct abstract states.
public enum AbstractTaskState: String, Codable, Sendable, Hashable {
    // Repository lifecycle
    case repoLoaded = "repo_loaded"
    case repoIndexed = "repo_indexed"

    // Build lifecycle
    case buildRunning = "build_running"
    case buildSucceeded = "build_succeeded"
    case buildFailed = "build_failed"

    // Test lifecycle
    case testsRunning = "tests_running"
    case testsPassed = "tests_passed"
    case failingTestIdentified = "failing_test_identified"

    // Patch lifecycle
    case candidatePatchGenerated = "candidate_patch_generated"
    case candidatePatchApplied = "candidate_patch_applied"
    case patchVerified = "patch_verified"
    case patchRejected = "patch_rejected"

    // Browser / UI lifecycle
    case pageLoaded = "page_loaded"
    case loginPageDetected = "login_page_detected"
    case permissionDialogActive = "permission_dialog_active"
    case modalDialogActive = "modal_dialog_active"
    case navigationCompleted = "navigation_completed"
    case formVisible = "form_visible"

    // General task states
    case taskStarted = "task_started"
    case taskCompleted = "task_completed"
    case goalReached = "goal_reached"
    case recoveryNeeded = "recovery_needed"
    case explorationActive = "exploration_active"
    case idle = "idle"
}
