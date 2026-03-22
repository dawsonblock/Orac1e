import Foundation

public protocol IntentSource: Sendable {
    func next() async -> Intent?
}

public struct DefaultIntentSource: IntentSource {
    public init() {}

    public func next() async -> Intent? {
        nil
    }
}
