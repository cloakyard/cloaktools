import Foundation

public enum FolderStarterPolicy: String, CaseIterable, Codable, Sendable, Identifiable {
    case followSettings, blank
    public var id: String { rawValue }
    public var title: String { self == .followSettings ? "Follow global & language settings" : "Always blank" }
}

public enum FolderPresetError: LocalizedError, Sendable {
    case invalid, full, missingTemplate
    public var errorDescription: String? {
        switch self {
        case .invalid: "Use a preset title up to 80 characters, a local folder, a file type and a valid filename without an extension."
        case .full: "You can save up to 32 folder presets. Remove one before adding another."
        case .missingTemplate: "This preset’s saved template is unavailable. Edit the preset and choose another template."
        }
    }
}

/// A starting point explicitly chosen by the user, never an automatic folder rule.
public struct FolderPreset: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var folder: URL
    public var templateID: String
    public var name: String
    public var starterPolicy: FolderStarterPolicy
    public init(id: UUID = UUID(), title: String, folder: URL, templateID: String = "builtin:text", name: String = "Untitled", starterPolicy: FolderStarterPolicy = .followSettings) {
        self.id = id; self.title = title; self.folder = folder; self.templateID = templateID; self.name = name; self.starterPolicy = starterPolicy
    }
    public func validate() throws {
        let validID = FileTemplate.allCases.contains { TemplateSource.builtIn($0).id == templateID }
            || (templateID.hasPrefix("custom:") && UUID(uuidString: String(templateID.dropFirst(7))) != nil)
        guard !title.isEmpty, title.count <= 80, title == title.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              folder.isFileURL, [nil, "", "localhost"].contains(folder.host), folder.path.hasPrefix("/"),
              folder.path.utf8.count < 4096, !folder.path.contains("\0"), folder.query == nil, folder.fragment == nil,
              validID else { throw FolderPresetError.invalid }
        try SafeOutput.validate(stem: name)
    }
    public func preferences(from global: Preferences) -> Preferences {
        var snapshot = global
        if starterPolicy == .blank { snapshot.includeHelloWorld = false }
        return snapshot
    }
    public func request(preferences global: Preferences, templates: [CustomTemplate]) throws -> CreationRequest {
        try validate()
        let sources = FileTemplate.allCases.map(TemplateSource.builtIn) + templates.map(TemplateSource.custom)
        guard let source = sources.first(where: { $0.id == templateID }) else { throw FolderPresetError.missingTemplate }
        // Validate imported content at ingress, then own it as part of the value snapshot.
        if case let .custom(template) = source { try template.validate() }
        return CreationRequest(folder: folder, source: source, preferences: preferences(from: global), name: name)
    }
}

public struct FolderPresetStore: Sendable {
    public static let maximumPresets = 32
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: Self { .init(url: PreferencesStore.standard.url.deletingLastPathComponent().appendingPathComponent("folder-presets.json")) }
    public func load() throws -> [FolderPreset] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let bytes = try LocalFileCapture.read(url, limit: 262_144)
        let presets = try JSONDecoder().decode([FolderPreset].self, from: bytes)
        try validate(presets); return presets
    }
    public func save(_ presets: [FolderPreset]) throws {
        try validate(presets)
        let bytes = try JSONEncoder().encode(presets)
        guard bytes.count <= 262_144 else { throw FolderPresetError.full }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
    private func validate(_ presets: [FolderPreset]) throws {
        guard presets.count <= Self.maximumPresets else { throw FolderPresetError.full }
        guard Set(presets.map(\.id)).count == presets.count else { throw FolderPresetError.invalid }
        for preset in presets { try preset.validate() }
    }
}
