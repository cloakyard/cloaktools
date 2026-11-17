import Foundation

public enum MarkdownDigestError: LocalizedError, Equatable {
    case invalidSelection, fileTooLarge(String), notText(String), unsupportedFile(String), totalTooLarge, outputTooLarge, duplicateFile
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: "Choose 1–32 local text files. Folders are not included."
        case let .fileTooLarge(name): "\(name) exceeds 1 MiB. Choose a smaller text file."
        case let .notText(name): "\(name) is not UTF-8 text, or contains binary control characters. Choose a text file."
        case let .unsupportedFile(name): "\(name) is not a regular file. Folders and symbolic links are not supported."
        case .totalTooLarge: "The selected text exceeds 8 MiB. Remove a file or choose smaller files."
        case .outputTooLarge: "The Markdown digest would exceed 12 MiB. Choose fewer or smaller files."
        case .duplicateFile: "This file is already included. Each selected path can appear once."
        }
    }
}

public struct DigestFile: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let text: String
    var displayName: String? = nil
    public var name: String { displayName ?? url.lastPathComponent }
    public var byteCount: Int { text.utf8.count }
    public var preview: String { String(text.prefix(65_536)) }
    public var previewIsTruncated: Bool { text.count > 65_536 }
}

public struct PreparedMarkdownDigest: Sendable {
    public let title: String
    public let fileCount: Int
    public let text: String
    public var byteCount: Int { text.utf8.count }
    public var preview: String { String(text.prefix(65_536)) }
    public var previewIsTruncated: Bool { text.count > 65_536 }
}

/// Explicit files only. No traversal, rendering, execution, redaction or network access.
public enum MarkdownDigest {
    public static let maximumFiles = 32
    public static let maximumFileBytes = 1_048_576
    public static let maximumTotalBytes = 8 * 1_048_576
    public static let maximumOutputBytes = 12 * 1_048_576

    public static func adding(_ urls: [URL], to existing: [DigestFile]) throws -> [DigestFile] {
        let paths = Set(existing.map { $0.url.standardizedFileURL.path })
        let fresh = urls.filter { !paths.contains($0.standardizedFileURL.path) }
        guard !fresh.isEmpty else { throw MarkdownDigestError.duplicateFile }
        guard existing.count + fresh.count <= maximumFiles else { throw MarkdownDigestError.invalidSelection }
        let combined = existing + (try capture(fresh))
        guard combined.reduce(0, { $0 + $1.byteCount }) <= maximumTotalBytes else { throw MarkdownDigestError.totalTooLarge }
        return combined
    }

    public static func capture(_ urls: [URL], displayNames: [String]? = nil) throws -> [DigestFile] {
        if let displayNames {
            guard displayNames.count == urls.count, displayNames.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 && !$0.contains("/") && !$0.contains("\0") }) else { throw MarkdownDigestError.invalidSelection }
        }
        guard (1...maximumFiles).contains(urls.count), urls.allSatisfy({
            $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost") && $0.user == nil && $0.password == nil && $0.query == nil && $0.fragment == nil && $0.path.hasPrefix("/") && !$0.path.contains("\0") && $0.path.utf8.count < 4096
        }) else { throw MarkdownDigestError.invalidSelection }
        guard Set(urls.map { $0.standardizedFileURL.path }).count == urls.count else { throw MarkdownDigestError.duplicateFile }
        var result: [DigestFile] = [], total = 0
        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw MarkdownDigestError.unsupportedFile(url.lastPathComponent) }
            let data: Data
            do { data = try LocalFileCapture.read(url, limit: maximumFileBytes) }
            catch LocalFileCapture.CaptureError.tooLarge { throw MarkdownDigestError.fileTooLarge(url.lastPathComponent) }
            guard let text = String(data: data, encoding: .utf8), !text.unicodeScalars.contains(where: {
                ($0.value < 32 && ![9, 10, 13].contains($0.value)) || $0.value == 127
            }) else { throw MarkdownDigestError.notText(url.lastPathComponent) }
            total += data.count
            guard total <= maximumTotalBytes else { throw MarkdownDigestError.totalTooLarge }
            result.append(.init(id: UUID(), url: url.standardizedFileURL, text: text, displayName: displayNames?[index]))
        }
        try Task.checkCancellation()
        return result
    }

    public static func prepare(_ files: [DigestFile], title: String) throws -> PreparedMarkdownDigest {
        try SafeOutput.validate(stem: title)
        guard (1...maximumFiles).contains(files.count) else { throw MarkdownDigestError.invalidSelection }
        guard Set(files.map { $0.url.standardizedFileURL.path }).count == files.count else { throw MarkdownDigestError.duplicateFile }
        guard files.reduce(0, { $0 + $1.byteCount }) <= maximumTotalBytes else { throw MarkdownDigestError.totalTooLarge }
        var output = "# \(heading(title))\n\n\(files.count) \(files.count == 1 ? "file" : "files") · Collected with CloakTools\n\n"
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            guard file.byteCount <= maximumFileBytes else { throw MarkdownDigestError.fileTooLarge(file.name) }
            let fence = try codeFence(for: file.text)
            let section = "## \(index + 1). \(heading(file.name))\n\n\(fence)\(language((file.name as NSString).pathExtension))\n" + file.text + (file.text.hasSuffix("\n") ? "" : "\n") + fence + "\n\n"
            guard output.utf8.count + section.utf8.count <= maximumOutputBytes else { throw MarkdownDigestError.outputTooLarge }
            output += section
        }
        try Task.checkCancellation()
        return .init(title: title, fileCount: files.count, text: output)
    }

    public static func save(_ digest: PreparedMarkdownDigest, in folder: URL) throws -> URL {
        try Task.checkCancellation()
        return try SafeOutput.publish(Data(digest.text.utf8), in: folder, stem: digest.title, extension: "md")
    }

    private static func codeFence(for text: String) throws -> String {
        var ticks = 0, tildes = 0, longestTicks = 0, longestTildes = 0
        for (index, byte) in text.utf8.enumerated() {
            if index.isMultiple(of: 4096) { try Task.checkCancellation() }
            ticks = byte == 96 ? ticks + 1 : 0; tildes = byte == 126 ? tildes + 1 : 0
            longestTicks = max(longestTicks, ticks); longestTildes = max(longestTildes, tildes)
        }
        return longestTicks <= longestTildes ? String(repeating: "`", count: max(3, longestTicks + 1)) : String(repeating: "~", count: max(3, longestTildes + 1))
    }

    private static func heading(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) { result += " " }
            else if (33...47).contains(scalar.value) || (58...64).contains(scalar.value) || (91...96).contains(scalar.value) || (123...126).contains(scalar.value) { result += "\\" + String(scalar) }
            else { result += String(scalar) }
        }
        return result
    }
    private static func language(_ ext: String) -> String {
        ["txt": "text", "md": "markdown", "json": "json", "csv": "csv", "py": "python", "js": "javascript", "ts": "typescript", "swift": "swift", "rs": "rust", "c": "c", "h": "c", "cpp": "cpp", "hpp": "cpp", "cs": "csharp", "java": "java", "go": "go", "rb": "ruby", "php": "php", "kt": "kotlin", "sh": "bash", "yaml": "yaml", "yml": "yaml", "toml": "toml", "html": "html", "css": "css", "sql": "sql", "xml": "xml"][ext.lowercased()] ?? "text"
    }
}
