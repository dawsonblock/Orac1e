// MCPDispatch.swift - Route MCP tool calls to module functions
//
// Maps tool names to handler functions. Wraps each call in a timeout.
// Formats responses as MCP content arrays.

import Foundation

/// Routes MCP tool calls to the appropriate module function.
@MainActor
public enum MCPDispatch {

    /// Per-tool-call timeout. Most tools complete in <2s; deep AX tree walks
    /// can take 10-20s for Chrome. 60s is the absolute ceiling — if a tool takes
    /// longer than this, the MCP server was effectively stuck.
    private static let toolTimeoutSeconds: TimeInterval = 60
    private static let traceRecorder = TraceRecorder()
    private static let traceStore = ExperienceStore()
    private static let failureArtifactWriter = FailureArtifactWriter()
    private static let runtimeContext = RuntimeContext.live(
        traceRecorder: traceRecorder,
        traceStore: traceStore,
        artifactWriter: failureArtifactWriter
    )
    private static let eventStore = EventStore()
    private static let commitCoordinator = CommitCoordinator(eventStore: eventStore, reducers: DefaultReducers.make())
    private static let runtime = RuntimeOrchestrator(
        eventStore: eventStore,
        commitCoordinator: commitCoordinator,
        policyEngine: runtimeContext.policyEngine,
        automationHost: runtimeContext.automationHost,
        workspaceRunner: runtimeContext.workspaceRunner,
        repositoryIndexer: runtimeContext.repositoryIndexer
    )

    /// Handle a tools/call request. Returns MCP-formatted result.
    /// Wraps every tool call in a timeout so no single tool can block
    /// the MCP server indefinitely (the #1 user-reported issue).
    public static func handle(_ params: [String: Any]) -> [String: Any] {
        guard let toolName = params["name"] as? String else {
            return errorContent("Missing tool name")
        }

        let args = params["arguments"] as? [String: Any] ?? [:]
        let startTime = DispatchTime.now()
        Log.info("Tool call: \(toolName)")

        // Run the actual tool dispatch with a hard timeout.
        // We use a DispatchWorkItem on a serial queue so the main
        // run-loop stays responsive to cancellation signals.
        let semaphore = DispatchSemaphore(value: 0)
        var response: [String: Any]?
        let work = DispatchWorkItem { [args] in
            let result: [String: Any]
            if toolName == "oracle_screenshot" {
                result = handleScreenshot(args)
            } else {
                let toolResult = dispatch(tool: toolName, args: args)
                result = formatResult(toolResult, toolName: toolName)
            }
            response = result
            semaphore.signal()
        }

        // Dispatch onto a dedicated queue so we can enforce the timeout.
        // NOTE: @MainActor methods called inside dispatch() will hop back
        // to the main actor automatically — we are only using the queue
        // as a timeout-enforcing wrapper, not to change isolation.
        // This pattern is intentional: we need hard timeouts to prevent
        // stuck tools from blocking the MCP server, which is the #1
        // user-reported issue.
        let queue = DispatchQueue(label: "oracle.mcp.tool.\(toolName)")
        queue.async(execute: work)

        let deadline = DispatchTime.now() + toolTimeoutSeconds
        let waitResult = semaphore.wait(timeout: deadline)

        // Log timing for every tool call (helps diagnose slow tools)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000

        if waitResult == .timedOut {
            work.cancel()
            Log.error("Tool \(toolName) TIMED OUT after \(Int(toolTimeoutSeconds))s")
            return errorContent("Tool \(toolName) timed out after \(Int(toolTimeoutSeconds))s")
        }

        if elapsed > 5000 {
            Log.warn("Tool \(toolName) took \(Int(elapsed))ms (slow)")
        } else {
            Log.info("Tool \(toolName) completed in \(Int(elapsed))ms")
        }

        return response ?? errorContent("Tool \(toolName) returned nil response")
    }

    /// Screenshot handler returns MCP image content type for inline display.
    private static func handleScreenshot(_ args: [String: Any]) -> [String: Any] {
        let result = AXScanner.screenshot(
            appName: str(args, "app"),
            fullResolution: bool(args, "full_resolution") ?? false
        )

        guard result.success,
              let data = result.data,
              let base64 = data["image"] as? String
        else {
            return formatResult(result, toolName: "oracle_screenshot")
        }

        // Return as MCP image + text caption (v1 pattern: both content types)
        let mimeType = data["mime_type"] as? String ?? "image/png"
        let width = data["width"] as? Int ?? 0
        let height = data["height"] as? Int ?? 0
        let windowTitle = data["window_title"] as? String ?? ""
        var caption = "Screenshot: \(width)x\(height)"
        if !windowTitle.isEmpty { caption += " - \(windowTitle)" }

        return [
            "content": [
                [
                    "type": "image",
                    "data": base64,
                    "mimeType": mimeType,
                ] as [String: Any],
                [
                    "type": "text",
                    "text": caption,
                ] as [String: Any],
            ] as [[String: Any]],
            "isError": false,
        ]
    }

    // MARK: - Dispatch

    private static func dispatch(tool: String, args: [String: Any]) -> ToolResult {
        switch tool {

        // Perception
        case "oracle_context":
            return AXScanner.getContext(appName: str(args, "app"))

        case "oracle_state":
            return AXScanner.getState(appName: str(args, "app"))

        case "oracle_find":
            return AXScanner.findElements(
                query: str(args, "query"),
                role: str(args, "role"),
                domId: str(args, "dom_id"),
                domClass: str(args, "dom_class"),
                identifier: str(args, "identifier"),
                appName: str(args, "app"),
                depth: int(args, "depth")
            )

        case "oracle_read":
            return AXScanner.readContent(
                appName: str(args, "app"),
                query: str(args, "query"),
                depth: int(args, "depth")
            )

        case "oracle_inspect":
            guard let query = str(args, "query") else {
                return ToolResult(success: false, error: "Missing required parameter: query")
            }
            return AXScanner.inspect(
                query: query,
                role: str(args, "role"),
                domId: str(args, "dom_id"),
                appName: str(args, "app")
            )

        case "oracle_element_at":
            guard let x = double(args, "x"), let y = double(args, "y") else {
                return ToolResult(success: false, error: "Missing required parameters: x, y")
            }
            return AXScanner.elementAt(x: x, y: y)

        case "oracle_screenshot":
            return AXScanner.screenshot(
                appName: str(args, "app"),
                fullResolution: bool(args, "full_resolution") ?? false
            )

        // Actions
        case "oracle_click":
            return FocusManager.withFocusRestore {
                Actions.click(
                    query: str(args, "query"),
                    role: str(args, "role"),
                    domId: str(args, "dom_id"),
                    appName: str(args, "app"),
                    x: double(args, "x"),
                    y: double(args, "y"),
                    button: str(args, "button"),
                    count: int(args, "count"),
                    runtime: runtime,
                    surface: .mcp,
                    approvalRequestID: str(args, "approval_request_id"),
                    toolName: tool
                )
            }

        case "oracle_type":
            guard let text = str(args, "text") else {
                return ToolResult(success: false, error: "Missing required parameter: text")
            }
            return FocusManager.withFocusRestore {
                Actions.typeText(
                    text: text,
                    into: str(args, "into"),
                    domId: str(args, "dom_id"),
                    appName: str(args, "app"),
                    clear: bool(args, "clear") ?? false,
                    runtime: runtime,
                    surface: .mcp,
                    approvalRequestID: str(args, "approval_request_id"),
                    toolName: tool
                )
            }

        // Press, hotkey, scroll are synthetic input tools that send events to the
        // FRONTMOST app. They need the target app to STAY focused after the tool
        // returns - the agent will call oracle_focus to restore when ready.
        // Do NOT wrap these in withFocusRestore, which would steal focus back
        // before the app processes the event (e.g. Cmd+L needs Chrome to stay
        // focused while it selects the address bar text).
        case "oracle_press":
            guard let key = str(args, "key") else {
                return ToolResult(success: false, error: "Missing required parameter: key")
            }
            let modifiers = (args["modifiers"] as? [String])
            return Actions.pressKey(
                key: key,
                modifiers: modifiers,
                appName: str(args, "app"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: str(args, "approval_request_id"),
                toolName: tool
            )

        case "oracle_hotkey":
            guard let keys = args["keys"] as? [String] else {
                return ToolResult(success: false, error: "Missing required parameter: keys (array of strings)")
            }
            return Actions.hotkey(
                keys: keys,
                appName: str(args, "app"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: str(args, "approval_request_id"),
                toolName: tool
            )

        case "oracle_scroll":
            guard let direction = str(args, "direction") else {
                return ToolResult(success: false, error: "Missing required parameter: direction")
            }
            return Actions.scroll(
                direction: direction,
                amount: int(args, "amount"),
                appName: str(args, "app"),
                x: double(args, "x"),
                y: double(args, "y"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: str(args, "approval_request_id"),
                toolName: tool
            )

        case "oracle_focus":
            guard let app = str(args, "app") else {
                return ToolResult(success: false, error: "Missing required parameter: app")
            }
            return Actions.focusApp(
                appName: app,
                windowTitle: str(args, "window"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: str(args, "approval_request_id"),
                toolName: tool
            )

        case "oracle_window":
            guard let action = str(args, "action"),
                  let app = str(args, "app")
            else {
                return ToolResult(success: false, error: "Missing required parameters: action, app")
            }
            return Actions.manageWindow(
                action: action,
                appName: app,
                windowTitle: str(args, "window"),
                x: double(args, "x"),
                y: double(args, "y"),
                width: double(args, "width"),
                height: double(args, "height"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: str(args, "approval_request_id"),
                toolName: tool
            )

        // Wait
        case "oracle_wait":
            guard let condition = str(args, "condition") else {
                return ToolResult(success: false, error: "Missing required parameter: condition")
            }
            return WaitManager.waitFor(
                condition: condition,
                value: str(args, "value"),
                appName: str(args, "app"),
                timeout: double(args, "timeout") ?? 10,
                interval: double(args, "interval") ?? 0.5
            )

        // Recipes
        case "oracle_recipes":
            let recipes = RecipeStore.listRecipes()
            let summaries: [[String: Any]] = recipes.map { recipe in
                var summary: [String: Any] = [
                    "name": recipe.name,
                    "description": recipe.description,
                ]
                if let app = recipe.app { summary["app"] = app }
                if let params = recipe.params {
                    summary["params"] = params.map { key, param in
                        ["name": key, "type": param.type, "description": param.description,
                         "required": param.required ?? false] as [String: Any]
                    }
                }
                return summary
            }
            return ToolResult(success: true, data: ["recipes": summaries, "count": summaries.count])

        case "oracle_run":
            if let resumeToken = str(args, "resume_token") {
                return RecipeEngine.resume(
                    resumeToken: resumeToken,
                    approvalRequestID: str(args, "approval_request_id"),
                    runtime: runtime,
                    taskID: traceRecorder.sessionID
                )
            }

            guard let recipeName = str(args, "recipe") else {
                return ToolResult(success: false, error: "Missing required parameter: recipe or resume_token")
            }
            guard let recipe = RecipeStore.loadRecipe(named: recipeName) else {
                return ToolResult(
                    success: false,
                    error: "Recipe '\(recipeName)' not found",
                    suggestion: "Use oracle_recipes to list available recipes"
                )
            }
            // Parse params from the MCP arguments
            let recipeParams: [String: String]
            if let paramsObj = args["params"] as? [String: Any] {
                recipeParams = paramsObj.reduce(into: [:]) { result, pair in
                    result[pair.key] = "\(pair.value)"
                }
            } else {
                recipeParams = [:]
            }

            return RecipeEngine.run(
                recipe: recipe,
                params: recipeParams,
                runtime: runtime,
                taskID: traceRecorder.sessionID
            )

        case "oracle_recipe_show":
            guard let name = str(args, "name") else {
                return ToolResult(success: false, error: "Missing required parameter: name")
            }
            guard let recipe = RecipeStore.loadRecipe(named: name) else {
                return ToolResult(
                    success: false,
                    error: "Recipe '\(name)' not found",
                    suggestion: "Use oracle_recipes to list available recipes"
                )
            }
            if let data = try? JSONEncoder().encode(recipe),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                return ToolResult(success: true, data: dict)
            }
            return ToolResult(success: false, error: "Failed to serialize recipe")

        case "oracle_recipe_save":
            guard let jsonStr = str(args, "recipe_json") else {
                return ToolResult(success: false, error: "Missing required parameter: recipe_json")
            }
            do {
                let name = try RecipeStore.saveRecipeJSON(jsonStr)
                return ToolResult(success: true, data: ["saved": name])
            } catch {
                return ToolResult(success: false, error: "Failed to save recipe: \(error)")
            }

        case "oracle_recipe_delete":
            guard let name = str(args, "name") else {
                return ToolResult(success: false, error: "Missing required parameter: name")
            }
            let deleted = RecipeStore.deleteRecipe(named: name)
            return ToolResult(
                success: deleted,
                data: deleted ? ["deleted": name] : nil,
                error: deleted ? nil : "Recipe '\(name)' not found"
            )

        // Vision
        case "oracle_parse_screen":
            return VisionScanner.parseScreen(
                appName: str(args, "app"),
                fullResolution: bool(args, "full_resolution") ?? false
            )

        case "oracle_ground":
            guard let description = str(args, "description") else {
                return ToolResult(success: false, error: "Missing required parameter: description")
            }
            let cropBox: [Double]?
            if let arr = args["crop_box"] as? [Any] {
                cropBox = arr.compactMap { val -> Double? in
                    if let d = val as? Double { return d }
                    if let i = val as? Int { return Double(i) }
                    return nil
                }
            } else {
                cropBox = nil
            }
            return VisionScanner.groundElement(
                description: description,
                appName: str(args, "app"),
                cropBox: cropBox
            )

        default:
            return ToolResult(success: false, error: "Unknown tool: \(tool)")
        }
    }

    // MARK: - Response Formatting

    /// Format a ToolResult as MCP content array.
    private static func formatResult(_ result: ToolResult, toolName: String) -> [String: Any] {
        let dict = result.toDict()

        // Serialize to JSON string for MCP text content
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
           let jsonStr = String(data: data, encoding: .utf8)
        {
            return [
                "content": [
                    ["type": "text", "text": jsonStr],
                ],
                "isError": !result.success,
            ]
        }

        return errorContent("Failed to serialize response for \(toolName)")
    }

    static func errorContent(_ message: String) -> [String: Any] {
        [
            "content": [
                ["type": "text", "text": "{\"success\":false,\"error\":\"\(message)\"}"],
            ],
            "isError": true,
        ]
    }

    // MARK: - Parameter Helpers

    private static func str(_ args: [String: Any], _ key: String) -> String? {
        args[key] as? String
    }

    private static func int(_ args: [String: Any], _ key: String) -> Int? {
        if let i = args[key] as? Int { return i }
        if let d = args[key] as? Double { return Int(d) }
        return nil
    }

    private static func double(_ args: [String: Any], _ key: String) -> Double? {
        if let d = args[key] as? Double { return d }
        if let i = args[key] as? Int { return Double(i) }
        return nil
    }

    private static func bool(_ args: [String: Any], _ key: String) -> Bool? {
        args[key] as? Bool
    }
}
