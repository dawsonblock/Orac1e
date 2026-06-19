import Testing
import Foundation
@testable import OracleOS

@Suite("Recipe Schema Validation")
@MainActor
struct RecipeSchemaTests {

    // MARK: - Helpers

    private func minimalRecipe(
        postconditions: [RecipePostcondition]? = nil,
        constraints: RecipeConstraints? = nil
    ) throws -> Recipe {
        let json: String = """
        {
            "schema_version": 2,
            "name": "test-recipe",
            "description": "A test recipe",
            "app": "Finder",
            "steps": [
                {"id": 1, "action": "click", "params": {}}
            ]
            \(postconditions != nil ? ",\"postconditions\": \(postconditionsJSON(postconditions!))" : "")
            \(constraints != nil ? ",\"constraints\": \(constraintsJSON(constraints!))" : "")
        }
        """
        return try JSONDecoder().decode(Recipe.self, from: Data(json.utf8))
    }

    private func postconditionsJSON(_ pcs: [RecipePostcondition]) -> String {
        let items = pcs.map { pc in
            var obj = "{\"kind\":\"\(pc.kind)\",\"target\":\"\(pc.target)\""
            if let expected = pc.expected { obj += ",\"expected\":\"\(expected)\"" }
            obj += "}"
            return obj
        }
        return "[\(items.joined(separator: ","))]"
    }

    private func constraintsJSON(_ c: RecipeConstraints) -> String {
        var parts: [String] = []
        if let d = c.maxDurationSeconds { parts.append("\"max_duration_seconds\":\(d)") }
        if let r = c.maxRetries { parts.append("\"max_retries\":\(r)") }
        if let a = c.requiresApproval { parts.append("\"requires_approval\":\(a)") }
        return "{\(parts.joined(separator: ","))}"
    }

    private var dummyState: WorldState {
        WorldState(observation: Observation())
    }

    // MARK: - Postcondition Tests

    @Test("Recipe with valid postconditions passes validation")
    func validPostconditions() throws {
        let recipe = try minimalRecipe(postconditions: [
            RecipePostcondition(kind: "element_exists", target: "Submit"),
            RecipePostcondition(kind: "app_frontmost", target: "Finder"),
        ])
        let result = RecipeValidator.validateFull(recipe: recipe, state: dummyState)
        #expect(result.isValid)
        #expect(result.violations.isEmpty)
    }

    @Test("Recipe with empty postcondition kind fails validation")
    func emptyPostconditionKind() throws {
        let recipe = try minimalRecipe(postconditions: [
            RecipePostcondition(kind: "", target: "something"),
        ])
        let result = RecipeValidator.validateFull(recipe: recipe, state: dummyState)
        #expect(!result.isValid)
        #expect(result.violations.contains(where: { $0.contains("empty kind") }))
    }

    @Test("Recipe with unknown postcondition kind fails validation")
    func unknownPostconditionKind() throws {
        let recipe = try minimalRecipe(postconditions: [
            RecipePostcondition(kind: "magic_check", target: "x"),
        ])
        let result = RecipeValidator.validateFull(recipe: recipe, state: dummyState)
        #expect(!result.isValid)
        #expect(result.violations.contains(where: { $0.contains("not a recognised kind") }))
    }

    // MARK: - Constraint Tests

    @Test("Recipe with valid constraints passes validation")
    func validConstraints() throws {
        let recipe = try minimalRecipe(constraints: RecipeConstraints(
            maxDurationSeconds: 60, maxRetries: 3, requiresApproval: true
        ))
        let result = RecipeValidator.validateFull(recipe: recipe, state: dummyState)
        #expect(result.isValid)
    }

    @Test("Recipe with negative duration fails validation")
    func negativeDuration() throws {
        let recipe = try minimalRecipe(constraints: RecipeConstraints(maxDurationSeconds: -1))
        let result = RecipeValidator.validateFull(recipe: recipe, state: dummyState)
        #expect(!result.isValid)
        #expect(result.violations.contains(where: { $0.contains("max_duration_seconds must be positive") }))
    }

    @Test("Recipe with negative retries fails validation")
    func negativeRetries() throws {
        let recipe = try minimalRecipe(constraints: RecipeConstraints(maxRetries: -2))
        let result = RecipeValidator.validateFull(recipe: recipe, state: dummyState)
        #expect(!result.isValid)
        #expect(result.violations.contains(where: { $0.contains("max_retries must be non-negative") }))
    }

    // MARK: - Backward Compatibility

    @Test("Legacy validate() returns Bool for valid recipe")
    func legacyValidateTrue() throws {
        let recipe = try minimalRecipe()
        #expect(RecipeValidator.validate(recipe: recipe, state: dummyState))
    }

    @Test("Bundled recipes still decode with extended schema")
    func bundledRecipesStillDecode() throws {
        let repoRoot = try Self.repositoryRoot()
        let recipesDir = repoRoot.appendingPathComponent("recipes")
        let files = try FileManager.default.contentsOfDirectory(
            at: recipesDir, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        #expect(!files.isEmpty)
        let decoder = OracleJSONCoding.makeDecoder()
        for file in files {
            let data = try Data(contentsOf: file)
            let recipe = try decoder.decode(Recipe.self, from: data)
            #expect(!recipe.name.isEmpty)
            #expect(!recipe.steps.isEmpty)
            // Existing recipes have no postconditions/constraints; that's fine.
            #expect(RecipeValidator.validate(recipe: recipe, state: dummyState))
        }
    }

    // MARK: - Root Finder

    private static func repositoryRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path
            ) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw TestError(message: "Could not find repository root")
    }

    private struct TestError: Error { let message: String }
}
