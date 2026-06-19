import Foundation

/// A pure function that produces a new ``WorldModelSnapshot`` from an existing
/// snapshot and a ``StateDiff``.
///
/// `StateUpdater` is intentionally stateless — it takes a snapshot and a diff
/// and returns a brand-new snapshot.  This keeps world-model advancement
/// deterministic and easy to test in isolation.
public enum StateUpdater {

    public static func apply(
        diff: StateDiff,
        to snapshot: WorldModelSnapshot
    ) -> WorldModelSnapshot {
        let ws = diff.incomingWorldState
        var notes = snapshot.notes

        for change in diff.changes {
            switch change {
            case let .applicationChanged(from, to):
                notes.append("app: \(from ?? "nil") → \(to ?? "nil")")
            case let .modalStateChanged(present):
                notes.append("modal: \(present ? "appeared" : "dismissed")")
            case let .branchChanged(from, to):
                notes.append("branch: \(from ?? "nil") → \(to ?? "nil")")
            default:
                break
            }
        }

        // Keep only the most recent notes to prevent unbounded growth.
        let trimmedNotes = Array(notes.suffix(20))
        let repo = ws.repositorySnapshot

        return snapshot.copy(
            activeApplication: .some(ws.observation.app),
            windowTitle: .some(ws.observation.windowTitle),
            url: .some(ws.observation.url),
            visibleElementCount: ws.observation.elements.count,
            modalPresent: ws.planningState.modalClass != nil,
            repositoryRoot: .some(repo?.workspaceRoot ?? snapshot.repositoryRoot),
            activeBranch: .some(repo?.activeBranch ?? snapshot.activeBranch),
            isGitDirty: repo?.isGitDirty ?? snapshot.isGitDirty,
            openFileCount: repo?.files.count ?? snapshot.openFileCount,
            planningStateID: .some(ws.planningState.id.rawValue),
            observationHash: .some(ws.observationHash),
            notes: trimmedNotes
        )
    }
}
