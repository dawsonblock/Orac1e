import Foundation
@testable import OracleOS

@MainActor
final class EvalObservationProvider: ObservationProvider {
    private let observations: [Observation]
    private var index = 0

    init(_ observations: [Observation]) {
        self.observations = observations
    }

    func observe() -> Observation {
        let observation = observations[min(index, observations.count - 1)]
        if index < observations.count - 1 {
            index += 1
        }
        return observation
    }
}

@MainActor
final class EvalExecutionDriver: AgentExecutionDriver {
    static var recordedSources: [PlannerSource] = []
    static var selectedExperimentReplay = false

    private let handler: (ActionIntent, PlannerDecision, ElementCandidate?) -> ToolResult

    init(handler: @escaping (ActionIntent, PlannerDecision, ElementCandidate?) -> ToolResult) {
        self.handler = handler
    }

    func execute(
        intent: ActionIntent,
        plannerDecision: PlannerDecision,
        selectedCandidate: ElementCandidate?
    ) -> ToolResult {
        handler(intent, plannerDecision, selectedCandidate)
    }
}

struct BrokenSwiftWorkspace {
    let root: URL
    let candidates: [CandidatePatch]
}

enum EvalWorkspaceMode {
    case buildBreak
    case failingTest
}

func makeTempGraphURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("graph.sqlite3", isDirectory: false)
}

func seedPromotedTransition(
    store: GraphStore,
    abstraction: StateAbstraction,
    from fromObservation: Observation,
    to toObservation: Observation,
    contract: ActionContract,
    postconditionClass: PostconditionClass,
    latencyMs: Int = 100
) {
    let fromState = abstraction.abstract(
        observation: fromObservation,
        observationHash: ObservationHash.hash(fromObservation)
    )
    let toState = abstraction.abstract(
        observation: toObservation,
        observationHash: ObservationHash.hash(toObservation)
    )
    for _ in 0..<5 {
        store.recordTransition(
            VerifiedTransition(
                fromPlanningStateID: fromState.id,
                toPlanningStateID: toState.id,
                actionContractID: contract.id,
                postconditionClass: postconditionClass,
                verified: true,
                failureClass: nil,
                latencyMs: latencyMs
            ),
            actionContract: contract,
            fromState: fromState,
            toState: toState
        )
    }
    _ = store.promoteEligibleEdges()
}

func makePromotedWorkflowPlan(
    goalPattern: String,
    agentKind: AgentKind,
    from observation: Observation,
    actionContract: ActionContract,
    semanticQuery: ElementQuery? = nil,
    successRate: Double = 0.92
) -> WorkflowPlan {
    let abstraction = StateAbstraction()
    let state = abstraction.abstract(
        observation: observation,
        observationHash: ObservationHash.hash(observation)
    )
    let step = WorkflowStep(
        agentKind: agentKind,
        stepPhase: agentKind == .code ? .engineering : .operatingSystem,
        actionContract: actionContract,
        semanticQuery: semanticQuery,
        fromPlanningStateID: state.id.rawValue,
        notes: ["seeded benchmark workflow"]
    )
    return WorkflowPlan(
        agentKind: agentKind,
        goalPattern: goalPattern,
        steps: [step],
        successRate: successRate,
        sourceTraceRefs: ["benchmark:\(goalPattern)"],
        sourceGraphEdgeRefs: [],
        evidenceTiers: [.candidate],
        repeatedTraceSegmentCount: 3,
        replayValidationSuccess: 1,
        promotionStatus: .promoted,
        lastValidatedAt: Date(),
        lastSucceededAt: Date()
    )
}

func makeBrokenSwiftWorkspace(mode: EvalWorkspaceMode) throws -> BrokenSwiftWorkspace {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let sources = root.appendingPathComponent("Sources/Example", isDirectory: true)
    let tests = root.appendingPathComponent("Tests/ExampleTests", isDirectory: true)
    try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)

    let package = """
    // swift-tools-version: 6.2
    import PackageDescription

    let package = Package(
        name: "Example",
        products: [
            .library(name: "Example", targets: ["Example"]),
        ],
        targets: [
            .target(name: "Example"),
            .testTarget(name: "ExampleTests", dependencies: ["Example"]),
        ]
    )
    """

    let goodSource = """
    public struct Calculator {
        public static func double(_ value: Int) -> Int {
            value * 2
        }
    }
    """

    let brokenBuildSource = """
    public struct Calculator {
        public static func double(_ value: Int) -> Int {
            value *
        }
    }
    """

    let failingTestSource = """
    public struct Calculator {
        public static func double(_ value: Int) -> Int {
            value * 3
        }
    }
    """

    let testSource = """
    import Testing
    @testable import Example

    @Test func doublesInput() {
        #expect(Calculator.double(2) == 4)
    }
    """

    let relaxedTestSource = """
    import Testing
    @testable import Example

    @Test func doublesInput() {
        #expect(Calculator.double(2) == 6)
    }
    """

    let gitignore = """
    .oracle/
    """

    try package.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
    try gitignore.write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
    try goodSource.write(to: sources.appendingPathComponent("Calculator.swift"), atomically: true, encoding: .utf8)
    try testSource.write(to: tests.appendingPathComponent("CalculatorTests.swift"), atomically: true, encoding: .utf8)

    try runProcess(["git", "init"], cwd: root)
    try runProcess(["git", "config", "user.email", "eval@example.com"], cwd: root)
    try runProcess(["git", "config", "user.name", "Eval Runner"], cwd: root)
    try runProcess(["git", "add", "."], cwd: root)
    try runProcess(["git", "commit", "-m", "baseline"], cwd: root)

    let workspaceSource: String
    let candidates: [CandidatePatch]
    switch mode {
    case .buildBreak:
        workspaceSource = brokenBuildSource
        candidates = [
            CandidatePatch(
                title: "Restore valid calculator implementation",
                summary: "Restore the known-good implementation so build and tests pass.",
                workspaceRelativePath: "Sources/Example/Calculator.swift",
                content: goodSource,
                hypothesis: "Revert the broken edit."
            ),
            CandidatePatch(
                title: "Replace build failure with test failure",
                summary: "Compiles but keeps the task failing under tests.",
                workspaceRelativePath: "Sources/Example/Calculator.swift",
                content: failingTestSource,
                hypothesis: "Compile first, then inspect test failure."
            ),
        ]
    case .failingTest:
        workspaceSource = failingTestSource
        candidates = [
            CandidatePatch(
                title: "Restore valid calculator implementation",
                summary: "Repair production code and keep the test strict.",
                workspaceRelativePath: "Sources/Example/Calculator.swift",
                content: goodSource,
                hypothesis: "The bug belongs in production code."
            ),
            CandidatePatch(
                title: "Relax the failing test",
                summary: "Make the test accept the current wrong behavior.",
                workspaceRelativePath: "Tests/ExampleTests/CalculatorTests.swift",
                content: relaxedTestSource,
                hypothesis: "Silence the failing assertion."
            ),
        ]
    }

    try workspaceSource.write(to: sources.appendingPathComponent("Calculator.swift"), atomically: true, encoding: .utf8)

    return BrokenSwiftWorkspace(root: root, candidates: candidates)
}

func runProcess(_ arguments: [String], cwd: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = cwd
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "process failed"
        throw NSError(domain: "OracleOSEvals", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }
}
