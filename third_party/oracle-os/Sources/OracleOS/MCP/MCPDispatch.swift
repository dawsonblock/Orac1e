// MCPDispatch.swift - Route MCP tool calls to module functions
//
// Maps tool names to handler functions. Wraps each call in a timeout.
// Formats responses as MCP content arrays.

import Foundation

private struct RecipeParamSummary: Encodable {
    let name: String
    let type: String
    let description: String
    let required: Bool
}

private struct RecipeSummary: Encodable {
    let name: String
    let description: String
    let app: String?
    let params: [RecipeParamSummary]?
}

private struct RecipeListPayload: Encodable {
    let recipes: [RecipeSummary]
    let count: Int
}

private struct RecipeSavedPayload: Encodable {
    let saved: String
}

private struct RecipeDeletedPayload: Encodable {
    let deleted: String
}

private struct RecipeDeletedFailurePayload: Encodable {
    let requestedName: String

    enum CodingKeys: String, CodingKey {
        case requestedName = "requested_name"
    }
}

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
        let request: MCPCallRequest
        do {
            request = try MCPBoundary.decodeCall(from: params)
        } catch {
            return MCPBoundary.errorContent(error.localizedDescription)
        }

        let startTime = DispatchTime.now()
        Log.info("Tool call: \(request.name)")

        // Run the actual tool dispatch with a hard timeout.
        // We use a DispatchWorkItem on a serial queue so the main
        // run-loop stays responsive to cancellation signals.
        let semaphore = DispatchSemaphore(value: 0)
        var response: [String: Any]?
        let work = DispatchWorkItem {
            let result: [String: Any]
            if let specialResult = handleSpecialTool(name: request.name, args: request.arguments) {
                result = specialResult
            } else {
                let toolResult = dispatch(tool: request.name, args: request.arguments)
                result = formatResult(toolResult, toolName: request.name)
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
        let queue = DispatchQueue(label: "oracle.mcp.tool.\(request.name)")
        queue.async(execute: work)

        let deadline = DispatchTime.now() + toolTimeoutSeconds
        let waitResult = semaphore.wait(timeout: deadline)

        // Log timing for every tool call (helps diagnose slow tools)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000

        if waitResult == .timedOut {
            work.cancel()
            Log.error("Tool \(request.name) TIMED OUT after \(Int(toolTimeoutSeconds))s")
            return MCPBoundary.errorContent("Tool \(request.name) timed out after \(Int(toolTimeoutSeconds))s")
        }

        if elapsed > 5000 {
            Log.warn("Tool \(request.name) took \(Int(elapsed))ms (slow)")
        } else {
            Log.info("Tool \(request.name) completed in \(Int(elapsed))ms")
        }

        return response ?? MCPBoundary.errorContent("Tool \(request.name) returned nil response")
    }

    /// Screenshot handler returns MCP image content type for inline display.
    private static func handleScreenshot(_ args: MCPArguments) -> [String: Any] {
        let result = AXScanner.screenshot(
            appName: args.string("app"),
            fullResolution: args.bool("full_resolution") ?? false
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

        return MCPBoundary.encodeImageResult(base64: base64, mimeType: mimeType, caption: caption)
    }

    /// Special handlers stay visibly separate from the normal typed dispatch path.
    /// This checkout only ships screenshot as a public MCP exception; experiment
    /// search remains an internal bounded subsystem, not a public tool surface.
    private static func handleSpecialTool(name: String, args: MCPArguments) -> [String: Any]? {
        switch name {
        case "oracle_screenshot":
            return handleScreenshot(args)
        default:
            return nil
        }
    }

    // MARK: - Dispatch

    private static func dispatch(tool: String, args: MCPArguments) -> ToolResult {
        switch tool {

        // Perception
        case "oracle_context":
            return AXScanner.getContext(appName: args.string("app"))

        case "oracle_state":
            return AXScanner.getState(appName: args.string("app"))

        case "oracle_find":
            return AXScanner.findElements(
                query: args.string("query"),
                role: args.string("role"),
                domId: args.string("dom_id"),
                domClass: args.string("dom_class"),
                identifier: args.string("identifier"),
                appName: args.string("app"),
                depth: args.int("depth")
            )

        case "oracle_read":
            return AXScanner.readContent(
                appName: args.string("app"),
                query: args.string("query"),
                depth: args.int("depth")
            )

        case "oracle_inspect":
            guard let query = args.string("query") else {
                return ToolResult(success: false, error: "Missing required parameter: query")
            }
            return AXScanner.inspect(
                query: query,
                role: args.string("role"),
                domId: args.string("dom_id"),
                appName: args.string("app")
            )

        case "oracle_element_at":
            guard let x = args.double("x"), let y = args.double("y") else {
                return ToolResult(success: false, error: "Missing required parameters: x, y")
            }
            return AXScanner.elementAt(x: x, y: y)

        case "oracle_screenshot":
            return AXScanner.screenshot(
                appName: args.string("app"),
                fullResolution: args.bool("full_resolution") ?? false
            )

        // Actions
        case "oracle_click":
            return FocusManager.withFocusRestore {
                Actions.click(
                    query: args.string("query"),
                    role: args.string("role"),
                    domId: args.string("dom_id"),
                    appName: args.string("app"),
                    x: args.double("x"),
                    y: args.double("y"),
                    button: args.string("button"),
                    count: args.int("count"),
                    runtime: runtime,
                    surface: .mcp,
                    approvalRequestID: args.string("approval_request_id"),
                    toolName: tool
                )
            }

        case "oracle_type":
            guard let text = args.string("text") else {
                return ToolResult(success: false, error: "Missing required parameter: text")
            }
            return FocusManager.withFocusRestore {
                Actions.typeText(
                    text: text,
                    into: args.string("into"),
                    domId: args.string("dom_id"),
                    appName: args.string("app"),
                    clear: args.bool("clear") ?? false,
                    runtime: runtime,
                    surface: .mcp,
                    approvalRequestID: args.string("approval_request_id"),
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
            guard let key = args.string("key") else {
                return ToolResult(success: false, error: "Missing required parameter: key")
            }
            let modifiers = args.stringArray("modifiers")
            return Actions.pressKey(
                key: key,
                modifiers: modifiers,
                appName: args.string("app"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: args.string("approval_request_id"),
                toolName: tool
            )

        case "oracle_hotkey":
            guard let keys = args.stringArray("keys") else {
                return ToolResult(success: false, error: "Missing required parameter: keys (array of strings)")
            }
            return Actions.hotkey(
                keys: keys,
                appName: args.string("app"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: args.string("approval_request_id"),
                toolName: tool
            )

        case "oracle_scroll":
            guard let direction = args.string("direction") else {
                return ToolResult(success: false, error: "Missing required parameter: direction")
            }
            return Actions.scroll(
                direction: direction,
                amount: args.int("amount"),
                appName: args.string("app"),
                x: args.double("x"),
                y: args.double("y"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: args.string("approval_request_id"),
                toolName: tool
            )

        case "oracle_focus":
            guard let app = args.string("app") else {
                return ToolResult(success: false, error: "Missing required parameter: app")
            }
            return Actions.focusApp(
                appName: app,
                windowTitle: args.string("window"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: args.string("approval_request_id"),
                toolName: tool
            )

        case "oracle_window":
            guard let action = args.string("action"),
                  let app = args.string("app")
            else {
                return ToolResult(success: false, error: "Missing required parameters: action, app")
            }
            return Actions.manageWindow(
                action: action,
                appName: app,
                windowTitle: args.string("window"),
                x: args.double("x"),
                y: args.double("y"),
                width: args.double("width"),
                height: args.double("height"),
                runtime: runtime,
                surface: .mcp,
                approvalRequestID: args.string("approval_request_id"),
                toolName: tool
            )

        // Wait
        case "oracle_wait":
            guard let condition = args.string("condition") else {
                return ToolResult(success: false, error: "Missing required parameter: condition")
            }
            return WaitManager.waitFor(
                condition: condition,
                value: args.string("value"),
                appName: args.string("app"),
                timeout: args.double("timeout") ?? 10,
                interval: args.double("interval") ?? 0.5
            )

        // Recipes
        case "oracle_recipes":
            let recipes = RecipeStore.listRecipes()
            let summaries = recipes.map { recipe in
                RecipeSummary(
                    name: recipe.name,
                    description: recipe.description,
                    app: recipe.app,
                    params: recipe.params?.map { key, param in
                        RecipeParamSummary(
                            name: key,
                            type: param.type,
                            description: param.description,
                            required: param.required ?? false
                        )
                    }.sorted { $0.name < $1.name }
                )
            }
            return MCPBoundary.makeToolResult(payload: RecipeListPayload(recipes: summaries, count: summaries.count))

        case "oracle_run":
            if let resumeToken = args.string("resume_token") {
                return RecipeEngine.resume(
                    resumeToken: resumeToken,
                    approvalRequestID: args.string("approval_request_id"),
                    runtime: runtime,
                    taskID: traceRecorder.sessionID
                )
            }

            guard let recipeName = args.string("recipe") else {
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
            let recipeParams = args.stringDictionary("params") ?? [:]

            return RecipeEngine.run(
                recipe: recipe,
                params: recipeParams,
                runtime: runtime,
                taskID: traceRecorder.sessionID
            )

        case "oracle_recipe_show":
            guard let name = args.string("name") else {
                return ToolResult(success: false, error: "Missing required parameter: name")
            }
            guard let recipe = RecipeStore.loadRecipe(named: name) else {
                return ToolResult(
                    success: false,
                    error: "Recipe '\(name)' not found",
                    suggestion: "Use oracle_recipes to list available recipes"
                )
            }
            return MCPBoundary.makeToolResult(payload: recipe)

        case "oracle_recipe_save":
            guard let jsonStr = args.string("recipe_json") else {
                return ToolResult(success: false, error: "Missing required parameter: recipe_json")
            }
            do {
                let name = try RecipeStore.saveRecipeJSON(jsonStr)
                return MCPBoundary.makeToolResult(payload: RecipeSavedPayload(saved: name))
            } catch {
                return ToolResult(success: false, error: "Failed to save recipe: \(error)")
            }

        case "oracle_recipe_delete":
            guard let name = args.string("name") else {
                return ToolResult(success: false, error: "Missing required parameter: name")
            }
            let deleted = RecipeStore.deleteRecipe(named: name)
            if deleted {
                return MCPBoundary.makeToolResult(payload: RecipeDeletedPayload(deleted: name))
            }
            return MCPBoundary.makeToolResult(
                success: false,
                payload: RecipeDeletedFailurePayload(requestedName: name),
                error: "Recipe '\(name)' not found"
            )

        // Vision
        case "oracle_parse_screen":
            return VisionScanner.parseScreen(
                appName: args.string("app"),
                fullResolution: args.bool("full_resolution") ?? false
            )

        case "oracle_ground":
            guard let description = args.string("description") else {
                return ToolResult(success: false, error: "Missing required parameter: description")
            }
            let cropBox = args.numberArray("crop_box")
            return VisionScanner.groundElement(
                description: description,
                appName: args.string("app"),
                cropBox: cropBox
            )

        default:
            return ToolResult(success: false, error: "Unknown tool: \(tool)")
        }
    }

    // MARK: - Response Formatting

    /// Format a ToolResult as MCP content array.
    private static func formatResult(_ result: ToolResult, toolName: String) -> [String: Any] {
        MCPBoundary.encodeResult(result, toolName: toolName)
    }

    static func errorContent(_ message: String) -> [String: Any] {
        MCPBoundary.errorContent(message)
    }
}
