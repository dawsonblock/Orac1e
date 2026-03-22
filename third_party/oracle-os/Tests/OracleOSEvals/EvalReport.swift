import Foundation

struct EvalReport {
    let taskName: String
    let family: EvalTaskFamily
    let runs: Int
    let metrics: EvalMetrics

    var summary: String {
        metrics.summary(taskName: "\(family.rawValue)/\(taskName)")
    }
}
