import Foundation

public enum ExportRecipeError: LocalizedError, Sendable {
    case invalidTitle, full, unsupportedVersion, changed, incompatibleMedia
    public var errorDescription: String? {
        switch self {
        case .invalidTitle: "Use a recipe name with 1–80 characters, without control characters or surrounding spaces."
        case .full: "You can save up to 32 export recipes. Remove one before adding another."
        case .unsupportedVersion: "These recipes use an unsupported format version. Keep the library and open it with a compatible CloakTools version."
        case .changed: "This recipe changed or was removed after you opened it. Save a new copy, or reopen the current recipe."
        case .incompatibleMedia: "This source cannot use the recipe’s media preset. Choose an available format in Export as, or cancel and select another source."
        }
    }
}

/// Only output settings. No input paths, destinations, file names or media bytes.
public enum ExportRecipeOptions: Codable, Equatable, Sendable {
    case image(ImageConversionOptions)
    case fit(ImageFitOptions)
    case media(MediaExportPreset)
    case optimize(OptimizationOptions)
    public var toolName: String {
        switch self { case .optimize: "Optimize Media"; case .image: "Convert Image"; case .fit: "Make It Fit"; case .media: "Export Media" }
    }
    public var symbol: String {
        switch self { case .optimize: "square.and.arrow.down"; case .image: "photo"; case .fit: "arrow.down.right.and.arrow.up.left"; case .media: "play.rectangle" }
    }
    public var summary: String {
        switch self {
        case let .optimize(options):
            options.steps?.map(\.title).joined(separator: " → ") ?? options.scanDPI.map { "Scanned PDF · \($0) DPI" } ?? "\(options.aggressive ? "Stronger" : "Standard") · \(options.imageFormat.title) · \(options.scale.formatted(.percent))"
        case let .image(options):
            options.format.isLossy ? "\(options.format.title) · \(Int((options.quality * 100).rounded()))% · \(options.background.title) background" : "PNG · Original dimensions · Keeps transparency"
        case let .fit(options):
            "\(options.format.title) · ≤\(options.sizeLimitText) · \(options.maximumWidth) × \(options.maximumHeight) px"
        case let .media(preset): preset.title
        }
    }
    public var detail: String {
        switch self {
        case let .optimize(options):
            options.steps != nil ? "Matching steps run in order for each file." : "Crop \(options.crop.rawValue) · Video \(options.videoFormat.rawValue) · Audio \(options.audioFormat.rawValue)"
        case .image: "Keeps the original dimensions. A new source and destination are reviewed each time."
        case let .fit(options):
            (options.format.isLossy ? "Quality floor \(Int((options.minimumQuality * 100).rounded()))% · \(options.background.title) background. " : "Keeps transparency. ")
            + (options.allowSmallerDimensions ? "May reduce dimensions further to meet the limit." : "Does not reduce beyond the chosen dimensions.")
        case let .media(preset): preset.detail + " Exports the full clip."
        }
    }
    public func validate() throws {
        switch self {
        case let .optimize(options): try options.validate()
        case let .image(options): try options.validate()
        case let .fit(options): try options.validate()
        case .media: break
        }
    }
    public func validateMediaCompatibility(_ available: [MediaExportPreset]) throws {
        guard case let .media(preset) = self, available.contains(preset) else { throw ExportRecipeError.incompatibleMedia }
    }
}

public struct ExportRecipe: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var title: String
    public var options: ExportRecipeOptions
    public init(id: UUID = UUID(), title: String, options: ExportRecipeOptions) {
        self.id = id; self.title = title; self.options = options
    }
    public func validate() throws {
        guard !title.isEmpty, title.count <= 80, title == title.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ExportRecipeError.invalidTitle }
        try options.validate()
    }
}

public struct ExportRecipeStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: Self { .init(url: PreferencesStore.standard.url.deletingLastPathComponent().appendingPathComponent("export-recipes.json")) }
    private struct Archive: Codable {
        var version = 1
        var recipes: [ExportRecipe]
    }
    public func load() throws -> [ExportRecipe] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let archive = try JSONDecoder().decode(Archive.self, from: LocalFileCapture.read(url, limit: 262_144))
        guard archive.version == 1 else { throw ExportRecipeError.unsupportedVersion }
        try validate(archive.recipes); return archive.recipes
    }
    public func save(_ recipes: [ExportRecipe]) throws {
        try validate(recipes)
        let data = try JSONEncoder().encode(Archive(recipes: recipes))
        guard data.count <= 262_144 else { throw ExportRecipeError.full }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
    /// Detect stale operation drafts instead of silently replacing a newer saved recipe.
    public func upsert(_ recipe: ExportRecipe, replacing original: ExportRecipe?) throws -> [ExportRecipe] {
        var recipes = try load()
        if let original {
            guard recipe.id == original.id, let index = recipes.firstIndex(where: { $0.id == original.id }), recipes[index] == original else { throw ExportRecipeError.changed }
            recipes[index] = recipe
        } else {
            guard !recipes.contains(where: { $0.id == recipe.id }) else { throw ExportRecipeError.changed }
            recipes.append(recipe)
        }
        recipes.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        try save(recipes); return recipes
    }
    private func validate(_ recipes: [ExportRecipe]) throws {
        guard recipes.count <= 32 else { throw ExportRecipeError.full }
        guard Set(recipes.map(\.id)).count == recipes.count else { throw ExportRecipeError.changed }
        for recipe in recipes { try recipe.validate() }
    }
}
