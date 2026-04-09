import AppKit
import ApplicationServices
import Foundation
import OracleControllerShared
import OracleOS

@MainActor
final class ControllerRuntimeBridge {
    let sessionID: String
    let sessionStartedAt: Date
    let traceRecorder: TraceRecorder
    let traceStore: ExperienceStore
    let artifactWriter: FailureArtifactWriter
    let runtimeContext: RuntimeContext
    let oracleRuntime: RuntimeOrchestrator
    let runtimeLifecycle: RuntimeLifecycle
    let diagnosticsBuilder: RuntimeDiagnosticsBuilder
    let codingRuntime: OracleCodingRuntime
    let resultMapper: ControllerRuntimeResultMapper

    init() {
        self.traceRecorder = TraceRecorder()
        self.traceStore = ExperienceStore()
        self.artifactWriter = FailureArtifactWriter()
        self.runtimeContext = RuntimeContext.live(
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter
        )
        self.diagnosticsBuilder = RuntimeDiagnosticsBuilder()
        let eventStore = EventStore()
        let commitCoordinator = CommitCoordinator(eventStore: eventStore, reducers: DefaultReducers.make())
        self.oracleRuntime = RuntimeOrchestrator(
            eventStore: eventStore,
            commitCoordinator: commitCoordinator,
            policyEngine: runtimeContext.policyEngine,
            automationHost: runtimeContext.automationHost,
            workspaceRunner: runtimeContext.workspaceRunner,
            repositoryIndexer: runtimeContext.repositoryIndexer
        )
        self.runtimeLifecycle = RuntimeLifecycle(approvalStore: runtimeContext.approvalStore)
        self.codingRuntime = OracleCodingRuntime()
        self.sessionID = traceRecorder.sessionID
        self.sessionStartedAt = Date()
        self.resultMapper = ControllerRuntimeResultMapper(sessionID: traceRecorder.sessionID)
        self.runtimeLifecycle.startControllerHeartbeat(sessionID: sessionID)
    }

    func currentSession(autoRefreshEnabled: Bool, appName: String?) -> ControllerSession {
        ControllerSession(
            id: sessionID,
            startedAt: sessionStartedAt,
            hostProcessID: getpid(),
            activeAppName: appName ?? NSWorkspace.shared.frontmostApplication?.localizedName,
            autoRefreshEnabled: autoRefreshEnabled
        )
    }

    func refreshSnapshot(appName: String?) -> ControlSnapshot {
        let observation = ObservationBuilder.capture(appName: appName)
        let screenshot = screenshotFrame(appName: appName)
        return ControlSnapshot(observation: map(observation), screenshot: screenshot)
    }

    func healthStatus() -> HealthStatus {
        let claudeConfig = loadClaudeConfig()
        let claudeConfigured = claudeConfig?.server(named: "oracle-os") != nil
        let health = VisionBridge.healthCheck()
        let permissions = [
            PermissionStatus(
                id: "accessibility",
                title: "Accessibility",
                granted: AXIsProcessTrusted(),
                detail: AXIsProcessTrusted() ? "Runtime can inspect and act on apps." : "Grant in System Settings > Privacy & Security > Accessibility."
            ),
            PermissionStatus(
                id: "screen-recording",
                title: "Screen Recording",
                granted: ScreenCapture.hasPermission(),
                detail: ScreenCapture.hasPermission() ? "Live monitor screenshots are available." : "Grant in System Settings > Privacy & Security > Screen Recording."
            ),
        ]
        let toolRegistry = discoverToolRegistryHealth()

        return HealthStatus(
            runtimeVersion: OracleOS.version,
            permissions: permissions,
            claudeConfigured: claudeConfigured,
            visionSidecarRunning: VisionBridge.isAvailable(),
            visionSidecarVersion: health?["version"] as? String,
            visionModelPath: VisionBridge.findModelPath(),
            recipeDirectoryPath: OracleProductPaths.recipesDirectory.path,
            recipeCount: RecipeStore.listRecipes().count,
            traceDirectoryPath: ExperienceStore.traceRootDirectory().path,
            applicationSupportPath: OracleProductPaths.dataRootDirectory.path,
            approvalsDirectoryPath: OracleProductPaths.approvalsDirectory.path,
            projectMemoryDirectoryPath: OracleProductPaths.projectMemoryDirectory.path,
            experimentsDirectoryPath: OracleProductPaths.experimentsDirectory.path,
            logsDirectoryPath: OracleProductPaths.logsDirectory.path,
            graphDatabasePath: OracleProductPaths.graphDatabaseURL.path,
            approvalBrokerActive: runtimeContext.approvalStore.isActive(),
            controllerConnected: runtimeLifecycle.controllerConnected(),
            policyMode: runtimeContext.config.policyMode.rawValue,
            runningFromAppBundle: OracleProductPaths.runningFromAppBundle,
            bundledHostAvailable: OracleProductPaths.runningFromAppBundle,
            bundledVisionBootstrapAvailable: OracleProductPaths.bundledVisionBootstrapDirectory != nil,
            visionInstallPath: OracleProductPaths.visionInstallDirectory.path,
            buildVersion: OracleProductPaths.buildVersion,
            buildNumber: OracleProductPaths.buildNumber,
            toolRegistry: toolRegistry
        )
    }



    private func discoverToolRegistryHealth() -> ToolRegistryHealth? {
        guard let root = CodingToolBootstrap.resolveToolsRoot() else {
            return nil
        }

        do {
            let registry = ToolRegistry()
            try registry.load(from: root)
            let manifests = registry.all().sorted { $0.id < $1.id }
            let tools = manifests.map { manifest in
                ToolHealthStatus(
                    id: manifest.id,
                    name: manifest.name,
                    kind: manifest.kind.rawValue,
                    capabilities: manifest.capabilities.sorted(),
                    baseURL: manifest.baseURL,
                    invokePath: manifest.invokePath,
                    healthPath: manifest.healthPath,
                    riskLevel: manifest.riskLevel.rawValue,
                    healthy: syncToolHealth(manifest),
                    detail: toolHealthDetail(manifest)
                )
            }
            let capabilities = Array(Set(manifests.flatMap(\.capabilities))).sorted()
            return ToolRegistryHealth(
                rootPath: root.path,
                toolCount: tools.count,
                capabilities: capabilities,
                tools: tools
            )
        } catch {
            return ToolRegistryHealth(
                rootPath: root.path,
                toolCount: 0,
                capabilities: [],
                tools: [
                    ToolHealthStatus(
                        id: "registry-error",
                        name: "Tool Registry",
                        kind: "system",
                        capabilities: [],
                        baseURL: root.path,
                        invokePath: "",
                        healthPath: "",
                        riskLevel: "low",
                        healthy: false,
                        detail: error.localizedDescription
                    )
                ]
            )
        }
    }

    private func syncToolHealth(_ manifest: ToolManifest) -> Bool {
        guard let url = URL(string: manifest.baseURL)?.appendingPathComponent(manifest.healthPath) else {
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        var healthy = false
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = TimeInterval(Double(manifest.timeouts.healthMs) / 1000.0)

        let task = URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                healthy = (200 ..< 300).contains(http.statusCode)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + .milliseconds(manifest.timeouts.healthMs + 250))
        return healthy
    }

    private func toolHealthDetail(_ manifest: ToolManifest) -> String {
        let endpoint = "\(manifest.baseURL)\(manifest.healthPath)"
        let caps = manifest.capabilities.joined(separator: ", ")
        return "\(manifest.kind.rawValue) · risk=\(manifest.riskLevel.rawValue) · caps=\(caps) · health=\(endpoint)"
    }

    func diagnosticsSnapshot() -> ControllerDiagnosticsSnapshot {
        let traceEvents = diagnosticsBuilder.loadTraceEvents()
        let observation = ObservationBuilder.capture(appName: nil)
        let hostSnapshot = runtimeContext.automationHost.snapshots.captureSnapshot(appName: observation.app)
        let browserSession = runtimeContext.browserController.snapshot(
            appName: observation.app,
            observation: observation
        ).map { BrowserSession(appName: observation.app ?? $0.browserApp, page: $0, available: true) }
        let snapshot = diagnosticsBuilder.build(
            graphStore: runtimeContext.graphStore,
            traceEvents: traceEvents,
            hostSnapshot: hostSnapshot,
            browserSession: browserSession
        )
        return map(snapshot)
    }

    func executeAction(_ request: ActionRequest) -> ActionRunResult {
        let result: ToolResult = switch request.kind {
        case .focus:
            Actions.focusApp(
                appName: request.appName ?? "",
                windowTitle: request.windowTitle,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_focus"
            )

        case .click:
            Actions.click(
                query: request.query,
                role: request.role,
                domId: request.domID,
                appName: request.appName,
                x: request.x,
                y: request.y,
                button: request.button,
                count: request.count,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_click"
            )

        case .type:
            Actions.typeText(
                text: request.text ?? "",
                into: request.query,
                domId: request.domID,
                appName: request.appName,
                clear: request.clearExisting,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_type"
            )

        case .press:
            Actions.pressKey(
                key: request.key ?? "",
                modifiers: request.modifiers,
                appName: request.appName,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_press"
            )

        case .scroll:
            Actions.scroll(
                direction: request.direction ?? "down",
                amount: request.amount,
                appName: request.appName,
                x: request.x,
                y: request.y,
                runtime: oracleRuntime,
                surface: .controller,
                approvalRequestID: request.approvalRequestID,
                taskID: sessionID,
                toolName: "oracle_scroll"
            )

        case .wait:
            WaitManager.waitFor(
                condition: request.waitCondition ?? "appFrontmost",
                value: request.waitValue,
                appName: request.appName,
                timeout: request.timeout ?? 10,
                interval: request.interval ?? 0.5
            )
        }

        return mapActionResult(request: request, result: result)
    }

    func listRecipes() -> [RecipeDocument] {
        RecipeStore.listRecipes().map(map)
    }

    func loadRecipe(named name: String) -> RecipeDocument? {
        RecipeStore.loadRecipe(named: name).map(map)
    }

    func saveRecipe(_ document: RecipeDocument) throws -> RecipeDocument {
        let savedName: String
        if let rawJSON = document.rawJSON, !rawJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            savedName = try RecipeStore.saveRecipeJSON(rawJSON)
        } else {
            try RecipeStore.saveRecipe(try map(document))
            savedName = document.name
        }
        guard let saved = loadRecipe(named: savedName) else {
            throw OracleError.actionFailed(description: "Saved recipe could not be reloaded")
        }
        return saved
    }

    func deleteRecipe(named name: String) -> Bool {
        RecipeStore.deleteRecipe(named: name)
    }

    func runRecipe(named name: String, params: [String: String]) -> RecipeRunResultDocument {
        guard let recipe = RecipeStore.loadRecipe(named: name) else {
            return RecipeRunResultDocument(
                recipeName: name,
                success: false,
                stepsCompleted: 0,
                totalSteps: 0,
                error: "Recipe not found",
                traceSessionID: sessionID,
                stepResults: []
            )
        }

        let result = RecipeEngine.run(
            recipe: recipe,
            params: params,
            runtime: oracleRuntime,
            taskID: sessionID
        )
        return mapRecipeRunResult(recipeName: name, totalStepsFallback: recipe.steps.count, result: result)
    }

    func resumeRecipe(resumeToken: String, approvalRequestID: String?) -> RecipeRunResultDocument {
        let result = RecipeEngine.resume(
            resumeToken: resumeToken,
            approvalRequestID: approvalRequestID,
            runtime: oracleRuntime,
            taskID: sessionID
        )
        let recipeName = (result.data?["recipe"] as? String) ?? "recipe"
        let recipe = RecipeStore.loadRecipe(named: recipeName)
        return mapRecipeRunResult(
            recipeName: recipeName,
            totalStepsFallback: recipe?.steps.count ?? 0,
            result: result
        )
    }

    func listApprovalRequests() -> [ApprovalRequestDocument] {
        runtimeContext.approvalStore.listPendingRequests().map(map)
    }

    func approveApprovalRequest(id: String) throws -> ApprovalReceipt {
        try runtimeContext.approvalStore.approve(requestID: id)
    }

    func rejectApprovalRequest(id: String) throws {
        try runtimeContext.approvalStore.reject(requestID: id)
    }


    func listCodingRuns() async throws -> [ControllerCodingRun] {
        let runs = try await codingRuntime.listRuns()
        return runs.map(map)
    }

    func loadCodingRun(id: String) async throws -> ControllerCodingRunDetail? {
        guard let detail = try await codingRuntime.loadRun(id: id) else {
            return nil
        }
        return map(detail)
    }

    func startCodingRun(_ submission: ControllerCodingRunSubmission) async throws -> ControllerCodingRunDetail {
        let mode = CodingRunMode(rawValue: submission.mode.rawValue) ?? .interactive
        let request = OracleCodingRunSubmission(
            repoPath: submission.repoPath,
            task: submission.task,
            mode: mode,
            retrievalQuery: submission.retrievalQuery,
            allowedPaths: submission.allowedPaths,
            validationCommands: submission.validationCommands
        )
        let detail = try await codingRuntime.start(request)
        return map(detail)
    }

    func approveCodingRun(id: String, reason: String?) async throws -> ControllerCodingRunDetail? {
        guard let detail = try await codingRuntime.approve(runID: id, reason: reason) else {
            return nil
        }
        return map(detail)
    }

    func rejectCodingRun(id: String, reason: String?) async throws -> ControllerCodingRunDetail? {
        guard let detail = try await codingRuntime.reject(runID: id, reason: reason) else {
            return nil
        }
        return map(detail)
    }

    func recordedSteps(since count: Int) -> [TraceStepViewModel] {
        Array(traceRecorder.allEvents().dropFirst(count)).map(map)
    }

    func recordedStepCount() -> Int {
        traceRecorder.allEvents().count
    }

    func listTraceSessions() -> [TraceSessionSummary] {
        let directory = ExperienceStore.resolveSessionsDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { fileURL in
                let sessionID = fileURL.deletingPathExtension().lastPathComponent
                let lineCount = (try? String(contentsOf: fileURL, encoding: .utf8).split(separator: "\n").count) ?? 0
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                return TraceSessionSummary(id: sessionID, stepCount: lineCount, lastUpdated: values?.contentModificationDate)
            }
            .sorted { ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast) }
    }

    func loadTraceSession(id: String) -> TraceSessionDetail? {
        let fileURL = ExperienceStore.resolveSessionsDirectory().appendingPathComponent("\(id).jsonl")
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let decoder = ControllerJSONCoding.makeDecoder()

        let steps = contents
            .split(separator: "\n")
            .compactMap { line -> TraceEvent? in
                try? decoder.decode(TraceEvent.self, from: Data(line.utf8))
            }
            .map(map)

        let summary = TraceSessionSummary(
            id: id,
            stepCount: steps.count,
            lastUpdated: (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        )

        return TraceSessionDetail(summary: summary, steps: steps)
    }

    private func mapActionResult(request: ActionRequest, result: ToolResult) -> ActionRunResult {
        let observation = ObservationBuilder.capture(appName: request.appName)
        return resultMapper.mapActionResult(
            request: request,
            result: result,
            resultingObservation: map(observation)
        )
    }

    private func mapRecipeRunResult(recipeName: String, totalStepsFallback: Int, result: ToolResult) -> RecipeRunResultDocument {
        resultMapper.mapRecipeRunResult(
            recipeName: recipeName,
            totalStepsFallback: totalStepsFallback,
            result: result
        )
    }

    private func screenshotFrame(appName: String?) -> ScreenshotFrame? {
        let result = AXScanner.screenshot(appName: appName, fullResolution: false)
        guard result.success,
              let data = result.data,
              let base64 = data["image"] as? String,
              let width = data["width"] as? Int,
              let height = data["height"] as? Int
        else {
            return nil
        }

        return ScreenshotFrame(
            base64PNG: base64,
            width: width,
            height: height,
            windowTitle: data["window_title"] as? String
        )
    }

    private func loadClaudeConfig() -> ClaudeConfig? {
        let configURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude.json", isDirectory: false)
        return try? ClaudeConfigStore.loadIfPresent(from: configURL)
    }

    private func map(_ observation: Observation) -> ObservationSnapshot {
        ObservationSnapshot(
            timestamp: observation.timestamp,
            appName: observation.app,
            windowTitle: observation.windowTitle,
            url: observation.url,
            focusedElementID: observation.focusedElementID,
            elements: observation.elements.map(map)
        )
    }

    private func map(_ element: UnifiedElement) -> ElementSnapshot {
        ElementSnapshot(
            id: element.id,
            source: element.source.rawValue,
            role: element.role,
            label: element.label,
            value: element.value,
            frame: element.frame.map {
                ElementFrameSnapshot(
                    x: $0.origin.x,
                    y: $0.origin.y,
                    width: $0.width,
                    height: $0.height
                )
            },
            enabled: element.enabled,
            visible: element.visible,
            focused: element.focused,
            confidence: element.confidence
        )
    }

    private func map(_ recipe: Recipe) -> RecipeDocument {
        let encoder = ControllerJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
        let rawJSON: String?
        if let encoded = try? encoder.encode(recipe) {
            rawJSON = String(data: encoded, encoding: .utf8)
        } else {
            rawJSON = nil
        }
        let params = recipe.params?.reduce(into: [String: RecipeParamDocument]()) { partialResult, entry in
            partialResult[entry.key] = RecipeParamDocument(
                id: entry.key,
                type: entry.value.type,
                description: entry.value.description,
                required: entry.value.required ?? false
            )
        }

        return RecipeDocument(
            schemaVersion: recipe.schemaVersion,
            name: recipe.name,
            description: recipe.description,
            app: recipe.app,
            params: params,
            preconditions: recipe.preconditions.map {
                RecipePreconditionsDocument(
                    appRunning: $0.appRunning,
                    urlContains: $0.urlContains
                )
            },
            steps: recipe.steps.map { step in
                RecipeStepDocument(
                    id: step.id,
                    action: step.action,
                    target: step.target.map(map),
                    params: step.params,
                    waitAfter: step.waitAfter.map { wait in
                        RecipeWaitConditionDocument(
                            condition: wait.condition,
                            target: wait.target.map(map),
                            value: wait.value,
                            timeout: wait.timeout
                        )
                    },
                    note: step.note,
                    onFailure: step.onFailure
                )
            },
            onFailure: recipe.onFailure,
            rawJSON: rawJSON
        )
    }

    private func map(_ document: RecipeDocument) throws -> Recipe {
        let data = try JSONSerialization.data(
            withJSONObject: recipeDictionary(from: document),
            options: [.prettyPrinted, .sortedKeys]
        )
        return try ControllerJSONCoding.makeDecoder().decode(Recipe.self, from: data)
    }

    private func map(_ locator: Locator) -> LocatorDocument {
        LocatorDocument(
            criteria: locator.criteria.map {
                CriterionDocument(
                    attribute: $0.attribute,
                    value: $0.value,
                    matchType: $0.matchType?.rawValue
                )
            },
            computedNameContains: locator.computedNameContains
        )
    }

    private func map(_ document: LocatorDocument) -> Locator {
        Locator(
            criteria: document.criteria.map { criterion in
                Criterion(
                    attribute: criterion.attribute,
                    value: criterion.value,
                    matchType: JSONPathHintComponent.MatchType(rawValue: criterion.matchType ?? "exact") ?? .exact
                )
            },
            computedNameContains: document.computedNameContains
        )
    }

    private func map(_ approval: ApprovalRequest) -> ApprovalRequestDocument {
        ApprovalRequestDocument(
            id: approval.id,
            createdAt: approval.createdAt,
            surface: approval.surface.rawValue,
            toolName: approval.toolName,
            appName: approval.appName,
            displayTitle: approval.displayTitle,
            reason: approval.reason,
            riskLevel: approval.riskLevel.rawValue,
            protectedOperation: approval.protectedOperation.rawValue,
            status: approval.status.rawValue,
            appProtectionProfile: approval.appProtectionProfile.rawValue
        )
    }

    private func map(_ snapshot: RuntimeDiagnosticsSnapshot) -> ControllerDiagnosticsSnapshot {
        ControllerDiagnosticsSnapshot(
            generatedAt: snapshot.generatedAt,
            graph: ControllerGraphDiagnostics(
                stableEdges: snapshot.graph.stableEdges.map(map),
                candidateEdges: snapshot.graph.candidateEdges.map(map),
                recoveryEdges: snapshot.graph.recoveryEdges.map(map),
                promotionEligibleCount: snapshot.graph.promotionEligibleCount,
                promotionsFrozen: snapshot.graph.promotionsFrozen,
                globalSuccessRate: snapshot.graph.globalSuccessRate
            ),
            workflows: snapshot.workflows.map(map),
            experiments: snapshot.experiments.map(map),
            recovery: ControllerRecoveryDiagnostics(
                recoveryStepCount: snapshot.recovery.recoveryStepCount,
                strategies: snapshot.recovery.strategies.map(map)
            ),
            projectMemory: snapshot.projectMemory.map(map),
            architectureFindings: snapshot.architectureFindings.map(map),
            repositoryIndexes: snapshot.repositoryIndexes.map(map),
            host: snapshot.host.map(map),
            browser: snapshot.browser.map(map)
        )
    }

    private func map(_ edge: DiagnosticsGraphEdge) -> ControllerGraphEdgeDiagnostics {
        ControllerGraphEdgeDiagnostics(
            id: edge.id,
            actionContractID: edge.actionContractID,
            fromPlanningStateID: edge.fromPlanningStateID,
            toPlanningStateID: edge.toPlanningStateID,
            agentKind: edge.agentKind,
            domain: edge.domain,
            workspaceRelativePath: edge.workspaceRelativePath,
            commandCategory: edge.commandCategory,
            plannerFamily: edge.plannerFamily,
            knowledgeTier: edge.knowledgeTier,
            attempts: edge.attempts,
            successRate: edge.successRate,
            averageLatencyMs: edge.averageLatencyMs,
            targetAmbiguityRate: edge.targetAmbiguityRate,
            rollingSuccessRate: edge.rollingSuccessRate,
            recoveryTagged: edge.recoveryTagged,
            approvalRequired: edge.approvalRequired,
            approvalOutcome: edge.approvalOutcome,
            lastSuccessAt: edge.lastSuccessAt,
            lastAttemptAt: edge.lastAttemptAt,
            failureHistogram: edge.failureHistogram,
            promotionEligible: edge.promotionEligible
        )
    }

    private func map(_ workflow: DiagnosticsWorkflowSummary) -> ControllerWorkflowDiagnostics {
        ControllerWorkflowDiagnostics(
            id: workflow.id,
            goalPattern: workflow.goalPattern,
            agentKind: workflow.agentKind,
            promotionStatus: workflow.promotionStatus,
            successRate: workflow.successRate,
            replayValidationSuccess: workflow.replayValidationSuccess,
            repeatedTraceSegmentCount: workflow.repeatedTraceSegmentCount,
            stepCount: workflow.stepCount,
            parameterSlots: workflow.parameterSlots,
            sourceTraceRefs: workflow.sourceTraceRefs,
            sourceGraphEdgeRefs: workflow.sourceGraphEdgeRefs,
            stale: workflow.stale
        )
    }

    private func map(_ experiment: DiagnosticsExperimentSummary) -> ControllerExperimentDiagnostics {
        ControllerExperimentDiagnostics(
            id: experiment.id,
            candidateCount: experiment.candidateCount,
            selectedCandidateID: experiment.selectedCandidateID,
            winningSandboxPath: experiment.winningSandboxPath,
            succeededCandidateCount: experiment.succeededCandidateCount,
            candidates: experiment.candidates.map(map)
        )
    }

    private func map(_ candidate: DiagnosticsExperimentCandidate) -> ControllerExperimentCandidateDiagnostics {
        ControllerExperimentCandidateDiagnostics(
            id: candidate.id,
            title: candidate.title,
            summary: candidate.summary,
            workspaceRelativePath: candidate.workspaceRelativePath,
            hypothesis: candidate.hypothesis,
            selected: candidate.selected,
            succeeded: candidate.succeeded,
            architectureRiskScore: candidate.architectureRiskScore,
            sandboxPath: candidate.sandboxPath,
            diffSummary: candidate.diffSummary,
            buildSummary: candidate.buildSummary,
            testSummary: candidate.testSummary,
            architectureFindings: candidate.architectureFindings
        )
    }

    private func map(_ strategy: DiagnosticsRecoveryStrategy) -> ControllerRecoveryStrategyDiagnostics {
        ControllerRecoveryStrategyDiagnostics(
            id: strategy.id,
            attempts: strategy.attempts,
            successes: strategy.successes,
            failures: strategy.failures,
            failureHistogram: strategy.failureHistogram
        )
    }

    private func map(_ record: DiagnosticsProjectMemoryRecord) -> ControllerProjectMemoryDiagnostics {
        ControllerProjectMemoryDiagnostics(
            id: record.id,
            title: record.title,
            summary: record.summary,
            kind: record.kind,
            knowledgeClass: record.knowledgeClass,
            status: record.status,
            path: record.path,
            affectedModules: record.affectedModules,
            evidenceRefs: record.evidenceRefs
        )
    }

    private func map(_ finding: DiagnosticsArchitectureFinding) -> ControllerArchitectureFindingDiagnostics {
        ControllerArchitectureFindingDiagnostics(
            id: finding.id,
            title: finding.title,
            summary: finding.summary,
            severity: finding.severity,
            affectedModules: finding.affectedModules,
            evidence: finding.evidence,
            riskScore: finding.riskScore,
            occurrences: finding.occurrences,
            governanceRuleID: finding.governanceRuleID
        )
    }

    private func map(_ index: DiagnosticsRepositoryIndex) -> ControllerRepositoryIndexDiagnostics {
        ControllerRepositoryIndexDiagnostics(
            id: index.id,
            workspaceRoot: index.workspaceRoot,
            buildTool: index.buildTool,
            activeBranch: index.activeBranch,
            isGitDirty: index.isGitDirty,
            indexedAt: index.indexedAt,
            fileCount: index.fileCount,
            symbolCount: index.symbolCount,
            dependencyCount: index.dependencyCount,
            callEdgeCount: index.callEdgeCount,
            testEdgeCount: index.testEdgeCount,
            buildTargetCount: index.buildTargetCount,
            topSymbols: index.topSymbols,
            buildTargets: index.buildTargets,
            topTests: index.topTests
        )
    }

    private func map(_ summary: OracleCodingRunSummary) -> ControllerCodingRun {
        ControllerCodingRun(
            id: summary.record.id,
            repoName: summary.record.repoName,
            repoPath: summary.record.repoPath,
            mode: ControllerCodingRunMode(rawValue: summary.record.mode.rawValue) ?? .interactive,
            status: ControllerCodingRunStatus(rawValue: summary.record.status.rawValue) ?? .failed,
            task: summary.record.task,
            createdAt: summary.record.createdAt,
            approvalRequired: summary.approvalRequired,
            approvalReasons: summary.pendingApprovalReasons
        )
    }

    private func map(_ detail: OracleCodingRunDetail) -> ControllerCodingRunDetail {
        ControllerCodingRunDetail(
            run: map(detail.summary),
            pendingProposal: detail.pendingProposal.map(map),
            events: detail.events.map(map),
            approvals: detail.approvals.map(map),
            artifactPaths: detail.artifactPaths
        )
    }

    private func map(_ pending: OracleCodingPendingProposal) -> ControllerCodingPendingProposal {
        ControllerCodingPendingProposal(
            worker: pending.worker,
            summary: pending.summary,
            diff: pending.diff,
            touchedPaths: pending.touchedPaths,
            changedLines: pending.changedLines,
            warnings: pending.warnings,
            commandsRequested: pending.commandsRequested,
            approvalReasons: pending.approvalReasons
        )
    }

    private func map(_ event: OracleCodingRunEvent) -> ControllerCodingRunEvent {
        ControllerCodingRunEvent(
            id: event.id,
            runID: event.runID,
            type: event.type,
            timestamp: event.timestamp,
            payload: event.payload
        )
    }

    private func map(_ approval: OracleCodingApprovalDecision) -> ControllerCodingApprovalDecision {
        ControllerCodingApprovalDecision(
            runID: approval.runID,
            approved: approval.approved,
            reason: approval.reason,
            timestamp: approval.timestamp
        )
    }

    private func map(_ host: DiagnosticsHostSnapshot) -> ControllerHostDiagnostics {
        ControllerHostDiagnostics(
            snapshotID: host.snapshotID,
            activeApplication: host.activeApplication,
            accessibilityGranted: host.accessibilityGranted,
            screenRecordingGranted: host.screenRecordingGranted,
            windowCount: host.windowCount,
            menuCount: host.menuCount,
            dialogTitle: host.dialogTitle,
            capturedWindowTitle: host.capturedWindowTitle,
            windows: host.windows.map(map)
        )
    }

    private func map(_ window: DiagnosticsHostWindow) -> ControllerHostWindowDiagnostics {
        ControllerHostWindowDiagnostics(
            id: window.id,
            appName: window.appName,
            title: window.title,
            elementCount: window.elementCount,
            focused: window.focused
        )
    }

    private func map(_ browser: DiagnosticsBrowserSnapshot) -> ControllerBrowserDiagnostics {
        ControllerBrowserDiagnostics(
            appName: browser.appName,
            available: browser.available,
            url: browser.url,
            title: browser.title,
            domain: browser.domain,
            indexedElementCount: browser.indexedElementCount,
            topIndexedLabels: browser.topIndexedLabels,
            simplifiedTextPreview: browser.simplifiedTextPreview
        )
    }

    private func recipeDictionary(from document: RecipeDocument) -> [String: Any] {
        var result: [String: Any] = [
            "schema_version": document.schemaVersion,
            "name": document.name,
            "description": document.description,
            "steps": document.steps.map(recipeStepDictionary),
        ]

        if let app = document.app, !app.isEmpty {
            result["app"] = app
        }
        if let params = document.params, !params.isEmpty {
            result["params"] = Dictionary(uniqueKeysWithValues: params.map { key, value in
                (
                    key,
                    [
                        "type": value.type,
                        "description": value.description,
                        "required": value.required,
                    ] as [String: Any]
                )
            })
        }
        if let preconditions = document.preconditions {
            var preconditionsDict: [String: Any] = [:]
            if let appRunning = preconditions.appRunning, !appRunning.isEmpty {
                preconditionsDict["app_running"] = appRunning
            }
            if let urlContains = preconditions.urlContains, !urlContains.isEmpty {
                preconditionsDict["url_contains"] = urlContains
            }
            if !preconditionsDict.isEmpty {
                result["preconditions"] = preconditionsDict
            }
        }
        if let onFailure = document.onFailure, !onFailure.isEmpty {
            result["on_failure"] = onFailure
        }

        return result
    }

    private func recipeStepDictionary(from step: RecipeStepDocument) -> [String: Any] {
        var result: [String: Any] = [
            "id": step.id,
            "action": step.action,
        ]

        if let target = step.target {
            result["target"] = locatorDictionary(from: target)
        }
        if let params = step.params, !params.isEmpty {
            result["params"] = params
        }
        if let waitAfter = step.waitAfter {
            result["wait_after"] = waitDictionary(from: waitAfter)
        }
        if let note = step.note, !note.isEmpty {
            result["note"] = note
        }
        if let onFailure = step.onFailure, !onFailure.isEmpty {
            result["on_failure"] = onFailure
        }

        return result
    }

    private func waitDictionary(from wait: RecipeWaitConditionDocument) -> [String: Any] {
        var result: [String: Any] = [
            "condition": wait.condition,
        ]
        if let target = wait.target {
            result["target"] = locatorDictionary(from: target)
        }
        if let value = wait.value, !value.isEmpty {
            result["value"] = value
        }
        if let timeout = wait.timeout {
            result["timeout"] = timeout
        }
        return result
    }

    private func locatorDictionary(from locator: LocatorDocument) -> [String: Any] {
        var result: [String: Any] = [
            "criteria": locator.criteria.map { criterion in
                var dictionary: [String: Any] = [
                    "attribute": criterion.attribute,
                    "value": criterion.value,
                ]
                if let matchType = criterion.matchType, !matchType.isEmpty {
                    dictionary["matchType"] = matchType
                }
                return dictionary
            },
        ]
        if let computedNameContains = locator.computedNameContains, !computedNameContains.isEmpty {
            result["computedNameContains"] = computedNameContains
        }
        return result
    }

    private func map(_ event: TraceEvent) -> TraceStepViewModel {
        let notePaths = event.notes?
            .split(separator: "|")
            .compactMap { segment -> String? in
                let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = trimmed.firstIndex(of: "=") {
                    return String(trimmed[trimmed.index(after: index)...])
                }
                return trimmed.hasPrefix("/") ? trimmed : nil
            } ?? []

        let artifactPaths = Array(Set(([event.screenshotPath].compactMap { $0 } + notePaths))).sorted()

        return TraceStepViewModel(
            sessionID: event.sessionID,
            stepID: event.stepID,
            timestamp: event.timestamp,
            toolName: event.toolName,
            actionName: event.actionName,
            actionTarget: event.actionTarget,
            actionText: event.actionText,
            selectedElementID: event.selectedElementID,
            selectedElementLabel: event.selectedElementLabel,
            candidateScore: event.candidateScore,
            candidateReasons: event.candidateReasons,
            preObservationHash: event.preObservationHash,
            postObservationHash: event.postObservationHash,
            postcondition: event.postcondition,
            verified: event.verified,
            success: event.success,
            failureClass: event.failureClass,
            surface: event.surface,
            policyMode: event.policyMode,
            protectedOperation: event.protectedOperation,
            approvalRequestID: event.approvalRequestID,
            approvalOutcome: event.approvalOutcome,
            blockedByPolicy: event.blockedByPolicy ?? false,
            appProfile: event.appProfile,
            agentKind: event.agentKind,
            domain: event.domain,
            plannerFamily: event.plannerFamily,
            workspaceRelativePath: event.workspaceRelativePath,
            commandCategory: event.commandCategory,
            commandSummary: event.commandSummary,
            repositorySnapshotID: event.repositorySnapshotID,
            buildResultSummary: event.buildResultSummary,
            testResultSummary: event.testResultSummary,
            patchID: event.patchID,
            projectMemoryRefs: event.projectMemoryRefs ?? [],
            experimentID: event.experimentID,
            candidateID: event.candidateID,
            sandboxPath: event.sandboxPath,
            selectedCandidate: event.selectedCandidate,
            experimentOutcome: event.experimentOutcome,
            architectureFindings: event.architectureFindings ?? [],
            refactorProposalID: event.refactorProposalID,
            knowledgeTier: event.knowledgeTier,
            elapsedMs: event.elapsedMs,
            screenshotPath: event.screenshotPath,
            artifactPaths: artifactPaths,
            notes: event.notes
        )
    }
}
