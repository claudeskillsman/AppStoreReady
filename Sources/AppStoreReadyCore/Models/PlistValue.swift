import Foundation

/// A property list value, independent of Foundation's `Any` bridging.
public indirect enum PlistValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case real(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case array([PlistValue])
    case dictionary([String: PlistValue])

    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        case .bool(let value): return value ? "YES" : "NO"
        default: return nil
        }
    }

    public var arrayValue: [PlistValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var dictionaryValue: [String: PlistValue]? {
        if case .dictionary(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .integer(let value): return value != 0
        case .string(let value):
            switch value.uppercased() {
            case "YES", "TRUE", "1": return true
            case "NO", "FALSE", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    public subscript(key: String) -> PlistValue? {
        dictionaryValue?[key]
    }

    /// Converts the output of `PropertyListSerialization`.
    public init?(foundation value: Any) {
        switch value {
        case let string as String:
            self = .string(string)
        case let date as Date:
            self = .date(date)
        case let data as Data:
            self = .data(data)
        case let array as [Any]:
            self = .array(array.compactMap { PlistValue(foundation: $0) })
        case let dictionary as [String: Any]:
            var result: [String: PlistValue] = [:]
            for (key, element) in dictionary {
                if let converted = PlistValue(foundation: element) {
                    result[key] = converted
                }
            }
            self = .dictionary(result)
        default:
            if let number = PlistValue.number(from: value) {
                self = number
            } else {
                return nil
            }
        }
    }

    private static func number(from value: Any) -> PlistValue? {
        #if canImport(Darwin)
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            if CFNumberIsFloatType(number as CFNumber) {
                return .real(number.doubleValue)
            }
            return .integer(number.intValue)
        }
        return nil
        #else
        switch value {
        case let bool as Bool where type(of: value) == Bool.self:
            return .bool(bool)
        case let int as Int:
            return .integer(int)
        case let double as Double:
            return .real(double)
        case let number as NSNumber:
            return .integer(number.intValue)
        default:
            return nil
        }
        #endif
    }
}
