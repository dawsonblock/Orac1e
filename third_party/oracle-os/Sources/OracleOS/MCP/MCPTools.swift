// MCPTools.swift - MCP tool definitions (names, descriptions, parameter schemas)
//
// All 22 tools defined here. Agent sees these descriptions and schemas.
// Make them excellent - they're the contract between Oracle OS and the agent.

import Foundation

private enum MCPValueKind: String, Encodable {
    case string
    case integer
    case number
    case boolean
    case object
    case array
}

private struct MCPArrayItemSchema: Encodable {
    let type: MCPValueKind
}

private struct MCPPropertySchema: Encodable {
    let type: MCPValueKind
    let description: String
    let items: MCPArrayItemSchema?

    static func scalar(_ kind: MCPValueKind, _ description: String) -> MCPPropertySchema {
        MCPPropertySchema(type: kind, description: description, items: nil)
    }

    static func array(_ kind: MCPValueKind, _ description: String) -> MCPPropertySchema {
        MCPPropertySchema(type: .array, description: description, items: MCPArrayItemSchema(type: kind))
    }
}

private struct MCPToolInputSchema: Encodable {
    let type = MCPValueKind.object
    let properties: [String: MCPPropertySchema]
    let required: [String]?
}

private struct MCPToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: MCPToolInputSchema

    init(
        name: String,
        description: String,
        properties: [String: MCPPropertySchema],
        required: [String] = []
    ) {
        self.name = name
        self.description = description
        self.inputSchema = MCPToolInputSchema(
            properties: properties,
            required: required.isEmpty ? nil : required
        )
    }
}

/// Tool definitions for the MCP server.
public enum MCPTools {

    /// All tool definitions as MCP-compatible dictionaries.
    @MainActor
    public static func definitions() -> [[String: Any]] {
        MCPBoundary.exportDefinitions(from: allDefinitions) ?? []
    }

    @MainActor
    private static var allDefinitions: [MCPToolDefinition] {
        perception + actions + wait + recipes + vision
    }

    // MARK: - Perception Tools (7)

    @MainActor
    private static let perception: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "oracle_context",
            description: "Get orientation for an app. Returns summary fields plus a canonical fused observation snapshot with element source and confidence metadata. Call this before acting on any app.",
            properties: [
                "app": .scalar(.string, "App name to get context for. If omitted, returns focused app."),
            ]
        ),
        MCPToolDefinition(
            name: "oracle_state",
            description: "List all running apps and their windows with titles, positions, and sizes.",
            properties: [
                "app": .scalar(.string, "Filter to a specific app."),
            ]
        ),
        MCPToolDefinition(
            name: "oracle_find",
            description: "Find elements in any app. Returns matching elements with role, name, position, and available actions.",
            properties: [
                "query": .scalar(.string, "Text to search for (matches title, value, identifier, description)."),
                "role": .scalar(.string, "AX role filter (e.g. AXButton, AXTextField, AXLink)."),
                "dom_id": .scalar(.string, "Find by DOM id (web apps, bypasses depth limits)."),
                "dom_class": .scalar(.string, "Find by CSS class."),
                "identifier": .scalar(.string, "Find by AX identifier."),
                "app": .scalar(.string, "Which app to search in."),
                "depth": .scalar(.integer, "Max search depth (default: 25, max: 100)."),
            ]
        ),
        MCPToolDefinition(
            name: "oracle_read",
            description: "Read text content from screen. Returns concatenated text from the element subtree.",
            properties: [
                "app": .scalar(.string, "Which app to read from."),
                "query": .scalar(.string, "Narrow to specific element."),
                "depth": .scalar(.integer, "How deep to read (default: 25)."),
            ]
        ),
        MCPToolDefinition(
            name: "oracle_inspect",
            description: "Full metadata about one element. Call this before acting on something you're unsure about. Returns role, title, position, size, actionable status, supported actions, editable, DOM id, and more.",
            properties: [
                "query": .scalar(.string, "Element to inspect."),
                "role": .scalar(.string, "AX role filter."),
                "dom_id": .scalar(.string, "Find by DOM id."),
                "app": .scalar(.string, "Which app."),
            ],
            required: ["query"]
        ),
        MCPToolDefinition(
            name: "oracle_element_at",
            description: "What element is at this screen position? Bridges screenshots and accessibility tree.",
            properties: [
                "x": .scalar(.number, "X coordinate."),
                "y": .scalar(.number, "Y coordinate."),
            ],
            required: ["x", "y"]
        ),
        MCPToolDefinition(
            name: "oracle_screenshot",
            description: "Take a screenshot for visual debugging. Returns base64 PNG.",
            properties: [
                "app": .scalar(.string, "Screenshot specific app window."),
                "full_resolution": .scalar(.boolean, "Native resolution instead of 1280px resize (default: false)."),
            ]
        ),
    ]

    // MARK: - Action Tools (7)

    @MainActor
    private static let actions: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "oracle_click",
            description: "Click an element. Tries AX-native first, falls back to synthetic click. Risky actions may return pending approval instead of executing immediately.",
            properties: [
                "query": .scalar(.string, "What to click (element text/name)."),
                "role": .scalar(.string, "AX role filter."),
                "dom_id": .scalar(.string, "Click by DOM id."),
                "app": .scalar(.string, "Which app (auto-focuses if needed)."),
                "x": .scalar(.number, "Click at X coordinate instead of element."),
                "y": .scalar(.number, "Click at Y coordinate."),
                "button": .scalar(.string, "left (default), right, or middle."),
                "count": .scalar(.integer, "Click count: 1=single, 2=double, 3=triple."),
                "approval_request_id": .scalar(.string, "Single-use approval token id to resume a previously gated action."),
            ]
        ),
        MCPToolDefinition(
            name: "oracle_type",
            description: "Type text into a field. If 'into' is specified, finds the field first. Risky text entry may require approval before execution.",
            properties: [
                "text": .scalar(.string, "Text to type."),
                "into": .scalar(.string, "Target field name (finds via accessibility). If omitted, types at focus."),
                "dom_id": .scalar(.string, "Target field by DOM id."),
                "app": .scalar(.string, "Which app."),
                "clear": .scalar(.boolean, "Clear field before typing (default: false)."),
                "approval_request_id": .scalar(.string, "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["text"]
        ),
        MCPToolDefinition(
            name: "oracle_press",
            description: "Press a single key. When app is provided, Oracle verifies the target app is frontmost after dispatch.",
            properties: [
                "key": .scalar(.string, "Key name: return, tab, escape, space, delete, up, down, left, right, f1-f12."),
                "modifiers": .array(.string, "Modifier keys: cmd, shift, option, control."),
                "app": .scalar(.string, "Auto-focus this app first (IMPORTANT for synthetic input)."),
                "approval_request_id": .scalar(.string, "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["key"]
        ),
        MCPToolDefinition(
            name: "oracle_hotkey",
            description: "Press a key combination. Modifier keys are auto-cleared afterward. Always include app parameter.",
            properties: [
                "keys": .array(.string, "Key combo, e.g. [\"cmd\", \"return\"] or [\"cmd\", \"shift\", \"p\"]."),
                "app": .scalar(.string, "Auto-focus this app first (IMPORTANT for synthetic input)."),
                "approval_request_id": .scalar(.string, "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["keys"]
        ),
        MCPToolDefinition(
            name: "oracle_scroll",
            description: "Scroll content in a direction.",
            properties: [
                "direction": .scalar(.string, "up, down, left, or right."),
                "amount": .scalar(.integer, "Scroll amount in lines (default: 3)."),
                "app": .scalar(.string, "Auto-focus this app first."),
                "x": .scalar(.number, "Scroll at specific X position."),
                "y": .scalar(.number, "Scroll at specific Y position."),
                "approval_request_id": .scalar(.string, "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["direction"]
        ),
        MCPToolDefinition(
            name: "oracle_focus",
            description: "Bring an app or window to the front. Returns verified success when the requested app becomes frontmost.",
            properties: [
                "app": .scalar(.string, "App name to focus."),
                "window": .scalar(.string, "Window title substring to focus specific window."),
                "approval_request_id": .scalar(.string, "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["app"]
        ),
        MCPToolDefinition(
            name: "oracle_window",
            description: "Window management: minimize, maximize, close, restore, move, resize, or list windows.",
            properties: [
                "action": .scalar(.string, "minimize, maximize, close, restore, move, resize, or list."),
                "app": .scalar(.string, "Target app."),
                "window": .scalar(.string, "Window title (if omitted, acts on frontmost window of app)."),
                "x": .scalar(.number, "X position for move."),
                "y": .scalar(.number, "Y position for move."),
                "width": .scalar(.number, "Width for resize."),
                "height": .scalar(.number, "Height for resize."),
                "approval_request_id": .scalar(.string, "Single-use approval token id to resume a previously gated action."),
            ],
            required: ["action", "app"]
        ),
    ]

    // MARK: - Wait Tool (1)

    @MainActor
    private static let wait: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "oracle_wait",
            description: "Wait for a condition instead of using fixed delays. Polls until condition is met or timeout.",
            properties: [
                "condition": .scalar(.string, "appFrontmost, urlContains, windowTitleContains, titleContains, elementExists, elementGone, urlChanged, titleChanged, focusEquals, valueEquals."),
                "value": .scalar(.string, "Match value. For focusEquals, this is the focused element label/query. For valueEquals, this is the focused element value."),
                "timeout": .scalar(.number, "Max seconds to wait (default: 10)."),
                "interval": .scalar(.number, "Poll interval in seconds (default: 0.5)."),
                "app": .scalar(.string, "App to check against."),
            ],
            required: ["condition"]
        ),
    ]

    // MARK: - Recipe Tools (5)

    @MainActor
    private static let recipes: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "oracle_recipes",
            description: "List all installed recipes with descriptions and parameters. ALWAYS check this first before doing multi-step tasks manually.",
            properties: [:]
        ),
        MCPToolDefinition(
            name: "oracle_run",
            description: "Execute a recipe with parameter substitution. Risky steps pause for approval and can be resumed with resume_token plus approval_request_id.",
            properties: [
                "recipe": .scalar(.string, "Recipe name."),
                "params": .scalar(.object, "Parameter values for substitution."),
                "resume_token": .scalar(.string, "Resume a previously paused recipe run."),
                "approval_request_id": .scalar(.string, "Single-use approval token id to resume a gated recipe step."),
            ],
            required: []
        ),
        MCPToolDefinition(
            name: "oracle_recipe_show",
            description: "View full recipe details: steps, parameters, preconditions.",
            properties: [
                "name": .scalar(.string, "Recipe name."),
            ],
            required: ["name"]
        ),
        MCPToolDefinition(
            name: "oracle_recipe_save",
            description: "Install a new recipe from JSON.",
            properties: [
                "recipe_json": .scalar(.string, "Complete recipe JSON string."),
            ],
            required: ["recipe_json"]
        ),
        MCPToolDefinition(
            name: "oracle_recipe_delete",
            description: "Delete a recipe.",
            properties: [
                "name": .scalar(.string, "Recipe name to delete."),
            ],
            required: ["name"]
        ),
    ]

    // MARK: - Vision Tools (2)

    @MainActor
    private static let vision: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "oracle_parse_screen",
            description: "Experimental full-screen vision parsing via the sidecar. The tool is available, but its schema and reliability are still being hardened. Prefer oracle_find for stable AX queries and oracle_ground for precise visual grounding.",
            properties: [
                "app": .scalar(.string, "Screenshot specific app window."),
                "full_resolution": .scalar(.boolean, "Native resolution instead of 1280px resize (default: false)."),
            ]
        ),
        MCPToolDefinition(
            name: "oracle_ground",
            description: "Find precise screen coordinates for a described UI element using vision (VLM). Use when oracle_find can't locate the element or returns AXGroup elements. Pass a text description of what to click. Requires the vision sidecar to be running.",
            properties: [
                "description": .scalar(.string, "What to find (e.g. 'Compose button', 'Send button', 'search field')."),
                "app": .scalar(.string, "Screenshot specific app window."),
                "crop_box": .array(.number, "Optional crop region [x1, y1, x2, y2] in logical points. Dramatically improves accuracy for overlapping panels (e.g. compose popup over inbox)."),
            ],
            required: ["description"]
        ),
    ]
}
