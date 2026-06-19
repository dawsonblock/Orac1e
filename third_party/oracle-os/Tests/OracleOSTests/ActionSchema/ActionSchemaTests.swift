import Foundation
import Testing
@testable import OracleOS

@Suite("Action Schema")
struct ActionSchemaTests {

    let library = ActionSchemaLibrary()

    // MARK: - Schema construction

    @Test("Click schema sets correct kind and preconditions")
    func clickSchemaConstruction() {
        let element = SemanticElement(id: "btn-1", kind: .button, label: "Send")
        let schema = library.click(element: element)

        #expect(schema.kind == .click)
        #expect(schema.name == "click_Send")
        #expect(schema.preconditions.count == 1)
    }

    @Test("Type schema sets preconditions and postconditions")
    func typeSchemaConstruction() {
        let element = SemanticElement(id: "input-1", kind: .input, label: "Search")
        let schema = library.type(text: "hello", into: element)

        #expect(schema.kind == .type)
        #expect(schema.preconditions.count == 1)
        #expect(schema.expectedPostconditions.count == 1)
    }

    @Test("Open application schema expects app frontmost")
    func openAppSchemaConstruction() {
        let schema = library.openApplication(name: "Safari")

        #expect(schema.kind == .openApplication)
        #expect(schema.preconditions.isEmpty)
        #expect(schema.expectedPostconditions.count == 1)
    }

    @Test("Run tests schema has correct kind")
    func runTestsSchemaConstruction() {
        let schema = library.runTests()
        #expect(schema.kind == .runTests)
        #expect(schema.name == "run_tests")
    }

    @Test("Build project schema has correct kind")
    func buildProjectSchemaConstruction() {
        let schema = library.buildProject()
        #expect(schema.kind == .buildProject)
    }

    @Test("Dismiss modal schema requires modal present")
    func dismissModalSchemaConstruction() {
        let schema = library.dismissModal()
        #expect(schema.kind == .dismissModal)
        #expect(schema.preconditions.count == 1)
        #expect(schema.expectedPostconditions.count == 1)
    }

    // MARK: - Precondition checking

    @Test("Preconditions met when element exists in state")
    func preconditionsMetWithElement() {
        let element = SemanticElement(id: "btn-1", kind: .button, label: "Send")
        let schema = library.click(element: element)
        let state = CompressedUIState(
            app: "Slack",
            elements: [element]
        )

        #expect(library.preconditionsMet(schema, in: state))
    }

    @Test("Preconditions not met when element missing from state")
    func preconditionsNotMetMissingElement() {
        let element = SemanticElement(id: "btn-1", kind: .button, label: "Send")
        let schema = library.click(element: element)
        let state = CompressedUIState(
            app: "Slack",
            elements: []
        )

        #expect(!library.preconditionsMet(schema, in: state))
    }

    @Test("App frontmost precondition matches correctly")
    func appFrontmostPrecondition() {
        let schema = library.openApplication(name: "Safari")
        let postState = CompressedUIState(
            app: "Safari",
            elements: []
        )
        // Open application has no preconditions, only postconditions.
        #expect(library.preconditionsMet(schema, in: postState))
    }

    @Test("Schema with no preconditions always passes")
    func noPreconditionsAlwaysPasses() {
        let schema = ActionSchema(
            name: "custom",
            kind: .custom,
            preconditions: [],
            expectedPostconditions: []
        )
        let state = CompressedUIState(elements: [])
        #expect(library.preconditionsMet(schema, in: state))
    }

    // MARK: - Schema identity

    @Test("ActionSchemaKind covers all expected cases")
    func schemaKindCoverage() {
        let allKinds = ActionSchemaKind.allCases
        #expect(allKinds.contains(.click))
        #expect(allKinds.contains(.type))
        #expect(allKinds.contains(.runTests))
        #expect(allKinds.contains(.buildProject))
        #expect(allKinds.contains(.applyPatch))
        #expect(allKinds.contains(.dismissModal))
    }

    // MARK: - Serialization

    @Test("ActionSchema toDict includes all fields")
    func schemaToDict() {
        let schema = library.runTests()
        let dict = schema.toDict()

        #expect(dict["name"] as? String == "run_tests")
        #expect(dict["kind"] as? String == "runTests")
    }

    // MARK: - isCodeAction

    @Test("Code action kinds are classified correctly")
    func codeActionKinds() {
        #expect(ActionSchemaKind.runTests.isCodeAction == true)
        #expect(ActionSchemaKind.buildProject.isCodeAction == true)
        #expect(ActionSchemaKind.applyPatch.isCodeAction == true)
        #expect(ActionSchemaKind.commitPatch.isCodeAction == true)
        #expect(ActionSchemaKind.revertPatch.isCodeAction == true)
    }

    @Test("Non-code action kinds are classified correctly")
    func nonCodeActionKinds() {
        #expect(ActionSchemaKind.click.isCodeAction == false)
        #expect(ActionSchemaKind.type.isCodeAction == false)
        #expect(ActionSchemaKind.navigate.isCodeAction == false)
        #expect(ActionSchemaKind.scroll.isCodeAction == false)
        #expect(ActionSchemaKind.custom.isCodeAction == false)
    }
}
