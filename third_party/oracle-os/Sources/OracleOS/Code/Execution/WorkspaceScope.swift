import Foundation

public enum WorkspaceScopeError: Error, LocalizedError, Sendable, Equatable {
    case invalidRoot(String)
    case outsideWorkspace(String)
    case missingPath(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRoot(path):
            "Invalid workspace root: \(path)"
        case let .outsideWorkspace(path):
            "Path is outside workspace scope: \(path)"
        case let .missingPath(path):
            "Missing workspace path: \(path)"
        }
    }
}

public struct WorkspaceScope: Sendable, Equatable {
    public let rootURL: URL

    public init(rootURL: URL) throws {
        let standardized = rootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkspaceScopeError.invalidRoot(standardized.path)
        }
        self.rootURL = standardized
    }

    public func resolve(relativePath: String?) throws -> URL? {
        guard let relativePath else { return nil }
        guard !relativePath.isEmpty else {
            throw WorkspaceScopeError.missingPath(relativePath)
        }

        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(rootURL.path) else {
            throw WorkspaceScopeError.outsideWorkspace(candidate.path)
        }
        return candidate
    }

    public func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(rootURL.path)
    }
}
