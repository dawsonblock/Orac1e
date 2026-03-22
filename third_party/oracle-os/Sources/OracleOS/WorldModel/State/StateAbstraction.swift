import Foundation

public final class StateAbstraction {
    public init() {}

    public func abstract(
        observation: Observation,
        repositorySnapshot: RepositorySnapshot? = nil,
        observationHash: String
    ) -> PlanningState {
        let features = extractFeatures(from: observation, repositorySnapshot: repositorySnapshot)
        let clusterKey = StateClusterKey(rawValue: buildClusterKey(from: features))
        let stateID = PlanningStateID(rawValue: clusterKey.rawValue)

        return PlanningState(
            id: stateID,
            clusterKey: clusterKey,
            appID: features.appID,
            domain: features.domain,
            windowClass: features.windowClass,
            taskPhase: features.taskPhase,
            focusedRole: features.focusedRole,
            modalClass: features.modalClass,
            navigationClass: features.navigationClass,
            controlContext: features.controlContext
        )
    }

    private func extractFeatures(from observation: Observation, repositorySnapshot: RepositorySnapshot?) -> StateFeatures {
        if let repositorySnapshot {
            return extractCodeFeatures(from: observation, repositorySnapshot: repositorySnapshot)
        }

        let appID = normalizedAppID(from: observation)
        let domain = normalizedDomain(from: observation.url)
        let windowClass = normalizedWindowClass(from: observation.windowTitle, appID: appID)
        let taskPhase = inferredTaskPhase(from: observation, appID: appID)
        let focusedRole = observation.focusedElement?.role
        let modalClass = inferredModalClass(from: observation)
        let navigationClass = inferredNavigationClass(from: observation, domain: domain)
        let controlContext = inferredControlContext(from: observation)

        return StateFeatures(
            appID: appID,
            domain: domain,
            windowClass: windowClass,
            taskPhase: taskPhase,
            focusedRole: focusedRole,
            modalClass: modalClass,
            navigationClass: navigationClass,
            controlContext: controlContext
        )
    }

    private func extractCodeFeatures(
        from observation: Observation,
        repositorySnapshot: RepositorySnapshot
    ) -> StateFeatures {
        let branch = repositorySnapshot.activeBranch ?? "detached"
        let taskPhase = repositorySnapshot.isGitDirty ? "code-dirty" : "code-clean"
        let focusedRole = observation.focusedElement?.role ?? "repository"
        let controlContext = [
            "tool:\(repositorySnapshot.buildTool.rawValue)",
            "tests:\(repositorySnapshot.testGraph.tests.count)",
            "files:\(repositorySnapshot.files.count)",
        ].joined(separator: "|")

        return StateFeatures(
            appID: "Workspace",
            domain: repositorySnapshot.buildTool.rawValue,
            windowClass: branch,
            taskPhase: taskPhase,
            focusedRole: focusedRole,
            modalClass: nil,
            navigationClass: "code",
            controlContext: controlContext
        )
    }

    private func buildClusterKey(from features: StateFeatures) -> String {
        [
            features.appID,
            features.domain ?? "none",
            features.windowClass ?? "none",
            features.taskPhase ?? "none",
            features.focusedRole ?? "none",
            features.modalClass ?? "none",
            features.navigationClass ?? "none",
            features.controlContext ?? "none",
        ].joined(separator: "|")
    }

    private func normalizedAppID(from observation: Observation) -> String {
        let raw = observation.app?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? raw! : "Unknown"
    }

    private func normalizedDomain(from urlString: String?) -> String? {
        guard let urlString,
              let url = URL(string: urlString),
              let host = url.host?.lowercased()
        else {
            return nil
        }
        return host
    }

    private func normalizedWindowClass(from windowTitle: String?, appID: String) -> String? {
        guard let windowTitle else { return nil }
        let title = windowTitle.lowercased()

        if title.contains("compose") {
            return "\(appID.lowercased())-compose"
        }
        if title.contains("inbox") {
            return "\(appID.lowercased())-inbox"
        }
        if title.contains("settings") {
            return "\(appID.lowercased())-settings"
        }
        if title.contains("finder") {
            return "finder-window"
        }

        return title
            .components(separatedBy: " - ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferredTaskPhase(from observation: Observation, appID: String) -> String? {
        let title = observation.windowTitle?.lowercased() ?? ""
        let labels = observation.elements.compactMap { $0.label?.lowercased() }

        if appID.localizedCaseInsensitiveContains("chrome") || appID.localizedCaseInsensitiveContains("safari") {
            if title.contains("compose") || labels.contains(where: { $0.contains("send") }) {
                return "compose"
            }
            if title.contains("inbox") || labels.contains(where: { $0.contains("compose") }) {
                return "browse"
            }
        }

        if labels.contains(where: { $0.contains("save") }) {
            return "save"
        }
        if labels.contains(where: { $0.contains("rename") }) {
            return "rename"
        }

        return nil
    }

    private func inferredModalClass(from observation: Observation) -> String? {
        let modalRoles = ["AXSheet", "AXDialog", "AXPopover", "AXAlert"]
        if observation.elements.contains(where: { element in
            guard let role = element.role else { return false }
            return modalRoles.contains(role)
        }) {
            return "modal-present"
        }
        return nil
    }

    private func inferredNavigationClass(from observation: Observation, domain: String?) -> String? {
        if let domain {
            if domain.contains("mail.google.com") {
                return "gmail"
            }
            if domain.contains("slack.com") {
                return "slack"
            }
        }

        if observation.url != nil {
            return "web"
        }

        return nil
    }

    private func inferredControlContext(from observation: Observation) -> String? {
        if let focusedLabel = observation.focusedElement?.label,
           let normalizedLabel = normalizedControlLabel(from: focusedLabel) {
            return "focused:\(normalizedLabel)"
        }

        if observation.elements.contains(where: { $0.role == "AXTextField" || $0.role == "AXTextArea" }) {
            return "editable-visible"
        }

        return nil
    }

    private func normalizedControlLabel(from label: String) -> String? {
        let normalized = label
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return nil
        }

        let canonicalKeywords = [
            "compose",
            "send",
            "subject",
            "body",
            "message",
            "search",
            "save",
            "rename",
            "reply",
            "forward",
        ]

        if let keyword = canonicalKeywords.first(where: { normalized.contains($0) }) {
            return keyword
        }

        return normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty })
    }
}
