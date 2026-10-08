import Foundation

/// Parser for the "old-style" ASCII property list format used by `project.pbxproj`.
///
/// Foundation's support for this format differs between platforms, so
/// AppStoreReady ships its own small, strict parser.
public struct OpenStepPlistParser {
    public struct ParseError: Error, CustomStringConvertible, Equatable {
        public let message: String
        public let line: Int
        public var description: String { "line \(line): \(message)" }
    }

    private let bytes: [UInt8]
    private var index = 0

    public static func parse(_ data: Data) throws -> PlistValue {
        var parser = OpenStepPlistParser(bytes: [UInt8](data))
        let value = try parser.parseValue()
        try parser.skipWhitespaceAndComments()
        if parser.index < parser.bytes.count {
            throw parser.error("unexpected content after the root object")
        }
        return value
    }

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    private func error(_ message: String) -> ParseError {
        let line = bytes[..<min(index, bytes.count)].reduce(1) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        return ParseError(message: message, line: line)
    }

    private var current: UInt8? {
        index < bytes.count ? bytes[index] : nil
    }

    private mutating func skipWhitespaceAndComments() throws {
        while let byte = current {
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                index += 1
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "*") {
                index += 2
                var closed = false
                while index + 1 < bytes.count {
                    if bytes[index] == UInt8(ascii: "*") && bytes[index + 1] == UInt8(ascii: "/") {
                        index += 2
                        closed = true
                        break
                    }
                    index += 1
                }
                if !closed { throw error("unterminated comment") }
            } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                while let next = current, next != UInt8(ascii: "\n") {
                    index += 1
                }
            } else {
                return
            }
        }
    }

    private mutating func expect(_ character: Character) throws {
        try skipWhitespaceAndComments()
        guard let byte = current, byte == character.asciiValue else {
            if index >= bytes.count {
                throw error("unexpected end of file, expected '\(character)'")
            }
            throw error("expected '\(character)'")
        }
        index += 1
    }

    private mutating func parseValue() throws -> PlistValue {
        try skipWhitespaceAndComments()
        guard let byte = current else { throw error("unexpected end of file") }
        switch byte {
        case UInt8(ascii: "{"):
            return try parseDictionary()
        case UInt8(ascii: "("):
            return try parseArray()
        case UInt8(ascii: "<"):
            return try parseData()
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            return .string(try parseQuotedString())
        default:
            return .string(try parseUnquotedString())
        }
    }

    private mutating func parseDictionary() throws -> PlistValue {
        index += 1
        var result: [String: PlistValue] = [:]
        while true {
            try skipWhitespaceAndComments()
            guard let byte = current else { throw error("unterminated dictionary") }
            if byte == UInt8(ascii: "}") {
                index += 1
                return .dictionary(result)
            }
            let keyValue = try parseValue()
            guard case .string(let key) = keyValue else { throw error("dictionary keys must be strings") }
            try expect("=")
            let value = try parseValue()
            try expect(";")
            result[key] = value
        }
    }

    private mutating func parseArray() throws -> PlistValue {
        index += 1
        var result: [PlistValue] = []
        while true {
            try skipWhitespaceAndComments()
            guard let byte = current else { throw error("unterminated array") }
            if byte == UInt8(ascii: ")") {
                index += 1
                return .array(result)
            }
            result.append(try parseValue())
            try skipWhitespaceAndComments()
            if current == UInt8(ascii: ",") {
                index += 1
            } else if current != UInt8(ascii: ")") {
                throw error("expected ',' or ')' in array")
            }
        }
    }

    private mutating func parseData() throws -> PlistValue {
        index += 1
        var hex: [UInt8] = []
        while let byte = current, byte != UInt8(ascii: ">") {
            if !(byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\t")) {
                hex.append(byte)
            }
            index += 1
        }
        guard current == UInt8(ascii: ">") else { throw error("unterminated data") }
        index += 1
        guard hex.count % 2 == 0 else { throw error("odd number of hex digits in data") }
        var data = Data()
        var position = 0
        while position < hex.count {
            guard let value = UInt8(String(decoding: hex[position..<position + 2], as: UTF8.self), radix: 16) else {
                throw error("invalid hex digit in data")
            }
            data.append(value)
            position += 2
        }
        return .data(data)
    }

    private static func isUnquotedCharacter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return true
        case UInt8(ascii: "_"), UInt8(ascii: "$"), UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: ":"),
             UInt8(ascii: "."), UInt8(ascii: "-"), UInt8(ascii: "@"), UInt8(ascii: "~"):
            return true
        default:
            return byte >= 0x80
        }
    }

    private mutating func parseUnquotedString() throws -> String {
        let start = index
        while let byte = current, OpenStepPlistParser.isUnquotedCharacter(byte) {
            index += 1
        }
        guard index > start else {
            throw error("unexpected character '\(Character(UnicodeScalar(bytes[index])))'")
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func parseQuotedString() throws -> String {
        let quote = bytes[index]
        index += 1
        var output: [UInt8] = []
        while let byte = current {
            if byte == quote {
                index += 1
                return String(decoding: output, as: UTF8.self)
            }
            if byte == UInt8(ascii: "\\") {
                index += 1
                guard let escaped = current else { break }
                index += 1
                switch escaped {
                case UInt8(ascii: "n"): output.append(UInt8(ascii: "\n"))
                case UInt8(ascii: "t"): output.append(UInt8(ascii: "\t"))
                case UInt8(ascii: "r"): output.append(UInt8(ascii: "\r"))
                case UInt8(ascii: "U"):
                    let end = min(index + 4, bytes.count)
                    let digits = String(decoding: bytes[index..<end], as: UTF8.self)
                    index = end
                    if let scalarValue = UInt32(digits, radix: 16), let scalar = UnicodeScalar(scalarValue) {
                        output.append(contentsOf: Array(String(Character(scalar)).utf8))
                    }
                default:
                    output.append(escaped)
                }
                continue
            }
            output.append(byte)
            index += 1
        }
        throw error("unterminated string")
    }
}
