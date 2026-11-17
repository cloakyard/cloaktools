import Foundation

public enum TemplateError: LocalizedError, Sendable {
    case invalidText, tooLarge, invalidMetadata, libraryFull
    public var errorDescription: String? {
        switch self {
        case .invalidText: "Choose a UTF-8 text or source file without null bytes. Binary templates are not supported yet."
        case .tooLarge: "A saved template can contain up to 1 MB. Choose a smaller file."
        case .invalidMetadata: "Use a name and filename with no slashes or control characters, and a short alphanumeric extension."
        case .libraryFull: "The library supports 64 templates and 16 MB of content. Remove a template before adding another."
        }
    }
}

/// Imported bytes are owned by the library. Subsequent changes to the source cannot alter them.
public struct CustomTemplate: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var suggestedName: String
    public let fileExtension: String
    public let content: Data
    public init(id: UUID = UUID(), title: String, suggestedName: String, fileExtension: String, content: Data) throws {
        self.id = id; self.title = title; self.suggestedName = suggestedName
        self.fileExtension = fileExtension; self.content = content
        try validate()
    }
    public func validate() throws {
        guard content.count <= 1_048_576 else { throw TemplateError.tooLarge }
        guard String(data: content, encoding: .utf8) != nil, !content.contains(0) else { throw TemplateError.invalidText }
        guard !title.isEmpty, title.count <= 80, title == title.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !fileExtension.isEmpty, fileExtension.utf8.count <= 16,
              fileExtension.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { throw TemplateError.invalidMetadata }
        do { try SafeOutput.validate(stem: suggestedName) } catch { throw TemplateError.invalidMetadata }
    }
    public static func importing(_ url: URL) throws -> Self {
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true else { throw TemplateError.invalidText }
        guard (properties.fileSize ?? Int.max) <= 1_048_576 else { throw TemplateError.tooLarge }
        let name = url.deletingPathExtension().lastPathComponent
        return try Self(title: name, suggestedName: name, fileExtension: url.pathExtension.isEmpty ? "txt" : url.pathExtension,
                        content: readBounded(url, limit: 1_048_576))
    }
}

public enum TemplateSource: Sendable, Identifiable {
    case builtIn(FileTemplate)
    case custom(CustomTemplate)
    public var id: String {
        switch self { case let .builtIn(t): "builtin:" + t.rawValue; case let .custom(t): "custom:" + t.id.uuidString }
    }
    public var title: String { switch self { case let .builtIn(t): t.title; case let .custom(t): t.title } }
    public var fileExtension: String { switch self { case let .builtIn(t): t.fileExtension; case let .custom(t): t.fileExtension } }
    public var suggestedName: String { switch self { case .builtIn: "Untitled"; case let .custom(t): t.suggestedName } }
    public var isPDF: Bool { if case .builtIn(.pdf) = self { true } else { false } }
    public func contents(using preferences: Preferences) throws -> Data {
        switch self {
        case let .builtIn(template): return try template.contents(using: preferences)
        case let .custom(template): try template.validate(); return template.content
        }
    }
    public func contentDescription(using preferences: Preferences) -> String {
        switch self {
        case let .custom(t): "Saved content · \(t.content.count.formatted()) bytes"
        case .builtIn(.pdf): "One blank A4 page"
        case .builtIn(.json): "Empty JSON object · {}"
        case let .builtIn(t): preferences.usesStarter(for: t) ? "Includes Hello World" : "Starts as a blank file"
        }
    }
}

public struct TemplateLibraryStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: Self { .init(url: PreferencesStore.standard.url.deletingLastPathComponent().appendingPathComponent("templates.json")) }
    public func load() throws -> [CustomTemplate] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 24_000_000 else { throw TemplateError.libraryFull }
        let templates = try JSONDecoder().decode([CustomTemplate].self, from: readBounded(url, limit: 24_000_000))
        try validate(templates); return templates
    }
    private func validate(_ templates: [CustomTemplate]) throws {
        guard templates.count <= 64, Set(templates.map(\.id)).count == templates.count,
              templates.reduce(0, { $0 + $1.content.count }) <= 16_777_216 else { throw TemplateError.libraryFull }
        for template in templates { try template.validate() }
    }
    public func save(_ templates: [CustomTemplate]) throws {
        try validate(templates)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(templates).write(to: url, options: .atomic)
    }
}

/// Bound reads even if the source grows after its initial size check.
private func readBounded(_ url: URL, limit: Int) throws -> Data {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var data = Data()
    while let chunk = try file.read(upToCount: min(65_536, limit + 1 - data.count)), !chunk.isEmpty {
        data.append(chunk)
        guard data.count <= limit else { throw TemplateError.tooLarge }
    }
    return data
}
