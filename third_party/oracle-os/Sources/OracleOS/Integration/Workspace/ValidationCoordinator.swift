import Foundation

private struct CodingValidationProfile: Decodable {
    let profile: String?
    let language: String?
    let commands: [String]?
    let stages: [CodingValidationProfileStage]?
}

private struct CodingValidationProfileStage: Decodable {
    let id: String
    let name: String
    let commands: [String]
    let haltOnFailure: Bool?
}

private struct CodingValidationExecutionStage: Sendable {
    let id: String
    let name: String
    let commands: [String]
    let haltOnFailure: Bool
}

private struct CodingValidationExecutionPlan: Sendable {
    let profileName: String
    let stages: [CodingValidationExecutionStage]

    var resolvedCommands: [String] {
        stages.flatMap(\.commands)
    }
}

public actor CodingValidationCoordinator {
    private let commands: [String]
    private let configRootURL: URL?

    public init(commands: [String], configRootURL: URL? = nil) {
        self.commands = commands
        self.configRootURL = configRootURL
    }

    public func resolvePlan(for repoURL: URL) -> CodingValidationExecutionPlan {
        return executionPlan(for: repoURL)
    }

    public func validate(repoURL: URL) async -> CodingValidationResult {
        let plan = executionPlan(for: repoURL)
        var steps: [CodingValidationStep] = []

        if plan.stages.isEmpty && plan.resolvedCommands.isEmpty {
            return CodingValidationResult(
                ok: false,
                steps: [],
                profileName: plan.profileName,
                stageCount: 0,
                resolvedCommands: [],
                errorCategory: "validation_unconfigured"
            )
        }

        for stage in plan.stages {
            for command in stage.commands {
                let step = await runShell(
                    command: command,
                    cwd: repoURL.path,
                    stageID: stage.id,
                    stageName: stage.name,
                    profileName: plan.profileName
                )
                steps.append(step)
                if !step.ok && stage.haltOnFailure {
                    return CodingValidationResult(
                        ok: false,
                        steps: steps,
                        profileName: plan.profileName,
                        stageCount: plan.stages.count,
                        resolvedCommands: plan.resolvedCommands
                    )
                }
            }
        }

        return CodingValidationResult(
            ok: true,
            steps: steps,
            profileName: plan.profileName,
            stageCount: plan.stages.count,
            resolvedCommands: plan.resolvedCommands
        )
    }

    private func executionPlan(for repoURL: URL) -> CodingValidationExecutionPlan {
        if !commands.isEmpty {
            return CodingValidationExecutionPlan(
                profileName: "custom",
                stages: [
                    CodingValidationExecutionStage(
                        id: "custom",
                        name: "Custom validation",
                        commands: commands,
                        haltOnFailure: true
                    )
                ]
            )
        }

        let inferredProfile = inferProfileName(for: repoURL)
        if let profile = loadProfile(named: inferredProfile) {
            let plan = executionPlan(from: profile, fallbackProfileName: inferredProfile)
            if !plan.stages.isEmpty {
                return plan
            }
        }

        if inferredProfile != "default", let fallback = loadProfile(named: "default") {
            let plan = executionPlan(from: fallback, fallbackProfileName: "default")
            if !plan.stages.isEmpty {
                return plan
            }
        }

        return CodingValidationExecutionPlan(profileName: inferredProfile, stages: [])
    }

    private func executionPlan(
        from profile: CodingValidationProfile,
        fallbackProfileName: String
    ) -> CodingValidationExecutionPlan {
        let profileName = profile.profile ?? profile.language ?? fallbackProfileName

        if let profileStages = profile.stages, !profileStages.isEmpty {
            let stages = profileStages
                .map { stage in
                    CodingValidationExecutionStage(
                        id: stage.id,
                        name: stage.name,
                        commands: stage.commands,
                        haltOnFailure: stage.haltOnFailure ?? true
                    )
                }
                .filter { !$0.commands.isEmpty }
            return CodingValidationExecutionPlan(profileName: profileName, stages: stages)
        }

        let legacyCommands = profile.commands ?? []
        if !legacyCommands.isEmpty {
            return CodingValidationExecutionPlan(
                profileName: profileName,
                stages: [
                    CodingValidationExecutionStage(
                        id: "legacy",
                        name: "Legacy validation",
                        commands: legacyCommands,
                        haltOnFailure: true
                    )
                ]
            )
        }

        return CodingValidationExecutionPlan(profileName: profileName, stages: [])
    }

    private func loadProfile(named profileName: String) -> CodingValidationProfile? {
        guard let configRootURL else { return nil }
        let profileURL = configRootURL
            .appendingPathComponent("configs", isDirectory: true)
            .appendingPathComponent("validation_profiles", isDirectory: true)
            .appendingPathComponent("\(profileName).json", isDirectory: false)

        guard let data = try? Data(contentsOf: profileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(CodingValidationProfile.self, from: data)
    }

    private func inferProfileName(for repoURL: URL) -> String {
        let fileManager = FileManager.default
        let root = repoURL.standardizedFileURL

        if fileManager.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
            return "swift"
        }
        if fileManager.fileExists(atPath: root.appendingPathComponent("pyproject.toml").path)
            || fileManager.fileExists(atPath: root.appendingPathComponent("requirements.txt").path)
            || fileManager.fileExists(atPath: root.appendingPathComponent("setup.py").path)
        {
            return "python"
        }
        if fileManager.fileExists(atPath: root.appendingPathComponent("tsconfig.json").path) {
            return "typescript"
        }
        if fileManager.fileExists(atPath: root.appendingPathComponent("package.json").path) {
            return packageProfileName(at: root.appendingPathComponent("package.json"))
        }
        if containsFileExtension("py", under: root) {
            return "python"
        }
        if containsFileExtension("ts", under: root) || containsFileExtension("tsx", under: root) {
            return "typescript"
        }
        if containsFileExtension("js", under: root) || containsFileExtension("jsx", under: root) {
            return "javascript"
        }
        return "default"
    }

    private func packageProfileName(at packageURL: URL) -> String {
        guard let data = try? Data(contentsOf: packageURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return "javascript"
        }

        let dependencyBuckets = [json["dependencies"], json["devDependencies"], json["peerDependencies"]]
            .compactMap { $0 as? [String: Any] }

        for bucket in dependencyBuckets {
            if bucket.keys.contains(where: { $0.localizedCaseInsensitiveContains("typescript") }) {
                return "typescript"
            }
        }

        return "javascript"
    }

    private func containsFileExtension(_ fileExtension: String, under root: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }

        var checked = 0
        for case let fileURL as URL in enumerator {
            checked += 1
            if checked > 1500 {
                return false
            }
            guard fileURL.pathExtension.caseInsensitiveCompare(fileExtension) == .orderedSame else {
                continue
            }
            return true
        }
        return false
    }

    private func runShell(
        command: String,
        cwd: String,
        stageID: String,
        stageName: String,
        profileName: String,
        timeoutSeconds: TimeInterval = 300  // 5 minutes default
    ) async -> CodingValidationStep {
        let startTime = Date()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var stdoutData = Data()
        var stderrData = Data()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        
        // Use readabilityHandler for non-blocking concurrent pipe draining
        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                stdoutData.append(chunk)
            }
        }
        
        stderrHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                stderrData.append(chunk)
            }
        }

        var timedOut = false
        var didTerminate = false
        
        // Run process with timeout handling
        do {
            try process.run()
            
            // Wait with timeout
            let timeoutWorkItem = DispatchWorkItem {
                timedOut = true
                if !didTerminate {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)
            
            process.waitUntilExit()
            timeoutWorkItem.cancel()
            didTerminate = true
            
        } catch {
            // Clean up handlers on error
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            return CodingValidationStep(
                name: command,
                ok: false,
                stdout: "",
                stderr: error.localizedDescription,
                exitCode: 1,
                stageID: stageID,
                stageName: stageName,
                profileName: profileName,
                timedOut: false,
                durationMs: durationMs,
                failureCategory: "process_start_failure"
            )
        }
        
        // Clear handlers after completion
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        
        // Determine failure category
        let failureCategory: String?
        if timedOut {
            failureCategory = "timeout"
        } else if process.terminationStatus != 0 {
            failureCategory = "exit_failure"
        } else {
            failureCategory = nil
        }
        
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        
        return CodingValidationStep(
            name: command,
            ok: !timedOut && process.terminationStatus == 0,
            stdout: stdout,
            stderr: stderr,
            exitCode: timedOut ? -1 : process.terminationStatus,
            stageID: stageID,
            stageName: stageName,
            profileName: profileName,
            timedOut: timedOut,
            durationMs: durationMs,
            failureCategory: failureCategory
        )
    }
}
