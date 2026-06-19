// main.swift - Oracle OS CLI entry point
//
// Commands:
//   oracle mcp       Start the MCP server
//   oracle setup     Interactive setup wizard
//   oracle doctor    Diagnose issues and suggest fixes
//   oracle dashboard Live terminal dashboard
//   oracle status    Quick health check
//   oracle tools     List discovered tool manifests
//   oracle coding    Run or review bounded coding runs
//   oracle version   Print version

import AppKit
import ApplicationServices
import Foundation
import OracleOS

// Force CoreGraphics server connection initialization.
// ScreenCaptureKit requires a CG connection to the window server.
_ = CGMainDisplayID()

@MainActor
func main() async {
    let args = CommandLine.arguments.dropFirst()
    let command = args.first ?? "help"

    switch command {
    case "mcp":
        let server = MCPServer()
        server.run()

    case "setup":
        let wizard = SetupWizard()
        wizard.run()

    case "doctor":
        var doctor = Doctor()
        doctor.run()

    case "dashboard":
        let dash = Dashboard()
        dash.run()

    case "status":
        printStatus()

    case "tools":
        printTools()

    case "coding":
        await handleCodingCommand(arguments: Array(args.dropFirst()))

    case "version", "--version", "-v":
        print("Oracle OS v\(OracleOS.version)")

    case "help", "--help", "-h":
        printUsage()

    default:
        fputs("Unknown command: \(command)\n", stderr)
        printUsage()
        exit(1)
    }
}

await main()

// MARK: - Status

@MainActor
func printStatus() {
    print("Oracle OS v\(OracleOS.version)")
    print("")

    let hasAX = AXIsProcessTrusted()
    print("Accessibility: \(hasAX ? "granted" : "NOT GRANTED")")
    if !hasAX {
        print("  Run: oracle setup")
    }

    let hasScreenRecording = ScreenCapture.hasPermission()
    print("Screen Recording: \(hasScreenRecording ? "granted" : "not granted")")

    let recipes = RecipeStore.listRecipes()
    print("Recipes: \(recipes.count) installed")

    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    print("Running apps: \(apps.count)")

    if let toolSummary = try? CodingToolBootstrap.loadSummary() {
        print("Tools root: \(toolSummary.rootPath)")
        print("Tools discovered: \(toolSummary.count)")
    } else {
        print("Tools discovered: unavailable")
    }

    print("")
    print(hasAX ? "Status: Ready" : "Status: Run `oracle setup` first")
}

@MainActor
func printTools() {
    print("Oracle OS v\(OracleOS.version)")
    print("")

    guard let root = CodingToolBootstrap.resolveToolsRoot() else {
        print("No tool manifests found.")
        print("Set ORACLE_TOOL_MANIFESTS or run from the workspace root.")
        return
    }

    do {
        let registry = ToolRegistry()
        try registry.load(from: root)
        let manifests = registry.all().sorted { $0.id < $1.id }
        print("Tool manifests root: \(root.path)")
        print("Tool count: \(manifests.count)")
        print("")

        let toolClient = ToolClient()
        for manifest in manifests {
            let healthy = syncCLIHealth(toolClient: toolClient, manifest: manifest)
            let status = healthy ? "healthy" : "unreachable"
            print("- \(manifest.id) [\(manifest.kind.rawValue)] - \(status)")
            print("    base: \(manifest.baseURL)")
            print("    caps: \(manifest.capabilities.joined(separator: ", "))")
        }

        let capabilities = Array(Set(manifests.flatMap(\.capabilities))).sorted()
        if !capabilities.isEmpty {
            print("")
            print("Capabilities:")
            for capability in capabilities {
                print("  - \(capability)")
            }
        }
    } catch {
        fputs("Failed to load tool manifests: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

@MainActor
func syncCLIHealth(toolClient: ToolClient, manifest: ToolManifest) -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var healthy = false
    Task {
        healthy = await toolClient.health(manifest)
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + .milliseconds(manifest.timeouts.healthMs + 250))
    return healthy
}

// MARK: - Coding

private struct CLIParsedArguments {
    var positionals: [String] = []
    var values: [String: [String]] = [:]

    func value(for key: String) -> String? { values[key]?.last }
    func values(for key: String) -> [String] { values[key] ?? [] }
}

private func parseCLIArguments(_ args: [String]) -> CLIParsedArguments {
    var parsed = CLIParsedArguments()
    var index = 0
    while index < args.count {
        let token = args[index]
        if token.hasPrefix("--") {
            let key = String(token.dropFirst(2))
            if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                parsed.values[key, default: []].append(args[index + 1])
                index += 2
            } else {
                parsed.values[key, default: []].append("true")
                index += 1
            }
        } else {
            parsed.positionals.append(token)
            index += 1
        }
    }
    return parsed
}

@MainActor
func handleCodingCommand(arguments: [String]) async {
    let subcommand = arguments.first ?? "help"
    let parsed = parseCLIArguments(Array(arguments.dropFirst()))
    let runtime = OracleCodingRuntime()

    do {
        switch subcommand {
        case "list":
            let runs = try await runtime.listRuns()
            if runs.isEmpty {
                print("No coding runs found.")
                return
            }
            for run in runs {
                let pending = run.approvalRequired ? " approval=pending" : ""
                print("\(run.record.id)  \(run.record.status.rawValue)  \(run.record.mode.rawValue)  \(run.record.repoName)\(pending)")
                print("  task: \(run.record.task)")
                if !run.pendingApprovalReasons.isEmpty {
                    print("  reasons: \(run.pendingApprovalReasons.joined(separator: " | "))")
                }
            }

        case "show":
            guard let runID = parsed.positionals.first else {
                throw CLIError.usage("oracle coding show <run-id>")
            }
            guard let detail = try await runtime.loadRun(id: runID) else {
                throw CLIError.message("Run not found: \(runID)")
            }
            printCodingRunDetail(detail)

        case "run":
            guard let repoPath = parsed.value(for: "repo") else {
                throw CLIError.usage("oracle coding run --repo /path/to/repo --task \"...\"")
            }
            guard let task = parsed.value(for: "task") else {
                throw CLIError.usage("oracle coding run --repo /path/to/repo --task \"...\"")
            }
            let mode = CodingRunMode(rawValue: parsed.value(for: "mode") ?? "interactive") ?? .interactive
            let retrievalQuery = parsed.value(for: "query")
            let allowedPaths = splitMultiValue(parsed.values(for: "allow"))
            let validationCommands = parsed.values(for: "validate")
            let submission = OracleCodingRunSubmission(
                repoPath: repoPath,
                task: task,
                mode: mode,
                retrievalQuery: retrievalQuery,
                allowedPaths: allowedPaths.isEmpty ? [""] : allowedPaths,
                validationCommands: validationCommands
            )
            let detail = try await runtime.start(submission)
            printCodingRunDetail(detail)

        case "approve":
            guard let runID = parsed.positionals.first else {
                throw CLIError.usage("oracle coding approve <run-id> [--reason text]")
            }
            guard let detail = try await runtime.approve(runID: runID, reason: parsed.value(for: "reason")) else {
                throw CLIError.message("Run not found: \(runID)")
            }
            printCodingRunDetail(detail)

        case "reject":
            guard let runID = parsed.positionals.first else {
                throw CLIError.usage("oracle coding reject <run-id> [--reason text]")
            }
            guard let detail = try await runtime.reject(runID: runID, reason: parsed.value(for: "reason")) else {
                throw CLIError.message("Run not found: \(runID)")
            }
            printCodingRunDetail(detail)

        case "help", "--help", "-h":
            printCodingUsage()

        default:
            throw CLIError.usage("Unknown coding subcommand: \(subcommand)")
        }
    } catch let error as CLIError {
        fputs(error.description + "\n", stderr)
        if case .usage = error {
            printCodingUsage()
        }
        exit(1)
    } catch {
        fputs(error.localizedDescription + "\n", stderr)
        exit(1)
    }
}

private enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case message(String)

    var description: String {
        switch self {
        case .usage(let message), .message(let message):
            return message
        }
    }
}

private func splitMultiValue(_ values: [String]) -> [String] {
    values
        .flatMap { $0.split(separator: ",").map(String.init) }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func printCodingRunDetail(_ detail: OracleCodingRunDetail) {
    let record = detail.summary.record
    print("Run: \(record.id)")
    print("Repo: \(record.repoName)")
    print("Path: \(record.repoPath)")
    print("Mode: \(record.mode.rawValue)")
    print("Status: \(record.status.rawValue)")
    print("Task: \(record.task)")
    if !detail.summary.pendingApprovalReasons.isEmpty {
        print("Approval reasons: \(detail.summary.pendingApprovalReasons.joined(separator: " | "))")
    }
    if let pending = detail.pendingProposal {
        print("Worker: \(pending.worker)")
        if !pending.touchedPaths.isEmpty {
            print("Touched files: \(pending.touchedPaths.joined(separator: ", "))")
        }
        print("Changed lines: \(pending.changedLines)")
        if !pending.warnings.isEmpty {
            print("Warnings: \(pending.warnings.joined(separator: " | "))")
        }
    }
    if !detail.approvals.isEmpty {
        print("Approvals:")
        for approval in detail.approvals {
            print("  - \(approval.approved ? "approved" : "rejected") at \(approval.timestamp): \(approval.reason ?? "")")
        }
    }
    if !detail.artifactPaths.isEmpty {
        print("Artifacts:")
        for path in detail.artifactPaths {
            print("  - \(path)")
        }
    }
    if !detail.events.isEmpty {
        print("Events:")
        for event in detail.events {
            let payload = event.payload.isEmpty ? "" : " \(event.payload)"
            print("  - \(event.timestamp) \(event.type)\(payload)")
        }
    }
}

private func printCodingUsage() {
    print("""
    Oracle coding commands

    Usage:
      oracle coding list
      oracle coding show <run-id>
      oracle coding run --repo /path/to/repo --task "Fix the bug" [--mode interactive|autonomous] [--query text] [--allow path1,path2] [--validate "pytest -q"]...
      oracle coding run --repo /path/to/repo --task "Fix the bug"   # uses staged profile auto-detection when --validate is omitted
      oracle coding approve <run-id> [--reason text]
      oracle coding reject <run-id> [--reason text]

    Environment:
      ORACLE_CODING_WORKSPACE_ROOT   Override coding workspace root
      ORACLE_CODING_RETRIEVAL_URL    Override retrieval broker base URL
      ORACLE_CODING_AIDER_URL        Override aider worker base URL
      ORACLE_CODING_HARDENED_URL     Override hardened worker base URL
      ORACLE_CODING_RUN_SERVER_URL   Override run server base URL
    """)
}

// MARK: - Usage

func printUsage() {
    print("""
    Oracle OS v\(OracleOS.version) - Accessibility-tree MCP server for AI agents

    Usage: oracle <command>

    Commands:
      mcp         Start the MCP server (used by Claude Code)
      setup       Interactive setup wizard (first-time configuration)
      doctor      Diagnose issues and suggest fixes
      dashboard   Live terminal dashboard (agent state, policy, metrics)
      status      Quick health check
      tools       List discovered tool manifests
      coding      Run or review bounded coding runs
      version     Print version

    Get started:
      oracle setup    Configure permissions and MCP
      oracle doctor   Check if everything is working
      oracle coding help

    Oracle OS gives AI agents eyes and hands on macOS.
    """)
}
