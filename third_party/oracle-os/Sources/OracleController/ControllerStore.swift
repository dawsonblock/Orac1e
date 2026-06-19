import AppKit
import Foundation
import Observation
import OracleControllerShared

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case missionControl
    case coding
    case control
    case recipes
    case traces
    case diagnostics
    case health
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .coding: return "Coding"
        case .control: return "Control"
        case .recipes: return "Recipes"
        case .traces: return "Traces"
        case .diagnostics: return "Diagnostics"
        case .health: return "Health"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .missionControl: return "gauge.with.dots.needle.67percent"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .control: return "slider.horizontal.3"
        case .recipes: return "list.bullet.rectangle"
        case .traces: return "point.3.connected.trianglepath.dotted"
        case .diagnostics: return "stethoscope"
        case .health: return "heart.text.square"
        case .settings: return "gearshape"
        }
    }

    var title: String { label }
    var systemImage: String { icon }
}

enum ControllerCodingMode: String, CaseIterable, Sendable {
    case interactive
    case autonomous
}

enum RecipeEditorMode: String, CaseIterable, Identifiable {
    case form
    case raw

    var id: String { rawValue }
}

struct ActionComposer {
    var kind: ActionKind = .focus
    var appName = ""
    var windowTitle = ""
    var query = ""
    var role = ""
    var domID = ""
    var text = ""
    var clearExisting = false
    var x = ""
    var y = ""
    var button = "left"
    var count = "1"
    var key = ""
    var modifiers = ""
    var direction = "down"
    var amount = "3"
    var waitCondition = "appFrontmost"
    var waitValue = ""
    var timeout = "10"
    var interval = "0.5"

    func makeRequest() -> ActionRequest {
        ActionRequest(
            kind: kind,
            appName: trimmedOrNil(appName),
            windowTitle: trimmedOrNil(windowTitle),
            query: trimmedOrNil(query),
            role: trimmedOrNil(role),
            domID: trimmedOrNil(domID),
            text: trimmedOrNil(text),
            clearExisting: clearExisting,
            x: doubleOrNil(x),
            y: doubleOrNil(y),
            button: trimmedOrNil(button),
            count: intOrNil(count),
            key: trimmedOrNil(key),
            modifiers: parsedModifiers,
            direction: trimmedOrNil(direction),
            amount: intOrNil(amount),
            waitCondition: trimmedOrNil(waitCondition),
            waitValue: trimmedOrNil(waitValue),
            timeout: doubleOrNil(timeout),
            interval: doubleOrNil(interval)
        )
    }

    mutating func hydrate(from snapshot: ControlSnapshot?) {
        guard let appName = snapshot?.observation.appName else { return }
        if self.appName.isEmpty {
            self.appName = appName
        }
    }

    private var parsedModifiers: [String]? {
        let values = modifiers
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func doubleOrNil(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func intOrNil(_ value: String) -> Int? {
        Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

@MainActor
@Observable
final class ControllerStore {
    var selectedSection: WorkspaceSection = .missionControl
    var session: ControllerSession?
    var snapshot: ControlSnapshot?
    var health: HealthStatus?
    var diagnostics: ControllerDiagnosticsSnapshot?
    var missionControl: MissionControlSnapshot?
    var productStatus: ProductEnvironmentStatus?
    var recipes: [RecipeDocument] = []
    var traceSessions: [TraceSessionSummary] = []
    var traceDetail: TraceSessionDetail?
    var approvalQueue: [ApprovalRequestDocument] = []
    var chatConversation: ChatConversation?
    var chatProviderStatus: ChatProviderStatus?
    var currentActionResult: ActionRunResult?
    var recentActions: [ActionRunResult] = []
    var latestRecipeRun: RecipeRunResultDocument?

    var selectedElementID: String?
    var selectedRecipeName: String?
    var selectedTraceSessionID: String?
    var selectedTraceStepID: String?
    var selectedGraphEdgeID: String?
    var selectedWorkflowID: String?
    var selectedExperimentID: String?
    var selectedProjectMemoryID: String?
    var selectedArchitectureFindingID: String?

    var actionComposer = ActionComposer()
    var recipeEditorMode: RecipeEditorMode = .form
    var draftRecipe = RecipeDocument(
        name: "new-recipe",
        description: "Operator workflow",
        steps: [RecipeStepDocument(id: 1, action: "focus")]
    )
    var rawRecipeText = ""
    var recipeRunParameters: [String: String] = [:]

    // MARK: Coding State
    var codingRuns: [ControllerCodingRun] = []
    var codingRunDetail: ControllerCodingRunDetail?
    var selectedCodingRunID: String?
    var codingRepoPath: String = ""
    var codingTask: String = ""
    var codingMode: ControllerCodingMode = .interactive
    var codingRetrievalQuery: String = ""
    var codingAllowedPathsText: String = ""
    var codingValidationCommandsText: String = ""
    var codingReason: String = ""

    var monitorAppName = ""
    var autoRefreshEnabled = true
    var isBusy = false
    var isLoaded = false
    var showOnboarding = false
    var onboardingStep: OnboardingStep = .welcome

    var errorMessage: String?
    var inlineMessage: String?

    var recipeSearchText = ""
    var traceSearchText = ""
    var elementSearchText = ""
    var chatInput = ""

    private var hostClient: HostProcessClient?
    private let productEnvironmentManager = ProductEnvironmentManager()
    var diagnosticsRefreshTask: Task<Void, Never>?
    var missionControlRefreshTask: Task<Void, Never>?

    var filteredElements: [ElementSnapshot] {
        let elements = snapshot?.observation.elements ?? []
        let query = elementSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return elements }
        return elements.filter {
            $0.label?.lowercased().contains(query) == true
                || $0.role?.lowercased().contains(query) == true
                || $0.value?.lowercased().contains(query) == true
        }
    }

    var filteredRecipes: [RecipeDocument] {
        let query = recipeSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recipes }
        return recipes.filter {
            $0.name.lowercased().contains(query)
                || $0.description.lowercased().contains(query)
                || ($0.app?.lowercased().contains(query) ?? false)
        }
    }

    var filteredTraceSessions: [TraceSessionSummary] {
        let query = traceSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return traceSessions }
        return traceSessions.filter { $0.id.lowercased().contains(query) }
    }

    var selectedElement: ElementSnapshot? {
        if let selectedElementID {
            return snapshot?.observation.elements.first(where: { $0.id == selectedElementID })
        }

        if let focusedElementID = snapshot?.observation.focusedElementID {
            return snapshot?.observation.elements.first(where: { $0.id == focusedElementID })
        }

        return snapshot?.observation.elements.first
    }

    var selectedTraceStep: TraceStepViewModel? {
        guard let selectedTraceStepID else { return traceDetail?.steps.first }
        return traceDetail?.steps.first(where: { $0.id == selectedTraceStepID })
    }

    var selectedGraphEdge: ControllerGraphEdgeDiagnostics? {
        let edges = (diagnostics?.graph.stableEdges ?? [])
            + (diagnostics?.graph.candidateEdges ?? [])
            + (diagnostics?.graph.recoveryEdges ?? [])
        guard let selectedGraphEdgeID else { return edges.first }
        return edges.first(where: { $0.id == selectedGraphEdgeID })
    }

    var selectedWorkflowDiagnostics: ControllerWorkflowDiagnostics? {
        guard let selectedWorkflowID else { return diagnostics?.workflows.first }
        return diagnostics?.workflows.first(where: { $0.id == selectedWorkflowID })
    }

    var selectedExperimentDiagnostics: ControllerExperimentDiagnostics? {
        guard let selectedExperimentID else { return diagnostics?.experiments.first }
        return diagnostics?.experiments.first(where: { $0.id == selectedExperimentID })
    }

    var selectedProjectMemoryDiagnostics: ControllerProjectMemoryDiagnostics? {
        guard let selectedProjectMemoryID else { return diagnostics?.projectMemory.first }
        return diagnostics?.projectMemory.first(where: { $0.id == selectedProjectMemoryID })
    }

    var selectedArchitectureFindingDiagnostics: ControllerArchitectureFindingDiagnostics? {
        guard let selectedArchitectureFindingID else { return diagnostics?.architectureFindings.first }
        return diagnostics?.architectureFindings.first(where: { $0.id == selectedArchitectureFindingID })
    }

    init() {
        self.hostClient = HostProcessClient { [weak self] event in
            self?.handle(event)
        }
    }

    func start() async {
        guard !isLoaded else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            let environmentStatus = try productEnvironmentManager.prepareEnvironment()
            productStatus = environmentStatus
            showOnboarding = !productEnvironmentManager.isOnboardingCompleted()
            if environmentStatus.migrationStatus.didMigrateAnything {
                inlineMessage = [
                    environmentStatus.migrationStatus.seededSampleRecipes > 0 ? "Seeded \(environmentStatus.migrationStatus.seededSampleRecipes) sample recipes." : nil,
                    !environmentStatus.migrationStatus.migratedLegacyItems.isEmpty ? "Imported legacy data." : nil,
                ]
                .compactMap { $0 }
                .joined(separator: " ")
            }
            let response = try await send(.init(command: .bootstrap, appName: monitorAppName.nilIfBlank))
            applyBootstrap(response.bootstrap)
            await loadDiagnostics()
            isLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reopenOnboarding() {
        onboardingStep = .welcome
        showOnboarding = true
    }

    func advanceOnboarding() {
        if let next = OnboardingStep(rawValue: onboardingStep.rawValue + 1) {
            onboardingStep = next
        }
    }

    func retreatOnboarding() {
        if let previous = OnboardingStep(rawValue: onboardingStep.rawValue - 1) {
            onboardingStep = previous
        }
    }

    func completeOnboarding() {
        productEnvironmentManager.setOnboardingCompleted(true)
        onboardingStep = .ready
        showOnboarding = false
        inlineMessage = "Oracle Controller is ready."
    }

    func openAccessibilitySettings() {
        productEnvironmentManager.openSystemSettingsForAccessibility()
    }

    func openScreenRecordingSettings() {
        productEnvironmentManager.openSystemSettingsForScreenRecording()
    }

    func installVisionBootstrap() async {
        do {
            isBusy = true
            defer { isBusy = false }
            productStatus = try productEnvironmentManager.installVisionBootstrap(repair: false)
            await refreshHealth()
            inlineMessage = "Vision bootstrap installed. Enable the sidecar when you are ready."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func repairVisionBootstrap() async {
        do {
            isBusy = true
            defer { isBusy = false }
            productStatus = try productEnvironmentManager.installVisionBootstrap(repair: true)
            await refreshHealth()
            inlineMessage = "Vision bootstrap repaired."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func revealDataFolder() {
        productEnvironmentManager.revealDataFolder()
    }

    func revealLogsFolder() {
        productEnvironmentManager.openLogsFolder()
    }

    func openHelp() {
        productEnvironmentManager.openHelp()
    }

    func openReleaseNotes() {
        productEnvironmentManager.openReleaseNotes()
    }

    func showAboutPanel() {
        let buildVersion = productStatus?.buildVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "Development"
        let buildNumber = productStatus?.buildNumber
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? buildVersion

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Oracle Controller",
            .applicationVersion: buildVersion,
            .version: buildNumber,
            .credits: "Safe local macOS operator and engineering console for Oracle OS.",
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func exportDiagnostics() {
        do {
            let destination = try productEnvironmentManager.exportDiagnostics(
                health: health,
                session: session,
                snapshot: snapshot,
                approvals: approvalQueue,
                traceDetail: traceDetail,
                recipes: recipes,
                productStatus: productStatus,
                diagnostics: diagnostics
            )
            inlineMessage = "Exported diagnostics to \(destination.lastPathComponent)."
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetControllerData() {
        let alert = NSAlert()
        alert.messageText = "Reset Oracle Controller data?"
        alert.informativeText = "This removes local traces, approvals, exports, packaged vision bootstrap files, and seeded runtime data under Application Support."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            productStatus = try productEnvironmentManager.resetAllData()
            productEnvironmentManager.setOnboardingCompleted(false)
            showOnboarding = true
            onboardingStep = .welcome
            inlineMessage = "Controller data reset."
            Task {
                await refreshHealth()
                await loadRecipes()
                await loadTraceSessions()
                await loadApprovalRequests()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshNow() async {
        do {
            let response = try await send(.init(command: .refreshSnapshot, appName: currentMonitorApp))
            if let snapshot = response.snapshot {
                apply(snapshot: snapshot)
            }
            await refreshMissionControl()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHealth() async {
        do {
            let response = try await send(.init(command: .getHealth))
            if let health = response.health {
                self.health = health
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadDiagnostics() async {
        do {
            let response = try await send(.init(command: .getDiagnostics))
            guard let diagnostics = response.diagnostics else { return }
            self.diagnostics = diagnostics
            selectedGraphEdgeID = selectedGraphEdgeID
                ?? diagnostics.graph.stableEdges.first?.id
                ?? diagnostics.graph.candidateEdges.first?.id
                ?? diagnostics.graph.recoveryEdges.first?.id
            selectedWorkflowID = selectedWorkflowID ?? diagnostics.workflows.first?.id
            selectedExperimentID = selectedExperimentID ?? diagnostics.experiments.first?.id
            selectedProjectMemoryID = selectedProjectMemoryID ?? diagnostics.projectMemory.first?.id
            selectedArchitectureFindingID = selectedArchitectureFindingID ?? diagnostics.architectureFindings.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: Coding Methods
    func loadCodingRuns() async {
        do {
            let response = try await send(.init(command: .listCodingRuns))
            if let codingRuns = response.codingRuns {
                self.codingRuns = codingRuns
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func loadCodingRunDetail(id: String) async {
        do {
            let response = try await send(.init(command: .loadCodingRun, codingRunID: id))
            if let codingRunDetail = response.codingRunDetail {
                self.codingRunDetail = codingRunDetail
                self.selectedCodingRunID = id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func startCodingRun() async {
        do {
            isBusy = true
            defer { isBusy = false }

            let allowedPaths = codingAllowedPathsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let validationCommands = codingValidationCommandsText
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let mode: ControllerCodingRunMode = codingMode == .autonomous ? .autonomous : .interactive

            let submission = ControllerCodingRunSubmission(
                repoPath: codingRepoPath,
                task: codingTask,
                mode: mode,
                retrievalQuery: codingRetrievalQuery.nilIfBlank,
                allowedPaths: allowedPaths,
                validationCommands: validationCommands
            )

            let response = try await send(.init(command: .startCodingRun, codingRunSubmission: submission))

            if let codingRun = response.codingRuns?.first {
                codingRuns.insert(codingRun, at: 0)
                selectedCodingRunID = codingRun.id
                inlineMessage = "Coding run started."
            } else {
                errorMessage = response.errorMessage ?? "Failed to start coding run"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func approveCodingRun(_ codingRun: ControllerCodingRun) async {
        do {
            let response = try await send(.init(command: .approveCodingRun,
                codingRunID: codingRun.id,
                codingRunReason: codingReason.nilIfBlank))

            if let approvals = response.approvals {
                approvalQueue = approvals
            }

            if let index = codingRuns.firstIndex(where: { $0.id == codingRun.id }) {
                let updated = ControllerCodingRun(
                    id: codingRun.id,
                    repoName: codingRun.repoName,
                    repoPath: codingRun.repoPath,
                    mode: codingRun.mode,
                    status: .applied,
                    task: codingRun.task,
                    createdAt: codingRun.createdAt,
                    approvalRequired: codingRun.approvalRequired,
                    approvalReasons: codingRun.approvalReasons
                )
                codingRuns[index] = updated
            }

            inlineMessage = "Coding run approved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func rejectCodingRun(_ codingRun: ControllerCodingRun) async {
        do {
            let response = try await send(.init(command: .rejectCodingRun,
                codingRunID: codingRun.id,
                codingRunReason: codingReason.nilIfBlank))

            if let approvals = response.approvals {
                approvalQueue = approvals
            }

            if let index = codingRuns.firstIndex(where: { $0.id == codingRun.id }) {
                let updated = ControllerCodingRun(
                    id: codingRun.id,
                    repoName: codingRun.repoName,
                    repoPath: codingRun.repoPath,
                    mode: codingRun.mode,
                    status: .rejected,
                    task: codingRun.task,
                    createdAt: codingRun.createdAt,
                    approvalRequired: codingRun.approvalRequired,
                    approvalReasons: codingRun.approvalReasons
                )
                codingRuns[index] = updated
            }

            inlineMessage = "Coding run rejected."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadApprovalRequests() async {
        do {
            let response = try await send(.init(command: .listApprovalRequests))
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approveApprovalRequest(_ request: ApprovalRequestDocument) async {
        do {
            _ = try await send(.init(command: .approveApprovalRequest, approvalRequestID: request.id))
            approvalQueue.removeAll { $0.id == request.id }
            inlineMessage = "Approved: \(request.displayTitle)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rejectApprovalRequest(_ request: ApprovalRequestDocument) async {
        do {
            _ = try await send(.init(command: .rejectApprovalRequest, approvalRequestID: request.id))
            approvalQueue.removeAll { $0.id == request.id }
            inlineMessage = "Rejected: \(request.displayTitle)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submitAction() async {
        let request = actionComposer.makeRequest()
        await executeAction(request)
    }

    func updateMonitoring() async {
        do {
            let config = MonitoringConfiguration(
                enabled: autoRefreshEnabled,
                appName: monitorAppName.nilIfBlank,
                intervalMs: 1000
            )
            let response = try await send(.init(command: .setMonitoring, monitoring: config))
            if let snapshot = response.snapshot {
                apply(snapshot: snapshot)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadRecipes() async {
        do {
            let response = try await send(.init(command: .listRecipes))
            if let recipes = response.recipes {
                self.recipes = recipes
                syncSelectionAfterRecipeRefresh()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectRecipe(named name: String) async {
        do {
            let response = try await send(.init(command: .loadRecipe, recipeName: name))
            guard let recipe = response.recipe else {
                errorMessage = response.errorMessage ?? "Recipe not found"
                return
            }

            apply(recipe: recipe)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createRecipe() {
        let baseName = "untitled-recipe-\(Int(Date().timeIntervalSince1970))"
        draftRecipe = RecipeDocument(
            name: baseName,
            description: "Describe the workflow.",
            app: snapshot?.observation.appName,
            params: [:],
            preconditions: RecipePreconditionsDocument(appRunning: snapshot?.observation.appName),
            steps: [RecipeStepDocument(id: 1, action: "focus")]
        )
        rawRecipeText = ""
        selectedRecipeName = nil
        recipeRunParameters = [:]
        recipeEditorMode = .form
        selectedSection = .recipes
    }

    func duplicateSelectedRecipe() {
        var copy = draftRecipe
        copy.name = "\(draftRecipe.name)-copy"
        copy.rawJSON = nil
        draftRecipe = copy
        rawRecipeText = ""
        selectedRecipeName = nil
        recipeEditorMode = .form
    }

    func addRecipeStep() {
        let nextID = (draftRecipe.steps.map(\.id).max() ?? 0) + 1
        draftRecipe.steps.append(RecipeStepDocument(id: nextID, action: "click"))
    }

    func removeRecipeStep(id: Int) {
        draftRecipe.steps.removeAll { $0.id == id }
        if draftRecipe.steps.isEmpty {
            addRecipeStep()
        }
    }

    func addRecipeParam() {
        let nextIndex = (draftRecipe.params?.count ?? 0) + 1
        let name = "param\(nextIndex)"
        var params = draftRecipe.params ?? [:]
        params[name] = RecipeParamDocument(id: name, type: "string", description: "Parameter", required: true)
        draftRecipe.params = params
    }

    func removeRecipeParam(id: String) {
        draftRecipe.params?.removeValue(forKey: id)
    }

    func saveDraftRecipe() async {
        if recipeEditorMode == .raw {
            if rawRecipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Raw recipe JSON is empty."
                return
            }
            draftRecipe.rawJSON = rawRecipeText
        } else {
            draftRecipe.rawJSON = nil
        }

        if let validationError = validateDraftRecipe() {
            errorMessage = validationError
            return
        }

        do {
            let response = try await send(.init(command: .saveRecipe, recipe: draftRecipe))
            guard let recipe = response.recipe else {
                errorMessage = response.errorMessage ?? "Save failed"
                return
            }
            inlineMessage = "Saved \(recipe.name)"
            await loadRecipes()
            apply(recipe: recipe)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelectedRecipe() async {
        guard let selectedRecipeName else { return }
        do {
            let response = try await send(.init(command: .deleteRecipe, recipeName: selectedRecipeName))
            guard response.acknowledged else {
                errorMessage = response.errorMessage ?? "Delete failed"
                return
            }
            inlineMessage = "Deleted \(selectedRecipeName)"
            await loadRecipes()
            createRecipe()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runSelectedRecipe() async {
        let recipeName = selectedRecipeName ?? draftRecipe.name

        do {
            isBusy = true
            defer { isBusy = false }
            let response = try await send(.init(command: .runRecipe, recipeName: recipeName, recipeParams: recipeRunParameters))
            if let recipeRun = response.recipeRun {
                latestRecipeRun = recipeRun
                inlineMessage = recipeRun.paused ? "Recipe paused pending approval." : (recipeRun.success ? "Recipe completed." : "Recipe failed.")
                if let approvals = response.approvals {
                    approvalQueue = approvals
                }
                await loadTraceSessions()
                if let traceSessionID = recipeRun.traceSessionID {
                    await loadTraceSession(id: traceSessionID)
                }
                await loadDiagnostics()
            } else {
                errorMessage = response.errorMessage ?? "Recipe run failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTraceSessions() async {
        do {
            let response = try await send(.init(command: .listTraceSessions))
            if let traceSessions = response.traceSessions {
                self.traceSessions = traceSessions
                if selectedTraceSessionID == nil {
                    selectedTraceSessionID = traceSessions.first?.id
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadTraceSession(id: String) async {
        do {
            let response = try await send(.init(command: .loadTraceSession, traceSessionID: id))
            guard let traceDetail = response.traceDetail else {
                errorMessage = response.errorMessage ?? "Trace not found"
                return
            }
            self.traceDetail = traceDetail
            self.selectedTraceSessionID = id
            self.selectedTraceStepID = traceDetail.steps.first?.id
            self.selectedSection = .traces
            await loadDiagnostics()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openArtifact(_ path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func revealArtifact(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func send(_ request: ControllerHostRequest) async throws -> ControllerHostResponse {
        guard let hostClient else {
            throw HostClientError.hostExited
        }
        return try await hostClient.send(request)
    }

    func executeAction(_ request: ActionRequest) async {
        do {
            isBusy = true
            defer { isBusy = false }
            let response = try await send(.init(command: .performAction, action: request))
            if let result = response.actionResult {
                record(result)
                if let resultingObservation = result.resultingObservation {
                    snapshot = ControlSnapshot(
                        capturedAt: Date(),
                        observation: resultingObservation,
                        screenshot: snapshot?.screenshot
                    )
                    selectedElementID = resultingObservation.focusedElementID
                }
                inlineMessage = result.approvalStatus == "pending"
                    ? (result.message ?? "Action pending approval.")
                    : (result.success ? (result.message ?? "Action completed.") : (result.message ?? "Action failed."))
                if let approvals = response.approvals {
                    approvalQueue = approvals
                }
                if let missionControl = response.missionControl {
                    self.missionControl = missionControl
                }
            } else {
                errorMessage = response.errorMessage ?? "Action failed"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ event: ControllerHostEvent) {
        switch event.kind {
        case .actionStarted:
            isBusy = true
            inlineMessage = event.message
            session = event.session ?? session

        case .actionCompleted:
            isBusy = false
            session = event.session ?? session
            if let action = event.action {
                record(action)
            }
            scheduleDiagnosticsRefresh()
            scheduleMissionControlRefresh()

        case .observationUpdated:
            session = event.session ?? session
            if let snapshot = event.snapshot {
                apply(snapshot: snapshot)
            }

        case .traceStepAppended:
            if let traceStep = event.traceStep {
                append(traceStep)
            }
            scheduleDiagnosticsRefresh()
            scheduleMissionControlRefresh()

        case .healthChanged:
            session = event.session ?? session
            if let health = event.health {
                self.health = health
            }
            scheduleDiagnosticsRefresh()
            scheduleMissionControlRefresh()

        case .recipesChanged:
            if let recipes = event.recipes {
                self.recipes = recipes
                syncSelectionAfterRecipeRefresh()
            }

        case .approvalsChanged:
            if let approvals = event.approvals {
                approvalQueue = approvals
            }

        case .missionControlChanged:
            if let missionControl = event.missionControl {
                self.missionControl = missionControl
            }
            if let providerStatus = event.chatProviderStatus {
                chatProviderStatus = providerStatus
            }

        case .chatStreamDelta:
            if let conversation = event.chatConversation {
                chatConversation = conversation
            }
            if let providerStatus = event.chatProviderStatus {
                chatProviderStatus = providerStatus
            }

        case .chatMessageCompleted:
            if let conversation = event.chatConversation {
                chatConversation = conversation
            }
            if let providerStatus = event.chatProviderStatus {
                chatProviderStatus = providerStatus
            }
        }
    }

    private func applyBootstrap(_ bootstrap: DashboardBootstrap?) {
        guard let bootstrap else { return }
        session = bootstrap.session
        snapshot = bootstrap.snapshot
        health = bootstrap.health
        recipes = bootstrap.recipes
        traceSessions = bootstrap.traceSessions
        approvalQueue = bootstrap.approvals
        missionControl = bootstrap.missionControl
        chatConversation = bootstrap.chatConversation
        chatProviderStatus = bootstrap.chatProviderStatus ?? bootstrap.missionControl?.providerStatus
        selectedElementID = bootstrap.snapshot?.observation.focusedElementID
        actionComposer.hydrate(from: bootstrap.snapshot)
        if monitorAppName.isEmpty {
            monitorAppName = bootstrap.session.activeAppName ?? bootstrap.snapshot?.observation.appName ?? ""
        }
        if selectedRecipeName == nil, let recipe = bootstrap.recipes.first {
            apply(recipe: recipe)
        }
        if selectedTraceSessionID == nil {
            selectedTraceSessionID = bootstrap.traceSessions.first?.id
        }
    }

    private func apply(snapshot: ControlSnapshot) {
        self.snapshot = snapshot
        selectedElementID = snapshot.observation.focusedElementID ?? selectedElementID
        actionComposer.hydrate(from: snapshot)
    }

    private func apply(recipe: RecipeDocument) {
        selectedRecipeName = recipe.name
        draftRecipe = recipe
        rawRecipeText = recipe.rawJSON ?? ""
        recipeRunParameters = recipe.params?.reduce(into: [String: String]()) { partialResult, entry in
            partialResult[entry.key] = partialResult[entry.key] ?? ""
        } ?? [:]
    }

    private func append(_ traceStep: TraceStepViewModel) {
        if let index = traceSessions.firstIndex(where: { $0.id == traceStep.sessionID }) {
            let updated = TraceSessionSummary(
                id: traceSessions[index].id,
                stepCount: traceSessions[index].stepCount + 1,
                lastUpdated: traceStep.timestamp
            )
            traceSessions[index] = updated
            traceSessions.sort { ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast) }
        } else {
            traceSessions.insert(
                TraceSessionSummary(id: traceStep.sessionID, stepCount: 1, lastUpdated: traceStep.timestamp),
                at: 0
            )
        }

        if selectedTraceSessionID == traceStep.sessionID {
            if traceDetail == nil {
                let summary = TraceSessionSummary(id: traceStep.sessionID, stepCount: 1, lastUpdated: traceStep.timestamp)
                traceDetail = TraceSessionDetail(summary: summary, steps: [traceStep])
            } else {
                let existingSteps = (traceDetail?.steps ?? []) + [traceStep]
                let summary = TraceSessionSummary(
                    id: traceStep.sessionID,
                    stepCount: existingSteps.count,
                    lastUpdated: traceStep.timestamp
                )
                traceDetail = TraceSessionDetail(summary: summary, steps: existingSteps)
            }
            selectedTraceStepID = traceStep.id
        }
    }

    private func record(_ action: ActionRunResult) {
        currentActionResult = action

        if recentActions.contains(where: { $0.id == action.id }) {
            return
        }

        recentActions.insert(action, at: 0)
        if recentActions.count > 8 {
            recentActions.removeLast()
        }
    }

    private func syncSelectionAfterRecipeRefresh() {
        guard let selectedRecipeName else { return }
        if let refreshed = recipes.first(where: { $0.name == selectedRecipeName }) {
            if self.selectedRecipeName == draftRecipe.name {
                apply(recipe: refreshed)
            }
        } else {
            self.selectedRecipeName = nil
        }
    }

    private func validateDraftRecipe() -> String? {
        if recipeEditorMode == .raw {
            return nil
        }

        if draftRecipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Recipe name is required."
        }
        if draftRecipe.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Recipe description is required."
        }
        if draftRecipe.steps.isEmpty {
            return "At least one recipe step is required."
        }
        return nil
    }

    var currentMonitorApp: String? {
        monitorAppName.nilIfBlank
    }

    private func requestForApprovedAction(from request: ActionRequest, approvalRequestID: String) -> ActionRequest {
        ActionRequest(
            kind: request.kind,
            appName: request.appName,
            windowTitle: request.windowTitle,
            query: request.query,
            role: request.role,
            domID: request.domID,
            text: request.text,
            clearExisting: request.clearExisting,
            x: request.x,
            y: request.y,
            button: request.button,
            count: request.count,
            key: request.key,
            modifiers: request.modifiers,
            direction: request.direction,
            amount: request.amount,
            waitCondition: request.waitCondition,
            waitValue: request.waitValue,
            timeout: request.timeout,
            interval: request.interval,
            approvalRequestID: approvalRequestID
        )
    }

    private func resumeRecipeRun(resumeToken: String, approvalRequestID: String) async {
        do {
            let response = try await send(
                .init(
                    command: .resumeRecipeRun,
                    approvalRequestID: approvalRequestID,
                    resumeToken: resumeToken
                )
            )
            if let recipeRun = response.recipeRun {
                latestRecipeRun = recipeRun
                inlineMessage = recipeRun.paused ? "Recipe still pending approval." : (recipeRun.success ? "Recipe completed." : "Recipe failed.")
            }
            if let approvals = response.approvals {
                approvalQueue = approvals
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
