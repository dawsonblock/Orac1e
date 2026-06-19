import Foundation
public struct TestMapBuilder {
    public init() {}
    public func buildMap(files: [ScannedFile]) -> [String: [String]] {
        var map: [String: [String]] = [:]
        for file in files where file.url.lastPathComponent.contains("Tests") {
            let subject = file.url.lastPathComponent.replacingOccurrences(of: "Tests.swift", with: ".swift")
            map[subject, default: []].append(file.url.path)
        }
        return map
    }
}
