import Foundation

public struct CriterionDocument: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var attribute: String
    public var value: String
    public var matchType: String?

    public init(id: UUID = UUID(), attribute: String, value: String, matchType: String? = nil) {
        self.id = id
        self.attribute = attribute
        self.value = value
        self.matchType = matchType
    }
}

public struct LocatorDocument: Codable, Sendable, Equatable {
    public var criteria: [CriterionDocument]
    public var computedNameContains: String?

    public init(criteria: [CriterionDocument] = [], computedNameContains: String? = nil) {
        self.criteria = criteria
        self.computedNameContains = computedNameContains
    }
}

public struct RecipeParamDocument: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var type: String
    public var description: String
    public var required: Bool

    public init(id: String, type: String, description: String, required: Bool) {
        self.id = id
        self.type = type
        self.description = description
        self.required = required
    }
}

public struct RecipePreconditionsDocument: Codable, Sendable, Equatable {
    public var appRunning: String?
    public var urlContains: String?

    public init(appRunning: String? = nil, urlContains: String? = nil) {
        self.appRunning = appRunning
        self.urlContains = urlContains
    }
}

public struct RecipeWaitConditionDocument: Codable, Sendable, Equatable {
    public var condition: String
    public var target: LocatorDocument?
    public var value: String?
    public var timeout: Double?

    public init(condition: String, target: LocatorDocument? = nil, value: String? = nil, timeout: Double? = nil) {
        self.condition = condition
        self.target = target
        self.value = value
        self.timeout = timeout
    }
}

public struct RecipeStepDocument: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var action: String
    public var target: LocatorDocument?
    public var params: [String: String]?
    public var waitAfter: RecipeWaitConditionDocument?
    public var note: String?
    public var onFailure: String?

    public init(
        id: Int,
        action: String,
        target: LocatorDocument? = nil,
        params: [String: String]? = nil,
        waitAfter: RecipeWaitConditionDocument? = nil,
        note: String? = nil,
        onFailure: String? = nil
    ) {
        self.id = id
        self.action = action
        self.target = target
        self.params = params
        self.waitAfter = waitAfter
        self.note = note
        self.onFailure = onFailure
    }
}

public struct RecipeDocument: Codable, Sendable, Equatable, Identifiable {
    public var schemaVersion: Int
    public var name: String
    public var description: String
    public var app: String?
    public var params: [String: RecipeParamDocument]?
    public var preconditions: RecipePreconditionsDocument?
    public var steps: [RecipeStepDocument]
    public var onFailure: String?
    public var rawJSON: String?

    public var id: String { name }

    public init(
        schemaVersion: Int = 2,
        name: String,
        description: String,
        app: String? = nil,
        params: [String: RecipeParamDocument]? = nil,
        preconditions: RecipePreconditionsDocument? = nil,
        steps: [RecipeStepDocument],
        onFailure: String? = nil,
        rawJSON: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.description = description
        self.app = app
        self.params = params
        self.preconditions = preconditions
        self.steps = steps
        self.onFailure = onFailure
        self.rawJSON = rawJSON
    }
}
