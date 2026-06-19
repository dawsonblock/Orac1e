import Foundation

/// Composite reducer — applies all sub-reducers in order.
public struct CompositeStateReducer: EventReducer {
    private let reducers: [any EventReducer]

    public init(reducers: [any EventReducer]) {
        self.reducers = reducers
    }

    public func apply(events: [EventEnvelope], to state: inout WorldStateModel) {
        let baseSequence = state.snapshot.lastSequenceNumber
        let newEvents = events.filter { $0.sequenceNumber > baseSequence }
        guard !newEvents.isEmpty else { return }

        for reducer in reducers {
            reducer.apply(events: newEvents, to: &state)
        }

        let maxSequence = newEvents.map(\.sequenceNumber).max() ?? baseSequence
        state.replaceCommittedSnapshot(
            state.snapshot.copy(lastSequenceNumber: maxSequence)
        )
    }
}

enum ReducerSupport {
    static func dictionary(from envelope: EventEnvelope) -> [String: Any] {
        guard !envelope.payload.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: envelope.payload),
              let dictionary = object as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }

    static func string(_ key: String, in payload: [String: Any]) -> String? {
        payload[key] as? String
    }

    static func bool(_ key: String, in payload: [String: Any]) -> Bool? {
        if let value = payload[key] as? Bool {
            return value
        }
        if let value = payload[key] as? NSNumber {
            return value.boolValue
        }
        if let value = payload[key] as? String {
            switch value.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    static func int(_ key: String, in payload: [String: Any]) -> Int? {
        if let value = payload[key] as? Int {
            return value
        }
        if let value = payload[key] as? NSNumber {
            return value.intValue
        }
        if let value = payload[key] as? String {
            return Int(value)
        }
        return nil
    }

    static func stringArray(_ key: String, in payload: [String: Any]) -> [String]? {
        if let values = payload[key] as? [String] {
            return values
        }
        if let values = payload[key] as? [Any] {
            return values.compactMap { $0 as? String }
        }
        return nil
    }

    static func appendUnique(_ existing: [String], value: String?, limit: Int? = nil) -> [String] {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return existing
        }

        var result = existing
        if !result.contains(value) {
            result.append(value)
        }

        if let limit, result.count > limit {
            result = Array(result.suffix(limit))
        }
        return result
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}
