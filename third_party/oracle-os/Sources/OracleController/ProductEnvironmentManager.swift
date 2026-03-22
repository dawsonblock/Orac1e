import AppKit
import Foundation
import OracleControllerShared
import OracleOS

struct ProductMigrationStatus: Equatable, Sendable {
    var migratedLegacyItems: [String] = []
    var warnings: [String] = []
    var seededSampleRecipes: Int = 0
    var importedDeveloperState = false

    var didMigrateAnything: Bool {
        !migratedLegacyItems.isEmpty || seededSampleRecipes > 0 || importedDeveloperState
    }
}

struct ProductEnvironmentStatus: Equatable, Sendable {
    let applicationSupportPath: String
    let logsPath: String
    let tracesPath: String
    let recipesPath: String
    let approvalsPath: String
    let graphDatabasePath: String
    let projectMemoryPath: String
    let experimentsPath: String
    let visionInstallPath: String
    let runningFromAppBundle: Bool
    let bundledHelperAvailable: Bool
    let bundledVisionBootstrapAvailable: Bool
    let bundledSampleRecipesAvailable: Bool
    let visionInstalled: Bool
    let buildVersion: String
    let buildNumber: String
    let migrationStatus: ProductMigrationStatus
}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case accessibility
    case screenRecording
    case runtime
    case vision
    case recipes
    case ready

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .runtime: return "Runtime Health"
        case .vision: return "Vision Setup"
        case .recipes: return "Quick Start"
        case .ready: return "Ready"
        }
    }
}

@MainActor
final class ProductEnvironmentManager {
    private let fileManager = FileManager.default
    private let onboardingKey = "oracle.controller.onboarding.completed"

    func prepareEnvironment() throws -> ProductEnvironmentStatus {
        try OracleProductPaths.ensureUserDirectories()
        var migrationStatus = migrateLegacyData()
        migrationStatus.seededSampleRecipes = try seedBundledRecipesIfNeeded()
        return status(migrationStatus: migrationStatus)
    }

    func installVisionBootstrap(repair: Bool = false) throws -> ProductEnvironmentStatus {
        guard let bundledVisionDirectory = OracleProductPaths.bundledVisionBootstrapDirectory else {
            throw NSError(
                domain: "ProductEnvironmentManager",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Bundled vision bootstrap assets are unavailable."]
            )
        }

        let destination = OracleProductPaths.visionInstallDirectory
        if repair, fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try OracleProductPaths.ensureUserDirectories()
        try copyItem(at: bundledVisionDirectory, to: destination)

        let launcher = destination.appendingPathComponent("oracle-vision", isDirectory: false)
        if fileManager.fileExists(atPath: launcher.path) {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)
        }

        return status(migrationStatus: ProductMigrationStatus())
    }

    func resetAllData() throws -> ProductEnvironmentStatus {
        if fileManager.fileExists(atPath: OracleProductPaths.dataRootDirectory.path) {
            try fileManager.removeItem(at: OracleProductPaths.dataRootDirectory)
        }
        if fileManager.fileExists(atPath: OracleProductPaths.logsDirectory.path) {
            try fileManager.removeItem(at: OracleProductPaths.logsDirectory)
        }
        return try prepareEnvironment()
    }

    func exportDiagnostics(
        health: HealthStatus?,
        session: ControllerSession?,
        snapshot: ControlSnapshot?,
        approvals: [ApprovalRequestDocument],
        traceDetail: TraceSessionDetail?,
        recipes: [RecipeDocument],
        productStatus: ProductEnvironmentStatus?,
        diagnostics: ControllerDiagnosticsSnapshot?
    ) throws -> URL {
        try OracleProductPaths.ensureUserDirectories()
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = OracleProductPaths.exportsDirectory.appendingPathComponent("diagnostics-\(timestamp).json", isDirectory: false)

        let payload: [String: Any] = [
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "session": session.map(Self.encodeDictionary) as Any,
            "health": health.map(Self.encodeDictionary) as Any,
            "snapshot": snapshot.map(Self.encodeDictionary) as Any,
            "approvals": approvals.map(Self.encodeDictionary),
            "trace_detail": traceDetail.map(Self.encodeDictionary) as Any,
            "recipes": recipes.map(Self.encodeDictionary),
            "product_status": productStatus.map(Self.encodeProductStatus) as Any,
            "diagnostics": diagnostics.map(Self.encodeDictionary) as Any,
        ]

        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination)
        return destination
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([OracleProductPaths.dataRootDirectory])
    }

    func openLogsFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([OracleProductPaths.logsDirectory])
    }

    func openHelp() {
        if let helpURL = OracleProductPaths.helpDocumentURL {
            NSWorkspace.shared.open(helpURL)
        }
    }

    func openReleaseNotes() {
        if let releaseNotesURL = OracleProductPaths.releaseNotesURL {
            NSWorkspace.shared.open(releaseNotesURL)
        }
    }

    func openSystemSettingsForAccessibility() {
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openSystemSettingsForScreenRecording() {
        openSystemSettings(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    func isOnboardingCompleted() -> Bool {
        UserDefaults.standard.bool(forKey: onboardingKey)
    }

    func setOnboardingCompleted(_ completed: Bool) {
        UserDefaults.standard.set(completed, forKey: onboardingKey)
    }

    private func status(migrationStatus: ProductMigrationStatus) -> ProductEnvironmentStatus {
        ProductEnvironmentStatus(
            applicationSupportPath: OracleProductPaths.dataRootDirectory.path,
            logsPath: OracleProductPaths.logsDirectory.path,
            tracesPath: OracleProductPaths.tracesRootDirectory.path,
            recipesPath: OracleProductPaths.recipesDirectory.path,
            approvalsPath: OracleProductPaths.approvalsDirectory.path,
            graphDatabasePath: OracleProductPaths.graphDatabaseURL.path,
            projectMemoryPath: OracleProductPaths.projectMemoryDirectory.path,
            experimentsPath: OracleProductPaths.experimentsDirectory.path,
            visionInstallPath: OracleProductPaths.visionInstallDirectory.path,
            runningFromAppBundle: OracleProductPaths.runningFromAppBundle,
            bundledHelperAvailable: OracleProductPaths.bundledHelperURL != nil,
            bundledVisionBootstrapAvailable: OracleProductPaths.bundledVisionBootstrapDirectory != nil,
            bundledSampleRecipesAvailable: OracleProductPaths.bundledSampleRecipesDirectory != nil,
            visionInstalled: fileManager.fileExists(atPath: OracleProductPaths.visionInstallDirectory.appendingPathComponent("server.py").path),
            buildVersion: OracleProductPaths.buildVersion,
            buildNumber: OracleProductPaths.buildNumber,
            migrationStatus: migrationStatus
        )
    }

    private func migrateLegacyData() -> ProductMigrationStatus {
        var status = ProductMigrationStatus()

        if fileManager.fileExists(atPath: OracleProductPaths.legacyRecipesDirectory.path) {
            do {
                let copied = try copyDirectoryContentsIfNeeded(
                    from: OracleProductPaths.legacyRecipesDirectory,
                    to: OracleProductPaths.recipesDirectory
                )
                if copied > 0 {
                    status.migratedLegacyItems.append("recipes:\(copied)")
                }
            } catch {
                status.warnings.append("Recipe migration failed: \(error.localizedDescription)")
            }
        }

        if fileManager.fileExists(atPath: OracleProductPaths.legacyApprovalsDirectory.path) {
            do {
                let copied = try copyDirectoryContentsIfNeeded(
                    from: OracleProductPaths.legacyApprovalsDirectory,
                    to: OracleProductPaths.approvalsDirectory
                )
                if copied > 0 {
                    status.migratedLegacyItems.append("approvals:\(copied)")
                }
            } catch {
                status.warnings.append("Approval migration failed: \(error.localizedDescription)")
            }
        }

        if fileManager.fileExists(atPath: OracleProductPaths.legacyLogsDirectory.path) {
            do {
                let copied = try copyDirectoryContentsIfNeeded(
                    from: OracleProductPaths.legacyLogsDirectory,
                    to: OracleProductPaths.logsDirectory
                )
                if copied > 0 {
                    status.migratedLegacyItems.append("logs:\(copied)")
                }
            } catch {
                status.warnings.append("Log migration failed: \(error.localizedDescription)")
            }
        }

        let legacyGraphDB = OracleProductPaths.legacyGraphDirectory.appendingPathComponent("oracleos.sqlite3", isDirectory: false)
        if fileManager.fileExists(atPath: legacyGraphDB.path),
           !fileManager.fileExists(atPath: OracleProductPaths.graphDatabaseURL.path)
        {
            do {
                try fileManager.createDirectory(at: OracleProductPaths.graphDirectory, withIntermediateDirectories: true)
                try fileManager.copyItem(at: legacyGraphDB, to: OracleProductPaths.graphDatabaseURL)
                status.migratedLegacyItems.append("graph:1")
            } catch {
                status.warnings.append("Graph migration failed: \(error.localizedDescription)")
            }
        }

        let legacyVenv = OracleProductPaths.legacyVisionDirectory.appendingPathComponent("venv", isDirectory: true)
        if fileManager.fileExists(atPath: legacyVenv.path),
           !fileManager.fileExists(atPath: OracleProductPaths.visionInstallDirectory.appendingPathComponent(".venv").path)
        {
            do {
                try copyItem(
                    at: legacyVenv,
                    to: OracleProductPaths.visionInstallDirectory.appendingPathComponent(".venv", isDirectory: true)
                )
                status.migratedLegacyItems.append("vision-venv:1")
            } catch {
                status.warnings.append("Vision environment migration failed: \(error.localizedDescription)")
            }
        }

        let legacyModel = OracleProductPaths.legacyVisionDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("ShowUI-2B", isDirectory: true)
        if fileManager.fileExists(atPath: legacyModel.path),
           !fileManager.fileExists(atPath: OracleProductPaths.visionModelDirectory.path)
        {
            do {
                try copyItem(at: legacyModel, to: OracleProductPaths.visionModelDirectory)
                status.migratedLegacyItems.append("vision-model:1")
            } catch {
                status.warnings.append("Vision model migration failed: \(error.localizedDescription)")
            }
        }

        if let developerRoot = OracleProductPaths.developerProjectRoot {
            let tracesRoot = developerRoot.appendingPathComponent(".traces", isDirectory: true)
            if fileManager.fileExists(atPath: tracesRoot.path) {
                do {
                    let copied = try copyDirectoryContentsIfNeeded(
                        from: tracesRoot,
                        to: OracleProductPaths.tracesRootDirectory
                    )
                    if copied > 0 {
                        status.importedDeveloperState = true
                        status.migratedLegacyItems.append("developer-traces:\(copied)")
                    }
                } catch {
                    status.warnings.append("Developer trace import failed: \(error.localizedDescription)")
                }
            }

            let projectMemoryRoot = developerRoot.appendingPathComponent("ProjectMemory", isDirectory: true)
            if fileManager.fileExists(atPath: projectMemoryRoot.path) {
                do {
                    let importedDestination = OracleProductPaths.projectMemoryDirectory
                        .appendingPathComponent("Imported-\(developerRoot.lastPathComponent)", isDirectory: true)
                    let copied = try copyDirectoryContentsIfNeeded(from: projectMemoryRoot, to: importedDestination)
                    if copied > 0 {
                        status.importedDeveloperState = true
                        status.migratedLegacyItems.append("developer-project-memory:\(copied)")
                    }
                } catch {
                    status.warnings.append("Developer project memory import failed: \(error.localizedDescription)")
                }
            }
        }

        return status
    }

    private func seedBundledRecipesIfNeeded() throws -> Int {
        guard let bundledRecipesDirectory = OracleProductPaths.bundledSampleRecipesDirectory else {
            return 0
        }

        let existingRecipes = (try? fileManager.contentsOfDirectory(
            at: OracleProductPaths.recipesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }) ?? []

        guard existingRecipes.isEmpty else {
            return 0
        }

        let bundledRecipes = try fileManager.contentsOfDirectory(
            at: bundledRecipesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }

        for recipe in bundledRecipes {
            let destination = OracleProductPaths.recipesDirectory.appendingPathComponent(recipe.lastPathComponent, isDirectory: false)
            try copyItem(at: recipe, to: destination)
        }

        return bundledRecipes.count
    }

    private func copyDirectoryContentsIfNeeded(from source: URL, to destination: URL) throws -> Int {
        guard fileManager.fileExists(atPath: source.path) else { return 0 }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let urls = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var copied = 0
        for url in urls {
            let target = destination.appendingPathComponent(url.lastPathComponent, isDirectory: url.hasDirectoryPath)
            if fileManager.fileExists(atPath: target.path) {
                continue
            }
            try copyItem(at: url, to: target)
            copied += 1
        }
        return copied
    }

    private func copyItem(at source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            return
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    private func openSystemSettings(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func encodeDictionary<T: Encodable>(_ value: T) -> [String: Any] {
        let encoder = ControllerJSONCoding.makeEncoder()
        guard
            let data = try? encoder.encode(value),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }

    private static func encodeProductStatus(_ value: ProductEnvironmentStatus) -> [String: Any] {
        [
            "application_support_path": value.applicationSupportPath,
            "logs_path": value.logsPath,
            "traces_path": value.tracesPath,
            "recipes_path": value.recipesPath,
            "approvals_path": value.approvalsPath,
            "graph_database_path": value.graphDatabasePath,
            "project_memory_path": value.projectMemoryPath,
            "experiments_path": value.experimentsPath,
            "vision_install_path": value.visionInstallPath,
            "running_from_app_bundle": value.runningFromAppBundle,
            "bundled_helper_available": value.bundledHelperAvailable,
            "bundled_vision_bootstrap_available": value.bundledVisionBootstrapAvailable,
            "bundled_sample_recipes_available": value.bundledSampleRecipesAvailable,
            "vision_installed": value.visionInstalled,
            "build_version": value.buildVersion,
            "build_number": value.buildNumber,
            "migration": [
                "migrated_legacy_items": value.migrationStatus.migratedLegacyItems,
                "warnings": value.migrationStatus.warnings,
                "seeded_sample_recipes": value.migrationStatus.seededSampleRecipes,
                "imported_developer_state": value.migrationStatus.importedDeveloperState,
            ],
        ]
    }
}
