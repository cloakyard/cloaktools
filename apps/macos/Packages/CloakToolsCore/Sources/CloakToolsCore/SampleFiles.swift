import Foundation

public enum SampleFileFormat: String, CaseIterable, Identifiable, Sendable {
    case json, csv, text, binary
    public var id: String { rawValue }
    public var title: String { switch self { case .json: "JSON"; case .csv: "CSV"; case .text: "Text"; case .binary: "Binary" } }
    public var fileExtension: String { switch self { case .text: "txt"; case .binary: "bin"; default: rawValue } }
    public var usesRecords: Bool { self == .json || self == .csv }
    public var detail: String {
        switch self {
        case .json: "Synthetic records with IDs, names, example emails and notes. Includes Unicode, quotes and line breaks."
        case .csv: "The same synthetic records as UTF-8 CSV, with a header, quoted fields and CRLF row endings."
        case .text: "Repeating ASCII text at the exact byte count. The last line may be partial."
        case .binary: "Zero-filled bytes at the exact size. Creates a .bin file for testing file-size limits."
        }
    }
}

public enum SampleByteUnit: Int, CaseIterable, Identifiable, Sendable {
    case bytes = 1, kibibytes = 1024, mebibytes = 1_048_576
    public var id: Int { rawValue }
    public var title: String { switch self { case .bytes: "Bytes"; case .kibibytes: "KiB"; case .mebibytes: "MiB" } }
}

public enum SampleFileError: LocalizedError, Equatable, Sendable {
    case invalidRecordCount, invalidSize
    public var errorDescription: String? {
        switch self {
        case .invalidRecordCount: "Enter a whole number from 1 to 10,000 records."
        case .invalidSize: "Enter a whole-number size from 1 byte to 32 MiB. 1 KiB = 1,024 bytes; 1 MiB = 1,048,576 bytes."
        }
    }
}

public enum SampleFileRequest: Equatable, Sendable {
    case json(records: Int), csv(records: Int), text(bytes: Int), binary(bytes: Int)
    public var format: SampleFileFormat {
        switch self { case .json: .json; case .csv: .csv; case .text: .text; case .binary: .binary }
    }
    public var recordCount: Int? { switch self { case let .json(count), let .csv(count): count; default: nil } }

    public init(format: SampleFileFormat, recordsText: String, sizeText: String, unit: SampleByteUnit) throws {
        if format.usesRecords {
            guard let count = Self.wholeNumber(recordsText), (1...SampleFiles.maximumRecords).contains(count) else { throw SampleFileError.invalidRecordCount }
            self = format == .json ? .json(records: count) : .csv(records: count)
        } else {
            guard let amount = Self.wholeNumber(sizeText), amount > 0, amount <= SampleFiles.maximumBytes / unit.rawValue else { throw SampleFileError.invalidSize }
            self = format == .text ? .text(bytes: amount * unit.rawValue) : .binary(bytes: amount * unit.rawValue)
        }
    }
    public func validate() throws {
        switch self {
        case let .json(count), let .csv(count):
            guard (1...SampleFiles.maximumRecords).contains(count) else { throw SampleFileError.invalidRecordCount }
        case let .text(count), let .binary(count):
            guard (1...SampleFiles.maximumBytes).contains(count) else { throw SampleFileError.invalidSize }
        }
    }
    private static func wholeNumber(_ input: String) -> Int? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 10, value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(value)
    }
}

public struct PreparedSampleFile: Sendable {
    public let request: SampleFileRequest
    public let data: Data
    public let preview: String
    public let previewDetail: String
    public var fileExtension: String { request.format.fileExtension }
    public var canCopyText: Bool { request.format != .binary }
    public var summary: String {
        if let count = request.recordCount { return "\(count.formatted()) \(count == 1 ? "record" : "records") · \(data.count.formatted()) bytes" }
        return "\(data.count.formatted()) bytes · Exact size"
    }
}

/// Reproducible synthetic content only. Generating a preview has no filesystem side effects.
public enum SampleFiles {
    public static let maximumRecords = 10_000
    public static let maximumBytes = 32 * 1_048_576
    public static let previewBytes = 8_192
    private struct Record: Encodable {
        let id: Int
        let name: String
        let email: String
        let active: Bool
        let note: String
        init(_ index: Int) {
            id = index; name = "Sample item \(index)"; email = "sample\(index)@example.com"; active = !index.isMultiple(of: 2)
            let notes = ["Ready to test", "Contains, a comma", "A \"quoted\" value", "First line\nSecond line", "Unicode · नमस्ते 🚀"]
            note = notes[(index - 1) % notes.count]
        }
    }

    public static func generate(_ request: SampleFileRequest) throws -> PreparedSampleFile {
        try request.validate(); try Task.checkCancellation()
        let data: Data
        switch request {
        case let .json(count):
            var records: [Record] = []; records.reserveCapacity(count)
            for index in 1...count {
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
                records.append(Record(index))
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var encoded = try encoder.encode(records); encoded.append(10); data = encoded
        case let .csv(count):
            var csv = "id,name,email,active,note\r\n"
            for index in 1...count {
                if index.isMultiple(of: 256) { try Task.checkCancellation() }
                let record = Record(index)
                let fields = [String(record.id), record.name, record.email, record.active ? "true" : "false", record.note]
                csv += fields.map(csvField).joined(separator: ",") + "\r\n"
            }
            data = Data(csv.utf8)
        case let .text(count):
            let block = Data(String(repeating: "Sample text from CloakTools.\n", count: 2048).utf8)
            var bytes = Data(); bytes.reserveCapacity(count)
            while bytes.count < count {
                try Task.checkCancellation()
                bytes.append(block.prefix(min(block.count, count - bytes.count)))
            }
            data = bytes
        case let .binary(count): data = Data(repeating: 0, count: count)
        }
        try Task.checkCancellation()
        if request.format == .binary {
            let count = min(data.count, 64)
            let preview = stride(from: 0, to: count, by: 16).map { offset in
                String(format: "%08X", offset) + "  " + Array(repeating: "00", count: min(16, count - offset)).joined(separator: " ")
            }.joined(separator: "\n")
            return .init(request: request, data: data, preview: preview, previewDetail: data.count > 64 ? "First 64 bytes · Hex preview" : "All \(count) bytes · Hex preview")
        }
        // Keep a UTF-8 boundary when a preview ends inside a multibyte scalar.
        var prefix = Data(data.prefix(previewBytes))
        while String(data: prefix, encoding: .utf8) == nil { prefix.removeLast() }
        return .init(request: request, data: data, preview: String(decoding: prefix, as: UTF8.self), previewDetail: prefix.count < data.count ? "First \(prefix.count.formatted()) bytes · Save and Copy include everything" : "Complete preview")
    }

    public static func save(_ prepared: PreparedSampleFile, in folder: URL, stem: String) throws -> URL {
        try Task.checkCancellation()
        return try SafeOutput.publish(prepared.data, in: folder, stem: stem, extension: prepared.fileExtension)
    }
    private static func csvField(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
