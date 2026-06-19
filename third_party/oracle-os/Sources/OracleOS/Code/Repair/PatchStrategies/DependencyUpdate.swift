import Foundation

public struct DependencyUpdate: Sendable {
    public static let strategy = PatchStrategy(
        kind: .dependencyUpdate,
        description: "Update dependency versions, resolve version conflicts, or fix import/module resolution issues.",
        applicabilitySignals: ["dependency", "version", "import", "module", "package", "resolution"],
        baseCost: 2.0,
        risk: 0.25
    )

    public static func isApplicable(errorSignature: String) -> Bool {
        let lowered = errorSignature.lowercased()
        return strategy.applicabilitySignals.contains { lowered.contains($0) }
    }
}
