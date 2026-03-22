// MARK: - IntentAPI
// Oracle-OS vNext — Controller boundary contract.
// The controller layer may ONLY interact with the runtime through this protocol.
// It must not call planners, executors, or mutate state directly.

import Foundation

/// The sole entry point for the UI / host layer into the runtime kernel.
public protocol IntentAPI: Sendable {
    /// Submit a user or system intent for execution.
    func submitIntent(_ intent: Intent) async throws -> IntentResponse
    /// Read current committed world state as a snapshot (read-only).
    func queryState() async throws -> RuntimeSnapshot
}
