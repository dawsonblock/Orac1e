import SwiftUI
import OracleControllerShared

struct CopilotDockView<Inspector: View>: View {
    @Bindable var store: ControllerStore
    @ViewBuilder let inspector: Inspector

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("AI Copilot", subtitle: store.chatProviderStatus?.detail ?? "Local advisory assistant for runtime state") {
                    HStack(spacing: 8) {
                        StatusBadge(
                            label: store.chatProviderStatus?.displayName ?? "Copilot",
                            tone: store.chatProviderStatus?.state == .ready ? .good : .warning
                        )
                        if let state = store.chatProviderStatus?.state {
                            StatusBadge(
                                label: state.rawValue.replacingOccurrences(of: "_", with: " ").capitalized,
                                tone: state == .ready ? .good : .warning
                            )
                        }
                    }

                    ChipRow(values: store.copilotContextChips)

                    if let messages = store.chatConversation?.messages, !messages.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(messages) { message in
                                ChatMessageBubble(message: message, store: store)
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "message.badge.waveform",
                            title: "Copilot is ready for context",
                            message: "Ask for runtime triage, approval summaries, trace interpretation, or the safest next step."
                        )
                        .frame(height: 220)
                    }

                    if let prompts = store.missionControl?.recommendedPrompts, !prompts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested prompts")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            ChipRow(values: prompts) { prompt in
                                store.chatInput = prompt
                                Task { await store.sendChatMessage() }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Ask the controller copilot", text: $store.chatInput, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)

                        HStack {
                            if store.isChatStreaming {
                                Button("Cancel") {
                                    Task { await store.cancelChatMessage() }
                                }
                                .buttonStyle(.bordered)
                            }

                            Spacer()

                            Button("Send") {
                                Task { await store.sendChatMessage() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                PanelCard("Inspector", subtitle: store.selectedSection.title) {
                    inspector
                }
            }
            .padding(16)
        }
        .frame(minWidth: 420)
    }
}

private struct ChipRow: View {
    let values: [String]
    var action: ((String) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button {
                        action?(value)
                    } label: {
                        Text(value)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.7), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(ControllerTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(action == nil)
                }
            }
        }
    }
}

private struct ChatMessageBubble: View {
    let message: ChatMessage
    @Bindable var store: ControllerStore

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            Text(message.role.rawValue.capitalized)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(message.content.isEmpty && message.isStreaming ? "Thinking…" : message.content)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                .padding(12)
                .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !message.citations.isEmpty {
                ChipRow(values: message.citations.map(\.title)) { title in
                    guard let citation = message.citations.first(where: { $0.title == title }) else { return }
                    store.openCitation(citation)
                }
            }

            if !message.draftActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(message.draftActions) { draft in
                        Button {
                            Task { await store.applyDraft(draft) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.title)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(draft.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var bubbleColor: Color {
        switch message.role {
        case .system:
            return Color.white.opacity(0.72)
        case .user:
            return ControllerTheme.accent.opacity(0.14)
        case .assistant:
            return Color.white.opacity(0.8)
        }
    }
}
