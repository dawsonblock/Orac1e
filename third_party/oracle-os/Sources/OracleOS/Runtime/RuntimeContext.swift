import Foundation

@MainActor
public final class RuntimeContext {
    public let config: RuntimeConfig
    public let traceRecorder: TraceRecorder
    public let traceStore: ExperienceStore
    public let artifactWriter: FailureArtifactWriter
    public let policyEngine: PolicyEngine
    public let approvalStore: ApprovalStore
    public let graphStore: GraphStore
    public let memoryStore: UnifiedMemoryStore
    public let stateAbstraction: StateAbstraction
    public let recoveryEngine: RecoveryEngine
    public let workspaceRunner: WorkspaceRunner
    public let repositoryIndexer: RepositoryIndexer
    public let architectureEngine: ArchitectureEngine
    public let experimentManager: ExperimentManager
    public let automationHost: AutomationHost
    public let browserController: BrowserController
    public let browserPageStateBuilder: BrowserPageStateBuilder
    public let stateMemoryIndex: StateMemoryIndex
    public let searchController: SearchController
    public let metricsRecorder: MetricsRecorder
    public private(set) lazy var telemetry: RuntimeTelemetry = RuntimeTelemetry(context: self)
    public let criticLoop: CriticLoop
    public let stateAbstractionEngine: StateAbstractionEngine

    public init(
        config: RuntimeConfig = .live(),
        traceRecorder: TraceRecorder,
        traceStore: ExperienceStore,
        artifactWriter: FailureArtifactWriter,
        policyEngine: PolicyEngine,
        approvalStore: ApprovalStore,
        graphStore: GraphStore = GraphStore(),
        memoryStore: UnifiedMemoryStore = UnifiedMemoryStore(),
        stateAbstraction: StateAbstraction = StateAbstraction(),
        recoveryEngine: RecoveryEngine = RecoveryEngine(),
        workspaceRunner: WorkspaceRunner = WorkspaceRunner(),
        repositoryIndexer: RepositoryIndexer = RepositoryIndexer(),
        architectureEngine: ArchitectureEngine = ArchitectureEngine(),
        experimentManager: ExperimentManager = ExperimentManager(),
        automationHost: AutomationHost = .live(),
        browserController: BrowserController = BrowserController(),
        browserPageStateBuilder: BrowserPageStateBuilder = BrowserPageStateBuilder(),
        stateMemoryIndex: StateMemoryIndex = StateMemoryIndex(),
        searchController: SearchController? = nil,
        metricsRecorder: MetricsRecorder = MetricsRecorder()
    ) {
        self.config = config
        self.traceRecorder = traceRecorder
        self.traceStore = traceStore
        self.artifactWriter = artifactWriter
        self.policyEngine = policyEngine
        self.approvalStore = approvalStore
        self.graphStore = graphStore
        self.memoryStore = memoryStore
        self.stateAbstraction = stateAbstraction
        self.recoveryEngine = recoveryEngine
        self.workspaceRunner = workspaceRunner
        self.repositoryIndexer = repositoryIndexer
        self.architectureEngine = architectureEngine
        self.experimentManager = experimentManager
        self.automationHost = automationHost
        self.browserController = browserController
        self.browserPageStateBuilder = browserPageStateBuilder
        self.stateMemoryIndex = stateMemoryIndex
        self.searchController = searchController ?? SearchController(
            generator: CandidateGenerator(
                stateMemoryIndex: stateMemoryIndex,
                graphStore: graphStore
            )
        )
        self.metricsRecorder = metricsRecorder
        self.criticLoop = CriticLoop()
        self.stateAbstractionEngine = StateAbstractionEngine()
    }

    public static func live(
        config: RuntimeConfig = .live(),
        traceRecorder: TraceRecorder,
        traceStore: ExperienceStore,
        artifactWriter: FailureArtifactWriter
    ) -> RuntimeContext {
        let policyEngine = PolicyEngine(mode: config.policyMode)
        let approvalStore = ApprovalStore(rootDirectory: config.approvalsDirectory)
        let graphStore = GraphStore()
        let stateMemoryIndex = StateMemoryIndex()

        return RuntimeContext(
            config: config,
            traceRecorder: traceRecorder,
            traceStore: traceStore,
            artifactWriter: artifactWriter,
            policyEngine: policyEngine,
            approvalStore: approvalStore,
            graphStore: graphStore,
            memoryStore: UnifiedMemoryStore(),
            stateAbstraction: StateAbstraction(),
            recoveryEngine: RecoveryEngine(),
            workspaceRunner: WorkspaceRunner(),
            repositoryIndexer: RepositoryIndexer(),
            architectureEngine: ArchitectureEngine(),
            experimentManager: ExperimentManager(),
            automationHost: .live(),
            browserController: BrowserController(),
            browserPageStateBuilder: BrowserPageStateBuilder(),
            stateMemoryIndex: stateMemoryIndex,
            searchController: SearchController(
                generator: CandidateGenerator(
                    stateMemoryIndex: stateMemoryIndex,
                    graphStore: graphStore
                )
            ),
            metricsRecorder: MetricsRecorder()
        )
    }
}
