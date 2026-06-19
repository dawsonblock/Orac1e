import Foundation
import Testing
@testable import OracleOS

@Suite("TraceCompression")
struct TraceCompressionTests {

    @Test("TraceCompressor.filter(.full) retains all elements")
    func filterFullRetainsElements() {
        let el1 = UnifiedElement(id: "1", source: .ax, role: "button", frame: .zero)
        let el2 = UnifiedElement(id: "2", source: .ax, role: "textField", frame: .zero)
        let obs = Observation(
            app: "TestApp",
            focusedElementID: "2",
            elements: [el1, el2]
        )

        let compressor = TraceCompressor()
        let filtered = compressor.filter(observation: obs, verbosity: .full)

        #expect(filtered.elements.count == 2)
        #expect(filtered.elements[0].id == "1")
        #expect(filtered.elements[1].id == "2")
    }

    @Test("TraceCompressor.filter(.minimal) strips non-focused elements")
    func filterMinimalStripsElements() {
        let el1 = UnifiedElement(id: "1", source: .ax, role: "button", frame: .zero)
        let el2 = UnifiedElement(id: "2", source: .ax, role: "textField", frame: .zero)
        let obs = Observation(
            app: "TestApp",
            focusedElementID: "2",
            elements: [el1, el2]
        )

        let compressor = TraceCompressor()
        let filtered = compressor.filter(observation: obs, verbosity: .minimal)

        #expect(filtered.elements.count == 1)
        #expect(filtered.elements[0].id == "2")
        #expect(filtered.app == "TestApp")
        #expect(filtered.focusedElementID == "2")
    }
    
    @Test("TraceCompressor.filter(.minimal) strips all elements if none focused")
    func filterMinimalStripsAllIfNoneFocused() {
        let el1 = UnifiedElement(id: "1", source: .ax, role: "button", frame: .zero)
        let el2 = UnifiedElement(id: "2", source: .ax, role: "textField", frame: .zero)
        let obs = Observation(
            app: "TestApp",
            focusedElementID: nil,
            elements: [el1, el2]
        )

        let compressor = TraceCompressor()
        let filtered = compressor.filter(observation: obs, verbosity: .minimal)

        #expect(filtered.elements.isEmpty)
    }
}
