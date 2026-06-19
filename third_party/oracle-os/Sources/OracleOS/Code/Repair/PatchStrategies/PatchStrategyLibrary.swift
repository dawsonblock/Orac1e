import Foundation

public struct PatchStrategyLibrary: Sendable {
    public static let shared = PatchStrategyLibrary()

    public let strategies: [PatchStrategy]

    public init(strategies: [PatchStrategy]? = nil) {
        self.strategies = strategies ?? Self.defaultStrategies
    }

    public func applicable(
        for errorSignature: String,
        snapshot: RepositorySnapshot?
    ) -> [PatchStrategy] {
        let lowered = errorSignature.lowercased()
        return strategies.filter { strategy in
            strategy.applicabilitySignals.contains { signal in
                lowered.contains(signal.lowercased())
            }
        }
        .sorted { $0.baseCost < $1.baseCost }
    }

    public func strategy(for kind: PatchStrategyKind) -> PatchStrategy? {
        strategies.first { $0.kind == kind }
    }

    private static let defaultStrategies: [PatchStrategy] = [
        PatchStrategy(
            kind: .boundaryFix,
            description: "Fix off-by-one or boundary condition errors",
            applicabilitySignals: [
                "index out of range", "bounds", "off-by-one", "overflow",
                "underflow", "array index", "out of bounds",
            ],
            baseCost: 0.8,
            risk: 0.1
        ),
        PatchStrategy(
            kind: .nullGuard,
            description: "Add nil/null guards to prevent crashes",
            applicabilitySignals: [
                "nil", "null", "unexpectedly found nil", "optional",
                "unwrap", "force unwrap", "NullPointerException",
            ],
            baseCost: 0.6,
            risk: 0.05
        ),
        PatchStrategy(
            kind: .typeCorrection,
            description: "Fix type mismatches and conversion errors",
            applicabilitySignals: [
                "type mismatch", "cannot convert", "incompatible types",
                "expected type", "cast", "coerce", "type error",
            ],
            baseCost: 1.0,
            risk: 0.12
        ),
        PatchStrategy(
            kind: .dependencyUpdate,
            description: "Update dependency versions or imports",
            applicabilitySignals: [
                "dependency", "import", "module not found", "package",
                "version", "resolve", "no such module",
            ],
            baseCost: 1.5,
            risk: 0.2
        ),
        PatchStrategy(
            kind: .testExpectationUpdate,
            description: "Update test assertions to match changed behavior",
            applicabilitySignals: [
                "assertion failed", "expected", "XCTAssert", "#expect",
                "test failed", "not equal", "mismatch",
            ],
            baseCost: 0.7,
            risk: 0.08
        ),
        PatchStrategy(
            kind: .configurationFix,
            description: "Fix configuration or environment settings",
            applicabilitySignals: [
                "configuration", "config", "environment", "setting",
                "permission", "entitlement", "plist",
            ],
            baseCost: 0.9,
            risk: 0.15
        ),
    ]
}
