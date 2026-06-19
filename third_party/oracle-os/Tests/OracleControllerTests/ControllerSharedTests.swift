import Foundation
import Testing
@testable import OracleControllerShared

struct ControllerSharedTests {
    @Test
    func actionRequestFlagsRiskyOperations() {
        let request = ActionRequest(kind: .click, query: "Send button")
        #expect(request.requiresConfirmation)

        let safeRequest = ActionRequest(kind: .focus, appName: "Finder")
        #expect(!safeRequest.requiresConfirmation)
    }

    @Test
    func hostRequestRoundTripsThroughJSON() throws {
        let request = ControllerHostRequest(
            command: .performAction,
            appName: "Google Chrome",
            action: ActionRequest(kind: .type, appName: "Google Chrome", query: "Search", text: "oracle"),
            monitoring: MonitoringConfiguration(enabled: true, appName: "Google Chrome", intervalMs: 1000)
        )

        let encoder = ControllerJSONCoding.makeEncoder()
        let decoder = ControllerJSONCoding.makeDecoder()

        let encoded = try encoder.encode(request)
        let decoded = try decoder.decode(ControllerHostRequest.self, from: encoded)

        #expect(decoded.command == .performAction)
        #expect(decoded.action?.text == "oracle")
        #expect(decoded.monitoring?.enabled == true)
    }

    @Test
    func traceEnvelopeRoundTrips() throws {
        let step = TraceStepViewModel(
            sessionID: "session-1",
            stepID: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            toolName: "oracle_focus",
            actionName: "focus",
            actionTarget: "Finder",
            actionText: nil,
            selectedElementID: nil,
            selectedElementLabel: nil,
            candidateScore: nil,
            candidateReasons: [],
            preObservationHash: "pre",
            postObservationHash: "post",
            postcondition: "appFrontmost:Finder",
            verified: true,
            success: true,
            failureClass: nil,
            elapsedMs: 42,
            screenshotPath: nil,
            artifactPaths: [],
            notes: nil
        )
        let event = ControllerHostEvent(kind: .traceStepAppended, traceStep: step)
        let envelope = ControllerHostEnvelope(event: event)

        let encoder = ControllerJSONCoding.makeEncoder()
        let decoder = ControllerJSONCoding.makeDecoder()

        let encoded = try encoder.encode(envelope)
        let decoded = try decoder.decode(ControllerHostEnvelope.self, from: encoded)

        #expect(decoded.kind == .event)
        #expect(decoded.event?.traceStep?.stepID == 1)
        #expect(decoded.event?.traceStep?.postObservationHash == "post")
    }

    @Test
    func recipeDocumentPreservesRawJSON() throws {
        let recipe = RecipeDocument(
            name: "gmail-send",
            description: "Send an email from Gmail.",
            app: "Google Chrome",
            params: [
                "recipient": RecipeParamDocument(id: "recipient", type: "string", description: "Email", required: true),
            ],
            steps: [
                RecipeStepDocument(id: 1, action: "focus"),
                RecipeStepDocument(id: 2, action: "click"),
            ],
            rawJSON: "{ \"name\": \"gmail-send\" }"
        )

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(RecipeDocument.self, from: data)

        #expect(decoded.name == "gmail-send")
        #expect(decoded.params?["recipient"]?.required == true)
        #expect(decoded.rawJSON == "{ \"name\": \"gmail-send\" }")
    }
}
