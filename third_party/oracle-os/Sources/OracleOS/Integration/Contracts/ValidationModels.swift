import Foundation

public struct CodingValidationStep: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let ok: Bool
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32
    public let stageID: String?
    public let stageName: String?
    public let profileName: String?
    public let timedOut: Bool
    public let durationMs: Int
    public let failureCategory: String?

    public init(
        name: String,
        ok: Bool,
        stdout: String,
        stderr: String,
        exitCode: Int32,
        stageID: String? = nil,
        stageName: String? = nil,
        profileName: String? = nil,
        timedOut: Bool = false,
        durationMs: Int = 0,
        failureCategory: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.ok = ok
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
        self.stageID = stageID
        self.stageName = stageName
        self.profileName = profileName
        self.timedOut = timedOut
        self.durationMs = durationMs
        self.failureCategory = failureCategory
    }
}

public struct CodingValidationResult: Codable, Sendable {
    public let ok: Bool
    public let steps: [CodingValidationStep]
    public let profileName: String?
    public let stageCount: Int
    public let resolvedCommands: [String]
    public let errorCategory: String?

    public init(
        ok: Bool,
        steps: [CodingValidationStep],
        profileName: String? = nil,
        stageCount: Int = 0,
        resolvedCommands: [String] = [],
        errorCategory: String? = nil
    ) {
        self.ok = ok
        self.steps = steps
        self.profileName = profileName
        self.stageCount = stageCount
        self.resolvedCommands = resolvedCommands
        self.errorCategory = errorCategory
    }
}

public struct CodingApprovalDecision: Codable, Sendable {
    public let runID: String
    public let approved: Bool
    public let reason: String?
    public let at: Date

    public init(runID: String, approved: Bool, reason: String? = nil, at: Date = Date()) {
        self.runID = runID
        self.approved = approved
        self.reason = reason
        self.at = at
    }
}
