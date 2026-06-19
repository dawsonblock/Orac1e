import Foundation

public struct ChangeImpactAnalyzer: Sendable {
    public init() {}

    public func affectedModules(for paths: [String]) -> [String] {
        Array(Set(paths.map(ArchitectureModuleGraph.moduleName(for:)))).sorted()
    }

    public func shouldReview(goalDescription: String, candidatePaths: [String]) -> Bool {
        let lowered = goalDescription.lowercased()
        if lowered.contains("refactor") || lowered.contains("architecture") || lowered.contains("boundary") {
            return true
        }
        return affectedModules(for: candidatePaths).count > 1
    }
}
