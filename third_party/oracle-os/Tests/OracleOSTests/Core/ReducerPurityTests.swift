import Foundation
import Testing
@testable import OracleOS

@Suite("Reducer Purity")
struct ReducerPurityTests {

    @Test("Reducer source files avoid side-effect frameworks and APIs")
    func reducerSourcesAvoidSideEffectDependencies() throws {
        let reducersDir = repositoryRoot()
            .appendingPathComponent("Sources/OracleOS/State/Reducers", isDirectory: true)
        let forbiddenTokens = [
            "import AppKit",
            "URLSession",
            "Process(",
            "FileManager.default",
            "NSWorkspace.shared",
        ]

        var offenders: [String] = []
        for fileURL in try swiftFiles(in: reducersDir) {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            if forbiddenTokens.contains(where: content.contains) {
                offenders.append(fileURL.lastPathComponent)
            }
        }

        #expect(
            offenders.isEmpty,
            "Reducer sources should remain pure. Offenders: \(offenders)"
        )
    }

    @Test("Reducers produce deterministic snapshots for identical event streams")
    func reducersAreDeterministicForSameInputs() {
        let reducer = CompositeStateReducer(
            reducers: [
                RuntimeStateReducer(),
                UIStateReducer(),
                MemoryStateReducer(),
                ProjectStateReducer(),
            ]
        )

        var stateA = WorldStateModel()
        var stateB = WorldStateModel()
        let events = sampleEvents()

        reducer.apply(events: events, to: &stateA)
        reducer.apply(events: events, to: &stateB)

        #expect(
            fingerprint(of: stateA.snapshot) == fingerprint(of: stateB.snapshot),
            "Reducer replay must be deterministic for the same event stream."
        )
    }

    @Test("Re-applying identical events is replay-stable")
    func reapplyingEventsIsReplayStable() {
        let reducer = CompositeStateReducer(
            reducers: [
                RuntimeStateReducer(),
                UIStateReducer(),
                MemoryStateReducer(),
                ProjectStateReducer(),
            ]
        )

        var state = WorldStateModel()
        let events = sampleEvents()

        reducer.apply(events: events, to: &state)
        let first = fingerprint(of: state.snapshot)
        reducer.apply(events: events, to: &state)
        let second = fingerprint(of: state.snapshot)

        #expect(first == second, "Pure reducers should remain replay-stable for repeated event streams.")
    }

    private func sampleEvents() -> [EventEnvelope] {
        let intentID = UUID()
        let commandID = UUID()
        let startedPayload = (try? JSONSerialization.data(withJSONObject: ["status": "started"])) ?? Data()
        let succeededPayload = (try? JSONSerialization.data(withJSONObject: ["status": "success"])) ?? Data()
        return [
            EventEnvelope(
                sequenceNumber: 0,
                commandID: commandID,
                intentID: intentID,
                timestamp: Date(timeIntervalSince1970: 1),
                eventType: "CommandStarted",
                payload: startedPayload
            ),
            EventEnvelope(
                sequenceNumber: 0,
                commandID: commandID,
                intentID: intentID,
                timestamp: Date(timeIntervalSince1970: 2),
                eventType: "CommandSucceeded",
                payload: succeededPayload
            ),
        ]
    }

    private func fingerprint(of snapshot: WorldModelSnapshot) -> String {
        [
            "\(snapshot.cycleCount)",
            snapshot.activeApplication ?? "nil",
            snapshot.windowTitle ?? "nil",
            snapshot.url ?? "nil",
            "\(snapshot.visibleElementCount)",
            "\(snapshot.modalPresent)",
            snapshot.repositoryRoot ?? "nil",
            snapshot.activeBranch ?? "nil",
            "\(snapshot.isGitDirty)",
            "\(snapshot.openFileCount)",
            snapshot.buildSucceeded.map { String(describing: $0) } ?? "nil",
            snapshot.failingTestCount.map { String(describing: $0) } ?? "nil",
            snapshot.planningStateID ?? "nil",
            snapshot.observationHash ?? "nil",
            snapshot.processNames.joined(separator: ","),
            snapshot.knowledgeSignals.joined(separator: ","),
            snapshot.notes.joined(separator: ","),
        ].joined(separator: "|")
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            files.append(url)
        }
        return files
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while true {
            let packageManifestURL = url.appendingPathComponent("Package.swift")
            if fileManager.fileExists(atPath: packageManifestURL.path) {
                return url
            }

            let parent = url.deletingLastPathComponent()
            if parent.path == url.path {
                return url
            }

            url = parent
        }
    }
}
