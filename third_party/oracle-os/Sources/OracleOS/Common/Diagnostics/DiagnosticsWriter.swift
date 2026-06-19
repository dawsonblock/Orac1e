import Foundation

/// Writes diagnostic JSON files to a specified directory.
///
/// ``DiagnosticsWriter`` produces canonical diagnostic artifacts:
/// - `task_graph.json` — nodes, edges, current node, edge success rates
/// - `planner_paths.json` — candidate paths, scores, selected path
/// - `patch_experiments.json` — patch experiment results and rankings
/// - `strategy_selection.jsonl` — strategy selection per planning cycle
public struct DiagnosticsWriter: Sendable {
    public let outputDirectory: URL

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    // MARK: - Task Graph

    /// Write ``task_graph.json`` from a ``TaskLedgerStore``.
    public func writeTaskLedger(_ store: TaskLedgerStore) {
        let payload = store.exportJSON()
        write(payload, to: "task_graph.json")
    }

    // MARK: - Planner Paths

    /// Diagnostic snapshot of a single candidate path.
    public struct PathSnapshot: @unchecked Sendable {
        public let edgeIDs: [String]
        public let actions: [String]
        public let terminalState: String?
        public let score: Double
        public let scoreBreakdowns: [[String: Any]]

        public init(
            edgeIDs: [String],
            actions: [String],
            terminalState: String?,
            score: Double,
            scoreBreakdowns: [[String: Any]]
        ) {
            self.edgeIDs = edgeIDs
            self.actions = actions
            self.terminalState = terminalState
            self.score = score
            self.scoreBreakdowns = scoreBreakdowns
        }

        func toDict() -> [String: Any] {
            var dict: [String: Any] = [
                "edge_ids": edgeIDs,
                "actions": actions,
                "score": score,
                "score_breakdowns": scoreBreakdowns,
            ]
            if let terminalState {
                dict["terminal_state"] = terminalState
            }
            return dict
        }
    }

    /// Write ``planner_paths.json`` with candidate paths and the selected path.
    public func writePlannerPaths(
        candidatePaths: [PathSnapshot],
        selectedPath: PathSnapshot?
    ) {
        var payload: [String: Any] = [
            "candidate_paths": candidatePaths.map { $0.toDict() },
        ]
        if let selectedPath {
            payload["selected_path"] = selectedPath.toDict()
        }
        payload["scores"] = candidatePaths.map {
            ["score": $0.score, "actions": $0.actions] as [String: Any]
        }
        write(payload, to: "planner_paths.json")
    }

    // MARK: - Patch Experiments

    /// Diagnostic snapshot of a patch experiment.
    public struct PatchExperimentSnapshot: Sendable {
        public let experimentID: String
        public let errorSignature: String
        public let candidates: [PatchCandidateSnapshot]
        public let selectedCandidateID: String?

        public init(
            experimentID: String,
            errorSignature: String,
            candidates: [PatchCandidateSnapshot],
            selectedCandidateID: String?
        ) {
            self.experimentID = experimentID
            self.errorSignature = errorSignature
            self.candidates = candidates
            self.selectedCandidateID = selectedCandidateID
        }

        func toDict() -> [String: Any] {
            [
                "experiment_id": experimentID,
                "error_signature": errorSignature,
                "candidates": candidates.map { $0.toDict() },
                "selected_candidate_id": selectedCandidateID ?? "",
            ]
        }
    }

    /// Diagnostic snapshot of a patch candidate result.
    public struct PatchCandidateSnapshot: Sendable {
        public let candidateID: String
        public let strategy: String
        public let testsPassed: Bool
        public let buildSucceeded: Bool
        public let selected: Bool

        public init(
            candidateID: String,
            strategy: String,
            testsPassed: Bool,
            buildSucceeded: Bool,
            selected: Bool
        ) {
            self.candidateID = candidateID
            self.strategy = strategy
            self.testsPassed = testsPassed
            self.buildSucceeded = buildSucceeded
            self.selected = selected
        }

        func toDict() -> [String: Any] {
            [
                "candidate_id": candidateID,
                "strategy": strategy,
                "tests_passed": testsPassed,
                "build_succeeded": buildSucceeded,
                "selected": selected,
            ]
        }
    }

    /// Write ``patch_experiments.json`` with experiment results.
    public func writePatchExperiments(_ experiments: [PatchExperimentSnapshot]) {
        let payload: [String: Any] = [
            "experiments": experiments.map { $0.toDict() },
        ]
        write(payload, to: "patch_experiments.json")
    }

    // MARK: - Strategy Selection

    /// Write a strategy selection snapshot for the current planning cycle.
    public func writeStrategySelection(_ strategy: SelectedStrategy, reevaluationCause: StrategyReevaluationCause? = nil) {
        let diagnostics = StrategyDiagnostics(
            selectedStrategy: strategy.kind,
            confidence: strategy.confidence,
            rationale: strategy.rationale,
            allowedOperatorFamilies: strategy.allowedOperatorFamilies,
            reevaluationCause: reevaluationCause
        )
        let payload = diagnostics.toDict()
        write(payload, to: "strategy_selection.json")
    }

    // MARK: - Helpers

    /// Build a ``PathSnapshot`` from a ``LedgerNavigator.ScoredPath`` with score breakdowns.
    public static func pathSnapshot(
        from path: LedgerNavigator.ScoredPath,
        scorer: LedgerScorer,
        goalState: AbstractTaskState? = nil,
        memoryBias: Double = 0
    ) -> PathSnapshot {
        let breakdowns: [[String: Any]] = path.edges.map { edge in
            let targetNode = path.nodes.first { $0.id == edge.toNodeID }
            let breakdown = scorer.scoreEdgeWithBreakdown(
                edge,
                goalState: goalState,
                targetState: targetNode?.abstractState,
                memoryBias: memoryBias
            )
            return breakdown.toDict()
        }
        return PathSnapshot(
            edgeIDs: path.edges.map(\.id),
            actions: path.edges.map(\.action),
            terminalState: path.terminalState?.rawValue,
            score: path.cumulativeScore,
            scoreBreakdowns: breakdowns
        )
    }

    private func write(_ payload: [String: Any], to filename: String) {
        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
            let url = outputDirectory.appendingPathComponent(filename)
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Diagnostics writing is best-effort; failures are non-fatal.
        }
    }
}
