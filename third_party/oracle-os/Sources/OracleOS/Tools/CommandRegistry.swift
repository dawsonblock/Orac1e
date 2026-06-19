import Foundation

public struct ToolCommandRegistry {
    public init() {}

    public func defaultCommands() -> [ToolCommandSpec] {
        [
            ToolCommandSpec(family: .app, name: "launch"),
            ToolCommandSpec(family: .window, name: "focus"),
            ToolCommandSpec(family: .menu, name: "select"),
            ToolCommandSpec(family: .dialog, name: "dismiss"),
            ToolCommandSpec(family: .click, name: "semantic_click"),
            ToolCommandSpec(family: .type, name: "semantic_type"),
            ToolCommandSpec(family: .hotkey, name: "press"),
            ToolCommandSpec(family: .capture, name: "snapshot"),
            ToolCommandSpec(family: .shell, name: "run"),
            ToolCommandSpec(family: .workflow, name: "replay"),
            ToolCommandSpec(family: .graphInspect, name: "inspect_graph"),
            ToolCommandSpec(family: .memoryInspect, name: "inspect_memory"),
        ]
    }
}
