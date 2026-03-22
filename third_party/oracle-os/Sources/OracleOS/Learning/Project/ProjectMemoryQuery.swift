import Foundation

public struct ProjectMemoryPlanningSignals: Sendable, Equatable {
    public let architectureDecisions: [ProjectMemoryRecord]
    public let openProblems: [ProjectMemoryRecord]
    public let rejectedApproaches: [ProjectMemoryRecord]
    public let knownGoodPatterns: [ProjectMemoryRecord]
    public let risks: [ProjectMemoryRecord]

    public init(
        architectureDecisions: [ProjectMemoryRecord] = [],
        openProblems: [ProjectMemoryRecord] = [],
        rejectedApproaches: [ProjectMemoryRecord] = [],
        knownGoodPatterns: [ProjectMemoryRecord] = [],
        risks: [ProjectMemoryRecord] = []
    ) {
        self.architectureDecisions = architectureDecisions
        self.openProblems = openProblems
        self.rejectedApproaches = rejectedApproaches
        self.knownGoodPatterns = knownGoodPatterns
        self.risks = risks
    }

    public var refs: [ProjectMemoryRef] {
        records.map(\.ref)
    }

    public var records: [ProjectMemoryRecord] {
        architectureDecisions + openProblems + rejectedApproaches + knownGoodPatterns + risks
    }

    public var hasArchitectureDecisions: Bool {
        !architectureDecisions.isEmpty
    }

    public var hasOpenProblems: Bool {
        !openProblems.isEmpty
    }

    public var hasRejectedApproaches: Bool {
        !rejectedApproaches.isEmpty
    }

    public var hasKnownGoodPatterns: Bool {
        !knownGoodPatterns.isEmpty
    }

    public var hasRisks: Bool {
        !risks.isEmpty
    }

    public var riskSummaries: [String] {
        risks.map { $0.summary.isEmpty ? $0.title : $0.summary }
    }

    public func preferredPaths(in snapshot: RepositorySnapshot) -> [String] {
        matchedPaths(
            in: snapshot,
            records: knownGoodPatterns + architectureDecisions
        )
    }

    public func avoidedPaths(in snapshot: RepositorySnapshot) -> [String] {
        matchedPaths(
            in: snapshot,
            records: rejectedApproaches + openProblems
        )
    }

    public func hasPreferredPath(_ path: String, in snapshot: RepositorySnapshot) -> Bool {
        preferredPaths(in: snapshot).contains(path)
    }

    public func hasAvoidedPath(_ path: String, in snapshot: RepositorySnapshot) -> Bool {
        avoidedPaths(in: snapshot).contains(path)
    }

    private func matchedPaths(
        in snapshot: RepositorySnapshot,
        records: [ProjectMemoryRecord]
    ) -> [String] {
        let haystacks = records.map { record in
            [
                record.title,
                record.summary,
                record.body,
                record.affectedModules.joined(separator: " "),
            ]
            .joined(separator: "\n")
            .lowercased()
        }

        var matches: [String] = []
        for path in snapshot.files.map(\.path) where snapshot.files.contains(where: { $0.path == path && !$0.isDirectory }) {
            let basename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
            let module = ArchitectureModuleGraph.moduleName(for: path).lowercased()
            let candidates = [path.lowercased(), basename, module]
            if haystacks.contains(where: { haystack in
                candidates.contains(where: { haystack.contains($0) })
            }) {
                matches.append(path)
            }
        }
        return orderedUnique(matches)
    }
}

public enum ProjectMemoryQuery {
    public static func relevantRecords(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        store: ProjectMemoryStore,
        limit: Int = 6
    ) -> [ProjectMemoryRef] {
        planningSignals(
            goalDescription: goalDescription,
            snapshot: snapshot,
            store: store,
            limit: limit
        ).refs
    }

    public static func architectureDecisions(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        store: ProjectMemoryStore,
        limit: Int = 6
    ) -> [ProjectMemoryRecord] {
        records(
            goalDescription: goalDescription,
            snapshot: snapshot,
            store: store,
            kind: .architectureDecision,
            limit: limit
        )
    }

    public static func knownProblems(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        store: ProjectMemoryStore,
        limit: Int = 6
    ) -> [ProjectMemoryRecord] {
        records(
            goalDescription: goalDescription,
            snapshot: snapshot,
            store: store,
            kind: .openProblem,
            limit: limit
        )
    }

    public static func rejectedApproaches(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        store: ProjectMemoryStore,
        limit: Int = 6
    ) -> [ProjectMemoryRecord] {
        records(
            goalDescription: goalDescription,
            snapshot: snapshot,
            store: store,
            kind: .rejectedApproach,
            limit: limit
        )
    }

    public static func knownGoodPatterns(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        store: ProjectMemoryStore,
        limit: Int = 6
    ) -> [ProjectMemoryRecord] {
        records(
            goalDescription: goalDescription,
            snapshot: snapshot,
            store: store,
            kind: .knownGoodPattern,
            limit: limit
        )
    }

    public static func risks(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        store: ProjectMemoryStore,
        limit: Int = 6
    ) -> [ProjectMemoryRecord] {
        records(
            goalDescription: goalDescription,
            snapshot: snapshot,
            store: store,
            kind: .risk,
            limit: limit
        )
    }

    public static func planningSignals(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        store: ProjectMemoryStore,
        limit: Int = 6
    ) -> ProjectMemoryPlanningSignals {
        ProjectMemoryPlanningSignals(
            architectureDecisions: architectureDecisions(
                goalDescription: goalDescription,
                snapshot: snapshot,
                store: store,
                limit: limit
            ),
            openProblems: knownProblems(
                goalDescription: goalDescription,
                snapshot: snapshot,
                store: store,
                limit: limit
            ),
            rejectedApproaches: rejectedApproaches(
                goalDescription: goalDescription,
                snapshot: snapshot,
                store: store,
                limit: limit
            ),
            knownGoodPatterns: knownGoodPatterns(
                goalDescription: goalDescription,
                snapshot: snapshot,
                store: store,
                limit: limit
            ),
            risks: risks(
                goalDescription: goalDescription,
                snapshot: snapshot,
                store: store,
                limit: limit
            )
        )
    }

    public static func modulesForSnapshot(_ snapshot: RepositorySnapshot) -> [String] {
        let modules = Set(snapshot.files.compactMap { file -> String? in
            guard !file.isDirectory else { return nil }
            return ArchitectureModuleGraph.moduleName(for: file.path)
        })
        return Array(modules).sorted()
    }

    private static func records(
        goalDescription: String,
        snapshot: RepositorySnapshot,
        store: ProjectMemoryStore,
        kind: ProjectMemoryKind,
        limit: Int
    ) -> [ProjectMemoryRecord] {
        let modules = modulesForSnapshot(snapshot)
        let normalizedGoal = goalDescription.lowercased()
        let candidates = store.allRecords().filter { record in
            record.kind == kind
        }

        let exactMatches = candidates.filter { record in
            recordMatchesGoal(record, normalizedGoal: normalizedGoal)
                && recordMatchesModules(record, modules: modules)
        }

        let moduleMatches = candidates.filter { record in
            recordMatchesModules(record, modules: modules)
        }

        let textMatches = candidates.filter { record in
            recordMatchesGoal(record, normalizedGoal: normalizedGoal)
        }

        return Array((exactMatches + moduleMatches + textMatches).uniqued(by: \.id).prefix(limit))
    }

    private static func recordMatchesGoal(
        _ record: ProjectMemoryRecord,
        normalizedGoal: String
    ) -> Bool {
        guard !normalizedGoal.isEmpty else {
            return true
        }
        let haystack = [
            record.title,
            record.summary,
            record.body,
            record.affectedModules.joined(separator: " "),
        ]
        .joined(separator: "\n")
        .lowercased()
        return haystack.contains(normalizedGoal) || normalizedGoal.split(separator: " ").contains(where: { haystack.contains(String($0)) })
    }

    private static func recordMatchesModules(
        _ record: ProjectMemoryRecord,
        modules: [String]
    ) -> Bool {
        guard !modules.isEmpty else {
            return true
        }
        let recordModules = Set(record.affectedModules)
        return modules.contains(where: { recordModules.contains($0) })
    }
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    return values.filter { seen.insert($0).inserted }
}

private extension Array {
    func uniqued<ID: Hashable>(by keyPath: KeyPath<Element, ID>) -> [Element] {
        var seen: Set<ID> = []
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
