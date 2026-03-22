import Foundation

public struct ConfigFix: Sendable {
    public static let strategy = PatchStrategy(
        kind: .configurationFix,
        description: "Fix configuration file errors such as incorrect build settings, missing environment variables, or malformed config values.",
        applicabilitySignals: ["config", "configuration", "setting", "environment", "variable", "plist", "json", "yaml"],
        baseCost: 1.0,
        risk: 0.12
    )

    public static func isApplicable(errorSignature: String) -> Bool {
        let lowered = errorSignature.lowercased()
        return strategy.applicabilitySignals.contains { lowered.contains($0) }
    }
}
