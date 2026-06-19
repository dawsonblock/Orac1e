import Foundation
public struct LanguageClassifier {
    public init() {}
    public func classify(_ file: ScannedFile) -> String {
        switch file.extension {
        case "swift": return "Swift"
        case "py": return "Python"
        case "ts": return "TypeScript"
        case "js": return "JavaScript"
        default: return "Unknown"
        }
    }
}
