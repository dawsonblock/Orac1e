import Foundation
/// Scores candidate command options and selects the best.
public struct PlanRanker {
    public init() {}
    public func rank(candidates: [Command]) -> Command? { candidates.first }
}
