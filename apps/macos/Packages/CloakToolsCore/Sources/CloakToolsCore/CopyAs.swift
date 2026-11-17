import Foundation

public enum CopyFormat: String, CaseIterable, Identifiable, Sendable {
    case paths, names, fileURLs, shellArguments, markdown, json
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .paths: "Full paths"
        case .names: "File names"
        case .fileURLs: "File URLs"
        case .shellArguments: "Shell arguments"
        case .markdown: "Markdown links"
        case .json: "JSON path list"
        }
    }
    public var detail: String {
        switch self {
        case .paths: "One absolute path per line."
        case .names: "Names with extensions, one per line."
        case .fileURLs: "Encoded file URLs, one per line."
        case .shellArguments: "Single-quoted arguments for sh, bash or zsh. No command is run."
        case .markdown: "A Markdown list linking to local files."
        case .json: "A JSON array of absolute paths."
        }
    }
}

public enum CopyAsError: LocalizedError, Sendable {
    case invalidSelection, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: "Choose 1–200 local files or folders."
        case .tooLarge: "This selection is too large to copy. Choose fewer items."
        }
    }
}

/// Paths only: never reads file contents, traverses folders or resolves symbolic links.
public struct CopySelection: Sendable {
    public static let maximumItems = 200
    public let files: [URL]
    public init(files: [URL]) throws {
        guard (1...Self.maximumItems).contains(files.count), files.allSatisfy({
            $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost") && $0.user == nil && $0.password == nil && $0.query == nil && $0.fragment == nil && $0.path.hasPrefix("/") && !$0.path.contains("\0") && $0.path.utf8.count < 4096
        }) else { throw CopyAsError.invalidSelection }
        self.files = files
    }
    public func text(as format: CopyFormat) throws -> String {
        let output: String
        switch format {
        case .paths: output = files.map(\.path).joined(separator: "\n")
        case .names: output = files.map { $0.lastPathComponent.isEmpty ? $0.path : $0.lastPathComponent }.joined(separator: "\n")
        case .fileURLs: output = files.map(\.absoluteString).joined(separator: "\n")
        case .shellArguments: output = files.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        case .markdown:
            output = files.map { "- [\(Self.markdownLabel($0.lastPathComponent.isEmpty ? $0.path : $0.lastPathComponent))](<\($0.absoluteString)>)" }.joined(separator: "\n")
        case .json:
            output = String(decoding: try JSONSerialization.data(withJSONObject: files.map(\.path), options: [.prettyPrinted, .withoutEscapingSlashes]), as: UTF8.self)
        }
        guard output.utf8.count <= 1_048_576 else { throw CopyAsError.tooLarge }
        return output
    }
    private static func markdownLabel(_ text: String) -> String {
        var output = ""
        for scalar in text.unicodeScalars {
            if scalar == "\n" { output += "\\\\n" }
            else if scalar == "\r" { output += "\\\\r" }
            else if scalar == "\t" { output += "\\\\t" }
            else if "\\`*_{}[]<>#~!|".unicodeScalars.contains(scalar) { output += "\\" + String(scalar) }
            else if CharacterSet.controlCharacters.contains(scalar) { output += " " }
            else { output += String(scalar) }
        }
        return output
    }
}
