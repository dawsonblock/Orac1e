import Foundation

public struct CommandLifecyclePayload: Codable, Sendable {
    public let router: String?
    public let status: String?
    public let reason: String?
    public let processNames: [String]?

    public init(
        router: String? = nil,
        status: String? = nil,
        reason: String? = nil,
        processNames: [String]? = nil
    ) {
        self.router = router
        self.status = status
        self.reason = reason
        self.processNames = processNames
    }
}

public struct UIObservationEventPayload: Codable, Sendable {
    public let appName: String?
    public let windowTitle: String?
    public let url: String?
    public let visibleElementCount: Int?
    public let modalPresent: Bool?
    public let observationHash: String?

    public init(
        appName: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        visibleElementCount: Int? = nil,
        modalPresent: Bool? = nil,
        observationHash: String? = nil
    ) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.visibleElementCount = visibleElementCount
        self.modalPresent = modalPresent
        self.observationHash = observationHash
    }
}

public struct AppFocusedPayload: Codable, Sendable {
    public let appName: String

    public init(appName: String) {
        self.appName = appName
    }
}

public struct WindowFocusedPayload: Codable, Sendable {
    public let appName: String?
    public let windowTitle: String?

    public init(appName: String? = nil, windowTitle: String? = nil) {
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

public struct NavigationObservedPayload: Codable, Sendable {
    public let url: String
    public let appName: String?

    public init(url: String, appName: String? = nil) {
        self.url = url
        self.appName = appName
    }
}

public struct ElementClickedPayload: Codable, Sendable {
    public let appName: String?
    public let query: String?
    public let domID: String?
    public let button: String?

    public init(appName: String? = nil, query: String? = nil, domID: String? = nil, button: String? = nil) {
        self.appName = appName
        self.query = query
        self.domID = domID
        self.button = button
    }
}

public struct TextEnteredPayload: Codable, Sendable {
    public let appName: String?
    public let query: String?
    public let domID: String?
    public let textLength: Int

    public init(appName: String? = nil, query: String? = nil, domID: String? = nil, textLength: Int) {
        self.appName = appName
        self.query = query
        self.domID = domID
        self.textLength = textLength
    }
}

public struct RepositoryObservedPayload: Codable, Sendable {
    public let repositoryRoot: String
    public let activeBranch: String?
    public let isGitDirty: Bool
    public let openFileCount: Int

    public init(repositoryRoot: String, activeBranch: String? = nil, isGitDirty: Bool, openFileCount: Int) {
        self.repositoryRoot = repositoryRoot
        self.activeBranch = activeBranch
        self.isGitDirty = isGitDirty
        self.openFileCount = openFileCount
    }
}

public struct FileReadPayload: Codable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct FileModifiedPayload: Codable, Sendable {
    public let path: String
    public let bytesWritten: Int?

    public init(path: String, bytesWritten: Int? = nil) {
        self.path = path
        self.bytesWritten = bytesWritten
    }
}

public struct BuildCompletedPayload: Codable, Sendable {
    public let succeeded: Bool

    public init(succeeded: Bool) {
        self.succeeded = succeeded
    }
}

public struct TestsCompletedPayload: Codable, Sendable {
    public let succeeded: Bool
    public let failingTestCount: Int?

    public init(succeeded: Bool, failingTestCount: Int? = nil) {
        self.succeeded = succeeded
        self.failingTestCount = failingTestCount
    }
}

public struct LessonPromotedPayload: Codable, Sendable {
    public let signal: String

    public init(signal: String) {
        self.signal = signal
    }
}

public struct RecipeRecordedPayload: Codable, Sendable {
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

public struct TraceSavedPayload: Codable, Sendable {
    public let traceID: String

    public init(traceID: String) {
        self.traceID = traceID
    }
}

public enum EventPayloadDecoder {
    public static func decode<T: Decodable>(_ type: T.Type, from envelope: EventEnvelope) -> T? {
        try? OracleJSONCoding.makeDecoder().decode(T.self, from: envelope.payload)
    }
}
