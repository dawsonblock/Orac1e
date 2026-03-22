import Foundation

public struct TraceCluster: Sendable {
    public let fingerprint: String
    public let traces: [[TraceEvent]]
    public let commonActionSequence: [String]
    public let similarity: Double

    public init(
        fingerprint: String,
        traces: [[TraceEvent]],
        commonActionSequence: [String],
        similarity: Double
    ) {
        self.fingerprint = fingerprint
        self.traces = traces
        self.commonActionSequence = commonActionSequence
        self.similarity = similarity
    }
}

public struct TraceClusterer: Sendable {
    public let minimumClusterSize: Int
    public let minimumSimilarity: Double

    public init(
        minimumClusterSize: Int = 2,
        minimumSimilarity: Double = 0.6
    ) {
        self.minimumClusterSize = minimumClusterSize
        self.minimumSimilarity = minimumSimilarity
    }

    public func cluster(traces: [[TraceEvent]]) -> [TraceCluster] {
        let fingerprinted = traces.map { trace -> (fingerprint: String, trace: [TraceEvent]) in
            let fingerprint = actionFingerprint(for: trace)
            return (fingerprint, trace)
        }

        var groups: [String: [[TraceEvent]]] = [:]
        for item in fingerprinted {
            groups[item.fingerprint, default: []].append(item.trace)
        }

        return groups.compactMap { fingerprint, traces -> TraceCluster? in
            guard traces.count >= minimumClusterSize else { return nil }

            let commonActions = commonActionSequence(for: traces)
            let similarity = averageSimilarity(traces: traces)
            guard similarity >= minimumSimilarity else { return nil }

            return TraceCluster(
                fingerprint: fingerprint,
                traces: traces,
                commonActionSequence: commonActions,
                similarity: similarity
            )
        }
        .sorted { $0.traces.count > $1.traces.count }
    }

    private func actionFingerprint(for trace: [TraceEvent]) -> String {
        trace.map(\.actionName).joined(separator: "→")
    }

    private func commonActionSequence(for traces: [[TraceEvent]]) -> [String] {
        guard let first = traces.first else { return [] }
        let baseline = first.map(\.actionName)
        return baseline.filter { action in
            traces.allSatisfy { trace in
                trace.contains(where: { $0.actionName == action })
            }
        }
    }

    private func averageSimilarity(traces: [[TraceEvent]]) -> Double {
        guard traces.count >= 2 else { return 1.0 }
        var totalSimilarity = 0.0
        var comparisons = 0
        for i in 0..<traces.count {
            for j in (i + 1)..<traces.count {
                totalSimilarity += traceSimilarity(traces[i], traces[j])
                comparisons += 1
            }
        }
        guard comparisons > 0 else { return 0 }
        return totalSimilarity / Double(comparisons)
    }

    private func traceSimilarity(_ a: [TraceEvent], _ b: [TraceEvent]) -> Double {
        let aActions = Set(a.map(\.actionName))
        let bActions = Set(b.map(\.actionName))
        let intersection = aActions.intersection(bActions).count
        let union = aActions.union(bActions).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }
}
