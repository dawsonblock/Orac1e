import Foundation
import Testing
@testable import OracleOS

@Suite("Recipe Compatibility")
struct RecipeCompatibilityTests {

    @Test("Bundled recipes decode with current schema")
    func bundledRecipesDecode() throws {
        let root = try repositoryRoot(from: URL(fileURLWithPath: #filePath))
        let recipesDirectory = root.appendingPathComponent("recipes", isDirectory: true)
        let recipeFiles = try FileManager.default.contentsOfDirectory(
            at: recipesDirectory,
            includingPropertiesForKeys: nil,
            options: []
        )
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        #expect(!recipeFiles.isEmpty)

        let decoder = OracleJSONCoding.makeDecoder()
        for file in recipeFiles {
            let data = try Data(contentsOf: file)
            let recipe = try decoder.decode(Recipe.self, from: data)
            #expect(!recipe.name.isEmpty)
            #expect(!recipe.steps.isEmpty)
        }
    }

    private func repositoryRoot(from fileURL: URL) throws -> URL {
        var current = fileURL.deletingLastPathComponent()
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw OracleError.actionFailed(description: "Could not locate repository root from \(fileURL.path)")
    }
}
