import Foundation
import Testing
@testable import OracleOS

@Suite("World Model")
struct WorldModelTests {

    // MARK: - WorldStateModel

    @Test("World state model starts with empty snapshot")
    func worldStateModelStartsEmpty() {
        let model = WorldStateModel()
        let snapshot = model.snapshot
        #expect(snapshot.activeApplication == nil)
        #expect(snapshot.visibleElementCount == 0)
        #expect(snapshot.modalPresent == false)
    }

    @Test("World state model resets from world state")
    func worldStateModelResetsFromWorldState() {
        let model = WorldStateModel()
        let ws = makeWorldState(app: "Safari", url: "https://example.com", elementCount: 5)
        model.reset(from: ws)

        let snapshot = model.snapshot
        #expect(snapshot.activeApplication == "Safari")
        #expect(snapshot.url == "https://example.com")
        #expect(snapshot.visibleElementCount == 5)
    }

    @Test("World state model applies diff incrementally")
    func worldStateModelAppliesDiff() {
        let model = WorldStateModel()
        let ws1 = makeWorldState(app: "Safari", url: "https://example.com")
        model.reset(from: ws1)

        let ws2 = makeWorldState(app: "Finder", url: nil)
        let diff = StateDiffEngine.diff(current: model.snapshot, incoming: ws2)
        model.apply(diff: diff)

        let snapshot = model.snapshot
        #expect(snapshot.activeApplication == "Finder")
        #expect(snapshot.url == nil)
    }

    @Test("World state model maintains history")
    func worldStateModelMaintainsHistory() {
        let model = WorldStateModel(maxHistory: 5)
        for i in 0..<3 {
            let ws = makeWorldState(app: "App\(i)")
            model.reset(from: ws)
        }

        let history = model.recentHistory(limit: 10)
        #expect(history.count == 3)
    }

    @Test("World state model limits history size")
    func worldStateModelLimitsHistory() {
        let model = WorldStateModel(maxHistory: 3)
        for i in 0..<6 {
            let ws = makeWorldState(app: "App\(i)")
            model.reset(from: ws)
        }

        let history = model.recentHistory(limit: 10)
        #expect(history.count == 3)
    }

    // MARK: - StateDiffEngine

    @Test("StateDiffEngine detects application change")
    func stateDiffEngineDetectsAppChange() {
        let current = WorldModelSnapshot(activeApplication: "Safari")
        let incoming = makeWorldState(app: "Finder")

        let diff = StateDiffEngine.diff(current: current, incoming: incoming)
        #expect(!diff.isEmpty)
        #expect(diff.changes.contains {
            if case .applicationChanged = $0 { return true }
            return false
        })
    }

    @Test("StateDiffEngine detects modal state change")
    func stateDiffEngineDetectsModalChange() {
        let current = WorldModelSnapshot(modalPresent: false)
        let incoming = makeWorldState(app: "Safari", modalClass: "dialog")

        let diff = StateDiffEngine.diff(current: current, incoming: incoming)
        #expect(diff.changes.contains {
            if case .modalStateChanged(present: true) = $0 { return true }
            return false
        })
    }

    @Test("StateDiffEngine produces empty diff when nothing changes")
    func stateDiffEngineProducesEmptyDiff() {
        let ws = makeWorldState(app: "Safari")
        let current = WorldModelSnapshot(from: ws)

        let diff = StateDiffEngine.diff(current: current, incoming: ws)
        #expect(diff.isEmpty)
    }

    @Test("StateDiffEngine detects URL change")
    func stateDiffEngineDetectsURLChange() {
        let current = WorldModelSnapshot(url: "https://old.com")
        let incoming = makeWorldState(app: "Safari", url: "https://new.com")

        let diff = StateDiffEngine.diff(current: current, incoming: incoming)
        #expect(diff.changes.contains {
            if case .urlChanged = $0 { return true }
            return false
        })
    }

    // MARK: - StateUpdater

    @Test("StateUpdater applies diff to produce new snapshot")
    func stateUpdaterAppliesDiff() {
        let current = WorldModelSnapshot(activeApplication: "Safari", modalPresent: false)
        let incoming = makeWorldState(app: "Finder")
        let diff = StateDiffEngine.diff(current: current, incoming: incoming)

        let updated = StateUpdater.apply(diff: diff, to: current)
        #expect(updated.activeApplication == "Finder")
    }

    @Test("StateUpdater preserves repository root when not in incoming state")
    func stateUpdaterPreservesRepoRoot() {
        let current = WorldModelSnapshot(repositoryRoot: "/tmp/project")
        let incoming = makeWorldState(app: "Safari")
        let diff = StateDiffEngine.diff(current: current, incoming: incoming)

        let updated = StateUpdater.apply(diff: diff, to: current)
        #expect(updated.repositoryRoot == "/tmp/project")
    }

    // MARK: - StateSimulator

    @Test("StateSimulator predicts modal dismissal")
    func stateSimulatorPredictsModalDismissal() {
        let simulator = StateSimulator()
        let snapshot = WorldModelSnapshot(modalPresent: true)
        let state = minimalReasoningState(agentKind: .os, modalPresent: true)

        let result = simulator.predict(from: snapshot, operator: Operator(kind: .dismissModal), state: state)
        #expect(result.predictedSnapshot.modalPresent == false)
        #expect(result.confidence > 0.5)
    }

    @Test("StateSimulator predicts application focus")
    func stateSimulatorPredictsAppFocus() {
        let simulator = StateSimulator()
        let snapshot = WorldModelSnapshot(activeApplication: "Finder")
        var state = minimalReasoningState(agentKind: .os)
        state.targetApplication = "Safari"

        let result = simulator.predict(from: snapshot, operator: Operator(kind: .focusWindow), state: state)
        #expect(result.predictedSnapshot.activeApplication == "Safari")
    }

    @Test("StateSimulator predicts git dirty after patch")
    func stateSimulatorPredictsGitDirty() {
        let simulator = StateSimulator()
        let snapshot = WorldModelSnapshot(isGitDirty: false)
        let state = minimalReasoningState(agentKind: .code, repoOpen: true)

        let result = simulator.predict(from: snapshot, operator: Operator(kind: .applyPatch), state: state)
        #expect(result.predictedSnapshot.isGitDirty == true)
    }

    @Test("StateSimulator returns low confidence for no-op dismissModal")
    func stateSimulatorLowConfidenceNoOp() {
        let simulator = StateSimulator()
        let snapshot = WorldModelSnapshot(modalPresent: false)
        let state = minimalReasoningState(agentKind: .os, modalPresent: false)

        let result = simulator.predict(from: snapshot, operator: Operator(kind: .dismissModal), state: state)
        #expect(result.confidence < 0.5)
    }

    // MARK: - WorldModelSnapshot init from WorldState

    @Test("WorldModelSnapshot initializes from WorldState")
    func worldModelSnapshotFromWorldState() {
        let ws = makeWorldState(
            app: "Chrome",
            url: "https://mail.google.com",
            elementCount: 12,
            modalClass: "alert"
        )
        let snapshot = WorldModelSnapshot(from: ws)

        #expect(snapshot.activeApplication == "Chrome")
        #expect(snapshot.url == "https://mail.google.com")
        #expect(snapshot.visibleElementCount == 12)
        #expect(snapshot.modalPresent == true)
    }

    // MARK: - StateDiffEngine with observation delta

    @Test("StateDiffEngine includes observation delta when previous observation provided")
    func stateDiffEngineIncludesObservationDelta() {
        let prevObs = Observation(
            app: "Safari",
            elements: [
                UnifiedElement(id: "btn-1", source: .ax, role: "AXButton", label: "Save", confidence: 0.9),
            ]
        )
        let prevWS = makeWorldState(app: "Safari", elementCount: 1)
        let current = WorldModelSnapshot(from: prevWS)

        let nextWS = makeWorldState(app: "Safari", elementCount: 2)

        let diff = StateDiffEngine.diff(
            current: current,
            incoming: nextWS,
            previousObservation: prevObs
        )

        #expect(diff.observationDelta != nil)
    }

    @Test("StateDiffEngine observation delta detects added elements")
    func stateDiffEngineDeltaDetectsAddedElements() {
        let prevObs = Observation(
            app: "App",
            elements: [
                UnifiedElement(id: "btn-1", source: .ax, role: "AXButton", label: "OK", confidence: 0.9),
            ]
        )
        let current = WorldModelSnapshot(activeApplication: "App", visibleElementCount: 1)

        let nextElements = [
            UnifiedElement(id: "btn-1", source: .ax, role: "AXButton", label: "OK", confidence: 0.9),
            UnifiedElement(id: "btn-2", source: .ax, role: "AXButton", label: "Cancel", confidence: 0.9),
        ]
        let nextWS = WorldState(
            observationHash: "hash-new",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "App|state"),
                clusterKey: StateClusterKey(rawValue: "App|state"),
                appID: "App",
                domain: nil,
                windowClass: nil,
                taskPhase: "test",
                focusedRole: nil,
                modalClass: nil,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(app: "App", elements: nextElements)
        )

        let diff = StateDiffEngine.diff(
            current: current,
            incoming: nextWS,
            previousObservation: prevObs
        )

        #expect(diff.observationDelta != nil)
        #expect(diff.observationDelta?.addedElements.count == 1)
        #expect(diff.observationDelta?.addedElements.first?.id == "btn-2")
    }

    @Test("StateDiffEngine without previous observation has nil delta")
    func stateDiffEngineWithoutPrevObsHasNilDelta() {
        let current = WorldModelSnapshot(activeApplication: "Safari")
        let incoming = makeWorldState(app: "Finder")

        let diff = StateDiffEngine.diff(current: current, incoming: incoming)
        #expect(diff.observationDelta == nil)
    }

    // MARK: - Helpers

    private func makeWorldState(
        app: String,
        url: String? = nil,
        elementCount: Int = 0,
        modalClass: String? = nil
    ) -> WorldState {
        let elements = (0..<elementCount).map { i in
            UnifiedElement(id: "el-\(i)", source: .ax, role: "AXButton", label: "Button \(i)", confidence: 0.9)
        }
        return WorldState(
            observationHash: "hash-\(app)",
            planningState: PlanningState(
                id: PlanningStateID(rawValue: "\(app)|state"),
                clusterKey: StateClusterKey(rawValue: "\(app)|state"),
                appID: app,
                domain: nil,
                windowClass: nil,
                taskPhase: "test",
                focusedRole: nil,
                modalClass: modalClass,
                navigationClass: nil,
                controlContext: nil
            ),
            observation: Observation(
                app: app,
                windowTitle: app,
                url: url,
                focusedElementID: nil,
                elements: elements
            )
        )
    }

    private func minimalReasoningState(
        agentKind: AgentKind,
        repoOpen: Bool = false,
        modalPresent: Bool = false
    ) -> ReasoningPlanningState {
        ReasoningPlanningState(
            taskContext: TaskContext(
                goal: Goal(description: "test goal", preferredAgentKind: agentKind),
                agentKind: agentKind,
                workspaceRoot: repoOpen ? "/tmp/workspace" : nil,
                phases: [.operatingSystem]
            ),
            worldState: WorldState(
                observationHash: "test",
                planningState: PlanningState(
                    id: PlanningStateID(rawValue: "test"),
                    clusterKey: StateClusterKey(rawValue: "test"),
                    appID: "Test",
                    domain: nil,
                    windowClass: nil,
                    taskPhase: "test",
                    focusedRole: nil,
                    modalClass: modalPresent ? "dialog" : nil,
                    navigationClass: nil,
                    controlContext: nil
                ),
                observation: Observation(
                    app: "Test",
                    windowTitle: "Test",
                    url: nil,
                    focusedElementID: nil,
                    elements: modalPresent
                        ? [UnifiedElement(id: "dialog", source: .ax, role: "AXDialog", label: "Dialog", confidence: 0.9)]
                        : []
                )
            ),
            memoryInfluence: MemoryInfluence()
        )
    }
}
