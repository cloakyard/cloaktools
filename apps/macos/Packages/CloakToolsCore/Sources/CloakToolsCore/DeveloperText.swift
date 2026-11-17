import Foundation

public enum JSONTextAction: String, CaseIterable, Identifiable, Sendable {
    case format, minify, validate
    public var id: String { rawValue }
    public var title: String { switch self { case .format: "Format"; case .minify: "Minify"; case .validate: "Validate" } }
}

public enum Base64Alphabet: String, CaseIterable, Identifiable, Sendable {
    case standard, urlSafe
    public var id: String { rawValue }
    public var title: String { self == .standard ? "Standard" : "URL-safe" }
}

public enum DeveloperTextError: LocalizedError, Equatable {
    case inputTooLarge, outputTooLarge, invalidJSON(String, line: Int, column: Int), invalidBase64, nonTextBase64
    public var errorDescription: String? {
        switch self {
        case .inputTooLarge: "This tool accepts up to 1 MiB of UTF-8 input. Try a smaller selection."
        case .outputTooLarge: "Formatted output exceeds 8 MiB. Use Minify or Validate instead."
        case let .invalidJSON(reason, line, column): "Line \(line), column \(column): \(reason)"
        case .invalidBase64: "Invalid Base64 for the selected alphabet. Check the characters and padding. Spaces and line breaks are allowed."
        case .nonTextBase64: "The decoded data is not UTF-8 text. For an image, switch to Image mode. Other binary files are not supported."
        }
    }
}

/// Pure, bounded transformations. Input and results are never persisted or logged.
public enum DeveloperText {
    public static let maximumInputBytes = 1_048_576
    public static let maximumOutputBytes = 8_388_608
    public static let maximumJSONDepth = 128

    /// Returns nil for validation. Token spelling, number precision, key order and duplicates are preserved.
    public static func json(_ input: String, action: JSONTextAction) throws -> String? {
        try checkSize(input)
        var parser = JSONTextParser(bytes: Array(input.utf8), action: action)
        return try parser.parse()
    }

    /// Uses the same strict grammar, retaining keys/order/duplicates while replacing scalar values.
    static func jsonExample(_ input: String) throws -> (text: String, valueCount: Int) {
        try checkSize(input)
        var parser = JSONTextParser(bytes: Array(input.utf8), action: .format, replaceValues: true)
        let text = try parser.parse() ?? ""
        guard text.utf8.count < maximumOutputBytes else { throw DeveloperTextError.outputTooLarge }
        return (text + "\n", parser.valueCount)
    }

    public static func encodeBase64(_ input: String, alphabet: Base64Alphabet = .standard) throws -> String {
        try checkSize(input)
        return encodeBase64Bytes(Data(input.utf8), alphabet: alphabet)
    }

    static func encodeBase64Bytes(_ data: Data, alphabet: Base64Alphabet) -> String {
        let encoded = data.base64EncodedString()
        return alphabet == .standard ? encoded : encoded.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    public static func decodeBase64(_ input: String, alphabet: Base64Alphabet = .standard) throws -> String {
        try checkSize(input)
        let data = try decodeBase64Bytes(input, alphabet: alphabet)
        guard let decoded = String(data: data, encoding: .utf8) else { throw DeveloperTextError.nonTextBase64 }
        return decoded
    }

    static func decodeBase64Bytes(_ input: String, alphabet: Base64Alphabet) throws -> Data {
        let bytes = input.utf8.filter { ![9, 10, 13, 32].contains($0) }
        guard bytes.allSatisfy({ byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 61 ||
                (alphabet == .standard ? byte == 43 || byte == 47 : byte == 45 || byte == 95)
        }) else { throw DeveloperTextError.invalidBase64 }
        var normalized = String(decoding: bytes, as: UTF8.self)
        if alphabet == .urlSafe { normalized = normalized.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") }
        let hasPadding = normalized.contains("=")
        guard normalized.utf8.count % 4 != 1 else { throw DeveloperTextError.invalidBase64 }
        let padded = hasPadding ? normalized : normalized + String(repeating: "=", count: (4 - normalized.utf8.count % 4) % 4)
        guard let data = Data(base64Encoded: padded) else { throw DeveloperTextError.invalidBase64 }
        // Foundation may accept non-zero pad bits; enforce a canonical representation.
        let canonical = data.base64EncodedString()
        guard normalized == (hasPadding ? canonical : canonical.replacingOccurrences(of: "=", with: "")) else { throw DeveloperTextError.invalidBase64 }
        return data
    }

    private static func checkSize(_ input: String) throws {
        guard input.utf8.count <= maximumInputBytes else { throw DeveloperTextError.inputTooLarge }
        try Task.checkCancellation()
    }
}

/// A strict JSON grammar with token-preserving output, avoiding numeric reserialization.
private struct JSONTextParser {
    let bytes: [UInt8]
    let action: JSONTextAction
    var replaceValues = false
    var valueCount = 0
    var index = 0
    var output: [UInt8] = []
    var pretty: Bool { action == .format }

    mutating func parse() throws -> String? {
        skipWhitespace()
        try value(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw failure("Unexpected content after the JSON value.") }
        return action == .validate ? nil : String(decoding: output, as: UTF8.self)
    }

    mutating func value(depth: Int) throws {
        try Task.checkCancellation()
        skipWhitespace()
        guard index < bytes.count else { throw failure("Expected a JSON value.") }
        switch bytes[index] {
        case 123, 91: try container(depth: depth)
        case 34: try string(replace: replaceValues)
        case 116: try literal("true")
        case 102: try literal("false")
        case 110: try literal("null")
        case 45, 48...57: try number()
        default: throw failure("Expected an object, array, string, number, true, false or null.")
        }
    }

    mutating func container(depth: Int) throws {
        guard depth < DeveloperText.maximumJSONDepth else { throw failure("JSON nesting exceeds 128 levels.") }
        let opening = bytes[index], isObject = opening == 123
        let closing: UInt8 = isObject ? 125 : 93
        index += 1; try emit([opening]); skipWhitespace()
        if consume(closing) { try emit([closing]); return }
        while true {
            try newline(depth + 1)
            if isObject {
                guard index < bytes.count, bytes[index] == 34 else { throw failure("Expected a quoted object key.") }
                try string(); skipWhitespace()
                guard consume(58) else { throw failure("Expected ':' after the object key.") }
                try emit(pretty ? [58, 32] : [58])
            }
            try value(depth: depth + 1); skipWhitespace()
            if consume(closing) { try newline(depth); try emit([closing]); return }
            guard consume(44) else { throw failure("Expected ',' or '\(isObject ? "}" : "]")'.") }
            try emit([44]); skipWhitespace()
            if index < bytes.count, bytes[index] == closing { throw failure("Remove the trailing comma.") }
        }
    }

    mutating func string(replace: Bool = false) throws {
        let start = index
        index += 1
        while index < bytes.count {
            if index % 4096 == 0 { try Task.checkCancellation() }
            let byte = bytes[index]
            if byte == 34 {
                index += 1
                if replace { valueCount += 1; try emit("\"REPLACE_ME\"".utf8) }
                else { try emit(bytes[start..<index]) }
                return
            }
            guard byte >= 32 else { throw failure("Control characters in strings must be escaped.") }
            if byte == 92 {
                index += 1
                guard index < bytes.count else { throw failure("Incomplete string escape.") }
                if bytes[index] == 117 {
                    index += 1
                    let code = try hexQuad()
                    if (0xD800...0xDBFF).contains(code) {
                        guard index + 1 < bytes.count, bytes[index] == 92, bytes[index + 1] == 117 else { throw failure("A high Unicode surrogate needs a matching low surrogate.") }
                        index += 2
                        guard (0xDC00...0xDFFF).contains(try hexQuad()) else { throw failure("Invalid Unicode surrogate pair.") }
                    } else if (0xDC00...0xDFFF).contains(code) { throw failure("A low Unicode surrogate needs a matching high surrogate.") }
                } else {
                    guard [34, 92, 47, 98, 102, 110, 114, 116].contains(bytes[index]) else { throw failure("Invalid string escape.") }
                    index += 1
                }
            } else { index += 1 }
        }
        throw failure("Unterminated string.")
    }

    mutating func hexQuad() throws -> Int {
        var code = 0
        for _ in 0..<4 {
            guard index < bytes.count else { throw failure("Unicode escapes need four hexadecimal digits.") }
            let digit: Int
            switch bytes[index] {
            case 48...57: digit = Int(bytes[index] - 48)
            case 65...70: digit = Int(bytes[index] - 65) + 10
            case 97...102: digit = Int(bytes[index] - 97) + 10
            default: throw failure("Unicode escapes need four hexadecimal digits.")
            }
            code = code * 16 + digit; index += 1
        }
        return code
    }

    mutating func number() throws {
        let start = index
        _ = consume(45)
        guard index < bytes.count else { throw failure("Expected a digit after '-'.") }
        if !consume(48) {
            guard (49...57).contains(bytes[index]) else { throw failure("Expected a digit.") }
            while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        }
        if consume(46) { try digits(reason: "Expected a digit after the decimal point.") }
        if consume(101) || consume(69) {
            if !consume(43) { _ = consume(45) }
            try digits(reason: "Expected a digit in the exponent.")
        }
        if replaceValues { valueCount += 1; try emit("0".utf8) }
        else { try emit(bytes[start..<index]) }
    }

    mutating func digits(reason: String) throws {
        let start = index
        while index < bytes.count, (48...57).contains(bytes[index]) { index += 1 }
        guard index > start else { throw failure(reason) }
    }

    mutating func literal(_ text: String) throws {
        for byte in text.utf8 {
            guard consume(byte) else { throw failure("Expected '\(text)'.") }
        }
        if replaceValues { valueCount += 1; try emit((text == "null" ? "null" : "false").utf8) }
        else { try emit(text.utf8) }
    }

    mutating func skipWhitespace() {
        while index < bytes.count, [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
    mutating func newline(_ depth: Int) throws {
        if pretty { try emit([10] + Array(repeating: 32, count: depth * 2)) }
    }
    mutating func emit<C: Collection>(_ content: C) throws where C.Element == UInt8 {
        guard action != .validate else { return }
        guard output.count + content.count <= DeveloperText.maximumOutputBytes else { throw DeveloperTextError.outputTooLarge }
        output.append(contentsOf: content)
    }
    func failure(_ message: String) -> DeveloperTextError {
        let prefix = String(decoding: bytes.prefix(index), as: UTF8.self)
        var line = 1, column = 1, previousCR = false
        for scalar in prefix.unicodeScalars {
            if scalar == "\r" { line += 1; column = 1; previousCR = true }
            else if scalar == "\n" { if !previousCR { line += 1 }; column = 1; previousCR = false }
            else { column += 1; previousCR = false }
        }
        return .invalidJSON(message, line: line, column: column)
    }
}
