import Foundation
import OracleControllerShared

extension ControllerStore {
    var latestAssistantMessage: ChatMessage? {
        chatConversation?.messages.last(where: { $0.role == .assistant })
    }

    var latestUserMessage: ChatMessage? {
        chatConversation?.messages.last(where: { $0.role == .user })
    }

    var isChatStreaming: Bool {
        latestAssistantMessage?.isStreaming == true
    }

    var copilotContextChips: [String] {
        var chips: [String] = []

        if let appName = snapshot?.observation.appName, !appName.isEmpty {
            chips.append(appName)
        }

        chips.append(selectedSection.title)

        if !approvalQueue.isEmpty {
            chips.append("\(approvalQueue.count) approvals")
        }

        if let traces = missionControl?.traceSessions.count, traces > 0 {
            chips.append("\(traces) traces")
        }

        if let provider = chatProviderStatus?.displayName {
            chips.append(provider)
        }

        return Array(chips.prefix(4))
    }

    func refreshMissionControl() async {
        do {
            let response = try await send(.init(command: .refreshMissionControl, appName: currentMonitorApp))
            if let missionControl = response.missionControl {
                self.missionControl = missionControl
            }
            if let providerStatus = response.chatProviderStatus {
                chatProviderStatus = providerStatus
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleDiagnosticsRefresh(delayMs: UInt64 = 300) {
        diagnosticsRefreshTask?.cancel()
        diagnosticsRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadDiagnostics()
        }
    }

    func scheduleMissionControlRefresh(delayMs: UInt64 = 300) {
        missionControlRefreshTask?.cancel()
        missionControlRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshMissionControl()
        }
    }

    func sendChatMessage() async {
        guard let prompt = chatInput.nilIfBlank else { return }
        let conversationID = chatConversation?.id
        chatInput = ""

        do {
            let response = try await send(
                .init(
                    command: .sendChatMessage,
                    appName: currentMonitorApp,
                    conversationID: conversationID,
                    chatPrompt: prompt
                )
            )
            if let missionControl = response.missionControl {
                self.missionControl = missionControl
            }
            if let conversation = response.chatConversation {
                chatConversation = conversation
            }
            if let providerStatus = response.chatProviderStatus {
                chatProviderStatus = providerStatus
            }
        } catch {
            chatInput = prompt
            errorMessage = error.localizedDescription
        }
    }

    func cancelChatMessage() async {
        do {
            let response = try await send(
                .init(
                    command: .cancelChatMessage,
                    conversationID: chatConversation?.id,
                    chatMessageID: latestAssistantMessage?.id
                )
            )
            if let conversation = response.chatConversation {
                chatConversation = conversation
            }
            if let providerStatus = response.chatProviderStatus {
                chatProviderStatus = providerStatus
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyDraft(_ draft: ChatActionDraft) async {
        switch draft.kind {
        case .action:
            guard let actionRequest = draft.actionRequest else { return }
            await executeAction(actionRequest)

        case .recipe:
            guard let recipeName = draft.recipeName else { return }
            selectedSection = .recipes
            await selectRecipe(named: recipeName)
            await runSelectedRecipe()

        case .openSection:
            guard let sectionID = draft.sectionID,
                  let section = WorkspaceSection(rawValue: sectionID)
            else {
                return
            }
            selectedSection = section
        }
    }

    func openCitation(_ citation: ChatCitation) {
        if let sectionID = citation.targetSectionID,
           let section = WorkspaceSection(rawValue: sectionID)
        {
            selectedSection = section
        }

        switch citation.kind {
        case .trace:
            if let traceID = citation.targetID {
                Task { await loadTraceSession(id: traceID) }
            }

        case .approval:
            selectedSection = .missionControl

        case .recipe:
            if let recipeName = citation.targetID {
                Task {
                    selectedSection = .recipes
                    await selectRecipe(named: recipeName)
                }
            }

        case .health, .diagnostics, .section:
            break
        }
    }
}
