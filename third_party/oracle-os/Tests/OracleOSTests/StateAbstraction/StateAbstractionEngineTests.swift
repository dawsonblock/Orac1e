import Foundation
import Testing
@testable import OracleOS

@Suite("State Abstraction Engine")
struct StateAbstractionEngineTests {

    let engine = StateAbstractionEngine()

    // MARK: - Role mapping

    @Test("Maps AXButton role to button kind")
    func mapButtonRole() {
        let kind = engine.mapRole("AXButton")
        #expect(kind == .button)
    }

    @Test("Maps AXTextField role to input kind")
    func mapInputRole() {
        let kind = engine.mapRole("AXTextField")
        #expect(kind == .input)
    }

    @Test("Maps AXLink role to link kind")
    func mapLinkRole() {
        let kind = engine.mapRole("AXLink")
        #expect(kind == .link)
    }

    @Test("Maps AXDialog role to dialog kind")
    func mapDialogRole() {
        let kind = engine.mapRole("AXDialog")
        #expect(kind == .dialog)
    }

    @Test("Maps nil role to unknown kind")
    func mapNilRole() {
        let kind = engine.mapRole(nil)
        #expect(kind == .unknown)
    }

    @Test("Maps AXGroup role to container kind")
    func mapGroupRole() {
        let kind = engine.mapRole("AXGroup")
        #expect(kind == .container)
    }

    // MARK: - Classification

    @Test("Classifies element with label")
    func classifyElementWithLabel() {
        let element = UnifiedElement(
            id: "btn-1",
            source: .ax,
            role: "AXButton",
            label: "Send",
            confidence: 0.9
        )
        let semantic = engine.classify(element)
        #expect(semantic.kind == .button)
        #expect(semantic.label == "Send")
        #expect(semantic.interactable == true)
    }

    @Test("Classifies element without label falls back to role")
    func classifyElementWithoutLabel() {
        let element = UnifiedElement(
            id: "grp-1",
            source: .ax,
            role: "AXGroup",
            label: nil,
            confidence: 0.8
        )
        let semantic = engine.classify(element)
        #expect(semantic.label == "AXGroup")
        #expect(semantic.interactable == false)
    }

    // MARK: - Deduplication

    @Test("Deduplicates elements with same kind and label")
    func deduplicatesSameKindAndLabel() {
        let elements = [
            SemanticElement(id: "1", kind: .button, label: "Send"),
            SemanticElement(id: "2", kind: .button, label: "Send"),
            SemanticElement(id: "3", kind: .button, label: "Cancel"),
        ]
        let result = engine.deduplicate(elements)
        #expect(result.count == 2)
        #expect(result[0].label == "Send")
        #expect(result[1].label == "Cancel")
    }

    // MARK: - Full compression

    @Test("Compress produces CompressedUIState from observation")
    func compressProducesState() {
        let observation = Observation(
            app: "Slack",
            windowTitle: "Slack - general",
            url: nil,
            focusedElementID: nil,
            elements: [
                UnifiedElement(id: "btn-send", source: .ax, role: "AXButton", label: "Send", confidence: 0.95),
                UnifiedElement(id: "input-msg", source: .ax, role: "AXTextField", label: "Message", confidence: 0.9),
                UnifiedElement(id: "grp-1", source: .ax, role: "AXGroup", label: nil, confidence: 0.5),
            ]
        )
        let state = engine.compress(observation)

        #expect(state.app == "Slack")
        #expect(state.windowTitle == "Slack - general")
        #expect(state.elements.count == 3)
        #expect(state.interactableElements.count == 2)
    }

    @Test("Compressed state filters interactable elements correctly")
    func interactableFilter() {
        let elements = [
            SemanticElement(id: "1", kind: .button, label: "OK", interactable: true),
            SemanticElement(id: "2", kind: .text, label: "Hello", interactable: false),
            SemanticElement(id: "3", kind: .input, label: "Name", interactable: true),
        ]
        let state = CompressedUIState(elements: elements)
        #expect(state.interactableElements.count == 2)
    }

    // MARK: - Serialization

    @Test("SemanticElement toDict round-trips key fields")
    func semanticElementToDict() {
        let element = SemanticElement(
            id: "btn-1",
            kind: .button,
            label: "Send",
            interactable: true
        )
        let dict = element.toDict()
        #expect(dict["kind"] as? String == "button")
        #expect(dict["label"] as? String == "Send")
        #expect(dict["interactable"] as? Bool == true)
    }
}
