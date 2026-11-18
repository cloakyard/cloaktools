import Foundation
import Darwin

public enum FileSetError: LocalizedError, Sendable {
    case invalidMetadata, invalidPath(String), conflict(String), missingTemplate(String), extensionMismatch(String), full
    public var errorDescription: String? {
        switch self {
        case .invalidMetadata: "Use a set name up to 80 characters and a valid folder name."
        case let .invalidPath(path): "“\(path)” is not a safe relative path. Use up to 8 levels, without hidden names, empty segments, colons, backslashes or control characters."
        case let .conflict(path): "“\(path)” conflicts with another item. Each path must be unique, including letter case; files cannot contain other items."
        case let .missingTemplate(path): "The saved template for “\(path)” is unavailable. Choose another file type before continuing."
        case let .extensionMismatch(path): "The extension of “\(path)” must match its file type. Change the type or correct the path."
        case .full: "Use 1–32 items per set, up to 16 MB of generated content. You can save up to 32 sets."
        }
    }
}

public struct FileSetEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var path: String
    /// nil denotes a directory. Files refer to a built-in or imported template.
    public var templateID: String?
    public init(id: UUID = UUID(), path: String, templateID: String? = nil) {
        self.id = id; self.path = path; self.templateID = templateID
    }
}

public struct FileSetDefinition: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var folderName: String
    public var entries: [FileSetEntry]
    public var starterPolicy: FolderStarterPolicy
    public init(id: UUID = UUID(), title: String = "My file set", folderName: String = "Untitled", entries: [FileSetEntry], starterPolicy: FolderStarterPolicy = .followSettings) {
        self.id = id; self.title = title; self.folderName = folderName; self.entries = entries; self.starterPolicy = starterPolicy
    }
    public static var notes: Self {
        .init(title: "Notes", folderName: "Notes", entries: [
            .init(path: "README.md", templateID: "builtin:markdown"),
            .init(path: "notes/Notes.md", templateID: "builtin:markdown"), .init(path: "assets")])
    }
    public static func sourceFiles(_ language: FileTemplate) -> Self {
        .init(title: "\(language.title) files", folderName: "\(language.title) files", entries: [
            .init(path: "README.md", templateID: "builtin:markdown"),
            .init(path: "src/main.\(language.fileExtension)", templateID: TemplateSource.builtIn(language).id), .init(path: "tests")])
    }
    public func preferences(from global: Preferences) -> Preferences {
        var result = global
        if starterPolicy == .blank { result.includeHelloWorld = false }
        return result
    }
    public func validate() throws {
        guard !title.isEmpty, title.count <= 80, title == title.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw FileSetError.invalidMetadata }
        try SafeOutput.validate(stem: folderName)
        guard (1...32).contains(entries.count) else { throw FileSetError.full }
        guard Set(entries.map(\.id)).count == entries.count else { throw FileSetError.invalidMetadata }
        var explicit = Set<String>()
        var paths: [String: (spelling: String, isFile: Bool)] = [:]
        for entry in entries {
            let components = entry.path.components(separatedBy: "/")
            guard (1...8).contains(components.count), entry.path.utf8.count <= 960, !entry.path.contains("\\") else { throw FileSetError.invalidPath(entry.path) }
            for component in components {
                do { try SafeOutput.validate(stem: component) } catch { throw FileSetError.invalidPath(entry.path) }
            }
            if let id = entry.templateID {
                guard FileTemplate.allCases.contains(where: { TemplateSource.builtIn($0).id == id })
                        || (id.hasPrefix("custom:") && UUID(uuidString: String(id.dropFirst(7))) != nil) else { throw FileSetError.missingTemplate(entry.path) }
            }
            for count in 1...components.count {
                let spelling = components.prefix(count).joined(separator: "/")
                let key = spelling.precomposedStringWithCanonicalMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
                let leaf = count == components.count, isFile = leaf && entry.templateID != nil
                if leaf, !explicit.insert(key).inserted { throw FileSetError.conflict(entry.path) }
                if let prior = paths[key] {
                    guard prior.spelling == spelling, !prior.isFile, !isFile else { throw FileSetError.conflict(entry.path) }
                } else { paths[key] = (spelling, isFile) }
            }
        }
    }
    public func validate(sources: [TemplateSource]) throws {
        try validate()
        for entry in entries {
            guard let id = entry.templateID else { continue }
            guard let source = sources.first(where: { $0.id == id }) else { throw FileSetError.missingTemplate(entry.path) }
            guard (entry.path as NSString).pathExtension.lowercased() == source.fileExtension.lowercased() else { throw FileSetError.extensionMismatch(entry.path) }
            if case let .custom(template) = source { try template.validate() }
        }
    }
}

/// Owns the exact bytes to publish. Nothing is written while preparing this value.
public struct PreparedFileSet: Sendable {
    public struct Item: Sendable {
        public let path: String
        public let data: Data?
    }
    public let folderName: String
    public let items: [Item]
    public var byteCount: Int { items.reduce(0) { $0 + ($1.data?.count ?? 0) } }
    public init(definition: FileSetDefinition, sources: [TemplateSource], preferences: Preferences) throws {
        try definition.validate(sources: sources)
        let prefs = definition.preferences(from: preferences)
        var result: [Item] = [], total = 0
        for entry in definition.entries {
            try Task.checkCancellation()
            let data: Data?
            if let id = entry.templateID, let source = sources.first(where: { $0.id == id }) { data = try source.contents(using: prefs) }
            else { data = nil }
            total += data?.count ?? 0
            guard total <= 16_777_216 else { throw FileSetError.full }
            result.append(Item(path: entry.path, data: data))
        }
        folderName = definition.folderName; items = result
    }
    /// Build inside a private sibling directory, then publish the whole folder with
    /// exclusive rename. Existing directories are never merged or modified.
    public func publish(in destination: URL, progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws -> URL {
        try SafeOutput.publishFolder(named: folderName, in: destination) { stage in
            for (index, item) in items.enumerated() {
                try Task.checkCancellation()
                let target = stage.appendingPathComponent(item.path)
                try FileManager.default.createDirectory(at: item.data == nil ? target : target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                if let data = item.data {
                    try data.write(to: target, options: .withoutOverwriting)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                }
                progress(index + 1, items.count)
            }
        }
    }
}

public struct FileSetStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: Self { .init(url: PreferencesStore.standard.url.deletingLastPathComponent().appendingPathComponent("file-sets.json")) }
    public func load() throws -> [FileSetDefinition] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let sets = try JSONDecoder().decode([FileSetDefinition].self, from: LocalFileCapture.read(url, limit: 2_097_152))
        try validate(sets); return sets
    }
    public func save(_ sets: [FileSetDefinition]) throws {
        try validate(sets)
        let data = try JSONEncoder().encode(sets)
        guard data.count <= 2_097_152 else { throw FileSetError.full }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    private func validate(_ sets: [FileSetDefinition]) throws {
        guard sets.count <= 32 else { throw FileSetError.full }
        guard Set(sets.map(\.id)).count == sets.count else { throw FileSetError.invalidMetadata }
        for set in sets { try set.validate() }
    }
}
