import Foundation

@MainActor
public protocol ObservationProvider {
    func observe() -> Observation
}
