import Foundation

public final class RepositoryIndexer: @unchecked Sendable {
    private struct ParsedFile {
        let file: RepositoryFile
        let text: String
        let lineCount: Int
    }

    private struct PendingSymbolEdge {
        let fromSymbolID: String
        let targetName: String
        let kind: SymbolEdgeKind
    }

    public init() {}

    public func index(workspaceRoot: URL) -> RepositorySnapshot {
        let buildTool = BuildToolDetector.detect(at: workspaceRoot)
        let files = enumerateFiles(workspaceRoot: workspaceRoot)
        let parsedFiles = loadParsedFiles(from: files, workspaceRoot: workspaceRoot)
        let symbolGraph = buildSymbolGraph(from: parsedFiles)
        let dependencyGraph = buildDependencyGraph(
            from: parsedFiles,
            allFiles: files,
            workspaceRoot: workspaceRoot
        )
        let callGraph = buildCallGraph(from: parsedFiles, symbolGraph: symbolGraph)
        let testGraph = buildTestGraph(from: parsedFiles, symbolGraph: symbolGraph)
        let buildGraph = buildBuildGraph(
            buildTool: buildTool,
            files: files,
            dependencyGraph: dependencyGraph
        )
        let branch = currentBranch(workspaceRoot: workspaceRoot)
        let dirty = gitDirty(workspaceRoot: workspaceRoot)
        let id = [
            workspaceRoot.path,
            buildTool.rawValue,
            branch ?? "detached",
            dirty ? "dirty" : "clean",
        ].joined(separator: "|")

        let indexURL = workspaceRoot
            .appendingPathComponent(".oracle", isDirectory: true)
            .appendingPathComponent("repo_index.json", isDirectory: false)
        let diagnostics = IndexDiagnostics(
            fileCount: files.count,
            symbolCount: symbolGraph.nodes.count,
            dependencyCount: dependencyGraph.edges.count,
            callEdgeCount: callGraph.edges.count,
            testEdgeCount: testGraph.edges.count,
            buildTargetCount: buildGraph.targets.count,
            persistedIndexPath: indexURL.path
        )

        let snapshot = RepositorySnapshot(
            id: id,
            workspaceRoot: workspaceRoot.path,
            buildTool: buildTool,
            files: files,
            symbolGraph: symbolGraph,
            dependencyGraph: dependencyGraph,
            callGraph: callGraph,
            testGraph: testGraph,
            buildGraph: buildGraph,
            activeBranch: branch,
            isGitDirty: dirty,
            indexDiagnostics: diagnostics
        )

        persist(snapshot: snapshot, to: indexURL)
        return snapshot
    }

    public func indexIfNeeded(workspaceRoot: URL) -> RepositorySnapshot {
        if let persisted = loadPersistedSnapshot(workspaceRoot: workspaceRoot),
           snapshotIsCurrent(persisted, workspaceRoot: workspaceRoot)
        {
            return persisted
        }
        return index(workspaceRoot: workspaceRoot)
    }

    public func loadPersistedSnapshot(workspaceRoot: URL) -> RepositorySnapshot? {
        let indexURL = Self.persistedIndexURL(workspaceRoot: workspaceRoot)
        guard let data = try? Data(contentsOf: indexURL) else {
            return nil
        }
        let decoder = OracleJSONCoding.makeDecoder()
        return try? decoder.decode(RepositorySnapshot.self, from: data)
    }

    public static func persistedIndexURL(workspaceRoot: URL) -> URL {
        workspaceRoot
            .appendingPathComponent(".oracle", isDirectory: true)
            .appendingPathComponent("repo_index.json", isDirectory: false)
    }

    private func enumerateFiles(workspaceRoot: URL) -> [RepositoryFile] {
        let resolvedRootPath = workspaceRoot.resolvingSymlinksInPath().path
        guard let enumerator = FileManager.default.enumerator(
            at: workspaceRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [RepositoryFile] = []
        for case let fileURL as URL in enumerator {
            let resolvedFilePath = fileURL.resolvingSymlinksInPath().path
            let relative = resolvedFilePath.replacingOccurrences(of: resolvedRootPath + "/", with: "")
            if shouldSkip(relativePath: relative) {
                continue
            }

            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let isDirectory = values?.isDirectory ?? false
            files.append(
                RepositoryFile(
                    path: relative,
                    isDirectory: isDirectory,
                    lastModifiedAt: values?.contentModificationDate
                )
            )
        }
        return files.sorted { $0.path < $1.path }
    }

    private func shouldSkip(relativePath: String) -> Bool {
        relativePath.hasPrefix(".build/")
            || relativePath.hasPrefix(".git/")
            || relativePath.hasPrefix("node_modules/")
            || relativePath.hasPrefix(".oracle/")
            || relativePath.hasPrefix("DerivedData/")
    }

    private func loadParsedFiles(from files: [RepositoryFile], workspaceRoot: URL) -> [ParsedFile] {
        files.compactMap { file in
            guard !file.isDirectory, shouldParseTextFile(path: file.path) else {
                return nil
            }

            let fileURL = workspaceRoot.appendingPathComponent(file.path, isDirectory: false)
            guard let data = FileManager.default.contents(atPath: fileURL.path),
                  let text = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            return ParsedFile(
                file: file,
                text: text,
                lineCount: max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
            )
        }
    }

    private func shouldParseTextFile(path: String) -> Bool {
        let supportedExtensions = [
            ".swift", ".py", ".js", ".jsx", ".ts", ".tsx",
            ".json", ".toml", ".yml", ".yaml", ".md"
        ]
        return supportedExtensions.contains(where: { path.hasSuffix($0) }) || path == "Package.swift"
    }

    private func buildSymbolGraph(from parsedFiles: [ParsedFile]) -> SymbolGraph {
        var nodes: [SymbolNode] = []
        var pendingEdges: [PendingSymbolEdge] = []

        for parsed in parsedFiles {
            let matches = extractSymbols(from: parsed)
            let sorted = matches.sorted { lhs, rhs in
                if lhs.lineStart == rhs.lineStart {
                    return lhs.name < rhs.name
                }
                return lhs.lineStart < rhs.lineStart
            }

            for index in sorted.indices {
                let current = sorted[index]
                let nextLine = index + 1 < sorted.count ? sorted[index + 1].lineStart - 1 : parsed.lineCount
                let lineEnd = max(current.lineStart, nextLine)
                let node = SymbolNode(
                    id: "\(parsed.file.path)|\(current.name)|\(current.kind.rawValue)|\(current.lineStart)",
                    name: current.name,
                    kind: current.kind,
                    file: parsed.file.path,
                    lineStart: current.lineStart,
                    lineEnd: lineEnd
                )
                nodes.append(node)

                if let inheritedName = current.inheritedName {
                    pendingEdges.append(
                        PendingSymbolEdge(
                            fromSymbolID: node.id,
                            targetName: inheritedName,
                            kind: current.edgeKind
                        )
                    )
                }
            }
        }

        let nameLookup = Dictionary(grouping: nodes, by: { $0.name.lowercased() })
        let edges = pendingEdges.compactMap { pending -> SymbolEdge? in
            guard let target = nameLookup[pending.targetName.lowercased()]?.first else {
                return nil
            }
            return SymbolEdge(
                fromSymbolID: pending.fromSymbolID,
                toSymbolID: target.id,
                kind: pending.kind
            )
        }

        return SymbolGraph(nodes: nodes, edges: edges)
    }

    private struct ExtractedSymbol {
        let name: String
        let kind: SymbolKind
        let lineStart: Int
        let inheritedName: String?
        let edgeKind: SymbolEdgeKind
    }

    private func extractSymbols(from parsed: ParsedFile) -> [ExtractedSymbol] {
        let language = language(for: parsed.file.path)
        let patterns: [(SymbolKind, String, Int?, SymbolEdgeKind)] = switch language {
        case .swift:
            [
                (.function, #"func\s+([A-Za-z_][A-Za-z0-9_]*)"#, nil, .defines),
                (.struct, #"struct\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*:\s*([A-Za-z_][A-Za-z0-9_]*))?"#, 2, .implements),
                (.class, #"class\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s*:\s*([A-Za-z_][A-Za-z0-9_]*))?"#, 2, .inherits),
                (.enum, #"enum\s+([A-Za-z_][A-Za-z0-9_]*)"#, nil, .defines),
                (.interface, #"protocol\s+([A-Za-z_][A-Za-z0-9_]*)"#, nil, .declares),
                (.constant, #"(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)"#, nil, .defines),
            ]
        case .python:
            [
                (.function, #"def\s+([A-Za-z_][A-Za-z0-9_]*)"#, nil, .defines),
                (.class, #"class\s+([A-Za-z_][A-Za-z0-9_]*)(?:\(([A-Za-z_][A-Za-z0-9_]*)\))?"#, 2, .inherits),
                (.variable, #"([A-Za-z_][A-Za-z0-9_]*)\s*="#, nil, .defines),
            ]
        case .javascript, .typescript:
            [
                (.function, #"function\s+([A-Za-z_][A-Za-z0-9_]*)"#, nil, .defines),
                (.class, #"class\s+([A-Za-z_][A-Za-z0-9_]*)(?:\s+extends\s+([A-Za-z_][A-Za-z0-9_]*))?"#, 2, .inherits),
                (.interface, #"interface\s+([A-Za-z_][A-Za-z0-9_]*)"#, nil, .declares),
                (.enum, #"enum\s+([A-Za-z_][A-Za-z0-9_]*)"#, nil, .defines),
                (.constant, #"(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)"#, nil, .defines),
            ]
        case .other:
            []
        }

        var results: [ExtractedSymbol] = []
        for (kind, pattern, inheritedGroup, edgeKind) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(parsed.text.startIndex..<parsed.text.endIndex, in: parsed.text)
            for match in regex.matches(in: parsed.text, range: range) {
                guard match.numberOfRanges > 1,
                      let nameRange = Range(match.range(at: 1), in: parsed.text)
                else {
                    continue
                }

                let lineStart = parsed.text[..<nameRange.lowerBound]
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .count + 1
                let inheritedName: String?
                if let inheritedGroup,
                   match.numberOfRanges > inheritedGroup,
                   let groupRange = Range(match.range(at: inheritedGroup), in: parsed.text)
                {
                    inheritedName = String(parsed.text[groupRange])
                } else {
                    inheritedName = nil
                }

                results.append(
                    ExtractedSymbol(
                        name: String(parsed.text[nameRange]),
                        kind: kind,
                        lineStart: lineStart,
                        inheritedName: inheritedName,
                        edgeKind: edgeKind
                    )
                )
            }
        }

        return results
    }

    private func buildDependencyGraph(
        from parsedFiles: [ParsedFile],
        allFiles: [RepositoryFile],
        workspaceRoot: URL
    ) -> DependencyGraph {
        var edges: [DependencyEdge] = []
        let allSourceFiles = allFiles.filter { !$0.isDirectory }.map(\.path)

        for parsed in parsedFiles {
            for match in extractDependencyMatches(text: parsed.text, path: parsed.file.path) {
                edges.append(
                    DependencyEdge(
                        sourcePath: parsed.file.path,
                        dependency: match.dependency,
                        toFile: resolveDependency(
                            dependency: match.dependency,
                            fromPath: parsed.file.path,
                            allFiles: allSourceFiles,
                            workspaceRoot: workspaceRoot
                        ),
                        type: match.type
                    )
                )
            }
        }

        return DependencyGraph(edges: edges)
    }

    private func extractDependencyMatches(
        text: String,
        path: String
    ) -> [(dependency: String, type: DependencyType)] {
        let language = language(for: path)
        let patterns: [(String, DependencyType)] = switch language {
        case .swift:
            [(#"import\s+([A-Za-z_][A-Za-z0-9_.]*)"#, .importDependency)]
        case .python:
            [
                (#"from\s+([A-Za-z_][A-Za-z0-9_.]*)\s+import"#, .importDependency),
                (#"import\s+([A-Za-z_][A-Za-z0-9_.]*)"#, .importDependency),
            ]
        case .javascript, .typescript:
            [
                (#"from\s+["']([^"']+)["']"#, .importDependency),
                (#"require\(["']([^"']+)["']\)"#, .include),
                (#"import\(["']([^"']+)["']\)"#, .include),
            ]
        case .other:
            []
        }

        var results: [(String, DependencyType)] = []
        for (pattern, type) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard match.numberOfRanges > 1,
                      let depRange = Range(match.range(at: 1), in: text)
                else {
                    continue
                }
                results.append((String(text[depRange]), type))
            }
        }
        return results
    }

    private func resolveDependency(
        dependency: String,
        fromPath: String,
        allFiles: [String],
        workspaceRoot: URL
    ) -> String? {
        if dependency.hasPrefix(".") {
            let baseURL = workspaceRoot
                .appendingPathComponent((fromPath as NSString).deletingLastPathComponent, isDirectory: true)
            let resolved = baseURL.appendingPathComponent(dependency).standardizedFileURL.path
            let relative = resolved.replacingOccurrences(of: workspaceRoot.standardizedFileURL.path + "/", with: "")
            let relativeWithoutExtension = (relative as NSString).deletingPathExtension
            let candidates = [
                relative,
                relative + ".swift",
                relative + ".ts",
                relative + ".tsx",
                relative + ".js",
                relative + ".jsx",
                relative + ".py",
                relativeWithoutExtension + ".swift",
                relativeWithoutExtension + ".ts",
                relativeWithoutExtension + ".js",
                relativeWithoutExtension + ".py",
            ]
            return candidates.first(where: { allFiles.contains($0) })
        }

        let moduleName = dependency.split(separator: ".").last.map(String.init) ?? dependency
        let lowercasedModule = moduleName.lowercased()

        let exactBaseMatch = allFiles.first { path in
            URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased() == lowercasedModule
        }
        if let exactBaseMatch {
            return exactBaseMatch
        }

        let sourceModuleMatch = allFiles.first { path in
            path.lowercased().contains("/\(lowercasedModule)/")
        }
        if let sourceModuleMatch {
            return sourceModuleMatch
        }

        return nil
    }

    private func buildCallGraph(
        from parsedFiles: [ParsedFile],
        symbolGraph: SymbolGraph
    ) -> CallGraph {
        let symbolsByFile = Dictionary(grouping: symbolGraph.nodes, by: \.file)
        let symbolsByName = Dictionary(grouping: symbolGraph.nodes, by: { $0.name.lowercased() })
        let ignoredNames: Set<String> = [
            "if", "for", "while", "switch", "guard", "return", "print", "init"
        ]
        let regex = try? NSRegularExpression(pattern: #"\b([A-Za-z_][A-Za-z0-9_]*)\s*\("#)

        var edges = Set<CallEdge>()
        for parsed in parsedFiles {
            guard let regex else { continue }
            let fileSymbols = symbolsByFile[parsed.file.path, default: []].sorted { $0.lineStart < $1.lineStart }
            guard !fileSymbols.isEmpty else { continue }

            let lines = parsed.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, line) in lines.enumerated() {
                let lineNumber = index + 1
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                for match in regex.matches(in: line, range: range) {
                    guard match.numberOfRanges > 1,
                          let nameRange = Range(match.range(at: 1), in: line)
                    else {
                        continue
                    }
                    let calleeName = String(line[nameRange]).lowercased()
                    guard !ignoredNames.contains(calleeName),
                          let caller = fileSymbols.last(where: { $0.lineStart <= lineNumber && $0.lineEnd >= lineNumber }),
                          let callees = symbolsByName[calleeName]
                    else {
                        continue
                    }

                    for callee in callees where callee.id != caller.id {
                        edges.insert(
                            CallEdge(
                                caller: caller.id,
                                callee: callee.id
                            )
                        )
                    }
                }
            }
        }

        return CallGraph(edges: Array(edges).sorted {
            if $0.caller == $1.caller {
                return $0.callee < $1.callee
            }
            return $0.caller < $1.caller
        })
    }

    private func buildTestGraph(
        from parsedFiles: [ParsedFile],
        symbolGraph: SymbolGraph
    ) -> TestGraph {
        let testNodes = symbolGraph.nodes.filter { isTest(path: $0.file, symbolName: $0.name) }
        let sourceNodes = symbolGraph.nodes.filter { !isTest(path: $0.file, symbolName: $0.name) }
        let parsedByPath = Dictionary(uniqueKeysWithValues: parsedFiles.map { ($0.file.path, $0.text) })

        var tests = testNodes.map {
            RepositoryTest(name: $0.name, path: $0.file, symbolID: $0.id)
        }

        let fileOnlyTests = parsedFiles
            .filter { parsed in
                isTestFile(path: parsed.file.path)
                    && !tests.contains(where: { test in test.path == parsed.file.path })
            }
            .map { RepositoryTest(name: URL(fileURLWithPath: $0.file.path).lastPathComponent, path: $0.file.path) }
        tests.append(contentsOf: fileOnlyTests)

        var edges = Set<TestEdge>()
        for testNode in testNodes {
            let text = parsedByPath[testNode.file] ?? ""
            let nameTokens = tokens(from: testNode.name)
            for sourceNode in sourceNodes {
                let sourceTokens = tokens(from: sourceNode.name)
                let sharedTokens = nameTokens.intersection(sourceTokens)
                let explicitMention = text.localizedCaseInsensitiveContains(sourceNode.name)
                if explicitMention || sharedTokens.count >= 2 {
                    edges.insert(TestEdge(testSymbolID: testNode.id, targetSymbolID: sourceNode.id))
                }
            }
        }

        return TestGraph(
            tests: tests.sorted { lhs, rhs in
                if lhs.path == rhs.path {
                    return lhs.name < rhs.name
                }
                return lhs.path < rhs.path
            },
            edges: Array(edges).sorted {
                if $0.testSymbolID == $1.testSymbolID {
                    return $0.targetSymbolID < $1.targetSymbolID
                }
                return $0.testSymbolID < $1.testSymbolID
            }
        )
    }

    private func buildBuildGraph(
        buildTool: BuildTool,
        files: [RepositoryFile],
        dependencyGraph: DependencyGraph
    ) -> BuildGraph {
        let sourceFiles = files.filter { !$0.isDirectory }
        switch buildTool {
        case .swiftPackage, .xcodebuild:
            let grouped = Dictionary(grouping: sourceFiles) { file -> String in
                let components = file.path.split(separator: "/").map(String.init)
                if components.count >= 2, components[0] == "Sources" {
                    return components[1]
                }
                if components.count >= 2, components[0] == "Tests" {
                    return components[1]
                }
                return "workspace"
            }

            let targets = grouped.keys.sorted().map { targetName -> BuildTarget in
                let targetFiles = grouped[targetName, default: []].map(\.path).sorted()
                let targetDependencies = Set(
                    dependencyGraph.edges.compactMap { edge -> String? in
                        guard targetFiles.contains(edge.sourcePath),
                              let toFile = edge.toFile
                        else {
                            return nil
                        }
                        let components = toFile.split(separator: "/").map(String.init)
                        if components.count >= 2, components[0] == "Sources" {
                            return components[1]
                        }
                        if components.count >= 2, components[0] == "Tests" {
                            return components[1]
                        }
                        return nil
                    }.filter { $0 != targetName }
                )

                return BuildTarget(
                    id: targetName,
                    name: targetName,
                    sourceFiles: targetFiles,
                    dependencies: Array(targetDependencies).sorted()
                )
            }
            return BuildGraph(targets: targets)
        case .npm, .pytest, .unknown:
            return BuildGraph(
                targets: [
                    BuildTarget(
                        id: "workspace",
                        name: "workspace",
                        sourceFiles: sourceFiles.map(\.path).sorted(),
                        dependencies: []
                    )
                ]
            )
        }
    }

    private func isTest(path: String, symbolName: String) -> Bool {
        isTestFile(path: path) || symbolName.lowercased().hasPrefix("test")
    }

    private func isTestFile(path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.contains("/tests/")
            || lowercased.contains("tests/")
            || lowercased.contains("test")
    }

    private func tokens(from text: String) -> Set<String> {
        let normalized = text
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .lowercased()
        let parts = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return Set(parts.filter { $0.count > 1 && $0 != "test" })
    }

    private enum SourceLanguage {
        case swift
        case python
        case javascript
        case typescript
        case other
    }

    private func language(for path: String) -> SourceLanguage {
        if path.hasSuffix(".swift") {
            return .swift
        }
        if path.hasSuffix(".py") {
            return .python
        }
        if path.hasSuffix(".ts") || path.hasSuffix(".tsx") {
            return .typescript
        }
        if path.hasSuffix(".js") || path.hasSuffix(".jsx") {
            return .javascript
        }
        return .other
    }

    private func persist(snapshot: RepositorySnapshot, to url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Index persistence is best-effort. Runtime indexing should still succeed.
        }
    }

    private func snapshotIsCurrent(
        _ snapshot: RepositorySnapshot,
        workspaceRoot: URL
    ) -> Bool {
        guard snapshot.activeBranch == currentBranch(workspaceRoot: workspaceRoot),
              snapshot.isGitDirty == gitDirty(workspaceRoot: workspaceRoot)
        else {
            return false
        }

        let currentFiles = enumerateFiles(workspaceRoot: workspaceRoot)
        guard currentFiles.count == snapshot.files.count else {
            return false
        }

        let snapshotFilesByPath = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.path, $0) })
        for current in currentFiles {
            guard let stored = snapshotFilesByPath[current.path],
                  stored.isDirectory == current.isDirectory,
                  stored.lastModifiedAt == current.lastModifiedAt
            else {
                return false
            }
        }

        return true
    }

    private func currentBranch(workspaceRoot: URL) -> String? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "branch", "--show-current"]
        process.currentDirectoryURL = workspaceRoot
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private func gitDirty(workspaceRoot: URL) -> Bool {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "status", "--porcelain"]
        process.currentDirectoryURL = workspaceRoot
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } catch {
            return false
        }
    }
}
