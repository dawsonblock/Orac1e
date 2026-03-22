import Foundation

public struct DependencyAnalyzer: Sendable {
    public init() {}

    public func findCycles(in moduleGraph: ArchitectureModuleGraph) -> [[String]] {
        var cycles: [[String]] = []
        var visited: Set<String> = []
        var stack: [String] = []
        var active: Set<String> = []

        func dfs(_ node: String) {
            visited.insert(node)
            active.insert(node)
            stack.append(node)

            for dependency in moduleGraph.modules[node] ?? [] {
                if !visited.contains(dependency) {
                    dfs(dependency)
                } else if active.contains(dependency),
                          let index = stack.firstIndex(of: dependency)
                {
                    cycles.append(Array(stack[index...]))
                }
            }

            _ = stack.popLast()
            active.remove(node)
        }

        for node in moduleGraph.modules.keys where !visited.contains(node) {
            dfs(node)
        }

        return cycles
    }

    public func findings(in moduleGraph: ArchitectureModuleGraph) -> [ArchitectureFinding] {
        findCycles(in: moduleGraph).map { cycle in
            ArchitectureFinding(
                title: "Dependency cycle detected",
                summary: "Cycle found across \(cycle.joined(separator: " -> "))",
                severity: .warning,
                affectedModules: cycle,
                evidence: cycle,
                riskScore: 0.75
            )
        }
    }
}
