import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public static func dictionary<T: Encodable>(from value: T, encoder: JSONEncoder = JSONEncoder()) throws -> [String: JSONValue] {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = JSONValue.from(any: object)?.objectValue else {
            throw NSError(
                domain: "JSONValue",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected top-level JSON object"]
            )
        }
        return dictionary
    }

    public static func decode<T: Decodable>(_ type: T.Type, from dictionary: [String: JSONValue], decoder: JSONDecoder = JSONDecoder()) throws -> T {
        let object = JSONValue.object(dictionary).foundationValue
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        return try decoder.decode(T.self, from: data)
    }

    public static func from(any value: Any) -> JSONValue? {
        switch value {
        case is NSNull:
            return .null
        case let value as String:
            return .string(value)
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .number(Double(value))
        case let value as Int8:
            return .number(Double(value))
        case let value as Int16:
            return .number(Double(value))
        case let value as Int32:
            return .number(Double(value))
        case let value as Int64:
            return .number(Double(value))
        case let value as UInt:
            return .number(Double(value))
        case let value as UInt8:
            return .number(Double(value))
        case let value as UInt16:
            return .number(Double(value))
        case let value as UInt32:
            return .number(Double(value))
        case let value as UInt64:
            return .number(Double(value))
        case let value as Double:
            return .number(value)
        case let value as Float:
            return .number(Double(value))
        case let value as NSNumber:
            return .number(value.doubleValue)
        case let value as [String: Any]:
            var object: [String: JSONValue] = [:]
            for (key, nested) in value {
                guard let converted = JSONValue.from(any: nested) else { return nil }
                object[key] = converted
            }
            return .object(object)
        case let value as [Any]:
            let converted = value.compactMap(JSONValue.from(any:))
            guard converted.count == value.count else { return nil }
            return .array(converted)
        default:
            return nil
        }
    }

    public var foundationValue: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues { $0.foundationValue }
        case .array(let value):
            return value.map { $0.foundationValue }
        case .null:
            return NSNull()
        }
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }
}
