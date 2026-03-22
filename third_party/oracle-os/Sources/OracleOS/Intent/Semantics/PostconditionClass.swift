import Foundation

public enum PostconditionClass: String, Codable, Sendable {
    case unknown
    case elementAppeared
    case elementDisappeared
    case navigationOccurred
    case modalOpened
    case modalClosed
    case textChanged
    case focusChanged
    case actionFailed
}
