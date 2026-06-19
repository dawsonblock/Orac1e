import Foundation

public struct IntegratedCodingRunRequest: Sendable {
    public let repoName: String
    public let repoURL: URL
    public let task: String
    public let mode: CodingRunMode
    public let retrievalQuery: String
    public let retrievalBaseURL: URL
    public let workerEndpoints: CodingWorkerEndpoints
    public let workspaceRoot: URL
    public let allowedPaths: [String]
    public let validationCommands: [String]
    public let validationConfigRootURL: URL?
    public let toolsRootURL: URL?
    public let preferredRetrievalToolID: String?
    public let preferredWorkerToolID: String?

    public init(
        repoName: String,
        repoURL: URL,
        task: String,
        mode: CodingRunMode,
        retrievalQuery: String,
        retrievalBaseURL: URL,
        workerEndpoints: CodingWorkerEndpoints,
        workspaceRoot: URL,
        allowedPaths: [String],
        validationCommands: [String],
        validationConfigRootURL: URL? = nil,
        toolsRootURL: URL? = nil,
        preferredRetrievalToolID: String? = nil,
        preferredWorkerToolID: String? = nil
    ) {
        self.repoName = repoName
        self.repoURL = repoURL
        self.task = task
        self.mode = mode
        self.retrievalQuery = retrievalQuery
        self.retrievalBaseURL = retrievalBaseURL
        self.workerEndpoints = workerEndpoints
        self.workspaceRoot = workspaceRoot
        self.allowedPaths = allowedPaths
        self.validationCommands = validationCommands
        self.validationConfigRootURL = validationConfigRootURL
        self.toolsRootURL = toolsRootURL
        self.preferredRetrievalToolID = preferredRetrievalToolID
        self.preferredWorkerToolID = preferredWorkerToolID
    }
}

public struct IntegratedCodingRunOutcome: Sendable {
    public let record: CodingRunRecord
    public let retrieval: CodingRetrievalResponse
    public let worker: CodingWorkerProposeResponse
    public let validation: CodingValidationResult
}

public actor IntegratedCodingRunService {
    private let workerClient: CodingWorkerClient
    private let retrievalClient: CodingRetrievalBrokerClient
    private let patchApplyService: CodingPatchApplyService
    private let toolClient: ToolClient

    public init(
        workerClient: CodingWorkerClient = CodingWorkerClient(),
        retrievalClient: CodingRetrievalBrokerClient = CodingRetrievalBrokerClient(),
        patchApplyService: CodingPatchApplyService = CodingPatchApplyService(),
        toolClient: ToolClient = ToolClient()
    ) {
        self.workerClient = workerClient
        self.retrievalClient = retrievalClient
        self.patchApplyService = patchApplyService
        self.toolClient = toolClient
    }

    public func execute(_ request: IntegratedCodingRunRequest) async throws -> IntegratedCodingRunOutcome {
        let runID = UUID().uuidString
        let runBaseURL = request.workspaceRoot.appendingPathComponent("runs", isDirectory: true)
        let ledger = CodingRunLedger(baseURL: runBaseURL)
        let events = CodingEventStore(baseURL: runBaseURL)
        let metadataStore = RunMetadataStore(baseURL: runBaseURL)
        let worktrees = CodingWorktreeCoordinator(workspaceRoot: request.workspaceRoot)
        let validator = CodingValidationCoordinator(
            commands: request.validationCommands,
            configRootURL: request.validationConfigRootURL
        )
        let router = CodingWorkerRouter(endpoints: request.workerEndpoints)
        let policy = CodingMutationPolicy(allowedPrefixes: request.allowedPaths)
        let toolAccess = loadToolAccess(for: request)

        var record = CodingRunRecord(
            id: runID,
            repoName: request.repoName,
            repoPath: request.repoURL.path,
            mode: request.mode,
            status: .created,
            task: request.task
        )
        try await ledger.upsert(record)
        try await events.append(CodingRunEvent(runID: runID, type: "run.created"))

        let worktreeURL = try await worktrees.createWorktree(runID: runID, sourceRepoURL: request.repoURL)
        let resolvedValidationPlan = await validator.resolvePlan(for: request.repoURL)
        try await metadataStore.put(
            CodingRunMetadata(
                runID: runID,
                canonicalRepoPath: request.repoURL.path,
                worktreePath: worktreeURL.path,
                validationCommands: resolvedValidationPlan.resolvedCommands,
                validationProfileName: resolvedValidationPlan.profileName,
                allowedPaths: request.allowedPaths,
                retrievalQuery: request.retrievalQuery,
                workerMode: request.mode
            )
        )
        try await events.append(
            CodingRunEvent(
                runID: runID,
                type: "worktree.created",
                payload: [
                    "path": worktreeURL.path,
                    "validation_profile": resolvedValidationPlan.profileName,
                    "validation_stage_count": String(resolvedValidationPlan.stageCount),
                ]
            )
        )

        record.status = .retrieving
        try await ledger.upsert(record)
        try await events.append(CodingRunEvent(runID: runID, type: "retrieval.started"))

        let retrievalRequest = CodingRetrievalRequest(
            repoName: request.repoName,
            repoPath: worktreeURL.path,
            query: request.retrievalQuery
        )
        let retrievalSelection = toolAccess?.selectRetrievalTool(preferredToolID: request.preferredRetrievalToolID)
        let retrievalResponse: CodingRetrievalResponse
        if let retrievalSelection {
            try await events.append(
                CodingRunEvent(
                    runID: runID,
                    type: "retrieval.tool_selected",
                    payload: [
                        "tool_id": retrievalSelection.id,
                        "capability": retrievalSelection.capability,
                    ]
                )
            )
            retrievalResponse = try await invokeRetrievalTool(
                manifest: retrievalSelection.manifest,
                capability: retrievalSelection.capability,
                request: retrievalRequest,
                runID: runID
            )
        } else {
            retrievalResponse = try await retrievalClient.search(
                baseURL: request.retrievalBaseURL,
                request: retrievalRequest
            )
        }
        try await events.append(
            CodingRunEvent(
                runID: runID,
                type: "retrieval.completed",
                payload: ["result_count": String(retrievalResponse.results.count)]
            )
        )

        record.status = .proposing
        try await ledger.upsert(record)
        let directRoute = router.route(for: request.mode)
        let workerSelection = toolAccess?.selectWorkerTool(
            for: request.mode,
            preferredToolID: request.preferredWorkerToolID
        )
        let context = CodingWorkerContext(
            files: CodingRetrievalFusion.topFiles(from: retrievalResponse.results, limit: 8),
            snippets: CodingRetrievalFusion.topSnippets(from: retrievalResponse.results, limit: 8)
        )
        let workerRequest = CodingWorkerProposeRequest(
            runID: runID,
            repoName: request.repoName,
            repoPath: worktreeURL.path,
            task: request.task,
            mode: request.mode,
            context: context,
            constraints: CodingWorkerConstraints(allowedPaths: request.allowedPaths)
        )
        let workerResponse: CodingWorkerProposeResponse
        if let workerSelection {
            try await events.append(
                CodingRunEvent(
                    runID: runID,
                    type: "worker.tool_selected",
                    payload: [
                        "tool_id": workerSelection.id,
                        "capability": workerSelection.capability,
                    ]
                )
            )
            workerResponse = try await invokeWorkerTool(
                manifest: workerSelection.manifest,
                capability: workerSelection.capability,
                request: workerRequest,
                runID: runID
            )
        } else {
            workerResponse = try await workerClient.propose(baseURL: directRoute.baseURL, request: workerRequest)
        }
        try await events.append(
            CodingRunEvent(
                runID: runID,
                type: "worker.diff_proposed",
                payload: [
                    "worker": workerResponse.worker,
                    "files": String(workerResponse.touchedFiles.count),
                ]
            )
        )

        let violations = policy.validatePaths(workerResponse.touchedFiles)
        guard violations.isEmpty else {
            record.status = .failed
            try await ledger.upsert(record)
            try await events.append(
                CodingRunEvent(
                    runID: runID,
                    type: "policy.blocked",
                    payload: ["paths": violations.joined(separator: ",")]
                )
            )
            throw NSError(
                domain: "IntegratedCodingRunService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Worker touched blocked paths: \(violations.joined(separator: ", "))"]
            )
        }

        try await patchApplyService.apply(diffText: workerResponse.diff, in: worktreeURL)

        record.status = .validating
        try await ledger.upsert(record)
        let validation = await validator.validate(repoURL: worktreeURL)
        try await events.append(
            CodingRunEvent(
                runID: runID,
                type: "validation.completed",
                payload: [
                    "ok": validation.ok ? "true" : "false",
                    "profile": validation.profileName ?? "unknown",
                    "stage_count": String(validation.stageCount),
                    "command_count": String(validation.resolvedCommands.count),
                ]
            )
        )

        record.status = validation.ok ? .awaitingApproval : .failed
        try await ledger.upsert(record)
        try await events.append(
            CodingRunEvent(
                runID: runID,
                type: validation.ok ? "run.awaiting_approval" : "run.failed"
            )
        )

        return IntegratedCodingRunOutcome(
            record: record,
            retrieval: retrievalResponse,
            worker: workerResponse,
            validation: validation
        )
    }

    private func loadToolAccess(for request: IntegratedCodingRunRequest) -> ToolAccess? {
        let registryRoot = request.toolsRootURL ?? CodingToolBootstrap.resolveToolsRoot()
        guard let registryRoot else { return nil }

        let registry = ToolRegistry()
        do {
            try registry.load(from: registryRoot)
            return ToolAccess(registry: registry, policy: ToolPolicy())
        } catch {
            return nil
        }
    }

    private func invokeRetrievalTool(
        manifest: ToolManifest,
        capability: String,
        request: CodingRetrievalRequest,
        runID: String
    ) async throws -> CodingRetrievalResponse {
        let envelope = ToolInvokeEnvelope(
            contractVersion: "1.0",
            runID: runID,
            toolID: manifest.id,
            capability: capability,
            payload: try JSONValue.dictionary(from: request),
            constraints: [:],
            context: [:],
            metadata: ["source": .string("oracle.integrated_run")]
        )
        let response = try await toolClient.invoke(manifest, envelope: envelope)
        if response.status == "error" {
            throw NSError(
                domain: "IntegratedCodingRunService",
                code: 20,
                userInfo: [NSLocalizedDescriptionKey: response.error ?? "Retrieval tool failed"]
            )
        }

        if let payload = try? JSONValue.decode(CodingRetrievalResponse.self, from: response.payload) {
            return payload
        }

        throw NSError(
            domain: "IntegratedCodingRunService",
            code: 21,
            userInfo: [NSLocalizedDescriptionKey: "Retrieval tool returned undecodable payload"]
        )
    }

    private func invokeWorkerTool(
        manifest: ToolManifest,
        capability: String,
        request: CodingWorkerProposeRequest,
        runID: String
    ) async throws -> CodingWorkerProposeResponse {
        let envelope = ToolInvokeEnvelope(
            contractVersion: "1.0",
            runID: runID,
            toolID: manifest.id,
            capability: capability,
            payload: try JSONValue.dictionary(from: request),
            constraints: [:],
            context: [:],
            metadata: ["source": .string("oracle.integrated_run")]
        )
        let response = try await toolClient.invoke(manifest, envelope: envelope)
        if response.status == "error" {
            throw NSError(
                domain: "IntegratedCodingRunService",
                code: 30,
                userInfo: [NSLocalizedDescriptionKey: response.error ?? "Worker tool failed"]
            )
        }

        if let payload = try? JSONValue.decode(CodingWorkerProposeResponse.self, from: response.payload) {
            return payload
        }

        throw NSError(
            domain: "IntegratedCodingRunService",
            code: 31,
            userInfo: [NSLocalizedDescriptionKey: "Worker tool returned undecodable payload"]
        )
    }
}

private struct ToolSelection {
    let manifest: ToolManifest
    let capability: String

    var id: String { manifest.id }
}

private struct ToolAccess {
    let registry: ToolRegistry
    let policy: ToolPolicy

    func selectRetrievalTool(preferredToolID: String?) -> ToolSelection? {
        let router = ToolRouter(registry: registry, policy: policy)
        guard let manifest = router.selectTool(for: "retrieval.code.search", preferredToolID: preferredToolID ?? "cocoindex") else {
            return nil
        }
        return ToolSelection(manifest: manifest, capability: "retrieval.code.search")
    }

    func selectWorkerTool(for mode: CodingRunMode, preferredToolID: String?) -> ToolSelection? {
        let router = ToolRouter(registry: registry, policy: policy)
        switch mode {
        case .interactive:
            let capability = "worker.code.interactive"
            guard let manifest = router.selectTool(for: capability, preferredToolID: preferredToolID ?? "aider") else {
                return nil
            }
            return ToolSelection(manifest: manifest, capability: capability)
        case .autonomous:
            let capability = "worker.code.issue_fix"
            guard let manifest = router.selectTool(for: capability, preferredToolID: preferredToolID ?? "hardened") else {
                return nil
            }
            return ToolSelection(manifest: manifest, capability: capability)
        }
    }
}
