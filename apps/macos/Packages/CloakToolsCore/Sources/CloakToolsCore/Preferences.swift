import Foundation

public enum SettingsCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case general, finder, newFiles, conversions, developer, openWith, privacy, about
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .general: "General"
        case .finder: "Finder Integration"
        case .newFiles: "New Files"
        case .conversions: "Conversions"
        case .developer: "Developer Tools"
        case .openWith: "Open With"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var developerToolsEnabled = false
    public var hasChosenTools = false
    public var includeHelloWorld = false
    public var languageChoices: [String: Bool] = Dictionary(uniqueKeysWithValues: FileTemplate.allCases.filter(\.isProgramming).map { ($0.rawValue, true) })
    public var lastCategory: SettingsCategory = .general
    public var optimizeCopiedImages = false
    public var optimizationFolder: URL?
    public var showMenuBarTools = true
    public var revealCreatedFile = true
    public var revealConvertedFile = true
    public var openAfterCreation = false
    public var imageConversion = ImageConversionOptions()
    public var favoriteTemplateIDs: Set<String> = []
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case optimizeCopiedImages, optimizationFolder, showMenuBarTools, developerToolsEnabled, hasChosenTools, includeHelloWorld, languageChoices, lastCategory, revealCreatedFile, revealConvertedFile, openAfterCreation, favoriteTemplateIDs, imageConversion
    }
    public init(from decoder: any Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        optimizeCopiedImages = try values.decodeIfPresent(Bool.self, forKey: .optimizeCopiedImages) ?? false
        optimizationFolder = try values.decodeIfPresent(URL.self, forKey: .optimizationFolder)
        showMenuBarTools = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarTools) ?? true
        // Existing installations keep the catalog they already had; only fresh installs opt in.
        developerToolsEnabled = try values.decodeIfPresent(Bool.self, forKey: .developerToolsEnabled) ?? true
        hasChosenTools = try values.decodeIfPresent(Bool.self, forKey: .hasChosenTools) ?? true
        includeHelloWorld = try values.decodeIfPresent(Bool.self, forKey: .includeHelloWorld) ?? false
        languageChoices = try values.decodeIfPresent([String: Bool].self, forKey: .languageChoices) ?? languageChoices
        lastCategory = try values.decodeIfPresent(SettingsCategory.self, forKey: .lastCategory) ?? .general
        revealCreatedFile = try values.decodeIfPresent(Bool.self, forKey: .revealCreatedFile) ?? true
        revealConvertedFile = try values.decodeIfPresent(Bool.self, forKey: .revealConvertedFile) ?? true
        openAfterCreation = try values.decodeIfPresent(Bool.self, forKey: .openAfterCreation) ?? false
        imageConversion = try values.decodeIfPresent(ImageConversionOptions.self, forKey: .imageConversion) ?? .init()
        try imageConversion.validate()
        favoriteTemplateIDs = try values.decodeIfPresent(Set<String>.self, forKey: .favoriteTemplateIDs) ?? []
        normalizeToolSelection()
    }
    public mutating func normalizeToolSelection() {
        if !developerToolsEnabled && lastCategory == .developer { lastCategory = .general }
    }
    public func usesStarter(for template: FileTemplate, folderWantsStarter: Bool? = nil) -> Bool {
        includeHelloWorld && template.isProgramming && languageChoices[template.rawValue, default: true]
            && (folderWantsStarter ?? true)
    }
}

/// The host is the sole writer. Extensions hand off intent, never cache settings.
/// Disk reads happen at request ingress; a value snapshot then belongs to the operation.
public struct PreferencesStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: PreferencesStore {
        .init(url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.cloakyard.cloaktools/preferences.json"))
    }
    public func load() throws -> Preferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return Preferences() }
        return try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
    }
    public func save(_ preferences: Preferences) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(preferences).write(to: url, options: .atomic)
    }
}
