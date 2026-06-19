import Foundation

public struct ProjectStateReducer: EventReducer {
    public init() {}

    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        let snapshot = state.snapshot
        var repositoryRoot = snapshot.repositoryRoot
        var activeBranch = snapshot.activeBranch
        var isGitDirty = snapshot.isGitDirty
        var openFileCount = snapshot.openFileCount
        var buildSucceeded = snapshot.buildSucceeded
        var failingTestCount = snapshot.failingTestCount

        for event in events {
            let payload = ReducerSupport.dictionary(from: event)

            switch event.eventType {
            case EventKinds.repositoryObserved:
                let typed = EventPayloadDecoder.decode(RepositoryObservedPayload.self, from: event)
                if let value = typed?.repositoryRoot ?? ReducerSupport.string("repositoryRoot", in: payload) ?? ReducerSupport.string("workspaceRoot", in: payload) {
                    repositoryRoot = value
                }
                if let value = typed?.activeBranch ?? ReducerSupport.string("activeBranch", in: payload) {
                    activeBranch = value
                }
                if let value = typed?.isGitDirty ?? ReducerSupport.bool("isGitDirty", in: payload) {
                    isGitDirty = value
                }
                if let value = typed?.openFileCount ?? ReducerSupport.int("openFileCount", in: payload) {
                    openFileCount = value
                }

            case EventKinds.fileRead:
                let typed = EventPayloadDecoder.decode(FileReadPayload.self, from: event)
                if typed?.path != nil || ReducerSupport.string("path", in: payload) != nil {
                    openFileCount = max(openFileCount, 1)
                }

            case EventKinds.fileModified:
                let typed = EventPayloadDecoder.decode(FileModifiedPayload.self, from: event)
                if typed?.path != nil || ReducerSupport.string("path", in: payload) != nil {
                    isGitDirty = true
                    openFileCount = max(openFileCount, 1)
                }

            case EventKinds.buildCompleted:
                let typed = EventPayloadDecoder.decode(BuildCompletedPayload.self, from: event)
                if let value = typed?.succeeded ?? ReducerSupport.bool("succeeded", in: payload) ?? ReducerSupport.bool("buildSucceeded", in: payload) {
                    buildSucceeded = value
                } else if let status = ReducerSupport.string("status", in: payload) {
                    buildSucceeded = (status.lowercased() == "success")
                }

            case EventKinds.testsCompleted:
                let typed = EventPayloadDecoder.decode(TestsCompletedPayload.self, from: event)
                if let value = typed?.failingTestCount ?? ReducerSupport.int("failingTestCount", in: payload) {
                    failingTestCount = value
                } else if let succeeded = typed?.succeeded ?? ReducerSupport.bool("succeeded", in: payload) {
                    failingTestCount = succeeded ? 0 : failingTestCount
                }

            default:
                break
            }
        }

        state.replaceCommittedSnapshot(
            snapshot.copy(
                repositoryRoot: .some(repositoryRoot),
                activeBranch: .some(activeBranch),
                isGitDirty: isGitDirty,
                openFileCount: openFileCount,
                buildSucceeded: .some(buildSucceeded),
                failingTestCount: .some(failingTestCount)
            )
        )
    }
}
