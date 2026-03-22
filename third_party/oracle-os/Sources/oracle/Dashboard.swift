// Dashboard.swift — Oracle OS terminal dashboard
//
// Renders a live ANSI terminal view of agent state, loop configuration,
// policy rules, recovery strategies, memory, and runtime metrics.
//
// Usage: oracle dashboard

import AppKit
import ApplicationServices
import Foundation
import OracleOS

// MARK: - ANSI helpers

private enum ANSI {
    static let reset  = "\u{001B}[0m"
    static let bold   = "\u{001B}[1m"
    static let dim    = "\u{001B}[2m"
    static let green  = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let cyan   = "\u{001B}[36m"
    static let blue   = "\u{001B}[34m"
    static let red    = "\u{001B}[31m"
    static let white  = "\u{001B}[37m"
    static let gray   = "\u{001B}[90m"

    static func bar(_ color: String, _ text: String) -> String {
        "\(color)\(bold)\(text)\(reset)"
    }
    static func ok(_ text: String) -> String   { "\(green)✓\(reset) \(text)" }
    static func warn(_ text: String) -> String { "\(yellow)⚠\(reset) \(text)" }
    static func fail(_ text: String) -> String { "\(red)✗\(reset) \(text)" }
    static func kv(_ key: String, _ val: String, width: Int = 28) -> String {
        let padded = key.padding(toLength: width, withPad: " ", startingAt: 0)
        return "  \(gray)\(padded)\(reset)\(val)"
    }
    static func divider(_ width: Int = 60) -> String {
        gray + String(repeating: "─", count: width) + reset
    }
    static func header(_ title: String) -> String {
        let line = String(repeating: "━", count: 60)
        return "\n\(cyan)\(bold)\(line)\(reset)\n  \(bold)\(title)\(reset)\n\(cyan)\(line)\(reset)"
    }
    static func subheader(_ title: String) -> String {
        "  \(blue)\(bold)▸ \(title)\(reset)"
    }
}

// MARK: - Dashboard

@MainActor
public struct Dashboard {
    public init() {}

    public func run() {
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        printTitle()
        printSystemStatus()
        printLoopConfig()
        printPolicyConfig()
        printRecoveryStrategies()
        printMemory()
        printMetrics()
        printFooter(now: now, formatter: formatter)
    }

    // MARK: - Title

    private func printTitle() {
        print("")
        print(ANSI.cyan + ANSI.bold + """
  ╔══════════════════════════════════════════════════════════╗
  ║          Oracle OS  —  Agent Dashboard                  ║
  ╚══════════════════════════════════════════════════════════╝
""" + ANSI.reset)
        print(ANSI.kv("Version", OracleOS.version))
        print(ANSI.kv("Platform", "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"))
    }

    // MARK: - System Status

    private func printSystemStatus() {
        print(ANSI.header("SYSTEM STATUS"))

        let hasAX = AXIsProcessTrusted()
        print(hasAX
            ? ANSI.ok("Accessibility: granted")
            : ANSI.fail("Accessibility: NOT GRANTED  →  oracle setup"))

        let hasSR = ScreenCapture.hasPermission()
        print(hasSR
            ? ANSI.ok("Screen Recording: granted")
            : ANSI.warn("Screen Recording: not granted  →  oracle setup"))

        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        let names = apps.prefix(6).compactMap(\.localizedName).joined(separator: ", ")
        let extra = apps.count > 6 ? " +\(apps.count - 6) more" : ""
        print(ANSI.ok("Running apps: \(apps.count)  [\(names)\(extra)]"))

        let recipes = RecipeStore.listRecipes()
        print(ANSI.ok("Recipes: \(recipes.count) installed"))
        for recipe in recipes.prefix(5) {
            print("    \(ANSI.gray)•\(ANSI.reset) \(recipe.name)  \(ANSI.gray)(\(recipe.steps.count) steps)\(ANSI.reset)")
        }
        if recipes.count > 5 {
            print("    \(ANSI.gray)… and \(recipes.count - 5) more\(ANSI.reset)")
        }

        // Vision sidecar
        if VisionBridge.isAvailable() {
            if let health = VisionBridge.healthCheck(),
               let status = health["status"] as? String {
                let models = (health["models_loaded"] as? [String])?.joined(separator: ", ") ?? "—"
                print(ANSI.ok("Vision Sidecar: \(status)  models: \(models)"))
            } else {
                print(ANSI.ok("Vision Sidecar: running"))
            }
        } else {
            print("  \(ANSI.gray)○ Vision Sidecar: idle (auto-starts on demand)\(ANSI.reset)")
        }

        // oracle-vision binary
        let visionPaths = [
            "/opt/homebrew/bin/oracle-vision",
            "/usr/local/bin/oracle-vision",
            (ProcessInfo.processInfo.arguments[0] as NSString)
                .deletingLastPathComponent + "/oracle-vision",
        ]
        let visionPath = visionPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        if let vp = visionPath {
            print(ANSI.ok("oracle-vision: \(vp)"))
        } else {
            print(ANSI.warn("oracle-vision: not found  →  oracle setup"))
        }
    }

    // MARK: - Loop Configuration

    private func printLoopConfig() {
        print(ANSI.header("AGENT LOOP CONFIGURATION"))

        let budget = LoopBudget()
        print(ANSI.subheader("LoopBudget (defaults)"))
        print(ANSI.kv("Max steps", "\(budget.maxSteps)"))
        print(ANSI.kv("Max recoveries", "\(budget.maxRecoveries)"))
        print(ANSI.kv("Max consecutive stalls", "\(budget.maxConsecutiveStalls)"))
        print(ANSI.kv("Max patch iterations", "\(budget.maxPatchIterations)"))
        print(ANSI.kv("Max build attempts", "\(budget.maxBuildAttempts)"))
        print(ANSI.kv("Max test attempts", "\(budget.maxTestAttempts)"))
        print(ANSI.kv("Max consecutive exploration", "\(budget.maxConsecutiveExplorationSteps)"))

        print("")
        print(ANSI.subheader("RunState fields"))
        let stateFields: [(String, String)] = [
            ("latestWorldState",        "WorldState?          — last perception snapshot"),
            ("lastAction",              "ActionIntent?        — previous intent"),
            ("lastDecisionContract",    "ActionContract?      — stall-detection anchor"),
            ("consecutiveStallCount",   "Int                  — increments on no-op cycles"),
            ("recentFailureCount",      "Int                  — resets on recovery"),
            ("diagnostics",             "LoopDiagnostics      — per-step trace"),
            ("budgetState",             "LoopBudgetState      — remaining budget"),
        ]
        for (name, desc) in stateFields {
            print(ANSI.kv(name, desc))
        }

        print("")
        print(ANSI.subheader("Termination reasons"))
        let reasons = [
            ("goalAchieved",       "✓ Postconditions met"),
            ("budgetExhausted",    "⚑ Step/time budget expired"),
            ("loopStalled",        "⟳ Same contract × world hash repeated"),
            ("policyBlocked",      "⛔ Hard policy block"),
            ("criticalError",      "✗ Unrecoverable runtime error"),
            ("recoveryFailed",     "✗ Recovery strategy exhausted"),
            ("userCancelled",      "↩ User interrupted"),
        ]
        for (reason, desc) in reasons {
            print("    \(ANSI.cyan)\(reason)\(ANSI.reset)  \(ANSI.gray)\(desc)\(ANSI.reset)")
        }
    }

    // MARK: - Policy Configuration

    private func printPolicyConfig() {
        print(ANSI.header("POLICY ENGINE"))

        print(ANSI.subheader("Protected operation guard"))
        print(ANSI.kv("Max consecutive protected ops", "3"))
        print(ANSI.kv("Lock scope", "per ProtectedOperation kind"))
        print(ANSI.kv("Reset trigger", "executionCoordinator.resetPolicyGuard()"))

        print("")
        print(ANSI.subheader("Sensitive workspace paths"))
        let sensitive = [
            "Package.swift", "Package.resolved", ".xcodeproj/", ".xcworkspace/",
            "Makefile", "Dockerfile", ".gitconfig", ".ssh/", "fastlane/", "scripts/",
        ]
        for path in sensitive {
            print("    \(ANSI.red)⛔\(ANSI.reset) \(path)")
        }

        print("")
        print(ANSI.subheader("Safe source paths"))
        let safe = [
            "Sources/", "Tests/", "src/", "lib/", "test/", "spec/",
            "docs/", "documentation/",
        ]
        for path in safe {
            print("    \(ANSI.green)✓\(ANSI.reset) \(path)")
        }

        print("")
        print(ANSI.subheader("Workspace-scope integrity guard"))
        print(ANSI.kv("Checked on", "every code-write intent"))
        print(ANSI.kv("Blocks", "paths starting with / or containing ../"))
        print(ANSI.kv("Returns", "workspaceScopeViolation (no driver call)"))
    }

    // MARK: - Recovery Strategies

    private func printRecoveryStrategies() {
        print(ANSI.header("RECOVERY STRATEGIES"))

        let strategies: [(String, String, String)] = [
            ("retryStrategy",             ".retry",   "Retry the last action up to maxRetries"),
            ("refreshObservation",        ".replan",  "Re-scan AX tree and rebuild world state"),
            ("refocusApp",                ".replan",  "Focus the frontmost application window"),
            ("dismissModal",              ".replan",  "Dismiss any blocking modal/dialog"),
            ("alternateElement",          ".replan",  "Try a different UI element for the intent"),
            ("refreshIndex",              ".replan",  "Refresh code repository index"),
            ("rerunFocusedTests",         ".replan",  "Re-run focused test suite"),
            ("revertPatch",               ".rollback","Revert the last applied patch"),
            ("stallRecovery",             ".replan",  "Refocus app + diversify from last action"),
        ]

        let colW = 26
        let header = "  \(ANSI.bold)\("Strategy".padding(toLength: colW, withPad: " ", startingAt: 0))Layer      Description\(ANSI.reset)"
        print(header)
        print("  " + ANSI.divider(58))
        for (name, layer, desc) in strategies {
            let namePad  = name.padding(toLength: colW, withPad: " ", startingAt: 0)
            let layerPad = layer.padding(toLength: 10, withPad: " ", startingAt: 0)
            print("  \(ANSI.cyan)\(namePad)\(ANSI.reset)\(ANSI.yellow)\(layerPad)\(ANSI.reset)\(ANSI.gray)\(desc)\(ANSI.reset)")
        }

        print("")
        print(ANSI.subheader("Failure → Strategy mapping"))
        let mapping: [(String, String)] = [
            (".elementNotFound",    "alternateElement, refreshObservation"),
            (".actionFailed",       "retryStrategy, refreshObservation"),
            (".dialogInterruption", "dismissModal, refreshObservation"),
            (".policyBlocked",      "refocusApp"),
            (".buildFailed",        "revertPatch, refreshIndex"),
            (".testFailed",         "rerunFocusedTests, revertPatch"),
            (".loopStalled",        "stallRecovery"),
        ]
        for (failure, strat) in mapping {
            print("    \(ANSI.red)\(failure)\(ANSI.reset)  \(ANSI.gray)→  \(strat)\(ANSI.reset)")
        }
    }

    // MARK: - Memory

    private func printMemory() {
        print(ANSI.header("PROJECT MEMORY"))

        let memRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("ProjectMemory")
        let subdirs = ["architecture-decisions", "known-good-patterns", "open-problems", "rejected-approaches"]
        var totalRecords = 0

        for subdir in subdirs {
            let dir = memRoot.appendingPathComponent(subdir)
            let files = (try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.filter { $0.pathExtension == "md" && $0.lastPathComponent != "README.md" } ?? []
            totalRecords += files.count
            let icon = files.isEmpty ? ANSI.gray + "○" + ANSI.reset : ANSI.green + "●" + ANSI.reset
            print("  \(icon) \(subdir)  \(ANSI.gray)(\(files.count) records)\(ANSI.reset)")
            for f in files.prefix(3) {
                print("    \(ANSI.gray)•\(ANSI.reset) \(f.deletingPathExtension().lastPathComponent)")
            }
        }

        // risk-register
        let riskFile = memRoot.appendingPathComponent("risk-register.md")
        if let content = try? String(contentsOf: riskFile, encoding: .utf8),
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = content.split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty && $0 != "6 %" }
            print("")
            print(ANSI.subheader("risk-register.md"))
            for line in lines.prefix(6) {
                print("    \(ANSI.gray)\(line)\(ANSI.reset)")
            }
        }

        // Critic state
        print("")
        print(ANSI.subheader("CriticLoop configuration"))
        print(ANSI.kv("Max consecutive unknowns", "3  →  escalates to failure"))
        print(ANSI.kv("Trust boundary", "executedThroughExecutor=false → failure"))
        print(ANSI.kv("No-op detection", "succeeded but no state change → failure"))
    }

    // MARK: - Metrics

    private func printMetrics() {
        print(ANSI.header("RUNTIME METRICS"))

        print(ANSI.subheader("Benchmark baseline"))
        print(ANSI.kv("Source", "EvalRunner task reports"))
        print(ANSI.kv("Data model", "EvalMetrics aggregated from run snapshots"))
        print(ANSI.kv("Placeholder JSON", "removed from Diagnostics/"))

        // Strategy baseline
        print("")
        print(ANSI.subheader("Strategy reevaluation triggers"))
        let triggers = [
            ("hardFailure",           "recentFailureCount ≥ 3  →  force strategy re-select"),
            ("policyBlocked ×3",      "max consecutive protected ops exceeded"),
            ("loopStalled",           "no world-state change after N cycles"),
            ("StrategyReevaluation",  "StrategyEvaluator.shouldReevaluate() → true"),
        ]
        for (trigger, desc) in triggers {
            print("    \(ANSI.yellow)⚡\(ANSI.reset) \(ANSI.bold)\(trigger)\(ANSI.reset)  \(ANSI.gray)\(desc)\(ANSI.reset)")
        }
    }

    // MARK: - Footer

    private func printFooter(now: Date, formatter: ISO8601DateFormatter) {
        print("")
        print("  " + ANSI.divider(58))
        print("  \(ANSI.gray)Generated: \(formatter.string(from: now))\(ANSI.reset)")
        print("  \(ANSI.gray)Oracle OS v\(OracleOS.version)  •  oracle doctor  •  oracle status\(ANSI.reset)")
        print("")
    }
}
