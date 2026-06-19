import Foundation
public struct CodeQueryResult: Sendable {
    public let files: [RankedFile]; public let symbols: [RankedSymbol]
    public let tests: [RankedTest]; public let dependencyPaths: [String]; public let confidence: Double
    public init(files: [RankedFile] = [], symbols: [RankedSymbol] = [],
                tests: [RankedTest] = [], dependencyPaths: [String] = [], confidence: Double = 1.0) {
        self.files = files; self.symbols = symbols; self.tests = tests
        self.dependencyPaths = dependencyPaths; self.confidence = confidence }
}
public struct RankedFile: Sendable { public let path: String; public let score: Double
    public init(path: String, score: Double) { self.path = path; self.score = score } }
public struct RankedSymbol: Sendable { public let name: String; public let file: String; public let score: Double
    public init(name: String, file: String, score: Double) { self.name = name; self.file = file; self.score = score } }
public struct RankedTest: Sendable { public let path: String; public let subject: String; public let score: Double
    public init(path: String, subject: String, score: Double) { self.path = path; self.subject = subject; self.score = score } }
