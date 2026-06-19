import Foundation
public struct SymbolExtractor {
    public init() {}
    public func extract(from file: ScannedFile) throws -> [ExtractedSymbol] {
        guard let source = try? String(contentsOf: file.url) else { return [] }
        // Lightweight regex-based extraction
        let pattern = #"(?:func|class|struct|enum|protocol|var|let)\s+(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
        return matches.compactMap { match -> ExtractedSymbol? in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return ExtractedSymbol(name: String(source[range]), file: file.url.path)
        }
    }
}
public struct ExtractedSymbol: Sendable {
    public let name: String; public let file: String
    public init(name: String, file: String) { self.name = name; self.file = file }
}
