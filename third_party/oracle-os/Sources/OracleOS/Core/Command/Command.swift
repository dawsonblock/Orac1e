import Foundation

public typealias CommandID = UUID

public struct Command: Sendable, Codable {
    public let id: UUID
    public let type: CommandType
    public let payload: CommandPayload
    public let metadata: CommandMetadata

    public init(
        id: UUID = UUID(),
        type: CommandType,
        payload: CommandPayload,
        metadata: CommandMetadata
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.metadata = metadata
    }

    // Backward-compatible command kind string used by legacy validators/telemetry.
    public var kind: String {
        switch payload {
        case .shell(let spec):
            return spec.category.rawValue
        case .ui(let action):
            return action.name
        case .code(let action):
            return action.name
        }
    }
}

public enum CommandType: String, Sendable, Codable {
    case system
    case ui
    case code
}

public enum CommandPayload: Sendable, Codable {
    case shell(CommandSpec)
    case ui(UIAction)
    case code(CodeAction)
}

public struct CommandMetadata: Sendable, Codable {
    public let intentID: UUID
    public let createdAt: Date
    public let source: String
    public let traceTags: [String]

    public init(
        intentID: UUID,
        createdAt: Date = Date(),
        source: String = "unknown",
        traceTags: [String] = []
    ) {
        self.intentID = intentID
        self.createdAt = createdAt
        self.source = source
        self.traceTags = traceTags
    }

    // Backward-compatible initializer/fields retained for transitional call sites.
    public init(
        intentID: UUID,
        planningStrategy: String = "unknown",
        rationale: String = "",
        timestamp: Date = Date(),
        confidence: Double = 1.0
    ) {
        let tags = rationale.isEmpty ? [] : [rationale]
        self.init(intentID: intentID, createdAt: timestamp, source: planningStrategy, traceTags: tags + ["confidence=\(confidence)"])
    }

    public var planningStrategy: String { source }
    public var rationale: String { traceTags.first ?? "" }
    public var timestamp: Date { createdAt }
    public var confidence: Double {
        if let encoded = traceTags.first(where: { $0.hasPrefix("confidence=") }),
           let value = Double(encoded.replacingOccurrences(of: "confidence=", with: ""))
        {
            return value
        }
        return 1.0
    }
}

public struct UIAction: Sendable, Codable {
    public let name: String
    public let app: String?
    public let query: String?
    public let text: String?
    public let role: String?
    public let domID: String?
    public let x: Double?
    public let y: Double?
    public let button: String?
    public let count: Int?
    public let windowTitle: String?
    public let clear: Bool?
    public let modifiers: [String]?
    public let amount: Int?
    public let width: Double?
    public let height: Double?

    public init(
        name: String,
        app: String? = nil,
        query: String? = nil,
        text: String? = nil,
        role: String? = nil,
        domID: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        button: String? = nil,
        count: Int? = nil,
        windowTitle: String? = nil,
        clear: Bool? = nil,
        modifiers: [String]? = nil,
        amount: Int? = nil,
        width: Double? = nil,
        height: Double? = nil
    ) {
        self.name = name
        self.app = app
        self.query = query
        self.text = text
        self.role = role
        self.domID = domID
        self.x = x
        self.y = y
        self.button = button
        self.count = count
        self.windowTitle = windowTitle
        self.clear = clear
        self.modifiers = modifiers
        self.amount = amount
        self.width = width
        self.height = height
    }
}

public struct CodeAction: Sendable, Codable {
    public let name: String
    public let query: String?
    public let filePath: String?
    public let patch: String?
    public let workspacePath: String?
    public let filter: String?
    public let app: String?

    public init(
        name: String,
        query: String? = nil,
        filePath: String? = nil,
        patch: String? = nil,
        workspacePath: String? = nil,
        filter: String? = nil,
        app: String? = nil
    ) {
        self.name = name
        self.query = query
        self.filePath = filePath
        self.patch = patch
        self.workspacePath = workspacePath
        self.filter = filter
        self.app = app
    }
}
