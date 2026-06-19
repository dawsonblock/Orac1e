import Foundation

public struct BoundaryFix: Sendable {
    public static let strategy = PatchStrategy(
        kind: .boundaryFix,
        description: "Fix off-by-one or boundary condition errors such as array index out of range, string bounds, or loop termination conditions.",
        applicabilitySignals: ["index out of range", "bounds", "overflow", "off-by-one", "subscript", "endIndex"],
        baseCost: 1.2,
        risk: 0.15
    )

    public static func isApplicable(errorSignature: String) -> Bool {
        let lowered = errorSignature.lowercased()
        return strategy.applicabilitySignals.contains { lowered.contains($0) }
    }
}
