import Foundation

@MainActor
public final class RuntimeLifecycle {
    private let approvalStore: ApprovalStore
    private var heartbeatTask: Task<Void, Never>?

    public init(approvalStore: ApprovalStore) {
        self.approvalStore = approvalStore
    }

    public func startControllerHeartbeat(sessionID: String, intervalSeconds: TimeInterval = 2) {
        stopControllerHeartbeat()

        heartbeatTask = Task {
            while !Task.isCancelled {
                approvalStore.writeControllerHeartbeat(sessionID: sessionID)
                let delay = UInt64(max(1, intervalSeconds) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    public func stopControllerHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    public func controllerConnected() -> Bool {
        approvalStore.controllerConnected()
    }
}
