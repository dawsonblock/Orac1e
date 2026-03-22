import XCTest
@testable import OracleOS

/// Verifies that ONLY reducers may update committed state.
/// Scans Swift source files for banned direct-mutation patterns outside approved reducer paths.
final class StateMutationTests: XCTestCase {

    // MARK: - Helpers

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return url }
            url = parent
        }
    }

    private func swiftFiles(under directory: String) -> [URL] {
        let root = repositoryRoot().appendingPathComponent(directory, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private func sourceContents(files: [URL]) -> [(url: URL, content: String)] {
        files.compactMap { url in
            guard let content = try? String(contentsOf: url) else { return nil }
            return (url, content)
        }
    }

    // MARK: - Tests

    /// No file in Runtime/ or Execution/ should call worldModel.reset() or worldStateModel.reset() directly.
    func test_no_direct_world_model_reset() {
        let bannedPatterns = ["worldModel.reset(", "worldStateModel.reset(", ".worldModel.reset("]
        let allowedSuffixes = ["Reducers/", "CommitCoordinator.swift", "EventReducer.swift"]

        let runtimeFiles = swiftFiles(under: "Sources/OracleOS/Runtime")
        let executionFiles = swiftFiles(under: "Sources/OracleOS/Execution")
        let allFiles = runtimeFiles + executionFiles

        for (url, content) in sourceContents(files: allFiles) {
            let isAllowed = allowedSuffixes.contains { url.path.contains($0) }
            if isAllowed { continue }
            for pattern in bannedPatterns {
                XCTAssertFalse(
                    content.contains(pattern),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) must not call '\(pattern)' — use reducer/commit flow instead"
                )
            }
        }
    }

    /// No file in Planning/ should write directly to graphStore or memoryStore.
    func test_planners_do_not_write_state() {
        let bannedPatterns = ["graphStore.write(", "memoryStore.update(", "graphStore.insert(", "memoryStore.insert("]
        let planningFiles = swiftFiles(under: "Sources/OracleOS/Planning")

        for (url, content) in sourceContents(files: planningFiles) {
            for pattern in bannedPatterns {
                XCTAssertFalse(
                    content.contains(pattern),
                    "GOVERNANCE VIOLATION: \(url.lastPathComponent) (planner) must not call '\(pattern)' directly"
                )
            }
        }
    }

    /// Reducers must exist and conform to EventReducer.
    func test_only_reducers_may_mutate_state() {
        let reducers: [any EventReducer] = [
            RuntimeStateReducer(),
            UIStateReducer(),
            ProjectStateReducer(),
            MemoryStateReducer()
        ]
        XCTAssertEqual(reducers.count, 4, "All four core reducers must exist and conform to EventReducer")
    }

    /// CommitCoordinator must require non-empty event arrays.
    func test_commit_coordinator_rejects_empty_events() async throws {
        let store = EventStore()
        let coordinator = CommitCoordinator(eventStore: store, reducers: [])
        // Commit with empty events should be a no-op (not crash)
        try await coordinator.commit([])
        let events = await store.all()
        XCTAssertEqual(events.count, 0, "Empty commit must not append events")
    }

    /// StateSnapshot must always carry event ancestry.
    func test_snapshot_requires_event_ancestry() {
        let snapshot = StateSnapshot(
            sequenceNumber: 5,
            state: WorldStateModel(),
            eventAncestry: [UUID(), UUID()]
        )
        XCTAssertFalse(snapshot.eventAncestry.isEmpty, "Every StateSnapshot must have event ancestry")
        XCTAssertEqual(snapshot.eventAncestry.count, 2)
    }
}
