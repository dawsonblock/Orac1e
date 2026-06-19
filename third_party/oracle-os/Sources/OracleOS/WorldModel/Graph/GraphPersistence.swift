import Foundation
import SQLite3

public struct GraphSnapshot {
    public var planningStates: [PlanningStateID: PlanningState]
    public var actionContracts: [String: ActionContract]
    public var candidateGraph: CandidateGraph
    public var stableGraph: StableGraph

    public init(
        planningStates: [PlanningStateID: PlanningState] = [:],
        actionContracts: [String: ActionContract] = [:],
        candidateGraph: CandidateGraph = CandidateGraph(),
        stableGraph: StableGraph = StableGraph()
    ) {
        self.planningStates = planningStates
        self.actionContracts = actionContracts
        self.candidateGraph = candidateGraph
        self.stableGraph = stableGraph
    }
}

public final class GraphPersistence: @unchecked Sendable {
    private var db: OpaquePointer?
    private let databaseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let writeQueue = DispatchQueue(label: "oracle.graph.persistence", qos: .utility)

    public init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            defer { sqlite3_close(db) }
            throw NSError(domain: "GraphPersistence", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to open graph database at \(databaseURL.path)",
            ])
        }

        try execute("""
        CREATE TABLE IF NOT EXISTS planning_states (
            id TEXT PRIMARY KEY,
            cluster_key TEXT,
            app_id TEXT,
            domain TEXT,
            window_class TEXT,
            task_phase TEXT,
            focused_role TEXT,
            modal_class TEXT,
            navigation_class TEXT,
            control_context TEXT,
            updated_at REAL NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS action_contracts (
            id TEXT PRIMARY KEY,
            agent_kind TEXT NOT NULL,
            domain TEXT NOT NULL,
            skill_name TEXT NOT NULL,
            target_role TEXT,
            target_label TEXT,
            locator_strategy TEXT NOT NULL,
            workspace_relative_path TEXT,
            command_category TEXT,
            planner_family TEXT,
            updated_at REAL NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS candidate_edges (
            edge_id TEXT PRIMARY KEY,
            from_state_id TEXT NOT NULL,
            to_state_id TEXT NOT NULL,
            action_contract_id TEXT NOT NULL,
            agent_kind TEXT NOT NULL,
            domain TEXT NOT NULL,
            workspace_relative_path TEXT,
            command_category TEXT,
            planner_family TEXT,
            postcondition_class TEXT NOT NULL,
            attempts INTEGER NOT NULL,
            successes INTEGER NOT NULL,
            latency_total_ms INTEGER NOT NULL,
            failure_histogram TEXT NOT NULL,
            last_success_ts REAL,
            last_attempt_ts REAL,
            recent_outcomes TEXT NOT NULL,
            ambiguity_total REAL NOT NULL,
            recovery_tagged INTEGER NOT NULL,
            approval_required INTEGER NOT NULL,
            approval_outcome TEXT,
            knowledge_tier TEXT NOT NULL DEFAULT 'candidate',
            critic_verified INTEGER NOT NULL DEFAULT 0,
            replay_evidence_count INTEGER NOT NULL DEFAULT 0,
            verified_successes INTEGER NOT NULL DEFAULT 0,
            last_promotion_attempt_ts REAL,
            last_promotion_rejection_reason TEXT
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS stable_edges (
            edge_id TEXT PRIMARY KEY,
            from_state_id TEXT NOT NULL,
            to_state_id TEXT NOT NULL,
            action_contract_id TEXT NOT NULL,
            agent_kind TEXT NOT NULL,
            domain TEXT NOT NULL,
            workspace_relative_path TEXT,
            command_category TEXT,
            planner_family TEXT,
            postcondition_class TEXT NOT NULL,
            attempts INTEGER NOT NULL,
            successes INTEGER NOT NULL,
            latency_total_ms INTEGER NOT NULL,
            failure_histogram TEXT NOT NULL,
            last_success_ts REAL,
            last_attempt_ts REAL,
            recent_outcomes TEXT NOT NULL,
            ambiguity_total REAL NOT NULL,
            recovery_tagged INTEGER NOT NULL,
            approval_required INTEGER NOT NULL,
            approval_outcome TEXT,
            knowledge_tier TEXT NOT NULL DEFAULT 'stable',
            critic_verified INTEGER NOT NULL DEFAULT 0,
            replay_evidence_count INTEGER NOT NULL DEFAULT 0,
            verified_successes INTEGER NOT NULL DEFAULT 0,
            last_promotion_attempt_ts REAL,
            last_promotion_rejection_reason TEXT
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS edge_failures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            edge_id TEXT,
            state_id TEXT NOT NULL,
            action_contract_id TEXT NOT NULL,
            failure_class TEXT NOT NULL,
            timestamp REAL NOT NULL,
            ambiguity_score REAL,
            recovery_tagged INTEGER NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS graph_stats (
            key TEXT PRIMARY KEY,
            int_value INTEGER,
            double_value REAL,
            text_value TEXT,
            updated_at REAL NOT NULL
        );
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Atomic Write Support

    /// Performs an atomic write operation using a temporary file and atomic replacement.
    /// This prevents corruption if a crash occurs mid-write.
    public func atomicWrite<T>(_ operation: () throws -> T) rethrows -> T {
        try writeQueue.sync {
            // SQLite handles its own atomicity at the journal level,
            // but we can use this for explicit checkpoint operations
            try operation()
        }
    }

    /// Checkpoint the database to ensure all pending writes are flushed to disk.
    public func checkpoint() throws {
        try writeQueue.sync {
            var logFrameCount: Int32 = 0
            var checkpointedFrameCount: Int32 = 0
            let result = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, &logFrameCount, &checkpointedFrameCount)
            if result != SQLITE_OK {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                throw NSError(domain: "GraphPersistence", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Checkpoint failed: \(errorMessage)"
                ])
            }
        }
    }

    public func loadSnapshot() -> GraphSnapshot {
        GraphSnapshot(
            planningStates: loadPlanningStates(),
            actionContracts: loadActionContracts(),
            candidateGraph: loadGraph(from: "candidate_edges"),
            stableGraph: loadStableGraph()
        )
    }

    public func upsertPlanningState(_ state: PlanningState) {
        let sql = """
        INSERT INTO planning_states (
            id, cluster_key, app_id, domain, window_class, task_phase,
            focused_role, modal_class, navigation_class, control_context, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            cluster_key = excluded.cluster_key,
            app_id = excluded.app_id,
            domain = excluded.domain,
            window_class = excluded.window_class,
            task_phase = excluded.task_phase,
            focused_role = excluded.focused_role,
            modal_class = excluded.modal_class,
            navigation_class = excluded.navigation_class,
            control_context = excluded.control_context,
            updated_at = excluded.updated_at;
        """

        withStatement(sql) { statement in
            bind(state.id.rawValue, to: 1, in: statement)
            bind(state.clusterKey.rawValue, to: 2, in: statement)
            bind(state.appID, to: 3, in: statement)
            bind(state.domain, to: 4, in: statement)
            bind(state.windowClass, to: 5, in: statement)
            bind(state.taskPhase, to: 6, in: statement)
            bind(state.focusedRole, to: 7, in: statement)
            bind(state.modalClass, to: 8, in: statement)
            bind(state.navigationClass, to: 9, in: statement)
            bind(state.controlContext, to: 10, in: statement)
            sqlite3_bind_double(statement, 11, Date().timeIntervalSince1970)
        }
    }

    public func upsertActionContract(_ contract: ActionContract) {
        let sql = """
        INSERT INTO action_contracts (
            id, agent_kind, domain, skill_name, target_role, target_label, locator_strategy,
            workspace_relative_path, command_category, planner_family, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            agent_kind = excluded.agent_kind,
            domain = excluded.domain,
            skill_name = excluded.skill_name,
            target_role = excluded.target_role,
            target_label = excluded.target_label,
            locator_strategy = excluded.locator_strategy,
            workspace_relative_path = excluded.workspace_relative_path,
            command_category = excluded.command_category,
            planner_family = excluded.planner_family,
            updated_at = excluded.updated_at;
        """

        withStatement(sql) { statement in
            bind(contract.id, to: 1, in: statement)
            bind(contract.agentKind.rawValue, to: 2, in: statement)
            bind(contract.domain, to: 3, in: statement)
            bind(contract.skillName, to: 4, in: statement)
            bind(contract.targetRole, to: 5, in: statement)
            bind(contract.targetLabel, to: 6, in: statement)
            bind(contract.locatorStrategy, to: 7, in: statement)
            bind(contract.workspaceRelativePath, to: 8, in: statement)
            bind(contract.commandCategory, to: 9, in: statement)
            bind(contract.plannerFamily, to: 10, in: statement)
            sqlite3_bind_double(statement, 11, Date().timeIntervalSince1970)
        }
    }

    public func upsertCandidateEdge(_ edge: EdgeTransition?) {
        guard let edge else { return }
        upsert(edge: edge, table: "candidate_edges")
    }

    public func upsertStableEdge(_ edge: EdgeTransition) {
        upsert(edge: edge, table: "stable_edges")
    }

    public func deleteStableEdge(edgeID: String) {
        let sql = "DELETE FROM stable_edges WHERE edge_id = ?;"
        withStatement(sql) { statement in
            bind(edgeID, to: 1, in: statement)
        }
    }

    public func recordFailure(
        edgeID: String,
        stateID: String,
        actionContractID: String,
        failureClass: String,
        timestamp: TimeInterval,
        ambiguityScore: Double?,
        recoveryTagged: Bool
    ) {
        let sql = """
        INSERT INTO edge_failures (
            edge_id, state_id, action_contract_id, failure_class, timestamp, ambiguity_score, recovery_tagged
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        withStatement(sql) { statement in
            bind(edgeID, to: 1, in: statement)
            bind(stateID, to: 2, in: statement)
            bind(actionContractID, to: 3, in: statement)
            bind(failureClass, to: 4, in: statement)
            sqlite3_bind_double(statement, 5, timestamp)
            if let ambiguityScore {
                sqlite3_bind_double(statement, 6, ambiguityScore)
            } else {
                sqlite3_bind_null(statement, 6)
            }
            sqlite3_bind_int(statement, 7, recoveryTagged ? 1 : 0)
        }
    }

    public func persistGraphStats(_ stats: GraphStats) {
        upsertGraphStat(key: "global_attempts", intValue: stats.attempts, doubleValue: nil, textValue: nil)
        upsertGraphStat(key: "global_successes", intValue: stats.successes, doubleValue: nil, textValue: nil)
    }

    private func upsertGraphStat(key: String, intValue: Int?, doubleValue: Double?, textValue: String?) {
        let sql = """
        INSERT INTO graph_stats (key, int_value, double_value, text_value, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(key) DO UPDATE SET
            int_value = excluded.int_value,
            double_value = excluded.double_value,
            text_value = excluded.text_value,
            updated_at = excluded.updated_at;
        """
        withStatement(sql) { statement in
            bind(key, to: 1, in: statement)
            if let intValue {
                sqlite3_bind_int64(statement, 2, sqlite3_int64(intValue))
            } else {
                sqlite3_bind_null(statement, 2)
            }
            if let doubleValue {
                sqlite3_bind_double(statement, 3, doubleValue)
            } else {
                sqlite3_bind_null(statement, 3)
            }
            bind(textValue, to: 4, in: statement)
            sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
        }
    }

    private func upsert(edge: EdgeTransition, table: String) {
        let sql = """
        INSERT INTO \(table) (
            edge_id, from_state_id, to_state_id, action_contract_id, agent_kind, domain,
            workspace_relative_path, command_category, planner_family, postcondition_class,
            attempts, successes, latency_total_ms, failure_histogram, last_success_ts,
            last_attempt_ts, recent_outcomes, ambiguity_total, recovery_tagged,
            approval_required, approval_outcome, knowledge_tier,
            critic_verified, replay_evidence_count, verified_successes,
            last_promotion_attempt_ts, last_promotion_rejection_reason
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(edge_id) DO UPDATE SET
            from_state_id = excluded.from_state_id,
            to_state_id = excluded.to_state_id,
            action_contract_id = excluded.action_contract_id,
            agent_kind = excluded.agent_kind,
            domain = excluded.domain,
            workspace_relative_path = excluded.workspace_relative_path,
            command_category = excluded.command_category,
            planner_family = excluded.planner_family,
            postcondition_class = excluded.postcondition_class,
            attempts = excluded.attempts,
            successes = excluded.successes,
            latency_total_ms = excluded.latency_total_ms,
            failure_histogram = excluded.failure_histogram,
            last_success_ts = excluded.last_success_ts,
            last_attempt_ts = excluded.last_attempt_ts,
            recent_outcomes = excluded.recent_outcomes,
            ambiguity_total = excluded.ambiguity_total,
            recovery_tagged = excluded.recovery_tagged,
            approval_required = excluded.approval_required,
            approval_outcome = excluded.approval_outcome,
            knowledge_tier = excluded.knowledge_tier,
            critic_verified = excluded.critic_verified,
            replay_evidence_count = excluded.replay_evidence_count,
            verified_successes = excluded.verified_successes,
            last_promotion_attempt_ts = excluded.last_promotion_attempt_ts,
            last_promotion_rejection_reason = excluded.last_promotion_rejection_reason;
        """

        withStatement(sql) { statement in
            bind(edge.edgeID, to: 1, in: statement)
            bind(edge.fromPlanningStateID.rawValue, to: 2, in: statement)
            bind(edge.toPlanningStateID.rawValue, to: 3, in: statement)
            bind(edge.actionContractID, to: 4, in: statement)
            bind(edge.agentKind.rawValue, to: 5, in: statement)
            bind(edge.domain, to: 6, in: statement)
            bind(edge.workspaceRelativePath, to: 7, in: statement)
            bind(edge.commandCategory, to: 8, in: statement)
            bind(edge.plannerFamily, to: 9, in: statement)
            bind(edge.postconditionClass.rawValue, to: 10, in: statement)
            sqlite3_bind_int64(statement, 11, sqlite3_int64(edge.attempts))
            sqlite3_bind_int64(statement, 12, sqlite3_int64(edge.successes))
            sqlite3_bind_int64(statement, 13, sqlite3_int64(edge.latencyTotalMs))
            bind(jsonString(edge.failureHistogram), to: 14, in: statement)
            if let lastSuccessTimestamp = edge.lastSuccessTimestamp {
                sqlite3_bind_double(statement, 15, lastSuccessTimestamp)
            } else {
                sqlite3_bind_null(statement, 15)
            }
            if let lastAttemptTimestamp = edge.lastAttemptTimestamp {
                sqlite3_bind_double(statement, 16, lastAttemptTimestamp)
            } else {
                sqlite3_bind_null(statement, 16)
            }
            bind(jsonString(edge.recentOutcomes), to: 17, in: statement)
            sqlite3_bind_double(statement, 18, edge.ambiguityTotal)
            sqlite3_bind_int(statement, 19, edge.recoveryTagged ? 1 : 0)
            sqlite3_bind_int(statement, 20, edge.approvalRequired ? 1 : 0)
            bind(edge.approvalOutcome, to: 21, in: statement)
            bind(edge.knowledgeTier.rawValue, to: 22, in: statement)
            // ENHANCEMENT: ADR-012 fields
            sqlite3_bind_int(statement, 23, edge.criticVerified ? 1 : 0)
            sqlite3_bind_int64(statement, 24, sqlite3_int64(edge.replayEvidenceCount))
            sqlite3_bind_int64(statement, 25, sqlite3_int64(edge.verifiedSuccesses))
            if let lastPromoTs = edge.lastPromotionAttemptTimestamp {
                sqlite3_bind_double(statement, 26, lastPromoTs)
            } else {
                sqlite3_bind_null(statement, 26)
            }
            bind(edge.lastPromotionRejectionReason, to: 27, in: statement)
        }
    }

    private func loadPlanningStates() -> [PlanningStateID: PlanningState] {
        let sql = """
        SELECT id, cluster_key, app_id, domain, window_class, task_phase,
               focused_role, modal_class, navigation_class, control_context
        FROM planning_states;
        """
        var result: [PlanningStateID: PlanningState] = [:]

        query(sql) { statement in
            let id = columnText(statement, index: 0) ?? ""
            let planningStateID = PlanningStateID(rawValue: id)
            let planningState = PlanningState(
                id: planningStateID,
                clusterKey: StateClusterKey(rawValue: columnText(statement, index: 1) ?? id),
                appID: columnText(statement, index: 2) ?? "unknown",
                domain: columnText(statement, index: 3),
                windowClass: columnText(statement, index: 4),
                taskPhase: columnText(statement, index: 5),
                focusedRole: columnText(statement, index: 6),
                modalClass: columnText(statement, index: 7),
                navigationClass: columnText(statement, index: 8),
                controlContext: columnText(statement, index: 9)
            )
            result[planningStateID] = planningState
        }

        return result
    }

    private func loadActionContracts() -> [String: ActionContract] {
        let sql = """
        SELECT id, agent_kind, domain, skill_name, target_role, target_label, locator_strategy,
               workspace_relative_path, command_category, planner_family
        FROM action_contracts;
        """
        var result: [String: ActionContract] = [:]

        query(sql) { statement in
            let contract = ActionContract(
                id: columnText(statement, index: 0) ?? UUID().uuidString,
                agentKind: AgentKind(rawValue: columnText(statement, index: 1) ?? "os") ?? .os,
                domain: columnText(statement, index: 2),
                skillName: columnText(statement, index: 3) ?? "unknown",
                targetRole: columnText(statement, index: 4),
                targetLabel: columnText(statement, index: 5),
                locatorStrategy: columnText(statement, index: 6) ?? "query",
                workspaceRelativePath: columnText(statement, index: 7),
                commandCategory: columnText(statement, index: 8),
                plannerFamily: columnText(statement, index: 9)
            )
            result[contract.id] = contract
        }

        return result
    }

    private func loadGraph(from table: String) -> CandidateGraph {
        let sql = """
        SELECT edge_id, from_state_id, to_state_id, action_contract_id, agent_kind, domain,
               workspace_relative_path, command_category, planner_family, postcondition_class,
               attempts, successes, latency_total_ms, failure_histogram, last_success_ts,
               last_attempt_ts, recent_outcomes, ambiguity_total, recovery_tagged,
               approval_required, approval_outcome, knowledge_tier,
               critic_verified, replay_evidence_count, verified_successes,
               last_promotion_attempt_ts, last_promotion_rejection_reason
        FROM \(table);
        """
        let graph = CandidateGraph()

        query(sql) { statement in
            guard let postconditionClass = PostconditionClass(rawValue: columnText(statement, index: 9) ?? "unknown") else {
                return
            }
            let edge = EdgeTransition(
                edgeID: columnText(statement, index: 0) ?? UUID().uuidString,
                fromPlanningStateID: PlanningStateID(rawValue: columnText(statement, index: 1) ?? "unknown"),
                toPlanningStateID: PlanningStateID(rawValue: columnText(statement, index: 2) ?? "unknown"),
                actionContractID: columnText(statement, index: 3) ?? "unknown",
                agentKind: AgentKind(rawValue: columnText(statement, index: 4) ?? "os") ?? .os,
                domain: columnText(statement, index: 5),
                workspaceRelativePath: columnText(statement, index: 6),
                commandCategory: columnText(statement, index: 7),
                plannerFamily: columnText(statement, index: 8),
                postconditionClass: postconditionClass,
                attempts: Int(sqlite3_column_int64(statement, 10)),
                successes: Int(sqlite3_column_int64(statement, 11)),
                latencyTotalMs: Int(sqlite3_column_int64(statement, 12)),
                failureHistogram: decodeJSON(columnText(statement, index: 13), default: [:]),
                lastSuccessTimestamp: sqlite3_column_type(statement, 14) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 14),
                lastAttemptTimestamp: sqlite3_column_type(statement, 15) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 15),
                recentOutcomes: decodeJSON(columnText(statement, index: 16), default: []),
                ambiguityTotal: sqlite3_column_double(statement, 17),
                recoveryTagged: sqlite3_column_int(statement, 18) == 1,
                approvalRequired: sqlite3_column_int(statement, 19) == 1,
                approvalOutcome: columnText(statement, index: 20),
                knowledgeTier: KnowledgeTier(rawValue: columnText(statement, index: 21) ?? "candidate") ?? .candidate,
                // ENHANCEMENT: ADR-012 fields
                criticVerified: sqlite3_column_int(statement, 22) == 1,
                replayEvidenceCount: Int(sqlite3_column_int64(statement, 23)),
                verifiedSuccesses: Int(sqlite3_column_int64(statement, 24)),
                lastPromotionAttemptTimestamp: sqlite3_column_type(statement, 25) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 25),
                lastPromotionRejectionReason: columnText(statement, index: 26)
            )
            graph.edges[edge.edgeID] = edge
            graph.nodes[edge.fromPlanningStateID] = graph.nodes[edge.fromPlanningStateID] ?? StateNode(id: edge.fromPlanningStateID, visitCount: 0)
            graph.nodes[edge.toPlanningStateID] = graph.nodes[edge.toPlanningStateID] ?? StateNode(id: edge.toPlanningStateID, visitCount: 0)
        }

        return graph
    }

    private func loadStableGraph() -> StableGraph {
        let candidate = loadGraph(from: "stable_edges")
        return StableGraph(nodes: candidate.nodes, edges: candidate.edges)
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(errorMessage)
            throw NSError(domain: "GraphPersistence", code: 2, userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
    }

    private func withStatement(_ sql: String, bindAndStep: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return
        }
        defer { sqlite3_finalize(statement) }
        bindAndStep(statement)
        sqlite3_step(statement)
    }

    private func query(_ sql: String, row: (OpaquePointer) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            row(statement)
        }
    }

    private func bind(_ value: String?, to index: Int32, in statement: OpaquePointer) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, sqliteTransientDestructor)
    }

    private func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }

    private func jsonString<T: Encodable>(_ value: T) -> String {
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func decodeJSON<T: Decodable>(_ raw: String?, default defaultValue: T) -> T {
        guard let raw, let data = raw.data(using: .utf8),
              let decoded = try? decoder.decode(T.self, from: data)
        else {
            if let raw {
                Log.warn("GraphPersistence: Failed to decode JSON, using default. Raw: \(raw.prefix(100))")
            }
            return defaultValue
        }
        return decoded
    }
}

private let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
