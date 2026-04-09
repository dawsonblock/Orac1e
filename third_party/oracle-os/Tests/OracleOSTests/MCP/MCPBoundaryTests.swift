import Foundation
import Testing
@testable import OracleOS

@Suite("MCP Boundary")
struct MCPBoundaryTests {

    @Test("Outer seam rejects non-object arguments")
    @MainActor
    func handleRejectsInvalidArgumentsShape() {
        let response = MCPDispatch.handle([
            "name": "oracle_recipes",
            "arguments": "not-an-object",
        ])

        #expect(response["isError"] as? Bool == true)
        let content = response["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        #expect(text?.contains("Invalid arguments payload") == true)
    }

    @Test("Typed argument access preserves scalar and array values")
    func typedArgumentsDecodeJSONValues() throws {
        let request = try MCPBoundary.decodeCall(from: [
            "name": "oracle_ground",
            "arguments": [
                "description": "Send button",
                "crop_box": [10, 20.5, 30, 40],
                "full_resolution": true,
            ],
        ])

        #expect(request.name == "oracle_ground")
        #expect(request.arguments.string("description") == "Send button")
        #expect(request.arguments.bool("full_resolution") == true)
        #expect(request.arguments.numberArray("crop_box") == [10, 20.5, 30, 40])
    }

    @Test("Shared typed export path preserves stable payload keys")
    func typedPayloadUsesSharedExportPath() {
        struct StablePayload: Encodable {
            let recipeName: String
            let totalSteps: Int

            enum CodingKeys: String, CodingKey {
                case recipeName = "recipe_name"
                case totalSteps = "total_steps"
            }
        }

        let result = MCPBoundary.makeToolResult(payload: StablePayload(recipeName: "compose", totalSteps: 3))
        let response = MCPBoundary.encodeResult(result, toolName: "oracle_run")

        let content = response["content"] as? [[String: Any]]
        let text = try #require(content?.first?["text"] as? String)
        let data = try #require(text.data(using: .utf8))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try #require(object["data"] as? [String: Any])

        #expect(payload["recipe_name"] as? String == "compose")
        #expect(payload["total_steps"] as? Double == 3)
    }

    @Test("Typed tool definitions preserve public catalog")
    @MainActor
    func typedToolDefinitionsPreserveCatalogShape() {
        let definitions = MCPTools.definitions()

        #expect(definitions.count == 22)
        let names = definitions.compactMap { $0["name"] as? String }
        #expect(names.contains("oracle_recipes"))
        #expect(names.contains("oracle_screenshot"))
        #expect(names.contains("oracle_ground"))

        let clickDefinition = definitions.first { ($0["name"] as? String) == "oracle_click" }
        let inputSchema = clickDefinition?["inputSchema"] as? [String: Any]
        let properties = inputSchema?["properties"] as? [String: Any]
        let approvalSchema = properties?["approval_request_id"] as? [String: Any]

        #expect(inputSchema?["type"] as? String == "object")
        #expect(approvalSchema?["type"] as? String == "string")
    }
}