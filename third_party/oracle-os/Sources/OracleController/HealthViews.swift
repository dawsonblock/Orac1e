import SwiftUI
import OracleControllerShared

struct HealthWorkspaceView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("Runtime Health", subtitle: "Permissions, sidecar state, and local configuration") {
                    if let health = store.health {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                            GridRow {
                                KVRow(key: "Runtime", value: health.runtimeVersion)
                                KVRow(key: "Recipes", value: "\(health.recipeCount)")
                            }
                            GridRow {
                                KVRow(key: "Sidecar", value: health.visionSidecarRunning ? "Running" : "Unavailable")
                                KVRow(key: "Model", value: health.visionModelPath ?? "Unknown")
                            }
                            GridRow {
                                KVRow(key: "Policy Mode", value: health.policyMode)
                                KVRow(key: "Controller", value: health.controllerConnected ? "Connected" : "Offline")
                            }
                            GridRow {
                                KVRow(key: "Approval Broker", value: health.approvalBrokerActive ? "Active" : "Offline")
                                KVRow(key: "Claude MCP", value: health.claudeConfigured ? "Configured" : "Missing")
                            }
                            GridRow {
                                KVRow(key: "Bundle Mode", value: health.runningFromAppBundle ? "Packaged App" : "Developer")
                                KVRow(key: "Bundled Host", value: health.bundledHostAvailable ? "Embedded" : "Missing")
                            }
                            GridRow {
                                KVRow(key: "Trace Dir", value: health.traceDirectoryPath)
                                KVRow(key: "Recipe Dir", value: health.recipeDirectoryPath)
                            }
                            GridRow {
                                KVRow(key: "App Support", value: health.applicationSupportPath)
                                KVRow(key: "Logs", value: health.logsDirectoryPath)
                            }
                            GridRow {
                                KVRow(key: "Graph DB", value: health.graphDatabasePath)
                                KVRow(key: "Vision Install", value: health.visionInstallPath)
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "cross.case.fill",
                            title: "No Health Snapshot",
                            message: "Refresh health to inspect permissions, sidecar availability, and runtime directories."
                        )
                        .frame(height: 260)
                    }
                }

                PanelCard("Permissions", subtitle: "System access required for production-grade control") {
                    if let permissions = store.health?.permissions, !permissions.isEmpty {
                        ForEach(permissions) { permission in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(permission.title)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(permission.detail ?? "")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(label: permission.granted ? "Granted" : "Required", tone: permission.granted ? .good : .warning)
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                PanelCard("Tool Registry", subtitle: "Manifest-discovered tools and current health probes") {
                    if let registry = store.health?.toolRegistry {
                        VStack(alignment: .leading, spacing: 12) {
                            KVRow(key: "Root", value: registry.rootPath, monospaced: true)
                            KVRow(key: "Tools", value: "\(registry.toolCount)")
                            if !registry.capabilities.isEmpty {
                                KVRow(key: "Capabilities", value: registry.capabilities.joined(separator: ", "))
                            }
                            ForEach(registry.tools) { tool in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(tool.name)
                                                .font(.system(size: 13, weight: .semibold))
                                            Text(tool.id)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        StatusBadge(label: tool.healthy ? "Healthy" : "Unreachable", tone: tool.healthy ? .good : .warning)
                                    }
                                    KVRow(key: "Kind", value: tool.kind)
                                    KVRow(key: "Risk", value: tool.riskLevel)
                                    KVRow(key: "Base URL", value: tool.baseURL, monospaced: true)
                                    if !tool.capabilities.isEmpty {
                                        KVRow(key: "Capabilities", value: tool.capabilities.joined(separator: ", "))
                                    }
                                    if let detail = tool.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "shippingbox",
                            title: "No Tool Registry",
                            message: "Tool manifests were not discovered. Set ORACLE_TOOL_MANIFESTS or run from the workspace root."
                        )
                        .frame(height: 220)
                    }
                }

                PanelCard("Product Setup", subtitle: "Packaged runtime, diagnostics, and optional vision bootstrap") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let productStatus = store.productStatus {
                            KVRow(key: "Build", value: "\(productStatus.buildVersion) (\(productStatus.buildNumber))")
                            KVRow(key: "Vision Assets", value: productStatus.bundledVisionBootstrapAvailable ? "Bundled" : "Missing")
                            KVRow(key: "Vision Installed", value: productStatus.visionInstalled ? "Yes" : "No")
                            if !productStatus.migrationStatus.migratedLegacyItems.isEmpty {
                                KVRow(
                                    key: "Imported",
                                    value: productStatus.migrationStatus.migratedLegacyItems.joined(separator: ", ")
                                )
                            }
                        }

                        HStack(spacing: 10) {
                            Button("Install Vision Bootstrap") {
                                Task { await store.installVisionBootstrap() }
                            }
                            Button("Repair Vision") {
                                Task { await store.repairVisionBootstrap() }
                            }
                            Button("Export Diagnostics") {
                                store.exportDiagnostics()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct HealthInspectorView: View {
    @Bindable var store: ControllerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PanelCard("System Summary", subtitle: "What still blocks a frictionless operator loop") {
                    if let health = store.health {
                        KVRow(key: "Claude MCP", value: health.claudeConfigured ? "Configured" : "Missing")
                        KVRow(key: "Sidecar Version", value: health.visionSidecarVersion ?? "Unknown")
                        KVRow(key: "Approval Broker", value: health.approvalBrokerActive ? "Active" : "Offline")
                        KVRow(key: "Controller", value: health.controllerConnected ? "Connected" : "Offline")
                        KVRow(key: "Policy Mode", value: health.policyMode)
                        KVRow(key: "Tool Root", value: health.toolRegistry?.rootPath ?? "Not Found", monospaced: true)
                        KVRow(key: "Tool Count", value: "\(health.toolRegistry?.toolCount ?? 0)")
                        KVRow(key: "App Support", value: health.applicationSupportPath, monospaced: true)
                        KVRow(key: "Logs", value: health.logsDirectoryPath, monospaced: true)
                        KVRow(key: "Trace Directory", value: health.traceDirectoryPath, monospaced: true)
                        KVRow(key: "Recipe Directory", value: health.recipeDirectoryPath, monospaced: true)
                        KVRow(key: "Project Memory", value: health.projectMemoryDirectoryPath, monospaced: true)
                        KVRow(key: "Experiments", value: health.experimentsDirectoryPath, monospaced: true)
                        KVRow(key: "Graph DB", value: health.graphDatabasePath, monospaced: true)
                    } else {
                        EmptyStateView(
                            systemImage: "stethoscope",
                            title: "No Health Data",
                            message: "Refresh the dashboard to populate controller diagnostics."
                        )
                        .frame(height: 260)
                    }
                }

                if let registry = store.health?.toolRegistry {
                    PanelCard("Tool Health", subtitle: "Discovered manifests and live health checks") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(registry.tools) { tool in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(tool.name)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(tool.baseURL)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        if !tool.capabilities.isEmpty {
                                            Text(tool.capabilities.joined(separator: ", "))
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    StatusBadge(label: tool.healthy ? "Healthy" : "Unreachable", tone: tool.healthy ? .good : .warning)
                                }
                                .padding(10)
                                .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}
