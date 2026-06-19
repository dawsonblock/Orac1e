import Foundation
public struct FileScanner {
    public init() {}
    public func scan(root: URL, extensions: [String] = ["swift","py","ts","js"]) throws -> [ScannedFile] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var files: [ScannedFile] = []
        for case let url as URL in enumerator {
            guard extensions.contains(url.pathExtension) else { continue }
            files.append(ScannedFile(url: url, extension: url.pathExtension))
        }
        return files
    }
}
public struct ScannedFile: Sendable {
    public let url: URL; public let `extension`: String
    public init(url: URL, extension ext: String) { self.url = url; self.extension = ext }
}
