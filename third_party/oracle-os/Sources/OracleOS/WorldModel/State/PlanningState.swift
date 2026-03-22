import Foundation

public struct PlanningState: Hashable, Codable, Sendable {
    public let id: PlanningStateID
    public let clusterKey: StateClusterKey
    public let appID: String
    public let domain: String?
    public let windowClass: String?
    public let taskPhase: String?
    public let focusedRole: String?
    public let modalClass: String?
    public let navigationClass: String?
    public let controlContext: String?

    public init(
        id: PlanningStateID,
        clusterKey: StateClusterKey,
        appID: String,
        domain: String?,
        windowClass: String?,
        taskPhase: String?,
        focusedRole: String?,
        modalClass: String?,
        navigationClass: String?,
        controlContext: String?
    ) {
        self.id = id
        self.clusterKey = clusterKey
        self.appID = appID
        self.domain = domain
        self.windowClass = windowClass
        self.taskPhase = taskPhase
        self.focusedRole = focusedRole
        self.modalClass = modalClass
        self.navigationClass = navigationClass
        self.controlContext = controlContext
    }

    public func toDict() -> [String: Any] {
        [
            "id": id.rawValue,
            "cluster_key": clusterKey.rawValue,
            "app_id": appID,
            "domain": domain as Any,
            "window_class": windowClass as Any,
            "task_phase": taskPhase as Any,
            "focused_role": focusedRole as Any,
            "modal_class": modalClass as Any,
            "navigation_class": navigationClass as Any,
            "control_context": controlContext as Any,
        ]
    }

    public static func from(dict: [String: Any]) -> PlanningState? {
        guard let id = dict["id"] as? String,
              let clusterKey = dict["cluster_key"] as? String,
              let appID = dict["app_id"] as? String
        else {
            return nil
        }

        return PlanningState(
            id: PlanningStateID(rawValue: id),
            clusterKey: StateClusterKey(rawValue: clusterKey),
            appID: appID,
            domain: dict["domain"] as? String,
            windowClass: dict["window_class"] as? String,
            taskPhase: dict["task_phase"] as? String,
            focusedRole: dict["focused_role"] as? String,
            modalClass: dict["modal_class"] as? String,
            navigationClass: dict["navigation_class"] as? String,
            controlContext: dict["control_context"] as? String
        )
    }
}
