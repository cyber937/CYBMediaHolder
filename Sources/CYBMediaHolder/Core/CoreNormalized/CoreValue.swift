//
//  CoreValue.swift
//  CYBMediaHolder
//
//  Type-safe value container for core/* normalization keys.
//  Eliminates Any/Dictionary usage for compile-time type safety.
//

import Foundation

/// Type-safe value container for core/* metadata.
///
/// `CoreValue` provides strong typing for all metadata values,
/// eliminating the need for `Any` or untyped dictionaries.
///
/// ## Design Notes
/// - All cases are primitive or common types
/// - `Equatable` and `Hashable` for comparison and dictionary keys
/// - `Sendable` for safe concurrent access
///
/// ## Future Extensions
/// - `.rational(numerator: Int64, denominator: Int64)` for exact frame rates
/// - `.timecode(hours:minutes:seconds:frames:)` for structured timecode
/// - `.array([CoreValue])` for multi-valued properties
public enum CoreValue: Sendable, Equatable, Hashable {

    /// Integer value (for dimensions, counts, etc.).
    case int(Int)

    /// 64-bit integer value (for file sizes, frame counts).
    case int64(Int64)

    /// Double-precision floating point (for duration, frame rate).
    case double(Double)

    /// Boolean value (for flags like HDR, drop-frame).
    case bool(Bool)

    /// String value (for codec names, timecode strings, etc.).
    case string(String)
}

// MARK: - Value Extraction

extension CoreValue {

    /// Extracts the value as Int, or nil if not an int.
    public var intValue: Int? {
        if case .int(let value) = self {
            return value
        }
        return nil
    }

    /// Extracts the value as Int64, or nil if not an int64.
    /// Also converts from Int if possible.
    public var int64Value: Int64? {
        switch self {
        case .int64(let value):
            return value
        case .int(let value):
            return Int64(value)
        default:
            return nil
        }
    }

    /// Extracts the value as Double, or nil if not a double.
    /// Also converts from Int/Int64 if possible.
    public var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        case .int64(let value):
            return Double(value)
        default:
            return nil
        }
    }

    /// Extracts the value as Bool, or nil if not a bool.
    public var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }

    /// Extracts the value as String, or nil if not a string.
    public var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }
}

// MARK: - Convenience Initializers

extension CoreValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension CoreValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension CoreValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension CoreValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

// MARK: - CustomStringConvertible

extension CoreValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .int(let value):
            return "\(value)"
        case .int64(let value):
            return "\(value)"
        case .double(let value):
            return String(format: "%.6g", value)
        case .bool(let value):
            return value ? "true" : "false"
        case .string(let value):
            return "\"\(value)\""
        }
    }
}

// MARK: - Codable

extension CoreValue: Codable {

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    private enum ValueType: String, Codable {
        case int
        case int64
        case double
        case bool
        case string
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ValueType.self, forKey: .type)

        switch type {
        case .int:
            let value = try container.decode(Int.self, forKey: .value)
            self = .int(value)
        case .int64:
            let value = try container.decode(Int64.self, forKey: .value)
            self = .int64(value)
        case .double:
            let value = try container.decode(Double.self, forKey: .value)
            self = .double(value)
        case .bool:
            let value = try container.decode(Bool.self, forKey: .value)
            self = .bool(value)
        case .string:
            let value = try container.decode(String.self, forKey: .value)
            self = .string(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .int(let value):
            try container.encode(ValueType.int, forKey: .type)
            try container.encode(value, forKey: .value)
        case .int64(let value):
            try container.encode(ValueType.int64, forKey: .type)
            try container.encode(value, forKey: .value)
        case .double(let value):
            try container.encode(ValueType.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case .bool(let value):
            try container.encode(ValueType.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case .string(let value):
            try container.encode(ValueType.string, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}
