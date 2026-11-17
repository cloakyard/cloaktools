import Foundation

public enum ExampleCopyFormat: String, Sendable {
    case json, environment
    public var title: String { self == .json ? "JSON" : "Environment" }
    public var fileExtension: String { self == .json ? "json" : "env" }
    public var explanation: String {
        self == .json
            ? "Strings → REPLACE_ME · Numbers → 0 · Booleans → false · Null stays null"
            : "Every value → REPLACE_ME · Comments removed · Variable names kept"
    }
    public var reviewNote: String {
        self == .json ? "Keys and array structure are kept. Review them for private information before sharing."
            : "Variable names are kept. Review them for private information before sharing."
    }
}

public enum ExampleCopyError: LocalizedError, Equatable {
    case unsupportedFile, tooLarge, notUTF8, outputTooLarge, invalidEnvironment(line: Int), noAssignments
    public var errorDescription: String? {
        switch self {
        case .unsupportedFile: "Choose a JSON file or an environment file named .env, .env.* or *.env."
        case .tooLarge: "Choose a file up to 1 MiB. The original has not been changed."
        case .notUTF8: "Choose a UTF-8 text file without binary or control characters."
        case .outputTooLarge: "The example would exceed 8 MiB. Choose a smaller or less deeply nested JSON file."
        case let .invalidEnvironment(line): "Line \(line): use a single-line NAME=value assignment, optionally starting with export. Multiline values and shell scripts are not supported."
        case .noAssignments: "This file has no environment assignments. Choose a file containing NAME=value lines."
        }
    }
}

public struct PreparedExampleCopy: Sendable {
    public let sourceName: String
    public let format: ExampleCopyFormat
    public let sourceText: String
    public let text: String
    public let valueCount: Int
    public var data: Data { Data(text.utf8) }
    public var suggestedName: String {
        guard format == .json else { return "Environment example" }
        let stem = (sourceName as NSString).deletingPathExtension + " example"
        return (try? SafeOutput.validate(stem: stem)) != nil ? stem : "Configuration example"
    }
    public var sourcePreview: String { String(sourceText.prefix(65_536)) }
    public var examplePreview: String { String(text.prefix(65_536)) }
    public func previewIsTruncated(source: Bool) -> Bool { (source ? sourceText : text).count > 65_536 }
}

/// Local, explicit placeholder copies. This is not a secret detector or anonymization guarantee.
public enum ExampleCopy {
    public static let maximumInputBytes = 1_048_576
    public static func capture(_ url: URL) throws -> PreparedExampleCopy {
        let bytes: Data
        do { bytes = try LocalFileCapture.read(url, limit: maximumInputBytes) }
        catch LocalFileCapture.CaptureError.tooLarge { throw ExampleCopyError.tooLarge }
        return try prepare(bytes, sourceName: url.lastPathComponent)
    }
    public static func prepare(_ bytes: Data, sourceName: String) throws -> PreparedExampleCopy {
        try Task.checkCancellation()
        guard bytes.count <= maximumInputBytes else { throw ExampleCopyError.tooLarge }
        let lower = sourceName.lowercased()
        let format: ExampleCopyFormat
        if lower.hasSuffix(".json") { format = .json }
        else if lower == ".env" || lower.hasPrefix(".env.") || lower.hasSuffix(".env") { format = .environment }
        else { throw ExampleCopyError.unsupportedFile }
        guard var input = String(data: bytes, encoding: .utf8) else { throw ExampleCopyError.notUTF8 }
        if input.hasPrefix("\u{FEFF}") { input.removeFirst() }
        guard !input.unicodeScalars.contains(where: { ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127 }) else { throw ExampleCopyError.notUTF8 }
        let text: String, count: Int
        switch format {
        case .json:
            do { (text, count) = try DeveloperText.jsonExample(input) }
            catch DeveloperTextError.outputTooLarge { throw ExampleCopyError.outputTooLarge }
        case .environment: (text, count) = try environmentExample(input)
        }
        try Task.checkCancellation()
        return .init(sourceName: sourceName, format: format, sourceText: input, text: text, valueCount: count)
    }
    public static func save(_ prepared: PreparedExampleCopy, in folder: URL, stem: String) throws -> URL {
        try Task.checkCancellation()
        return try SafeOutput.publish(prepared.data, in: folder, stem: stem, extension: prepared.format.fileExtension)
    }
    private static func environmentExample(_ input: String) throws -> (String, Int) {
        let lines = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var output: [String] = []
        for (offset, line) in lines.enumerated() {
            try Task.checkCancellation()
            var assignment = line.trimmingCharacters(in: .whitespaces)
            if assignment.isEmpty || assignment.hasPrefix("#") { continue }
            var exported = false
            if assignment.hasPrefix("export ") || assignment.hasPrefix("export\t") {
                exported = true; assignment = String(assignment.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            }
            guard let equals = assignment.firstIndex(of: "=") else { throw ExampleCopyError.invalidEnvironment(line: offset + 1) }
            let key = String(assignment[..<equals]).trimmingCharacters(in: .whitespaces)
            let value = String(assignment[assignment.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            let keyBytes = Array(key.utf8)
            func letter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 }
            guard let first = keyBytes.first, letter(first), keyBytes.allSatisfy({ letter($0) || (48...57).contains($0) }), singleLineValue(value) else {
                throw ExampleCopyError.invalidEnvironment(line: offset + 1)
            }
            output.append((exported ? "export " : "") + key + "=REPLACE_ME")
        }
        guard !output.isEmpty else { throw ExampleCopyError.noAssignments }
        return (output.joined(separator: "\n") + "\n", output.count)
    }
    private static func singleLineValue(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard let quote = bytes.first, quote == 34 || quote == 39 else {
            let unquoted = value.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces)
            return !unquoted.hasSuffix("\\") && !unquoted.contains("\"") && !unquoted.contains("'")
        }
        var index = 1
        while index < bytes.count {
            if quote == 34, bytes[index] == 92 { index += 2; continue }
            if bytes[index] == quote {
                let tail = String(decoding: bytes.dropFirst(index + 1), as: UTF8.self).trimmingCharacters(in: .whitespaces)
                return tail.isEmpty || tail.hasPrefix("#")
            }
            index += 1
        }
        return false
    }
}
