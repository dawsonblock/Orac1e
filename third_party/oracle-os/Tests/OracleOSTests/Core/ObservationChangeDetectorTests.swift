import Foundation
import Testing
@testable import OracleOS

@Suite("Observation Change Detector")
struct ObservationChangeDetectorTests {

    // MARK: - Identical observations produce empty delta

    @Test("Identical observations produce empty delta")
    func identicalObservationsProduceEmptyDelta() {
        let elements = [
            makeElement(id: "btn-1", role: "AXButton", label: "Save"),
            makeElement(id: "btn-2", role: "AXButton", label: "Cancel"),
        ]
        let obs = Observation(app: "Safari", windowTitle: "Main", url: "https://example.com", elements: elements)

        let delta = ObservationChangeDetector.detect(previous: obs, incoming: obs)

        #expect(delta.isEmpty)
        #expect(delta.changeCount == 0)
    }

    // MARK: - Application change detected

    @Test("Application name change detected")
    func applicationChangeDetected() {
        let prev = Observation(app: "Safari", elements: [])
        let next = Observation(app: "Finder", elements: [])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(!delta.isEmpty)
        #expect(delta.applicationChanged?.from == "Safari")
        #expect(delta.applicationChanged?.to == "Finder")
    }

    // MARK: - Window title change detected

    @Test("Window title change detected")
    func windowTitleChangeDetected() {
        let prev = Observation(app: "Safari", windowTitle: "Page 1", elements: [])
        let next = Observation(app: "Safari", windowTitle: "Page 2", elements: [])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.windowTitleChanged?.from == "Page 1")
        #expect(delta.windowTitleChanged?.to == "Page 2")
    }

    // MARK: - URL change detected

    @Test("URL change detected")
    func urlChangeDetected() {
        let prev = Observation(app: "Safari", url: "https://old.com", elements: [])
        let next = Observation(app: "Safari", url: "https://new.com", elements: [])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.urlChanged?.from == "https://old.com")
        #expect(delta.urlChanged?.to == "https://new.com")
    }

    // MARK: - Focus change detected

    @Test("Focus change detected")
    func focusChangeDetected() {
        let prev = Observation(app: "Safari", focusedElementID: "el-1", elements: [])
        let next = Observation(app: "Safari", focusedElementID: "el-2", elements: [])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.focusChanged?.from == "el-1")
        #expect(delta.focusChanged?.to == "el-2")
    }

    // MARK: - Added elements detected

    @Test("Added elements detected")
    func addedElementsDetected() {
        let prev = Observation(app: "Safari", elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "Save"),
        ])
        let next = Observation(app: "Safari", elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "Save"),
            makeElement(id: "btn-2", role: "AXButton", label: "Cancel"),
        ])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.addedElements.count == 1)
        #expect(delta.addedElements.first?.id == "btn-2")
        #expect(delta.removedElementIDs.isEmpty)
    }

    // MARK: - Removed elements detected

    @Test("Removed elements detected")
    func removedElementsDetected() {
        let prev = Observation(app: "Safari", elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "Save"),
            makeElement(id: "btn-2", role: "AXButton", label: "Cancel"),
        ])
        let next = Observation(app: "Safari", elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "Save"),
        ])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.removedElementIDs.count == 1)
        #expect(delta.removedElementIDs.contains("btn-2"))
        #expect(delta.addedElements.isEmpty)
    }

    // MARK: - Changed element properties detected

    @Test("Changed element label detected")
    func changedElementLabelDetected() {
        let prev = Observation(app: "Safari", elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "Save"),
        ])
        let next = Observation(app: "Safari", elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "Save Draft"),
        ])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.changedElements.count == 1)
        #expect(delta.changedElements.first?.elementID == "btn-1")
        #expect(delta.changedElements.first?.changedProperties.contains(.label) == true)
    }

    @Test("Changed element enabled state detected")
    func changedElementEnabledStateDetected() {
        let prev = Observation(app: "App", elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "Submit", enabled: true),
        ])
        let next = Observation(app: "App", elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "Submit", enabled: false),
        ])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.changedElements.count == 1)
        #expect(delta.changedElements.first?.changedProperties.contains(.enabled) == true)
    }

    @Test("Changed element value detected")
    func changedElementValueDetected() {
        let prev = Observation(app: "App", elements: [
            UnifiedElement(id: "input-1", source: .ax, role: "AXTextField", label: "Name", value: "Alice"),
        ])
        let next = Observation(app: "App", elements: [
            UnifiedElement(id: "input-1", source: .ax, role: "AXTextField", label: "Name", value: "Bob"),
        ])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.changedElements.count == 1)
        #expect(delta.changedElements.first?.changedProperties.contains(.value) == true)
        #expect(delta.changedElements.first?.changedProperties.contains(.label) == false)
    }

    // MARK: - Multiple changes in single delta

    @Test("Multiple changes tracked in single delta")
    func multipleChangesTracked() {
        let prev = Observation(app: "Safari", windowTitle: "Page 1", url: "https://old.com", elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "OK"),
            makeElement(id: "btn-2", role: "AXButton", label: "Cancel"),
        ])
        let next = Observation(app: "Finder", windowTitle: "Desktop", url: nil, elements: [
            makeElement(id: "btn-1", role: "AXButton", label: "Open"),
            makeElement(id: "btn-3", role: "AXButton", label: "Close"),
        ])

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.applicationChanged != nil)
        #expect(delta.windowTitleChanged != nil)
        #expect(delta.urlChanged != nil)
        #expect(delta.addedElements.count == 1) // btn-3
        #expect(delta.removedElementIDs.count == 1) // btn-2
        #expect(delta.changedElements.count == 1) // btn-1 label changed
        #expect(delta.changeCount >= 6)
    }

    // MARK: - Unchanged elements not reported

    @Test("Unchanged elements not included in delta")
    func unchangedElementsNotReported() {
        let elements = [
            makeElement(id: "btn-1", role: "AXButton", label: "OK"),
            makeElement(id: "btn-2", role: "AXButton", label: "Cancel"),
        ]
        let prev = Observation(app: "App", elements: elements)
        let next = Observation(app: "App", elements: elements)

        let delta = ObservationChangeDetector.detect(previous: prev, incoming: next)

        #expect(delta.changedElements.isEmpty)
        #expect(delta.addedElements.isEmpty)
        #expect(delta.removedElementIDs.isEmpty)
    }

    // MARK: - Helpers

    private func makeElement(
        id: String,
        role: String = "AXButton",
        label: String = "Button",
        enabled: Bool = true
    ) -> UnifiedElement {
        UnifiedElement(id: id, source: .ax, role: role, label: label, enabled: enabled, confidence: 0.9)
    }
}
