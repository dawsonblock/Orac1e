public struct AlternateElementStrategy: RecoveryStrategy {

    public let name = "alternate_element"
    public let layer: RecoveryLayer = .alternateTargeting

    public func prepare(
        failure: FailureClass,
        state: WorldState,
memoryStore: UnifiedMemoryStore
    ) async throws -> RecoveryPreparation? {
        let fallbackLabel = state.observation.focusedElement?.label
        let query = ElementQuery(
            text: state.lastAction?.targetQuery ?? fallbackLabel,
            role: state.lastAction?.role ?? state.observation.focusedElement?.role,
            editable: state.lastAction?.action == "type" || state.lastAction?.action == "fill_form",
            clickable: (state.lastAction?.action == "click" || state.lastAction?.action == "read-file") || state.lastAction == nil,
            visibleOnly: true,
            app: state.observation.app
        )
        guard query.text != nil || query.role != nil else {
            return nil
        }

        let alternate = state.rankedCandidates(query: query, memoryStore: memoryStore)
            .first {
                $0.element.id != state.lastAction?.elementID
                    && $0.element.id != state.observation.focusedElementID
                    && $0.score >= OSTargetResolver.minimumScore
            }

        guard let alternate else {
            return nil
        }

        let intent: ActionIntent
        switch state.lastAction?.action {
        case "type", "fill_form":
            intent = .type(
                app: state.observation.app,
                into: alternate.element.label ?? query.text,
                domID: alternate.element.id,
                text: state.lastAction?.text ?? ""
            )
        case "read-file":
            intent = ActionIntent(
                agentKind: .os,
                app: state.observation.app ?? "Finder",
                name: "read file \(alternate.element.label ?? query.text ?? "")",
                action: "read-file",
                query: alternate.element.label ?? query.text,
                role: alternate.element.role,
                domID: alternate.element.id
            )
        default:
            intent = .click(
                app: state.observation.app,
                query: alternate.element.label ?? query.text,
                role: alternate.element.role,
                domID: alternate.element.id
            )
        }

        return RecoveryPreparation(
            strategyName: name,
            resolution: SkillResolution(
                intent: intent,
                selectedCandidate: alternate,
                semanticQuery: query
            ),
            notes: ["switching to alternate candidate after \(failure.rawValue)"]
        )
    }
}
