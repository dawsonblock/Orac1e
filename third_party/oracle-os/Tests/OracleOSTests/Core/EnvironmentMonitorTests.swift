import Testing
import Foundation
@testable import OracleOS

@Suite("Environment Monitor")
@MainActor
struct EnvironmentMonitorTests {

    private let monitor = EnvironmentMonitor()

    // MARK: - Helpers

    private func state(
        app: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        elementLabels: [String] = []
    ) -> WorldState {
        let elements = elementLabels.map { label in
            UnifiedElement(
                id: UUID().uuidString,
                source: .ax,
                role: "AXButton",
                label: label,
                value: nil,
                frame: .zero,
                enabled: true,
                visible: true,
                focused: false,
                confidence: 1.0
            )
        }
        let obs = Observation(
            app: app,
            windowTitle: windowTitle,
            url: url,
            elements: elements
        )
        return WorldState(observation: obs)
    }

    // MARK: - No Mismatches

    @Test("No mismatch when expectations are empty")
    func noExpectation() {
        let ws = state(app: "Finder")
        let exp = ExpectationModel()
        let delta = monitor.detectChanges(between: ws, and: exp)
        #expect(delta == nil)
    }

    @Test("No mismatch when app matches")
    func appMatches() {
        let ws = state(app: "Finder")
        let exp = ExpectationModel(expectedApp: "Finder")
        #expect(monitor.detectChanges(between: ws, and: exp) == nil)
    }

    // MARK: - App Mismatches

    @Test("Mismatch when expected app differs")
    func appMismatch() {
        let ws = state(app: "Safari")
        let exp = ExpectationModel(expectedApp: "Finder")
        let delta = monitor.detectChanges(between: ws, and: exp)
        #expect(delta != nil)
        #expect(delta!.changedElements.contains(where: { $0.contains("expected_app") }))
    }

    // MARK: - Element Mismatches

    @Test("Mismatch when expected element is absent")
    func missingElement() {
        let ws = state(app: "Finder", elementLabels: ["Open", "Close"])
        let exp = ExpectationModel(expectedElements: ["Submit"])
        let delta = monitor.detectChanges(between: ws, and: exp)
        #expect(delta != nil)
        #expect(delta!.changedElements.contains(where: { $0.contains("missing_element") }))
    }

    @Test("No mismatch when all expected elements present")
    func allElementsPresent() {
        let ws = state(app: "Finder", elementLabels: ["Open", "Submit"])
        let exp = ExpectationModel(expectedElements: ["Open"])
        #expect(monitor.detectChanges(between: ws, and: exp) == nil)
    }

    // MARK: - URL and Window

    @Test("Mismatch when URL does not match")
    func urlMismatch() {
        let ws = state(url: "https://example.com/page")
        let exp = ExpectationModel(expectedURL: "github.com")
        let delta = monitor.detectChanges(between: ws, and: exp)
        #expect(delta != nil)
        #expect(delta!.changedElements.contains(where: { $0.contains("expected_url") }))
    }

    @Test("Mismatch when window title does not match")
    func windowMismatch() {
        let ws = state(windowTitle: "Documents")
        let exp = ExpectationModel(expectedWindowTitle: "Settings")
        let delta = monitor.detectChanges(between: ws, and: exp)
        #expect(delta != nil)
        #expect(delta!.changedElements.contains(where: { $0.contains("expected_window") }))
    }

    // MARK: - Reconciliation

    @Test("Reconciliation reports passed and failed checks")
    func reconciliation() {
        let obs = Observation(app: "Finder", elements: [])
        let ws = WorldState(observation: obs)
        let postconditions: [Postcondition] = [
            .appFrontmost("Finder"),
            .elementAppeared("NonExistent"),
        ]
        let result = monitor.reconcile(
            worldState: ws,
            postconditions: postconditions,
            observation: obs
        )
        #expect(!result.consistent)
        #expect(result.passedChecks.count == 1)
        #expect(result.failedChecks.count == 1)
    }

    @Test("Reconciliation consistent when all postconditions pass")
    func reconciliationConsistent() {
        let obs = Observation(app: "Safari")
        let ws = WorldState(observation: obs)
        let result = monitor.reconcile(
            worldState: ws,
            postconditions: [.appFrontmost("Safari")],
            observation: obs
        )
        #expect(result.consistent)
    }
}
