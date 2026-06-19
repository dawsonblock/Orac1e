public struct ActionIntent: Sendable, Codable, Equatable {
    public let agentKind: AgentKind
    public let app: String
    public let name: String
    public let action: String
    public let query: String?
    public let text: String?
    public let role: String?
    public let domID: String?
    public let x: Double?
    public let y: Double?
    public let button: String?
    public let count: Int?
    public let modifiers: [String]?
    public let amount: Int?
    public let windowTitle: String?
    public let clear: Bool?
    public let width: Double?
    public let height: Double?
    public let workspaceRoot: String?
    public let workspaceRelativePath: String?
    public let codeCommand: CommandSpec?
    public let postconditions: [Postcondition]

    public var elementID: String? { domID }
    public var targetQuery: String? { query }
    public var domain: String { agentKind == .code ? "code" : "os" }
    public var commandCategory: String? { codeCommand?.category.rawValue }
    public var commandSummary: String? { codeCommand?.summary }

    public init(
        agentKind: AgentKind = .os,
        app: String,
        name: String? = nil,
        action: String,
        query: String? = nil,
        text: String? = nil,
        role: String? = nil,
        domID: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        button: String? = nil,
        count: Int? = nil,
        modifiers: [String]? = nil,
        amount: Int? = nil,
        windowTitle: String? = nil,
        clear: Bool? = nil,
        width: Double? = nil,
        height: Double? = nil,
        workspaceRoot: String? = nil,
        workspaceRelativePath: String? = nil,
        codeCommand: CommandSpec? = nil,
        postconditions: [Postcondition] = []
    ) {
        self.agentKind = agentKind
        self.app = app
        self.name = name ?? "\(action) \(query ?? "")"
        self.action = action
        self.query = query
        self.text = text
        self.role = role
        self.domID = domID
        self.x = x
        self.y = y
        self.button = button
        self.count = count
        self.modifiers = modifiers
        self.amount = amount
        self.windowTitle = windowTitle
        self.clear = clear
        self.width = width
        self.height = height
        self.workspaceRoot = workspaceRoot ?? codeCommand?.workspaceRoot
        self.workspaceRelativePath = workspaceRelativePath ?? codeCommand?.workspaceRelativePath
        self.codeCommand = codeCommand
        self.postconditions = postconditions
    }
    public static func click(
        app: String?,
        query: String? = nil,
        role: String? = nil,
        domID: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        button: String? = nil,
        count: Int? = nil,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            agentKind: .os,
            app: app ?? "",
            name: "click \(query ?? domID ?? "")",
            action: "click",
            query: query,
            text: nil,
            role: role,
            domID: domID,
            x: x,
            y: y,
            button: button,
            count: count,
            postconditions: postconditions
        )
    }

    public static func type(
        app: String?,
        into: String? = nil,
        domID: String? = nil,
        text: String,
        clear: Bool = false,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            agentKind: .os,
            app: app ?? "",
            name: "type into \(into ?? domID ?? "")",
            action: "type",
            query: into,
            text: text,
            domID: domID,
            clear: clear,
            postconditions: postconditions
        )
    }

    public static func focus(
        app: String,
        windowTitle: String? = nil,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            agentKind: .os,
            app: app,
            name: "focus \(app)",
            action: "focus",
            query: windowTitle ?? app,
            text: nil,
            windowTitle: windowTitle,
            postconditions: postconditions
        )
    }

    public static func press(
        app: String?,
        key: String,
        modifiers: [String]? = nil,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            agentKind: .os,
            app: app ?? "",
            name: "press \(modifiers.map { $0.joined(separator: "+") + "+" } ?? "")\(key)",
            action: "press",
            query: key,
            text: nil,
            role: modifiers?.joined(separator: "+"),
            modifiers: modifiers,
            postconditions: postconditions
        )
    }

    public static func hotkey(
        app: String?,
        keys: [String],
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            agentKind: .os,
            app: app ?? "",
            name: "hotkey \(keys.joined(separator: "+"))",
            action: "hotkey",
            query: keys.joined(separator: "+"),
            modifiers: keys,
            postconditions: postconditions
        )
    }

    public static func scroll(
        app: String?,
        direction: String,
        amount: Int?,
        x: Double? = nil,
        y: Double? = nil,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            agentKind: .os,
            app: app ?? "",
            name: "scroll \(direction)",
            action: "scroll",
            query: direction,
            x: x,
            y: y,
            amount: amount,
            postconditions: postconditions
        )
    }

    public static func manageWindow(
        app: String,
        action: String,
        windowTitle: String?,
        x: Double?,
        y: Double?,
        width: Double?,
        height: Double?,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            agentKind: .os,
            app: app,
            name: "window \(action)",
            action: "manageWindow",
            query: action,
            x: x,
            y: y,
            windowTitle: windowTitle,
            width: width,
            height: height,
            postconditions: postconditions
        )
    }

    public static func code(
        name: String? = nil,
        command: CommandSpec,
        workspaceRelativePath: String? = nil,
        text: String? = nil,
        postconditions: [Postcondition] = []
    ) -> ActionIntent {
        ActionIntent(
            agentKind: .code,
            app: "Workspace",
            name: name ?? command.summary,
            action: command.category.rawValue,
            query: workspaceRelativePath ?? command.workspaceRelativePath,
            text: text,
            workspaceRoot: command.workspaceRoot,
            workspaceRelativePath: workspaceRelativePath ?? command.workspaceRelativePath,
            codeCommand: command,
            postconditions: postconditions
        )
    }

    /// Create an ``ActionIntent`` from an ``ActionSchema``.
    ///
    /// Used by the search-centric runtime loop to convert search
    /// candidates back into executable intents. The `app` field
    /// defaults to `"unknown"` because schema-level actions do not
    /// carry app context; the runtime resolves the actual app name
    /// from the current observation before execution.
    public static func fromSchema(_ schema: ActionSchema, app: String = "unknown") -> ActionIntent {
        ActionIntent(
            agentKind: schema.kind.isCodeAction ? .code : .os,
            app: app,
            name: schema.name,
            action: schema.kind.rawValue,
            query: schema.name,
            text: schema.name
        )
    }
}
