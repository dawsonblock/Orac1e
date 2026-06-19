import Foundation

/// Reducers are the ONLY entities that may update WorldState.
/// INVARIANT: apply() must be a pure function — same input always yields same output.
public protocol EventReducer: Sendable {
    func apply(events: [EventEnvelope], to state: inout WorldStateModel)
}
