import Foundation

public struct TypeCorrection: Sendable {
    public static let strategy = PatchStrategy(
        kind: .typeCorrection,
        description: "Fix type mismatches, incorrect casts, or protocol conformance issues.",
        applicabilitySignals: ["type", "cast", "cannot convert", "protocol", "conformance", "mismatch"],
        baseCost: 1.5,
        risk: 0.18
    )

    public static func isApplicable(errorSignature: String) -> Bool {
        let lowered = errorSignature.lowercased()
        return strategy.applicabilitySignals.contains { lowered.contains($0) }
    }
}
