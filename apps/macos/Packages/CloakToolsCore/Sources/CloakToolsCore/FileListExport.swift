import Foundation
import Darwin

public enum FileListFormat: String, CaseIterable, Identifiable, Sendable {
    case csv, markdown
    public var id: String { rawValue }
    public var title: String { self == .csv ? "CSV" : "Markdown" }
    public var fileExtension: String { self == .csv ? "csv" : "md" }
}
public enum ListedItemKind: String, Sendable { case file = "File", folder = "Folder", symbolicLink = "Symbolic link" }
public struct FileListOptions: Equatable, Sendable {
    public var format: FileListFormat = .csv
    public var includeKind = true
    public var includeSize = true
    public var includeModified = false
    public var includePath = false
    public init() {}
}
public enum FileListError: LocalizedError, Equatable {
    case invalidSelection, duplicateItem, unavailable(String), unsupported(String), outputTooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: "Choose 1–200 local files or folders."
        case .duplicateItem: "These items are already included. Each selected path can appear once."
        case let .unavailable(name): "Could not read details for \(name). It may have moved or be unavailable. Your existing selection is kept."
        case let .unsupported(name): "\(name) is not an ordinary file, folder or symbolic link. Choose another item."
        case .outputTooLarge: "The exported list would exceed 2 MiB. Use fewer items or turn off full paths."
        }
    }
}
public struct ListedFile: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let kind: ListedItemKind
    public let size: Int64?
    public let modified: Date
    public var name: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
}
public struct PreparedFileList: Sendable {
    public let format: FileListFormat
    public let itemCount: Int
    public let text: String
    public let protectedCells: Int
    public var byteCount: Int { text.utf8.count }
    public var preview: String { String(text.prefix(65_536)) }
    public var previewIsTruncated: Bool { text.count > 65_536 }
}

/// Metadata only. lstat does not open file contents, enumerate folders or follow the final symbolic link.
public enum FileListExport {
    public static let maximumItems = 200
    public static let maximumOutputBytes = 2 * 1_048_576

    public static func capture(_ urls: [URL]) throws -> [ListedFile] {
        try Task.checkCancellation()
        guard (1...maximumItems).contains(urls.count), urls.allSatisfy({
            $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost") && $0.user == nil && $0.password == nil && $0.query == nil && $0.fragment == nil && $0.path.hasPrefix("/") && !$0.path.contains("\0") && $0.path.utf8.count < 4096
        }) else { throw FileListError.invalidSelection }
        let urls = urls.map(\.standardizedFileURL)
        guard Set(urls.map(\.path)).count == urls.count else { throw FileListError.duplicateItem }
        return try urls.map { url in
            try Task.checkCancellation()
            var info = stat()
            guard url.path.withCString({ lstat($0, &info) }) == 0 else { throw FileListError.unavailable(url.lastPathComponent) }
            let kind: ListedItemKind
            switch info.st_mode & mode_t(S_IFMT) {
            case mode_t(S_IFREG): kind = .file
            case mode_t(S_IFDIR): kind = .folder
            case mode_t(S_IFLNK): kind = .symbolicLink
            default: throw FileListError.unsupported(url.lastPathComponent)
            }
            return .init(id: UUID(), url: url, kind: kind, size: kind == .file ? max(0, info.st_size) : nil,
                         modified: Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)))
        }
    }
    public static func adding(_ urls: [URL], to existing: [ListedFile]) throws -> [ListedFile] {
        let paths = Set(existing.map { $0.url.standardizedFileURL.path })
        let fresh = urls.filter { !paths.contains($0.standardizedFileURL.path) }
        guard !fresh.isEmpty else { throw FileListError.duplicateItem }
        guard existing.count + fresh.count <= maximumItems else { throw FileListError.invalidSelection }
        return existing + (try capture(fresh))
    }
    public static func prepare(_ items: [ListedFile], options: FileListOptions) throws -> PreparedFileList {
        try Task.checkCancellation()
        guard (1...maximumItems).contains(items.count) else { throw FileListError.invalidSelection }
        guard Set(items.map { $0.url.standardizedFileURL.path }).count == items.count else { throw FileListError.duplicateItem }
        var columns = ["Name"]
        if options.includeKind { columns.append("Kind") }
        if options.includeSize { columns.append("Size (bytes)") }
        if options.includeModified { columns.append("Modified (UTC)") }
        if options.includePath { columns.append("Full path") }
        let dateFormatter = ISO8601DateFormatter(); dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        var protectedCells = 0
        func csvCell(_ value: String, protect: Bool) -> String {
            var value = value
            if protect, let first = value.unicodeScalars.first(where: {
                !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) && $0.value != 0xFEFF
            }), [61, 43, 45, 64].contains(first.value) { value = "'" + value; protectedCells += 1 }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func row(_ values: [String], protect: Bool) -> String {
            options.format == .csv ? values.map { csvCell($0, protect: protect) }.joined(separator: ",") + "\r\n"
                : "| " + values.map(markdownCell).joined(separator: " | ") + " |\n"
        }
        var output = row(columns, protect: false)
        if options.format == .markdown { output += "| " + Array(repeating: "---", count: columns.count).joined(separator: " | ") + " |\n" }
        for item in items {
            try Task.checkCancellation()
            var values = [item.name]
            if options.includeKind { values.append(item.kind.rawValue) }
            if options.includeSize { values.append(item.size.map(String.init) ?? "") }
            if options.includeModified { values.append(dateFormatter.string(from: item.modified)) }
            if options.includePath { values.append(item.url.path) }
            let next = row(values, protect: true)
            guard output.utf8.count + next.utf8.count <= maximumOutputBytes else { throw FileListError.outputTooLarge }
            output += next
        }
        try Task.checkCancellation()
        return .init(format: options.format, itemCount: items.count, text: output, protectedCells: protectedCells)
    }
    public static func save(_ list: PreparedFileList, in folder: URL, stem: String) throws -> URL {
        try Task.checkCancellation()
        return try SafeOutput.publish(Data(list.text.utf8), in: folder, stem: stem, extension: list.format.fileExtension)
    }
    private static func markdownCell(_ value: String) -> String {
        var output = ""
        for scalar in value.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars {
            if CharacterSet.newlines.contains(scalar) { output += " ↵ " }
            else if scalar == "\t" { output += " ⇥ " }
            else if CharacterSet.controlCharacters.contains(scalar) { output += "�" }
            else if (33...47).contains(scalar.value) || (58...64).contains(scalar.value) || (91...96).contains(scalar.value) || (123...126).contains(scalar.value) { output += "\\" + String(scalar) }
            else { output += String(scalar) }
        }
        return output
    }
}
