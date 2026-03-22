import CoreGraphics
import Foundation
import Testing
@testable import OracleOS

@Suite("Browser Automation")
struct BrowserAutomationTests {
    @Test("DOM flattener assigns stable element indexes")
    func domFlattenerAssignsIndexes() {
        let flattened = DOMFlattener.flatten([
            [
                "role": "button",
                "label": "Sign in",
                "id": "signin",
                "tag": "button",
                "enabled": true,
                "visible": true,
            ],
            [
                "role": "textbox",
                "label": "Email",
                "id": "email",
                "tag": "input",
                "enabled": true,
                "visible": true,
            ],
        ])

        #expect(flattened.count == 2)
        #expect(flattened.map(\.index) == [1, 2])
        #expect(flattened.first?.label == "Sign in")
        #expect(flattened.last?.domID == "email")
    }

    @Test("Browser target resolver returns a clear candidate")
    func browserTargetResolverReturnsClearCandidate() throws {
        let snapshot = PageSnapshot(
            browserApp: "Google Chrome",
            title: "Login",
            url: "https://example.com/login",
            domain: "example.com",
            simplifiedText: "Login Sign in Email",
            indexedElements: [
                PageIndexedElement(
                    id: "signin",
                    index: 1,
                    role: "button",
                    label: "Sign in",
                    value: nil,
                    domID: "signin",
                    tag: "button",
                    className: nil,
                    frame: CGRect(x: 0, y: 0, width: 100, height: 30),
                    focused: false,
                    enabled: true,
                    visible: true
                ),
                PageIndexedElement(
                    id: "help",
                    index: 2,
                    role: "link",
                    label: "Help",
                    value: nil,
                    domID: "help",
                    tag: "a",
                    className: nil,
                    frame: nil,
                    focused: false,
                    enabled: true,
                    visible: true
                ),
            ]
        )

        let selection = try BrowserTargetResolver.resolve(
            query: ElementQuery(text: "Sign in", role: "button", clickable: true),
            in: snapshot
        )

        #expect(selection.match.element.domID == "signin")
        #expect(selection.match.score >= BrowserTargetResolver.minimumScore)
    }

    @Test("Browser target resolver fails closed on ambiguity")
    func browserTargetResolverFailsClosedOnAmbiguity() {
        let snapshot = PageSnapshot(
            browserApp: "Google Chrome",
            title: "Compose",
            url: "https://mail.example.com",
            domain: "mail.example.com",
            simplifiedText: "Send Send",
            indexedElements: [
                PageIndexedElement(
                    id: "send-primary",
                    index: 1,
                    role: "button",
                    label: "Send",
                    value: nil,
                    domID: "send-primary",
                    tag: "button",
                    className: nil,
                    frame: nil,
                    focused: false,
                    enabled: true,
                    visible: true
                ),
                PageIndexedElement(
                    id: "send-secondary",
                    index: 2,
                    role: "button",
                    label: "Send",
                    value: nil,
                    domID: "send-secondary",
                    tag: "button",
                    className: nil,
                    frame: nil,
                    focused: false,
                    enabled: true,
                    visible: true
                ),
            ]
        )

        #expect(throws: SkillResolutionError.self) {
            try BrowserTargetResolver.resolve(
                query: ElementQuery(text: "Send", role: "button", clickable: true),
                in: snapshot
            )
        }
    }

    @Test("Browser action adapter produces runtime-safe intents")
    func browserActionAdapterProducesRuntimeSafeIntents() throws {
        let snapshot = PageSnapshot(
            browserApp: "Google Chrome",
            title: "Login",
            url: "https://example.com/login",
            domain: "example.com",
            simplifiedText: "Sign in Email",
            indexedElements: [
                PageIndexedElement(
                    id: "signin",
                    index: 1,
                    role: "button",
                    label: "Sign in",
                    value: nil,
                    domID: "signin",
                    tag: "button",
                    className: nil,
                    frame: nil,
                    focused: false,
                    enabled: true,
                    visible: true
                ),
                PageIndexedElement(
                    id: "email",
                    index: 2,
                    role: "textbox",
                    label: "Email",
                    value: nil,
                    domID: "email",
                    tag: "input",
                    className: nil,
                    frame: nil,
                    focused: false,
                    enabled: true,
                    visible: true
                ),
            ]
        )
        let clickSelection = try BrowserTargetResolver.resolve(
            query: ElementQuery(text: "Sign in", role: "button", clickable: true),
            in: snapshot
        )
        let typeSelection = try BrowserTargetResolver.resolve(
            query: ElementQuery(text: "Email", role: "textbox", editable: true),
            in: snapshot
        )

        let clickIntent = BrowserActionAdapter.clickIntent(selection: clickSelection, appName: "Google Chrome")
        let typeIntent = BrowserActionAdapter.typeIntent(selection: typeSelection, text: "user@example.com", appName: "Google Chrome")

        #expect(clickIntent.action == "click")
        #expect(clickIntent.domID == "signin")
        #expect(typeIntent.action == "type")
        #expect(typeIntent.domID == "email")
        #expect(typeIntent.postconditions.isEmpty == false)
    }
}
