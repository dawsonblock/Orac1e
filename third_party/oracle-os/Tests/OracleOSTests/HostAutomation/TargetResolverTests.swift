import Foundation
import Testing
@testable import OracleOS

@Suite("Host Target Resolver")
struct TargetResolverTests {

    @Test("Minimum score threshold is 0.60")
    func minimumScoreThreshold() {
        #expect(HostTargetResolver.minimumScore == 0.60)
    }

    @Test("Maximum ambiguity threshold is 0.20")
    func maximumAmbiguityThreshold() {
        #expect(HostTargetResolver.maximumAmbiguity == 0.20)
    }

    @Test("Resolver uses ElementRanker pipeline")
    func resolverUsesElementRanker() {
        let elements = [
            UnifiedElement(id: "btn1", source: .ax, role: "AXButton", label: "Save", confidence: 0.95),
            UnifiedElement(id: "btn2", source: .ax, role: "AXButton", label: "Cancel", confidence: 0.9),
        ]
        let query = ElementQuery(text: "Save", clickable: true, visibleOnly: true)
        let ranked = HostTargetResolver.rank(query: query, elements: elements)
        #expect(!ranked.isEmpty)
        #expect(ranked.first?.element.id == "btn1" || ranked.first?.element.label == "Save")
    }

    @Test("Resolver throws on empty element list")
    func resolverThrowsOnEmpty() {
        let query = ElementQuery(text: "Missing", clickable: true, visibleOnly: true)
        #expect(throws: SkillResolutionError.self) {
            try HostTargetResolver.resolve(query: query, elements: [])
        }
    }

    @Test("Host target selection carries ambiguity score")
    func selectionCarriesAmbiguity() {
        let candidate = ElementCandidate(
            element: UnifiedElement(id: "btn", source: .ax, role: "AXButton", label: "OK", confidence: 0.95),
            score: 0.9,
            reasons: ["exact match"],
            ambiguityScore: 0.05
        )
        let selection = HostTargetSelection(
            candidate: candidate,
            ambiguityScore: 0.05,
            notes: ["test"]
        )
        #expect(selection.ambiguityScore < HostTargetResolver.maximumAmbiguity)
    }
}
