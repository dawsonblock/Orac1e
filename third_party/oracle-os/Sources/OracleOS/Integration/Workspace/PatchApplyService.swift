import Foundation

public actor CodingPatchApplyService {
    public init() {}

    public func apply(diffText: String, in repoURL: URL) throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("diff")
        try diffText.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try CodingShell.run(["git", "-C", repoURL.path, "apply", "--check", tempURL.path])
        try CodingShell.run(["git", "-C", repoURL.path, "apply", tempURL.path])
    }
}
