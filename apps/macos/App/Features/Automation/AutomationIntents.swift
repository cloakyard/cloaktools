import AppIntents
import AppKit
import CloakToolsCore
import UniformTypeIdentifiers
import Security

enum AutomationAvailability {
    /// LinkDaemon rejects this ad-hoc preview without a team identity on macOS 27.
    static var hasSigningIdentity: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let team = SecTaskCopyValueForEntitlement(task, "com.apple.developer.team-identifier" as CFString, nil) as? String else { return false }
        return !team.isEmpty
    }
}

enum FitImageFormat: String, AppEnum {
    case jpeg, png, heic
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Image format"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.jpeg: "JPEG", .png: "PNG", .heic: "HEIC"]
    var format: ImageOutputFormat { ImageOutputFormat(rawValue: rawValue)! }
}

/// Cancellation follows the Shortcuts task into the bounded, synchronous native core.
private func automationWorker<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    let task = Task.detached(priority: .userInitiated, operation: work)
    return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
}

private func automationURL(_ file: IntentFile) async throws -> URL {
    if let url = file.fileURL { return url }
    return try await file.file(contentType: file.type ?? .data).fileURL
}

struct FitImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Make Image Fit"
    static let description = IntentDescription("Return a measured image within your byte and dimension limits. Does not save beside or replace the source. Add Quick Look or Save File in Shortcuts to review or keep the result. Accepts one still PNG, JPEG, TIFF or HEIC up to 100 MB and 40 megapixels.", categoryName: "Images", resultValueName: "Fitted image")
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "Image", supportedContentTypes: [.image], inputConnectionBehavior: .connectToPreviousIntentResult) var image: IntentFile
    @Parameter(title: "Format", default: .jpeg) var format: FitImageFormat
    @Parameter(title: "Maximum size (KB)", default: 500, inclusiveRange: (1, 100_000)) var kilobytes: Int
    @Parameter(title: "Maximum width", default: 1600, inclusiveRange: (1, 20_000)) var width: Int
    @Parameter(title: "Maximum height", default: 1600, inclusiveRange: (1, 20_000)) var height: Int
    @Parameter(title: "Minimum quality (%)", default: 60, inclusiveRange: (10, 100)) var quality: Int
    @Parameter(title: "Reduce dimensions to meet size", default: true) var reduceDimensions: Bool
    static var parameterSummary: some ParameterSummary {
        Summary("Fit \(\.$image) within \(\.$kilobytes) KB") {
            \.$format; \.$width; \.$height; \.$quality; \.$reduceDimensions
        }
    }
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        // Validate again: values can arrive through variables, outside the editor's ranges.
        guard (1...100_000).contains(kilobytes), (10...100).contains(quality) else { throw ImageFitError.invalidOptions }
        let options = ImageFitOptions(format: format.format, maximumBytes: kilobytes * 1000, maximumWidth: width,
                                      maximumHeight: height, minimumQuality: Double(quality) / 100,
                                      background: .white, allowSmallerDimensions: reduceDimensions)
        try options.validate()
        let url = try await automationURL(image)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let result = try await automationWorker { try ImageFit.preview(ImageConversion.prepare(url), options: options) }
        let stem = (image.filename as NSString).deletingPathExtension
        let name = (try? SafeOutput.validate(stem: stem)) != nil && stem.utf8.count <= 116 ? stem : "Image"
        return .result(value: IntentFile(data: try result.exportData(), filename: name + " fit." + options.format.fileExtension, type: options.format.type))
    }
}

struct MakeMarkdownDigestIntent: AppIntent {
    static let title: LocalizedStringResource = "Make Markdown Digest"
    static let description = IntentDescription("Collect 1–32 selected UTF-8 files in their supplied order, with literal fenced contents. Each file can be up to 1 MiB, with 8 MiB total input. Returns a Markdown file without saving or modifying the sources. Review with Quick Look before sharing.", categoryName: "Files", resultValueName: "Markdown digest")
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "Files", supportedContentTypes: [.item], inputConnectionBehavior: .connectToPreviousIntentResult) var files: [IntentFile]
    @Parameter(title: "Document name", default: "Collected notes") var name: String
    static var parameterSummary: some ParameterSummary { Summary("Collect \(\.$files) as \(\.$name)") }
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard (1...MarkdownDigest.maximumFiles).contains(files.count) else { throw MarkdownDigestError.invalidSelection }
        try SafeOutput.validate(stem: name)
        var urls: [URL] = [], scopes: [URL] = []
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        for file in files {
            try Task.checkCancellation()
            let url = try await automationURL(file)
            if url.startAccessingSecurityScopedResource() { scopes.append(url) }
            urls.append(url)
        }
        let capturedURLs = urls, title = name, names = files.map(\.filename)
        let result = try await automationWorker { try MarkdownDigest.prepare(MarkdownDigest.capture(capturedURLs, displayNames: names), title: title) }
        return .result(value: IntentFile(data: Data(result.text.utf8), filename: result.title + ".md", type: UTType(filenameExtension: "md") ?? .plainText))
    }
}

struct SavedFileSetEntity: AppEntity {
    let id: UUID
    let title: String
    let count: Int
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved file set"
    static let defaultQuery = SavedFileSetQuery()
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)", subtitle: "\(count) items") }
}

struct SavedFileSetQuery: EntityStringQuery {
    private func available() async throws -> [SavedFileSetEntity] {
        try await automationWorker {
            let preferences = try PreferencesStore.standard.load()
            let sources = FileTemplate.allCases.map(TemplateSource.builtIn) + (try TemplateLibraryStore.standard.load()).map(TemplateSource.custom)
            return try FileSetStore.standard.load().filter { preferences.tools.includes($0, sources: sources) }
                .map { .init(id: $0.id, title: $0.title, count: $0.entries.count) }
        }
    }
    func entities(for identifiers: [UUID]) async throws -> [SavedFileSetEntity] {
        let values = try await available()
        return identifiers.compactMap { id in values.first { $0.id == id } }
    }
    func suggestedEntities() async throws -> [SavedFileSetEntity] { try await available() }
    func entities(matching string: String) async throws -> [SavedFileSetEntity] {
        try await available().filter { $0.title.localizedStandardContains(string) }
    }
}

struct ReviewFileSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Review Saved File Set"
    static let description = IntentDescription("Open a saved file set in CloakTools. Choose a destination and review its files before creating. This action starts the review; it does not create files or wait for the review to finish. Save a set in New Files first.", categoryName: "Files")
    static var supportedModes: IntentModes { .foreground }
    @Parameter(title: "File set") var fileSet: SavedFileSetEntity
    static var parameterSummary: some ParameterSummary { Summary("Review \(\.$fileSet) in CloakTools") }
    @MainActor func perform() async throws -> some IntentResult {
        guard let definition = try FileSetStore.standard.load().first(where: { $0.id == fileSet.id }) else {
            throw AutomationError.missingFileSet
        }
        let preferences = try PreferencesStore.standard.load()
        let sources = FileTemplate.allCases.map(TemplateSource.builtIn) + (try TemplateLibraryStore.standard.load()).map(TemplateSource.custom)
        guard preferences.tools.includes(definition, sources: sources) else { throw ToolAvailabilityError.developerToolsOff }
        AppModel.shared.chooseFileSetFolder(definition)
        return .result()
    }
}

enum AutomationError: LocalizedError {
    case missingFileSet
    var errorDescription: String? { "This saved file set is no longer available. Choose another set in Shortcuts." }
}

struct CloakToolsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ReviewFileSetIntent(), phrases: ["Review a file set in \(.applicationName)"], shortTitle: "Review File Set", systemImageName: "folder.badge.plus")
    }
    static var shortcutTileColor: ShortcutTileColor { .blue }
}

struct OptimizeMediaIntent: AppIntent {
    static let title: LocalizedStringResource = "Optimize Media File"
    static let description = IntentDescription("Return a smaller copy of a local image, PDF, movie or audio file.", categoryName: "Media", resultValueName: "Optimized file")
    static var supportedModes: IntentModes { .background }
    @Parameter(title: "File", supportedContentTypes: [.image, .pdf, .movie, .audio], inputConnectionBehavior: .connectToPreviousIntentResult) var file: IntentFile
    @Parameter(title: "Stronger compression", default: false) var aggressive: Bool
    static var parameterSummary: some ParameterSummary { Summary("Optimize \(\.$file)") { \.$aggressive } }

    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let url = try await automationURL(file)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var options = OptimizationOptions()
        options.aggressive = aggressive
        let result = try await MediaOptimization.prepare(url, options: options)
        // IntentFile(data:) owns its bytes after the private workspace is released.
        guard result.outputBytes <= 100_000_000 else { throw AutomationResultError.tooLarge }
        return .result(value: IntentFile(data: try Data(contentsOf: result.previewURL), filename: result.filename,
                                         type: UTType(filenameExtension: result.previewURL.pathExtension)))
    }
}

private enum AutomationResultError: LocalizedError {
    case tooLarge
    var errorDescription: String? { "Use the Workbench to save outputs larger than 100 MB." }
}
