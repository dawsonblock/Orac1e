import Foundation
import OracleControllerShared
import OracleOS

actor HostOutput {
    private let encoder: JSONEncoder
    private let handle: FileHandle

    init(handle: FileHandle = .standardOutput) {
        self.handle = handle
        self.encoder = ControllerJSONCoding.makeEncoder(outputFormatting: [.sortedKeys])
    }

    func send(response: ControllerHostResponse) {
        sendEnvelope(ControllerHostEnvelope(response: response))
    }

    func send(event: ControllerHostEvent) {
        sendEnvelope(ControllerHostEnvelope(event: event))
    }

    private func sendEnvelope(_ envelope: ControllerHostEnvelope) {
        guard let data = try? encoder.encode(envelope) else { return }
        handle.write(data)
        handle.write(Data("\n".utf8))
    }
}

actor ControllerHostServer {
    private let output: HostOutput
    private let bridge: ControllerRuntimeBridge
    private var monitoringTask: Task<Void, Never>?
    private var monitoringConfiguration = MonitoringConfiguration(enabled: false)
    private var lastHealth: HealthStatus?
    private let chatPersistenceURL: URL
    private var chatConversation: ChatConversation?
    private var chatTask: Task<Void, Never>?

    init(output: HostOutput, bridge: ControllerRuntimeBridge) {
        self.output = output
        self.bridge = bridge
        self.chatPersistenceURL = OracleProductPaths.chatDirectory.appendingPathComponent("latest-conversation.json", isDirectory: false)
        self.chatConversation = Self.loadConversation(from: self.chatPersistenceURL)
    }

    func handle(_ request: ControllerHostRequest) async {
        switch request.command {
        case .bootstrap:
            let snapshot = await MainActor.run { bridge.refreshSnapshot(appName: request.appName) }
            let health = await MainActor.run { bridge.healthStatus() }
            let providerStatus = await MainActor.run { bridge.chatProviderStatus() }
            let missionControl = await MainActor.run { bridge.missionControlSnapshot(appName: request.appName) }
            lastHealth = health
            let monitoring = monitoringConfiguration
            let existingConversation = chatConversation
            let bootstrap = await MainActor.run {
                DashboardBootstrap(
                    session: bridge.currentSession(
                        autoRefreshEnabled: monitoring.enabled,
                        appName: request.appName
                    ),
                    snapshot: snapshot,
                    health: health,
                    recipes: bridge.listRecipes(),
                    traceSessions: bridge.listTraceSessions(),
                    approvals: bridge.listApprovalRequests(),
                    missionControl: missionControl,
                    chatConversation: existingConversation,
                    chatProviderStatus: providerStatus
                )
            }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                bootstrap: bootstrap
            ))

        case .refreshSnapshot:
            let snapshot = await MainActor.run { bridge.refreshSnapshot(appName: request.appName) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                snapshot: snapshot
            ))

        case .refreshMissionControl:
            let appName = request.appName ?? monitoringConfiguration.appName
            let missionControl = await MainActor.run {
                bridge.missionControlSnapshot(appName: appName)
            }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                missionControl: missionControl,
                chatProviderStatus: missionControl.providerStatus
            ))

        case .sendChatMessage:
            guard let prompt = request.chatPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing chat prompt"
                ))
                return
            }

            let appName = request.appName ?? monitoringConfiguration.appName
            let missionControl = await MainActor.run {
                bridge.missionControlSnapshot(appName: appName)
            }
            let providerStatus = missionControl.providerStatus
            let conversation = upsertConversation(with: prompt, conversationID: request.conversationID)
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                acknowledged: true,
                missionControl: missionControl,
                chatConversation: conversation,
                chatProviderStatus: providerStatus
            ))
            startChatResponse(
                prompt: prompt,
                missionControl: missionControl,
                providerStatus: providerStatus
            )

        case .cancelChatMessage:
            chatTask?.cancel()
            chatTask = nil
            let updatedConversation = markActiveAssistantMessageStopped(
                fallback: "Response cancelled."
            )
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                acknowledged: true,
                chatConversation: updatedConversation,
                chatProviderStatus: await MainActor.run { bridge.chatProviderStatus() }
            ))
            if let updatedConversation {
                await output.send(event: ControllerHostEvent(
                    kind: .chatMessageCompleted,
                    chatConversation: updatedConversation,
                    chatProviderStatus: await MainActor.run { bridge.chatProviderStatus() }
                ))
            }

        case .listCodingRuns:
            do {
                let runs = try await bridge.listCodingRuns()
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    codingRuns: runs
                ))
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .loadCodingRun:
            guard let runID = request.codingRunID else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing coding run id"
                ))
                return
            }
            do {
                let detail = try await bridge.loadCodingRun(id: runID)
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    codingRunDetail: detail,
                    errorMessage: detail == nil ? "Run not found" : nil
                ))
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .startCodingRun:
            guard let submission = request.codingRunSubmission else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing coding run submission"
                ))
                return
            }
            do {
                let detail = try await bridge.startCodingRun(submission)
                let runs = try await bridge.listCodingRuns()
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    codingRuns: runs,
                    codingRunDetail: detail
                ))
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .approveCodingRun:
            guard let runID = request.codingRunID else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing coding run id"
                ))
                return
            }
            do {
                let detail = try await bridge.approveCodingRun(id: runID, reason: request.codingRunReason)
                let runs = try await bridge.listCodingRuns()
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    codingRuns: runs,
                    codingRunDetail: detail,
                    errorMessage: detail == nil ? "Run not found" : nil
                ))
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .rejectCodingRun:
            guard let runID = request.codingRunID else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing coding run id"
                ))
                return
            }
            do {
                let detail = try await bridge.rejectCodingRun(id: runID, reason: request.codingRunReason)
                let runs = try await bridge.listCodingRuns()
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    codingRuns: runs,
                    codingRunDetail: detail,
                    errorMessage: detail == nil ? "Run not found" : nil
                ))
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .getHealth:
            let health = await MainActor.run { bridge.healthStatus() }
            lastHealth = health
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                health: health
            ))

        case .getDiagnostics:
            let diagnostics = await MainActor.run { bridge.diagnosticsSnapshot() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                diagnostics: diagnostics
            ))

        case .performAction:
            guard let action = request.action else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing action payload"
                ))
                return
            }

            let stepCountBefore = await MainActor.run { bridge.recordedStepCount() }
            let monitoring = monitoringConfiguration
            let session = await MainActor.run {
                bridge.currentSession(autoRefreshEnabled: monitoring.enabled, appName: action.appName)
            }
            await output.send(event: ControllerHostEvent(kind: .actionStarted, session: session, message: action.displayTitle))
            let actionResult = await MainActor.run { bridge.executeAction(action) }
            let newSteps = await MainActor.run { bridge.recordedSteps(since: stepCountBefore) }
            let approvals = await MainActor.run { bridge.listApprovalRequests() }

            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                actionResult: actionResult,
                approvals: approvals
            ))
            await output.send(event: ControllerHostEvent(kind: .actionCompleted, session: session, action: actionResult))
            await output.send(event: ControllerHostEvent(kind: .approvalsChanged, session: session, approvals: approvals))
            for step in newSteps {
                await output.send(event: ControllerHostEvent(kind: .traceStepAppended, session: session, traceStep: step))
            }
            await emitMissionControlUpdate(appName: action.appName)

        case .listApprovalRequests:
            let approvals = await MainActor.run { bridge.listApprovalRequests() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                approvals: approvals
            ))

        case .approveApprovalRequest:
            guard let approvalRequestID = request.approvalRequestID else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing approval request id"
                ))
                return
            }

            do {
                _ = try await MainActor.run { try bridge.approveApprovalRequest(id: approvalRequestID) }
                let approvals = await MainActor.run { bridge.listApprovalRequests() }
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: true,
                    approvals: approvals
                ))
                await output.send(event: ControllerHostEvent(kind: .approvalsChanged, approvals: approvals))
                await emitMissionControlUpdate(appName: monitoringConfiguration.appName)
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .rejectApprovalRequest:
            guard let approvalRequestID = request.approvalRequestID else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing approval request id"
                ))
                return
            }

            do {
                try await MainActor.run { try bridge.rejectApprovalRequest(id: approvalRequestID) }
                let approvals = await MainActor.run { bridge.listApprovalRequests() }
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: true,
                    approvals: approvals
                ))
                await output.send(event: ControllerHostEvent(kind: .approvalsChanged, approvals: approvals))
                await emitMissionControlUpdate(appName: monitoringConfiguration.appName)
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .listRecipes:
            let recipes = await MainActor.run { bridge.listRecipes() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                recipes: recipes
            ))

        case .loadRecipe:
            guard let recipeName = request.recipeName else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing recipe name"
                ))
                return
            }

            let recipe = await MainActor.run { bridge.loadRecipe(named: recipeName) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                recipe: recipe,
                errorMessage: recipe == nil ? "Recipe not found" : nil
            ))

        case .saveRecipe:
            guard let recipe = request.recipe else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing recipe payload"
                ))
                return
            }

            do {
                let saved = try await MainActor.run { try bridge.saveRecipe(recipe) }
                let recipes = await MainActor.run { bridge.listRecipes() }
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    recipe: saved
                ))
                await output.send(event: ControllerHostEvent(kind: .recipesChanged, recipes: recipes))
            } catch {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: error.localizedDescription
                ))
            }

        case .deleteRecipe:
            guard let recipeName = request.recipeName else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing recipe name"
                ))
                return
            }
            let deleted = await MainActor.run { bridge.deleteRecipe(named: recipeName) }
            let recipes = await MainActor.run { bridge.listRecipes() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                acknowledged: deleted,
                errorMessage: deleted ? nil : "Recipe not found"
            ))
            await output.send(event: ControllerHostEvent(kind: .recipesChanged, recipes: recipes))

        case .runRecipe:
            guard let recipeName = request.recipeName else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing recipe name"
                ))
                return
            }
            let stepCountBefore = await MainActor.run { bridge.recordedStepCount() }
            let monitoring = monitoringConfiguration
            let session = await MainActor.run {
                bridge.currentSession(
                    autoRefreshEnabled: monitoring.enabled,
                    appName: monitoring.appName
                )
            }
            let runResult = await MainActor.run {
                bridge.runRecipe(named: recipeName, params: request.recipeParams ?? [:])
            }
            let newSteps = await MainActor.run { bridge.recordedSteps(since: stepCountBefore) }
            let approvals = await MainActor.run { bridge.listApprovalRequests() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                recipeRun: runResult,
                approvals: approvals
            ))
            await output.send(event: ControllerHostEvent(kind: .approvalsChanged, session: session, approvals: approvals))
            for step in newSteps {
                await output.send(event: ControllerHostEvent(kind: .traceStepAppended, session: session, traceStep: step))
            }
            await emitMissionControlUpdate(appName: monitoring.appName)

        case .resumeRecipeRun:
            guard let resumeToken = request.resumeToken else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing resume token"
                ))
                return
            }
            let stepCountBefore = await MainActor.run { bridge.recordedStepCount() }
            let monitoring = monitoringConfiguration
            let session = await MainActor.run {
                bridge.currentSession(
                    autoRefreshEnabled: monitoring.enabled,
                    appName: monitoring.appName
                )
            }
            let runResult = await MainActor.run {
                bridge.resumeRecipe(resumeToken: resumeToken, approvalRequestID: request.approvalRequestID)
            }
            let approvals = await MainActor.run { bridge.listApprovalRequests() }
            let newSteps = await MainActor.run { bridge.recordedSteps(since: stepCountBefore) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                recipeRun: runResult,
                approvals: approvals
            ))
            await output.send(event: ControllerHostEvent(kind: .approvalsChanged, session: session, approvals: approvals))
            for step in newSteps {
                await output.send(event: ControllerHostEvent(kind: .traceStepAppended, session: session, traceStep: step))
            }
            await emitMissionControlUpdate(appName: monitoring.appName)

        case .listTraceSessions:
            let traces = await MainActor.run { bridge.listTraceSessions() }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                traceSessions: traces
            ))

        case .loadTraceSession:
            guard let traceSessionID = request.traceSessionID else {
                await output.send(response: ControllerHostResponse(
                    requestID: request.id,
                    command: request.command,
                    acknowledged: false,
                    errorMessage: "Missing trace session id"
                ))
                return
            }
            let detail = await MainActor.run { bridge.loadTraceSession(id: traceSessionID) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                traceDetail: detail,
                errorMessage: detail == nil ? "Trace session not found" : nil
            ))

        case .setMonitoring:
            monitoringConfiguration = request.monitoring ?? MonitoringConfiguration(enabled: false)
            restartMonitoringLoop()
            let monitoring = monitoringConfiguration
            let session = await MainActor.run {
                bridge.currentSession(
                    autoRefreshEnabled: monitoring.enabled,
                    appName: monitoring.appName
                )
            }
            let snapshot = await MainActor.run { bridge.refreshSnapshot(appName: monitoring.appName) }
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                acknowledged: true
            ))
            await output.send(event: ControllerHostEvent(kind: .observationUpdated, session: session, snapshot: snapshot))
            await emitMissionControlUpdate(appName: monitoring.appName)

        case .ping:
            await output.send(response: ControllerHostResponse(
                requestID: request.id,
                command: request.command,
                acknowledged: true
            ))
        }
    }

    private func upsertConversation(with prompt: String, conversationID: String?) -> ChatConversation {
        let now = Date()
        let current = (chatConversation?.id == conversationID || conversationID == nil) ? chatConversation : nil
        let conversationID = current?.id ?? conversationID ?? UUID().uuidString
        let title = current?.title ?? suggestedConversationTitle(for: prompt)
        let createdAt = current?.createdAt ?? now
        let userMessage = ChatMessage(
            id: UUID().uuidString,
            role: .user,
            content: prompt,
            createdAt: now
        )
        let assistantMessage = ChatMessage(
            id: UUID().uuidString,
            role: .assistant,
            content: "",
            createdAt: now,
            isStreaming: true
        )
        let conversation = ChatConversation(
            id: conversationID,
            title: title,
            createdAt: createdAt,
            updatedAt: now,
            messages: (current?.messages ?? []) + [userMessage, assistantMessage]
        )
        chatConversation = conversation
        persistConversation()
        return conversation
    }

    private func startChatResponse(
        prompt: String,
        missionControl: MissionControlSnapshot,
        providerStatus: ChatProviderStatus
    ) {
        chatTask?.cancel()
        guard let conversation = chatConversation,
              let assistantMessageID = conversation.messages.last?.id
        else {
            return
        }

        chatTask = Task {
            let finalText: String
            do {
                if providerStatus.state == .ready {
                    finalText = try await ClaudeLocalCopilot.complete(
                        conversation: conversation,
                        prompt: prompt,
                        missionControl: missionControl
                    ) { chunk in
                        let updatedConversation = await self.appendChatDelta(
                            messageID: assistantMessageID,
                            delta: chunk
                        )
                        if let updatedConversation {
                            await self.output.send(event: ControllerHostEvent(
                                kind: .chatStreamDelta,
                                chatConversation: updatedConversation,
                                chatProviderStatus: providerStatus,
                                chatMessageID: assistantMessageID,
                                chatDelta: chunk
                            ))
                        }
                    }
                } else {
                    finalText = ClaudeLocalCopilot.setupGuidance(for: providerStatus)
                }
            } catch {
                finalText = "Copilot response failed: \(error.localizedDescription)"
            }

            let completedConversation = self.completeChatMessage(
                messageID: assistantMessageID,
                content: finalText,
                citations: ClaudeLocalCopilot.citations(for: prompt, missionControl: missionControl),
                draftActions: ClaudeLocalCopilot.drafts(for: missionControl)
            )
            await output.send(event: ControllerHostEvent(
                kind: .chatMessageCompleted,
                chatConversation: completedConversation,
                chatProviderStatus: providerStatus,
                chatMessageID: assistantMessageID
            ))
        }
    }

    private func appendChatDelta(messageID: String, delta: String) -> ChatConversation? {
        guard var conversation = chatConversation else { return nil }
        let updatedMessages = conversation.messages.map { message in
            guard message.id == messageID else { return message }
            return ChatMessage(
                id: message.id,
                role: message.role,
                content: message.content + delta,
                createdAt: message.createdAt,
                isStreaming: true,
                citations: message.citations,
                draftActions: message.draftActions
            )
        }
        conversation = ChatConversation(
            id: conversation.id,
            title: conversation.title,
            createdAt: conversation.createdAt,
            updatedAt: Date(),
            messages: updatedMessages
        )
        chatConversation = conversation
        persistConversation()
        return conversation
    }

    private func completeChatMessage(
        messageID: String,
        content: String,
        citations: [ChatCitation],
        draftActions: [ChatActionDraft]
    ) -> ChatConversation {
        let current = chatConversation ?? ChatConversation(id: UUID().uuidString, title: "Copilot")
        let updatedMessages = current.messages.map { message in
            guard message.id == messageID else { return message }
            return ChatMessage(
                id: message.id,
                role: message.role,
                content: content,
                createdAt: message.createdAt,
                isStreaming: false,
                citations: citations,
                draftActions: draftActions
            )
        }
        let conversation = ChatConversation(
            id: current.id,
            title: current.title,
            createdAt: current.createdAt,
            updatedAt: Date(),
            messages: updatedMessages
        )
        chatConversation = conversation
        persistConversation()
        return conversation
    }

    private func markActiveAssistantMessageStopped(fallback: String) -> ChatConversation? {
        guard let current = chatConversation,
              let message = current.messages.last,
              message.role == .assistant
        else {
            return chatConversation
        }

        let updatedMessages = Array(current.messages.dropLast()) + [
            ChatMessage(
                id: message.id,
                role: message.role,
                content: message.content.isEmpty ? fallback : message.content,
                createdAt: message.createdAt,
                isStreaming: false,
                citations: message.citations,
                draftActions: message.draftActions
            ),
        ]

        let conversation = ChatConversation(
            id: current.id,
            title: current.title,
            createdAt: current.createdAt,
            updatedAt: Date(),
            messages: Array(updatedMessages)
        )
        chatConversation = conversation
        persistConversation()
        return conversation
    }

    private func emitMissionControlUpdate(appName: String?) async {
        let actualAppName = appName ?? monitoringConfiguration.appName
        let missionControl = await MainActor.run {
            bridge.missionControlSnapshot(appName: actualAppName)
        }
        await output.send(event: ControllerHostEvent(
            kind: .missionControlChanged,
            missionControl: missionControl,
            chatProviderStatus: missionControl.providerStatus
        ))
    }

    private func persistConversation() {
        guard let chatConversation else { return }
        do {
            try FileManager.default.createDirectory(
                at: chatPersistenceURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = ControllerJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
            let data = try encoder.encode(chatConversation)
            try data.write(to: chatPersistenceURL, options: .atomic)
        } catch {
            // Persistence failure should not crash the host process.
        }
    }

    private func suggestedConversationTitle(for prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Mission Control Copilot" }
        return trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed
    }

    private static func loadConversation(from url: URL) -> ChatConversation? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = ControllerJSONCoding.makeDecoder()
        return try? decoder.decode(ChatConversation.self, from: data)
    }

    private func restartMonitoringLoop() {
        monitoringTask?.cancel()
        guard monitoringConfiguration.enabled else { return }

        let monitoring = monitoringConfiguration
        let interval = UInt64(max(250, monitoring.intervalMs)) * 1_000_000
        monitoringTask = Task {
            while !Task.isCancelled {
                let snapshot = await MainActor.run { bridge.refreshSnapshot(appName: monitoring.appName) }
                let health = await MainActor.run { bridge.healthStatus() }
                let session = await MainActor.run {
                    bridge.currentSession(
                        autoRefreshEnabled: monitoring.enabled,
                        appName: monitoring.appName
                    )
                }
                await output.send(event: ControllerHostEvent(kind: .observationUpdated, session: session, snapshot: snapshot))
                if health != lastHealth {
                    lastHealth = health
                    await output.send(event: ControllerHostEvent(kind: .healthChanged, session: session, health: health))
                    await emitMissionControlUpdate(appName: monitoring.appName)
                }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }
}
