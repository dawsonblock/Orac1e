import Foundation
import Testing
@testable import OracleOS

@Suite("Browser Target Resolver")
struct BrowserTargetResolverTests {

    @Test("Minimum score threshold is 0.65")
    func minimumScoreThreshold() {
        #expect(BrowserTargetResolver.minimumScore == 0.65)
    }

    @Test("Maximum ambiguity threshold is 0.15")
    func maximumAmbiguityThreshold() {
        #expect(BrowserTargetResolver.maximumAmbiguity == 0.15)
    }

    @Test("Browser target score combines text, role, visibility, and additional signals")
    func targetScoreCombinesFactors() {
        let score = BrowserTargetScore(
            textSimilarity: 0.9,
            roleMatch: 1.0,
            visibilityScore: 1.0
        )
        #expect(score.totalScore > 0)
        let expected = 0.40 * 0.9 + 0.25 * 1.0 + 0.15 * 1.0
        #expect(abs(score.totalScore - expected) < 0.001)
    }

    @Test("DOM indexer produces signals from snapshot")
    func domIndexerProducesSignals() {
        let snapshot = PageSnapshot(
            browserApp: "Safari",
            title: "Test Page",
            url: "https://example.com",
            domain: "example.com",
            simplifiedText: "Submit Home",
            indexedElements: [
                PageIndexedElement(id: "btn1", index: 0, role: "AXButton", label: "Submit", value: nil, domID: nil, tag: "button", className: nil, frame: nil, focused: false, enabled: true, visible: true),
                PageIndexedElement(id: "link1", index: 1, role: "AXLink", label: "Home", value: nil, domID: nil, tag: "a", className: nil, frame: nil, focused: false, enabled: true, visible: true),
            ]
        )
        let signals = DOMIndexer.index(snapshot: snapshot)
        #expect(!signals.isEmpty)
        #expect(signals.allSatisfy { !$0.text.isEmpty })
    }

    @Test("DOM indexer filters elements without labels")
    func domIndexerFiltersUnlabeled() {
        let snapshot = PageSnapshot(
            browserApp: "Safari",
            title: "Test",
            url: "https://example.com",
            domain: "example.com",
            simplifiedText: "OK",
            indexedElements: [
                PageIndexedElement(id: "div1", index: 0, role: "AXGroup", label: nil, value: nil, domID: nil, tag: "div", className: nil, frame: nil, focused: false, enabled: true, visible: true),
                PageIndexedElement(id: "btn1", index: 1, role: "AXButton", label: "OK", value: nil, domID: nil, tag: "button", className: nil, frame: nil, focused: false, enabled: true, visible: true),
            ]
        )
        let signals = DOMIndexer.index(snapshot: snapshot)
        #expect(signals.count == 1)
        #expect(signals.first?.text == "OK")
    }

    @Test("DOM indexer detects form relationships")
    func domIndexerDetectsFormRelationships() {
        let snapshot = PageSnapshot(
            browserApp: "Safari",
            title: "Form",
            url: "https://example.com",
            domain: "example.com",
            simplifiedText: "Email Submit",
            indexedElements: [
                PageIndexedElement(id: "input1", index: 0, role: "AXTextField", label: "Email", value: nil, domID: nil, tag: "input", className: nil, frame: nil, focused: false, enabled: true, visible: true),
                PageIndexedElement(id: "submit", index: 1, role: "AXButton", label: "Submit", value: nil, domID: nil, tag: "button", className: nil, frame: nil, focused: false, enabled: true, visible: true),
            ]
        )
        let signals = DOMIndexer.index(snapshot: snapshot)
        let inputSignal = signals.first { $0.elementID == "input1" }
        let submitSignal = signals.first { $0.elementID == "submit" }
        #expect(inputSignal?.formRelationship == "form-input")
        #expect(submitSignal?.formRelationship == "form-submit")
    }
}
