// WaitManager.swift - oracle_wait polling implementation
//
// Polls for conditions (urlContains, elementExists, etc.) with timeout.
// Reuses the typed wait contracts in Core/Wait.

import Foundation

/// Polling-based wait for conditions.
@MainActor
public final class WaitManager {

    /// Wait for a condition to be met.
    public static func waitFor(
        condition: String,
        value: String?,
        appName: String?,
        timeout: Double,
        interval: Double
    ) -> ToolResult {
        let typedCondition = WaitCondition.parse(
            condition: condition,
            value: value,
            baseline: baseline(for: condition, appName: appName)
        )

        guard let typedCondition else {
            return ToolResult(
                success: false,
                error: "Unsupported wait condition: \(condition)",
                suggestion: "Use one of: urlContains, titleContains, elementExists, elementGone, urlChanged, titleChanged, focusEquals, valueEquals."
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if WaitEvaluator.isSatisfied(typedCondition, appName: appName) {
                return ToolResult(
                    success: true,
                    data: [
                        "condition": condition,
                        "met": true,
                    ]
                )
            }
            Thread.sleep(forTimeInterval: interval)
        }

        return ToolResult(
            success: false,
            error: "Timed out after \(Int(timeout))s waiting for \(condition)" +
                (value != nil ? " '\(value!)'" : ""),
            suggestion: "Increase timeout or check if the condition can be met. Use oracle_context to see current state."
        )
    }

    private static func baseline(for condition: String, appName: String?) -> String? {
        let observation = ObservationBuilder.capture(appName: appName)
        switch condition {
        case "urlChanged":
            return observation.url
        case "titleChanged":
            return observation.windowTitle
        default:
            return nil
        }
    }
}
