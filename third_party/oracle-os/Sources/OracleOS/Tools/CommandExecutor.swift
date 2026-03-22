import Foundation

@MainActor
public final class ToolCommandExecutor {
    private let runtime: RuntimeOrchestrator
    private let automationHost: AutomationHost

    public init(runtime: RuntimeOrchestrator, automationHost: AutomationHost) {
        self.runtime = runtime
        self.automationHost = automationHost
    }

    public func execute(_ command: ToolCommandSpec) -> ToolResult {
        switch (command.family, command.name) {
        case (.app, "launch"):
            return Actions.focusApp(
                appName: command.arguments["app"] ?? "",
                runtime: runtime,
                surface: .controller,
                toolName: "tool_app_launch"
            )
        case (.window, "focus"):
            return Actions.focusApp(
                appName: command.arguments["app"] ?? "",
                windowTitle: command.arguments["window"],
                runtime: runtime,
                surface: .controller,
                toolName: "tool_window_focus"
            )
        case (.click, "semantic_click"):
            return Actions.click(
                query: command.arguments["query"],
                role: command.arguments["role"],
                domId: command.arguments["dom_id"],
                appName: command.arguments["app"],
                x: nil,
                y: nil,
                button: nil,
                count: nil,
                runtime: runtime,
                surface: .controller,
                toolName: "tool_semantic_click"
            )
        case (.type, "semantic_type"):
            return Actions.typeText(
                text: command.arguments["text"] ?? "",
                into: command.arguments["query"],
                domId: command.arguments["dom_id"],
                appName: command.arguments["app"],
                clear: false,
                runtime: runtime,
                surface: .controller,
                toolName: "tool_semantic_type"
            )
        case (.capture, "snapshot"):
            let snapshot = automationHost.snapshots.captureSnapshot(appName: command.arguments["app"])
            return ToolResult(
                success: true,
                data: [
                    "snapshot_id": snapshot.snapshotID,
                    "active_app": snapshot.activeApplication?.localizedName as Any,
                    "window_count": snapshot.windows.count,
                    "dialog_title": snapshot.dialog?.title as Any,
                ]
            )
        default:
            return ToolResult(
                success: false,
                error: "Unsupported tool command \(command.family.rawValue):\(command.name)"
            )
        }
    }
}
