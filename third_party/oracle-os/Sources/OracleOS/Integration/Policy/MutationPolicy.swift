import Foundation

public struct CodingMutationPolicy: Sendable {
    public let allowedPrefixes: [String]
    public let blockedPrefixes: [String]
    public let maxChangedLines: Int

    public init(
        allowedPrefixes: [String],
        blockedPrefixes: [String] = [".github/", "infra/", "deploy/", "auth/"],
        maxChangedLines: Int = 300
    ) {
        self.allowedPrefixes = allowedPrefixes
        self.blockedPrefixes = blockedPrefixes
        self.maxChangedLines = maxChangedLines
    }

    public func validatePaths(_ paths: [String]) -> [String] {
        paths.filter { path in
            let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "./"))
            let allowed = allowedPrefixes.isEmpty || allowedPrefixes.contains {
                normalized.hasPrefix($0.trimmingCharacters(in: CharacterSet(charactersIn: "./")))
            }
            let blocked = blockedPrefixes.contains {
                normalized.hasPrefix($0.trimmingCharacters(in: CharacterSet(charactersIn: "./")))
            }
            return !allowed || blocked
        }
    }
}
