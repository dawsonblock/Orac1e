import Foundation

public struct CodingWorkerEndpoints: Sendable {
    public let aider: URL
    public let hardened: URL

    public init(aider: URL, hardened: URL) {
        self.aider = aider
        self.hardened = hardened
    }
}

public struct CodingWorkerRoute: Sendable {
    public let kind: CodingWorkerKind
    public let baseURL: URL
}

public final class CodingWorkerRouter: Sendable {
    private let endpoints: CodingWorkerEndpoints

    public init(endpoints: CodingWorkerEndpoints) {
        self.endpoints = endpoints
    }

    public func route(for mode: CodingRunMode) -> CodingWorkerRoute {
        switch mode {
        case .interactive:
            return CodingWorkerRoute(kind: .aider, baseURL: endpoints.aider)
        case .autonomous:
            return CodingWorkerRoute(kind: .codeAgentRuntimeHardened, baseURL: endpoints.hardened)
        }
    }
}
