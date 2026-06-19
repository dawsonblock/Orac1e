import Foundation

struct ToolPolicyDecision {
    let allowed: Bool
    let reason: String?
}

final class ToolPolicy {
    func evaluate(manifest: ToolManifest, capability: String) -> ToolPolicyDecision {
        guard manifest.capabilities.contains(capability) else {
            return ToolPolicyDecision(allowed: false, reason: "Tool lacks requested capability")
        }

        switch manifest.riskLevel {
        case .low, .medium:
            return ToolPolicyDecision(allowed: true, reason: nil)
        case .high:
            return ToolPolicyDecision(allowed: false, reason: "High-risk tools are disabled by default")
        }
    }
}
