import Foundation

public enum RepositoryQuery {
    public static func files(matching symbol: String, in snapshot: RepositorySnapshot) -> [String] {
        CodeQueryEngine()
            .findSymbol(named: symbol, in: snapshot)
            .map(\.file)
            .uniqued()
    }

    public static func references(to symbol: String, in snapshot: RepositorySnapshot) -> [String] {
        CodeQueryEngine()
            .findFilesReferencing(symbol: symbol, in: snapshot)
            .uniqued()
    }

    public static func buildEntrypoints(in snapshot: RepositorySnapshot) -> [String] {
        let knownFiles = [
            "Package.swift",
            "package.json",
            "pyproject.toml",
            "pytest.ini",
        ]
        let projectFiles = snapshot.files.filter {
            $0.path.hasSuffix(".xcodeproj") || $0.path.hasSuffix(".xcworkspace")
        }.map(\.path)

        return (knownFiles + projectFiles).filter { path in
            snapshot.files.contains(where: { $0.path == path })
        }.uniqued()
    }

    public static func likelyFiles(
        for failureOutput: String,
        in snapshot: RepositorySnapshot
    ) -> [String] {
        CodeQueryEngine()
            .findLikelyRootCause(failureDescription: failureOutput, in: snapshot)
            .map(\.path)
            .uniqued()
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
