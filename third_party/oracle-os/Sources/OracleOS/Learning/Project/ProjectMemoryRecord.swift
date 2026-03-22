import Foundation

public enum ProjectMemoryKind: String, Codable, Sendable, CaseIterable {
    case architectureDecision = "architecture-decision"
    case openProblem = "open-problem"
    case rejectedApproach = "rejected-approach"
    case knownGoodPattern = "known-good-pattern"
    case risk

    public var directoryName: String {
        switch self {
        case .architectureDecision:
            "architecture-decisions"
        case .openProblem:
            "open-problems"
        case .rejectedApproach:
            "rejected-approaches"
        case .knownGoodPattern:
            "known-good-patterns"
        case .risk:
            "."
        }
    }

    public var titlePrefix: String {
        switch self {
        case .architectureDecision:
            "Architecture Decision"
        case .openProblem:
            "Open Problem"
        case .rejectedApproach:
            "Rejected Approach"
        case .knownGoodPattern:
            "Known Good Pattern"
        case .risk:
            "Risk"
        }
    }
}

public enum ProjectMemoryStatus: String, Codable, Sendable, CaseIterable {
    case draft
    case accepted
}

public struct ProjectMemoryRef: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: String
    public let kind: ProjectMemoryKind
    public let knowledgeClass: KnowledgeClass
    public let status: ProjectMemoryStatus
    public let title: String
    public let summary: String
    public let path: String
    public let affectedModules: [String]
    public let evidenceRefs: [String]
    public let sourceTraceIDs: [String]

    public init(
        id: String,
        kind: ProjectMemoryKind,
        knowledgeClass: KnowledgeClass,
        status: ProjectMemoryStatus,
        title: String,
        summary: String,
        path: String,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.knowledgeClass = knowledgeClass
        self.status = status
        self.title = title
        self.summary = summary
        self.path = path
        self.affectedModules = affectedModules
        self.evidenceRefs = evidenceRefs
        self.sourceTraceIDs = sourceTraceIDs
    }
}

public struct ProjectMemoryRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: ProjectMemoryKind
    public let knowledgeClass: KnowledgeClass
    public let status: ProjectMemoryStatus
    public let title: String
    public let summary: String
    public let affectedModules: [String]
    public let evidenceRefs: [String]
    public let sourceTraceIDs: [String]
    public let createdAt: Date
    public let updatedAt: Date
    public let path: String
    public let body: String

    public init(
        id: String,
        kind: ProjectMemoryKind,
        knowledgeClass: KnowledgeClass,
        status: ProjectMemoryStatus,
        title: String,
        summary: String,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        path: String,
        body: String
    ) {
        self.id = id
        self.kind = kind
        self.knowledgeClass = knowledgeClass
        self.status = status
        self.title = title
        self.summary = summary
        self.affectedModules = affectedModules
        self.evidenceRefs = evidenceRefs
        self.sourceTraceIDs = sourceTraceIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.path = path
        self.body = body
    }

    public var ref: ProjectMemoryRef {
        ProjectMemoryRef(
            id: id,
            kind: kind,
            knowledgeClass: knowledgeClass,
            status: status,
            title: title,
            summary: summary,
            path: path,
            affectedModules: affectedModules,
            evidenceRefs: evidenceRefs,
            sourceTraceIDs: sourceTraceIDs
        )
    }
}

public struct ProjectMemoryDraft: Sendable, Equatable {
    public let kind: ProjectMemoryKind
    public let knowledgeClass: KnowledgeClass
    public let title: String
    public let summary: String
    public let affectedModules: [String]
    public let evidenceRefs: [String]
    public let sourceTraceIDs: [String]
    public let body: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        kind: ProjectMemoryKind,
        knowledgeClass: KnowledgeClass,
        title: String,
        summary: String,
        affectedModules: [String] = [],
        evidenceRefs: [String] = [],
        sourceTraceIDs: [String] = [],
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.kind = kind
        self.knowledgeClass = knowledgeClass
        self.title = title
        self.summary = summary
        self.affectedModules = affectedModules
        self.evidenceRefs = evidenceRefs
        self.sourceTraceIDs = sourceTraceIDs
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ArchitectureDecisionRecord: Codable, Sendable, Equatable {
    public let record: ProjectMemoryRecord
}

public struct OpenProblemRecord: Codable, Sendable, Equatable {
    public let record: ProjectMemoryRecord
}

public struct RejectedApproachRecord: Codable, Sendable, Equatable {
    public let record: ProjectMemoryRecord
}

public struct KnownGoodPatternRecord: Codable, Sendable, Equatable {
    public let record: ProjectMemoryRecord
}

public struct RiskRecord: Codable, Sendable, Equatable {
    public let record: ProjectMemoryRecord
}
