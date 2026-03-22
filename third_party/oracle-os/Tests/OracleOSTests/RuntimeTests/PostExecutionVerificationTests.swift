import Foundation
import XCTest
@testable import OracleOS

final class PostExecutionVerificationTests: XCTestCase {
    func test_outcome_verifier_marks_file_change_verified_when_readback_matches_patch() {
        let command = Command(
            type: .code,
            payload: .code(CodeAction(name: "modifyFile", filePath: "/tmp/demo.txt", patch: "patched", workspacePath: "/tmp")),
            metadata: CommandMetadata(intentID: UUID())
        )

        let artifact = ArtifactPayload(kind: "patch", identifier: "/tmp/demo.txt", data: "patched".data(using: .utf8))
        let routed = RoutedExecutionResult(
            status: .success,
            evidence: ExecutionEvidence(
                artifacts: [artifact],
                expectedPostconditions: [.fileExists("/tmp/demo.txt"), .fileContentsChanged("/tmp/demo.txt")]
            )
        )
        let observed = PostExecutionObservation(
            fileExistsByPath: ["/tmp/demo.txt": true],
            fileContentsByPath: ["/tmp/demo.txt": "patched"]
        )

        let report = OutcomeVerifier().verify(
            command: command,
            snapshotBeforeExecution: WorldModelSnapshot(repositoryRoot: "/tmp"),
            routedResult: routed,
            observedAfterExecution: observed,
            policyDecision: PolicyDecision(allowed: true, reason: nil),
            preconditionsPassed: true
        )

        XCTAssertTrue(report.postconditionsPassed)
    }

    func test_outcome_verifier_marks_missing_readback_as_failure() {
        let command = Command(
            type: .code,
            payload: .code(CodeAction(name: "modifyFile", filePath: "/tmp/demo.txt", patch: "patched", workspacePath: "/tmp")),
            metadata: CommandMetadata(intentID: UUID())
        )

        let routed = RoutedExecutionResult(
            status: .success,
            evidence: ExecutionEvidence(
                expectedPostconditions: [.fileExists("/tmp/demo.txt"), .fileContentsChanged("/tmp/demo.txt")]
            )
        )
        let observed = PostExecutionObservation(
            fileExistsByPath: ["/tmp/demo.txt": false],
            fileContentsByPath: [:]
        )

        let report = OutcomeVerifier().verify(
            command: command,
            snapshotBeforeExecution: WorldModelSnapshot(repositoryRoot: "/tmp"),
            routedResult: routed,
            observedAfterExecution: observed,
            policyDecision: PolicyDecision(allowed: true, reason: nil),
            preconditionsPassed: true
        )

        XCTAssertFalse(report.postconditionsPassed)
        XCTAssertTrue(report.notes.contains(where: { $0.contains("file missing") }))
    }
}
