import Foundation

// MARK: - ParsedValue — a heterogeneous JSON scalar
//
// Payloads decoded off a device (or off a file) are dictionaries of mixed value types:
// a heart rate is an integer, a battery percentage a double, a log line a string, an
// RR series an array of integers. `ParsedValue` is the one box that holds any of them.
//
// WIRE SHAPE: it encodes and decodes as the BARE JSON scalar/array, never as a tagged
// union — `{"heart_rate": 60}` decodes straight into `["heart_rate": .int(60)]`, and
// `.int(7)` encodes back to `7`. That matters downstream: a payload dictionary is
// serialized with sorted keys to obtain deterministic JSON, and that JSON is the natural
// dedupe key of a stored event. A wrapper object (or an unstable encoding) would break it.

/// One value of a decoded payload: an integer, a double, a string, an array of integers,
/// a boolean, or JSON `null`.
public enum ParsedValue: Codable, Equatable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)
    case intArray([Int])
    case bool(Bool)
    case null

    /// Decodes the bare JSON value.
    ///
    /// The order of the attempts is load-bearing. `Bool` is tried BEFORE `Int` because
    /// `JSONDecoder` happily reads `true` as the integer `1`; asking for the integer first
    /// would silently turn every flag into a number.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
            return
        }
        if let whole = try? container.decode(Int.self) {
            self = .int(whole)
            return
        }
        if let real = try? container.decode(Double.self) {
            self = .double(real)
            return
        }
        if let text = try? container.decode(String.self) {
            self = .string(text)
            return
        }
        if let numbers = try? container.decode([Int].self) {
            self = .intArray(numbers)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported payload value")
    }

    /// Encodes the bare JSON value — no discriminator, no wrapper object.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let whole):      try container.encode(whole)
        case .double(let real):    try container.encode(real)
        case .string(let text):    try container.encode(text)
        case .intArray(let items): try container.encode(items)
        case .bool(let flag):      try container.encode(flag)
        case .null:                try container.encodeNil()
        }
    }
}

public extension ParsedValue {

    /// The integer, when this value is an integer.
    var intValue: Int? {
        if case .int(let whole) = self { return whole }
        return nil
    }

    /// The number as a `Double`. An `.int` is promoted, so a payload that arrived as `60`
    /// and one that arrived as `60.0` read the same on the math side.
    var doubleValue: Double? {
        switch self {
        case .double(let real): return real
        case .int(let whole):   return Double(whole)
        default:                return nil
        }
    }

    /// The text, when this value is a string.
    var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// The integer series, when this value is an array of integers.
    var intArrayValue: [Int]? {
        if case .intArray(let items) = self { return items }
        return nil
    }
}
