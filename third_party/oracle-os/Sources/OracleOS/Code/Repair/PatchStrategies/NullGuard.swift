import Foundation

public struct NullGuard: Sendable {
    public static let strategy = PatchStrategy(
        kind: .nullGuard,
        description: "Add nil/null checks or optional unwrapping guards to prevent force-unwrap crashes or nil reference errors.",
        applicabilitySignals: ["nil", "null", "unwrap", "force unwrap", "unexpectedly found nil", "optional"],
        baseCost: 0.8,
        risk: 0.08
    )

    public static func isApplicable(errorSignature: String) -> Bool {
        let lowered = errorSignature.lowercased()
        return strategy.applicabilitySignals.contains { lowered.contains($0) }
    }
}
