import Foundation

public enum ReasoningOperatorKind: String, CaseIterable, Sendable {
    case runTests = "run_tests"
    case buildProject = "build_project"
    case applyPatch = "apply_patch"
    case revertPatch = "revert_patch"
    case dismissModal = "dismiss_modal"
    case clickTarget = "click_target"
    case openApplication = "open_application"
    case navigateBrowser = "navigate_browser"
    case rerunTests = "rerun_tests"
    case retryWithAlternateTarget = "retry_alternate_target"
    case focusWindow = "focus_window"
    case restartApplication = "restart_application"
    case rollbackPatch = "rollback_patch"
}

public struct Operator: Sendable, Hashable {
    public let kind: ReasoningOperatorKind
    public let baseCost: Double
    public let risk: Double
    public let agentKind: AgentKind
    public let stepPhase: TaskStepPhase

    public init(kind: ReasoningOperatorKind) {
        self.kind = kind
        switch kind {
        case .runTests:
            self.baseCost = 1.0
            self.risk = 0.05
            self.agentKind = .code
            self.stepPhase = .engineering
        case .buildProject:
            self.baseCost = 1.1
            self.risk = 0.05
            self.agentKind = .code
            self.stepPhase = .engineering
        case .applyPatch:
            self.baseCost = 2.0
            self.risk = 0.2
            self.agentKind = .code
            self.stepPhase = .engineering
        case .revertPatch:
            self.baseCost = 1.4
            self.risk = 0.1
            self.agentKind = .code
            self.stepPhase = .engineering
        case .dismissModal:
            self.baseCost = 0.4
            self.risk = 0.02
            self.agentKind = .os
            self.stepPhase = .operatingSystem
        case .clickTarget:
            self.baseCost = 0.6
            self.risk = 0.08
            self.agentKind = .os
            self.stepPhase = .operatingSystem
        case .openApplication:
            self.baseCost = 0.5
            self.risk = 0.03
            self.agentKind = .os
            self.stepPhase = .operatingSystem
        case .navigateBrowser:
            self.baseCost = 0.8
            self.risk = 0.06
            self.agentKind = .os
            self.stepPhase = .operatingSystem
        case .rerunTests:
            self.baseCost = 0.9
            self.risk = 0.04
            self.agentKind = .code
            self.stepPhase = .engineering
        case .retryWithAlternateTarget:
            self.baseCost = 0.7
            self.risk = 0.1
            self.agentKind = .os
            self.stepPhase = .operatingSystem
        case .focusWindow:
            self.baseCost = 0.3
            self.risk = 0.02
            self.agentKind = .os
            self.stepPhase = .operatingSystem
        case .restartApplication:
            self.baseCost = 1.5
            self.risk = 0.15
            self.agentKind = .os
            self.stepPhase = .operatingSystem
        case .rollbackPatch:
            self.baseCost = 1.2
            self.risk = 0.08
            self.agentKind = .code
            self.stepPhase = .engineering
        }
    }

    public var name: String { kind.rawValue }

    public func precondition(_ state: ReasoningPlanningState) -> Bool {
        switch kind {
        case .runTests:
            return state.agentKind != .os && state.repoOpen
        case .buildProject:
            return state.agentKind != .os && state.repoOpen
        case .applyPatch:
            return state.agentKind != .os && state.repoOpen && !state.candidateWorkspacePaths.isEmpty
        case .revertPatch:
            return state.agentKind != .os && state.repoOpen && state.patchApplied
        case .dismissModal:
            return state.agentKind != .code && state.modalPresent
        case .clickTarget:
            return state.agentKind != .code && !state.visibleTargets.isEmpty
        case .openApplication:
            guard state.agentKind != .code else { return false }
            guard let targetApplication = state.targetApplication else { return false }
            return targetApplication != state.activeApplication
        case .navigateBrowser:
            guard state.agentKind != .code else { return false }
            guard let targetDomain = state.targetDomain else { return false }
            return targetDomain != state.currentDomain
        case .rerunTests:
            return state.agentKind != .os && state.repoOpen && (state.testsObserved || state.patchApplied)
        case .retryWithAlternateTarget:
            return state.agentKind != .code && !state.visibleTargets.isEmpty
        case .focusWindow:
            return state.agentKind != .code && state.targetApplication != nil
        case .restartApplication:
            return state.agentKind != .code && state.targetApplication != nil
        case .rollbackPatch:
            return state.agentKind != .os && state.repoOpen && state.patchApplied
        }
    }

    public func effect(_ state: ReasoningPlanningState) -> ReasoningPlanningState {
        var projected = state
        switch kind {
        case .runTests, .rerunTests:
            projected.testsObserved = true
            if projected.failingTests == nil {
                projected.failingTests = 1
            }
            projected.buildSucceeded = nil
        case .buildProject:
            projected.buildSucceeded = true
        case .applyPatch:
            projected.patchApplied = true
            projected.repoDirty = true
        case .revertPatch:
            projected.patchApplied = false
        case .dismissModal:
            projected.modalPresent = false
        case .clickTarget:
            break
        case .openApplication:
            projected.activeApplication = projected.targetApplication
        case .navigateBrowser:
            projected.currentDomain = projected.targetDomain
        case .retryWithAlternateTarget:
            break
        case .focusWindow:
            projected.activeApplication = projected.targetApplication
        case .restartApplication:
            projected.activeApplication = projected.targetApplication
            projected.modalPresent = false
        case .rollbackPatch:
            projected.patchApplied = false
            projected.repoDirty = false
        }
        return projected
    }

    public func actionContract(for state: ReasoningPlanningState, goal: Goal) -> ActionContract? {
        switch kind {
        case .runTests:
            guard let workspaceRoot = state.workspaceRoot else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(workspaceRoot)",
                agentKind: .code,
                skillName: "run_tests",
                targetRole: nil,
                targetLabel: nil,
                locatorStrategy: "reasoning",
                workspaceRelativePath: state.preferredWorkspacePath,
                commandCategory: CodeCommandCategory.test.rawValue,
                plannerFamily: PlannerFamily.code.rawValue
            )
        case .buildProject:
            guard let workspaceRoot = state.workspaceRoot else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(workspaceRoot)",
                agentKind: .code,
                skillName: "run_build",
                targetRole: nil,
                targetLabel: nil,
                locatorStrategy: "reasoning",
                workspaceRelativePath: state.preferredWorkspacePath,
                commandCategory: CodeCommandCategory.build.rawValue,
                plannerFamily: PlannerFamily.code.rawValue
            )
        case .applyPatch:
            let path = state.preferredWorkspacePath ?? state.candidateWorkspacePaths.first
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(path ?? "generate")",
                agentKind: .code,
                skillName: path == nil ? "generate_patch" : "edit_file",
                targetRole: nil,
                targetLabel: path.map { URL(fileURLWithPath: $0).lastPathComponent },
                locatorStrategy: "reasoning",
                workspaceRelativePath: path,
                commandCategory: (path == nil ? CodeCommandCategory.generatePatch : .editFile).rawValue,
                plannerFamily: PlannerFamily.code.rawValue
            )
        case .revertPatch:
            guard let workspaceRoot = state.workspaceRoot else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(workspaceRoot)",
                agentKind: .code,
                skillName: "git_status",
                targetRole: nil,
                targetLabel: nil,
                locatorStrategy: "reasoning",
                workspaceRelativePath: state.preferredWorkspacePath,
                commandCategory: CodeCommandCategory.gitStatus.rawValue,
                plannerFamily: PlannerFamily.code.rawValue
            )
        case .dismissModal:
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|escape",
                agentKind: .os,
                skillName: "press",
                targetRole: nil,
                targetLabel: "escape",
                locatorStrategy: "reasoning-dismiss-modal",
                plannerFamily: PlannerFamily.os.rawValue
            )
        case .clickTarget:
            guard let label = bestVisibleTarget(for: state, goal: goal) else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(state.activeApplication ?? "unknown")|\(label)",
                agentKind: .os,
                skillName: "click",
                targetRole: nil,
                targetLabel: label,
                locatorStrategy: "reasoning-click",
                plannerFamily: PlannerFamily.os.rawValue
            )
        case .openApplication:
            guard let targetApplication = state.targetApplication else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(targetApplication)",
                agentKind: .os,
                skillName: "focus",
                targetRole: nil,
                targetLabel: targetApplication,
                locatorStrategy: "reasoning-focus",
                plannerFamily: PlannerFamily.os.rawValue
            )
        case .navigateBrowser:
            guard let targetDomain = state.targetDomain else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(targetDomain)",
                agentKind: .os,
                skillName: "navigate_url",
                targetRole: nil,
                targetLabel: targetDomain.hasPrefix("http") ? targetDomain : "https://\(targetDomain)",
                locatorStrategy: "reasoning-browser-nav",
                plannerFamily: PlannerFamily.os.rawValue
            )
        case .rerunTests:
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(state.workspaceRoot ?? "workspace")",
                agentKind: .code,
                skillName: "run_tests",
                targetRole: nil,
                targetLabel: nil,
                locatorStrategy: "reasoning-rerun",
                workspaceRelativePath: state.preferredWorkspacePath,
                commandCategory: CodeCommandCategory.test.rawValue,
                plannerFamily: PlannerFamily.code.rawValue
            )
        case .retryWithAlternateTarget:
            guard let label = bestVisibleTarget(for: state, goal: goal) else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(state.activeApplication ?? "unknown")|\(label)",
                agentKind: .os,
                skillName: "click",
                targetRole: nil,
                targetLabel: label,
                locatorStrategy: "reasoning-retry-alternate",
                plannerFamily: PlannerFamily.os.rawValue
            )
        case .focusWindow:
            guard let targetApplication = state.targetApplication else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(targetApplication)",
                agentKind: .os,
                skillName: "focus",
                targetRole: nil,
                targetLabel: targetApplication,
                locatorStrategy: "reasoning-focus-window",
                plannerFamily: PlannerFamily.os.rawValue
            )
        case .restartApplication:
            guard let targetApplication = state.targetApplication else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(targetApplication)",
                agentKind: .os,
                skillName: "focus",
                targetRole: nil,
                targetLabel: targetApplication,
                locatorStrategy: "reasoning-restart-app",
                plannerFamily: PlannerFamily.os.rawValue
            )
        case .rollbackPatch:
            guard let workspaceRoot = state.workspaceRoot else { return nil }
            return ActionContract(
                id: "reasoning|\(kind.rawValue)|\(workspaceRoot)",
                agentKind: .code,
                skillName: "git_status",
                targetRole: nil,
                targetLabel: nil,
                locatorStrategy: "reasoning-rollback",
                workspaceRelativePath: state.preferredWorkspacePath,
                commandCategory: CodeCommandCategory.gitStatus.rawValue,
                plannerFamily: PlannerFamily.code.rawValue
            )
        }
    }

    public func semanticQuery(for state: ReasoningPlanningState, goal: Goal) -> ElementQuery? {
        guard kind == .clickTarget,
              let label = bestVisibleTarget(for: state, goal: goal)
        else {
            return nil
        }
        return ElementQuery(
            text: label,
            clickable: true,
            visibleOnly: true,
            app: state.activeApplication ?? state.targetApplication
        )
    }

    private func bestVisibleTarget(for state: ReasoningPlanningState, goal: Goal) -> String? {
        let goalTokens = Set(goal.description.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let scored = state.visibleTargets.compactMap { label -> (String, Int)? in
            let lowered = label.lowercased()
            let overlap = goalTokens.filter { lowered.contains($0) }.count
            guard overlap > 0 else { return nil }
            return (label, overlap)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0 < rhs.0
            }
            return lhs.1 > rhs.1
        }
        return scored.first?.0
    }
}
