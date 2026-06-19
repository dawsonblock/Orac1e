import Foundation

public enum RouterError: LocalizedError {
    case invalidRoute(expected: CommandType, actual: CommandType)

    public var errorDescription: String? {
        switch self {
        case .invalidRoute(let expected, let actual):
            return "Invalid route: expected \(expected.rawValue), got \(actual.rawValue)"
        }
    }
}
