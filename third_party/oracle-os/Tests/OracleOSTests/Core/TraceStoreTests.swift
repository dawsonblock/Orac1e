import Foundation
import Testing
@testable import OracleOS

@Suite("Trace Store")
struct TraceStoreTests {

    @Test("ExperienceStore writes JSONL events")
    func traceStoreWritesJSONL() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ExperienceStore(directoryURL: tempDirectory)

        let event = TraceEvent(
            sessionID: "trace-session",
            taskID: nil,
            stepID: 1,
            toolName: "oracle_type",
            actionName: "type",
            actionTarget: "Body",
            actionText: "hello",
            selectedElementID: "body-field",
            selectedElementLabel: "Body",
            candidateScore: nil,
            candidateReasons: [],
            preObservationHash: "pre",
            postObservationHash: "post",
            postcondition: "element_value_equals:Body=hello",
            verified: true,
            success: true,
            failureClass: nil,
            recoveryStrategy: nil,
            elapsedMs: 100,
            screenshotPath: nil,
            notes: nil
        )

        let url = try store.append(event)
        let data = try Data(contentsOf: url)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")

        #expect(lines.count == 1)

        let lineData = Data(lines[0].utf8)
        let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any]

        #expect(object?["sessionID"] as? String == "trace-session")
        #expect(object?["preObservationHash"] as? String == "pre")
        #expect(object?["toolName"] as? String == "oracle_type")
        #expect(object?["verified"] as? Bool == true)
    }

    @Test("One session file preserves ordered step IDs")
    func traceStorePreservesOrderedStepIDs() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ExperienceStore(directoryURL: tempDirectory)
        let recorder = TraceRecorder(sessionID: "ordered-session")

        for action in ["focus", "click", "type"] {
            let event = TraceEvent(
                sessionID: recorder.sessionID,
                taskID: nil,
                stepID: recorder.makeStepID(),
                toolName: "oracle_\(action)",
                actionName: action,
                actionTarget: nil,
                actionText: nil,
                selectedElementID: nil,
                selectedElementLabel: nil,
                candidateScore: nil,
                candidateReasons: [],
                preObservationHash: "pre-\(action)",
                postObservationHash: "post-\(action)",
                postcondition: nil,
                verified: true,
                success: true,
                failureClass: nil,
                recoveryStrategy: nil,
                elapsedMs: 1,
                screenshotPath: nil,
                notes: nil
            )
            recorder.record(event)
            _ = try store.append(event)
        }

        let fileURL = tempDirectory.appendingPathComponent("ordered-session.jsonl")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(separator: "\n")

        #expect(lines.count == 3)

        let stepIDs = try lines.map { line -> Int in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            return object?["stepID"] as? Int ?? -1
        }

        #expect(stepIDs == [1, 2, 3])
    }
}
