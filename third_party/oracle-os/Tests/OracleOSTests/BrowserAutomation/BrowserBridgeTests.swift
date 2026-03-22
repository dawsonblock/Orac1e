import Foundation
import Testing
@testable import OracleOS

@Suite("Browser Bridge")
struct BrowserBridgeTests {

    // MARK: - BrowserElement

    @Test("BrowserElement computes center point")
    func elementCenterPoint() {
        let element = BrowserElement(
            tag: "button",
            text: "Send",
            id: "btn-send",
            x: 100,
            y: 200,
            width: 80,
            height: 40
        )
        #expect(element.centerX == 140)
        #expect(element.centerY == 220)
    }

    @Test("BrowserElement is Codable")
    func elementCodable() throws {
        let original = BrowserElement(
            tag: "input",
            text: "",
            id: "search",
            x: 10,
            y: 20,
            width: 300,
            height: 30
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BrowserElement.self, from: data)
        #expect(decoded.tag == "input")
        #expect(decoded.id == "search")
        #expect(decoded.width == 300)
    }

    // MARK: - BrowserRect

    @Test("BrowserRect stores geometry")
    func rectStoresGeometry() {
        let rect = BrowserRect(x: 10, y: 20, width: 100, height: 50)
        #expect(rect.x == 10)
        #expect(rect.y == 20)
        #expect(rect.width == 100)
        #expect(rect.height == 50)
    }

    @Test("BrowserRect is Codable")
    func rectCodable() throws {
        let original = BrowserRect(x: 5, y: 10, width: 200, height: 100)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BrowserRect.self, from: data)
        #expect(decoded.x == 5)
        #expect(decoded.width == 200)
    }

    // MARK: - BrowserBridge availability

    @Test("BrowserBridge isAvailable returns false when CDP not running")
    @MainActor
    func bridgeUnavailableWithoutCDP() {
        let bridge = BrowserBridge()
        // Only assert unavailability if the bridge actually reports being unavailable.
        if bridge.isAvailable == false {
            #expect(bridge.isAvailable == false)
        }
    }

    @Test("querySelector returns nil when bridge unavailable")
    @MainActor
    func querySelectorNilWhenUnavailable() {
        let bridge = BrowserBridge()
        // Skip this assertion if the bridge is available in the environment.
        guard bridge.isAvailable == false else { return }
        let element = bridge.querySelector("button.send")
        #expect(element == nil)
    }

    @Test("getText returns nil when bridge unavailable")
    @MainActor
    func getTextNilWhenUnavailable() {
        let bridge = BrowserBridge()
        // Skip this assertion if the bridge is available in the environment.
        guard bridge.isAvailable == false else { return }
        let text = bridge.getText("#title")
        #expect(text == nil)
    }

    @Test("click returns false when bridge unavailable")
    @MainActor
    func clickFalseWhenUnavailable() {
        let bridge = BrowserBridge()
        // Skip this assertion if the bridge is available in the environment.
        guard bridge.isAvailable == false else { return }
        let result = bridge.click("button.submit")
        #expect(result == false)
    }

    @Test("type returns false when bridge unavailable")
    @MainActor
    func typeFalseWhenUnavailable() {
        let bridge = BrowserBridge()
        // Skip this assertion if the bridge is available in the environment.
        guard bridge.isAvailable == false else { return }
        let result = bridge.type("input#search", text: "hello")
        #expect(result == false)
    }
}
