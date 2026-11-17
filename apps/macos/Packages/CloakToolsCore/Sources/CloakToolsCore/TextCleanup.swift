import Foundation

public enum EmptyLinePolicy: String, CaseIterable, Identifiable, Sendable {
    case keep, collapse, remove
    public var id: String { rawValue }
    public var title: String { switch self { case .keep: "Keep all"; case .collapse: "Keep one"; case .remove: "Remove" } }
}

public struct TextCleanupOptions: Equatable, Sendable {
    public var trimLineEnds = true
    public var trimLineStarts = false
    public var collapseSpaces = false
    public var emptyLines: EmptyLinePolicy = .keep
    public init() {}
}

public enum TextCleanupError: LocalizedError, Equatable {
    case inputTooLarge, binaryText
    public var errorDescription: String? {
        switch self {
        case .inputTooLarge: "Text exceeds 1 MiB. Use a smaller selection."
        case .binaryText: "Text contains binary control characters. Use plain text with ordinary tabs and line breaks."
        }
    }
}

public struct PreparedTextCleanup: Sendable {
    public let source: String
    public let text: String
    public let changedLines: Int
    public let removedLines: Int
    public let sourceLineCount: Int
    public let resultLineCount: Int
    public var byteCount: Int { text.utf8.count }
    public var preview: String { String(text.prefix(65_536)) }
    public var previewIsTruncated: Bool { text.count > 65_536 }
}

/// Only ASCII spaces/tabs and explicitly selected blank lines are changed.
/// CRLF, CR and LF sequences on retained lines, Unicode and a final newline stay intact.
public enum TextCleanup {
    public static let maximumInputBytes = 1_048_576

    public static func prepare(_ input: String, options: TextCleanupOptions) throws -> PreparedTextCleanup {
        try Task.checkCancellation()
        guard input.utf8.count <= maximumInputBytes else { throw TextCleanupError.inputTooLarge }
        let bytes = Array(input.utf8)
        guard !bytes.contains(where: { ($0 < 32 && $0 != 9 && $0 != 10 && $0 != 13) || $0 == 127 }) else { throw TextCleanupError.binaryText }
        var output = [UInt8](); output.reserveCapacity(bytes.count)
        var position = 0, changed = 0, removed = 0, sourceLines = 0, resultLines = 0, previousWasEmpty = false
        while position < bytes.count {
            try Task.checkCancellation()
            let start = position
            while position < bytes.count, bytes[position] != 10, bytes[position] != 13 {
                if position.isMultiple(of: 4096) { try Task.checkCancellation() }
                position += 1
            }
            let contentEnd = position
            if position < bytes.count {
                if bytes[position] == 13, position + 1 < bytes.count, bytes[position + 1] == 10 { position += 2 }
                else { position += 1 }
            }
            sourceLines += 1
            let original = bytes[start..<contentEnd]
            let empty = original.allSatisfy { $0 == 32 || $0 == 9 }
            if empty && (options.emptyLines == .remove || (options.emptyLines == .collapse && previousWasEmpty)) {
                changed += 1; removed += 1; continue
            }
            previousWasEmpty = empty
            var lower = start, upper = contentEnd
            if options.trimLineStarts { while lower < upper && (bytes[lower] == 32 || bytes[lower] == 9) { lower += 1 } }
            if options.trimLineEnds { while upper > lower && (bytes[upper - 1] == 32 || bytes[upper - 1] == 9) { upper -= 1 } }
            var line = [UInt8](); line.reserveCapacity(upper - lower)
            var wasSpace = false
            for index in lower..<upper {
                if index.isMultiple(of: 4096) { try Task.checkCancellation() }
                let byte = bytes[index], space = byte == 32 || byte == 9
                if options.collapseSpaces && space {
                    if !wasSpace { line.append(32) }
                } else { line.append(byte) }
                wasSpace = space
            }
            if !original.elementsEqual(line) { changed += 1 }
            output.append(contentsOf: line); output.append(contentsOf: bytes[contentEnd..<position])
            if !line.isEmpty || contentEnd < position { resultLines += 1 }
        }
        try Task.checkCancellation()
        return .init(source: input, text: String(decoding: output, as: UTF8.self), changedLines: changed, removedLines: removed,
                     sourceLineCount: sourceLines, resultLineCount: resultLines)
    }
    public static func save(_ result: PreparedTextCleanup, in folder: URL, stem: String) throws -> URL {
        try Task.checkCancellation()
        return try SafeOutput.publish(Data(result.text.utf8), in: folder, stem: stem, extension: "txt")
    }
}
