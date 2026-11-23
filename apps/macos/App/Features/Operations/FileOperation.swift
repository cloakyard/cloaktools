import SwiftUI
import AppKit
import CloakToolsCore

@MainActor @Observable
final class FileOperation: Identifiable {
    let id = UUID()
    let intent: FinderIntent
    let preferences: Preferences
    let sources: [TemplateSource]
    var selectedTemplateID: String
    var source: TemplateSource { sources.first { $0.id == selectedTemplateID } ?? .builtIn(.text) }
    var presetTitle: String?
    var name = "Untitled"
    var destination: URL
    var onFormatChanged: (() -> Void)?
    var conversionOptions: ImageConversionOptions
    var recipe: ExportRecipe?
    var preparedImage: PreparedImage?
    var imageThumbnail: NSImage?
    var preparing = false
    var busy: Bool { preparing || running }
    private var preparationTask: Task<PreparedImage, Error>?
    var stopping = false
    var running = false
    var cancelled = false
    var error: String?
    var output: URL?
    private var task: Task<URL, Error>?
    init(intent: FinderIntent, preferences: Preferences, sources: [TemplateSource], recipe: ExportRecipe? = nil) {
        self.intent = intent; self.preferences = preferences; self.sources = sources
        self.recipe = recipe
        switch intent {
        case let .create(folder, _), let .templates(folder), let .clipboard(folder): destination = folder
        case let .convert(image): destination = image.deletingLastPathComponent()
        case .assemble, .copy, .fit, .structure, .collect, .compare: destination = FileManager.default.homeDirectoryForCurrentUser
        }
        conversionOptions = preferences.imageConversion
        if case let .image(options) = recipe?.options { conversionOptions = options }
        switch intent {
        case let .create(_, template): selectedTemplateID = TemplateSource.builtIn(template).id
        case .clipboard, .assemble, .copy, .fit, .structure, .collect, .compare: selectedTemplateID = TemplateSource.builtIn(.text).id
        case .templates: selectedTemplateID = sources.first(where: { if case .custom = $0 { true } else { false } })?.id ?? TemplateSource.builtIn(.text).id
        case .convert: selectedTemplateID = TemplateSource.builtIn(.text).id
        }
        name = source.suggestedName
        if case let .convert(url) = intent { prepareImage(url) }
    }
    var isCreation: Bool { if case .convert = intent { false } else { true } }
    func chooseDestination() {
        let panel = NSOpenPanel(); panel.title = "Choose output folder"; panel.prompt = "Choose Folder"
        panel.directoryURL = destination; panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let folder = panel.url { destination = folder; error = nil }
    }
    private func prepareImage(_ url: URL) {
        preparing = true
        let worker = Task.detached(priority: .userInitiated) { try ImageConversion.prepare(url) }
        preparationTask = worker
        Task { [self] in
            do {
                let prepared = try await worker.value
                if worker.isCancelled { throw CancellationError() }
                preparedImage = prepared; imageThumbnail = NSImage(data: prepared.thumbnailPNG)
            } catch is CancellationError { cancelled = true }
            catch { self.error = error.localizedDescription }
            preparing = false; preparationTask = nil; stopping = false
        }
    }
    func start() {
        guard !busy, output == nil, isCreation || preparedImage != nil else { return }
        if isCreation {
            do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        }
        error = nil; cancelled = false; running = true
        let request = CreationRequest(folder: destination, source: source, preferences: preferences, name: name)
        let intent = intent, prepared = preparedImage, options = conversionOptions, folder = destination
        let worker = Task.detached(priority: .userInitiated) {
            switch intent { case .clipboard, .assemble, .copy, .fit, .structure, .collect, .compare: throw ToolError.invalidRequest; case .create, .templates: return try request.perform(); case .convert: guard let prepared else { throw ToolError.unsupportedImage }; return try ImageConversion.copy(prepared, options: options, in: folder) }
        }
        task = worker
        Task { [self] in
            do {
                let url = try await worker.value
                output = url
                if isCreation ? preferences.revealCreatedFile : preferences.revealConvertedFile { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                if isCreation && preferences.openAfterCreation {
                    CreatedFileOpener.open(url, inPreview: request.source.isPDF) { [weak self] in self?.error = $0 }
                }
            } catch is CancellationError { cancelled = true }
            catch { self.error = error.localizedDescription }
            running = false; task = nil; stopping = false
        }
    }
    func cancel() { guard busy else { return }; stopping = true; task?.cancel(); preparationTask?.cancel() }
    func openInPreview() {
        guard let output else { return }
        CreatedFileOpener.open(output, inPreview: true) { [weak self] in self?.error = $0 }
    }

}

@MainActor
final class OperationWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    let operation: FileOperation
    init(operation: FileOperation) {
        self.operation = operation
        let height: CGFloat = operation.isCreation ? 344 : (operation.conversionOptions.format.isLossy ? 432 : 360)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 448, height: height), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = operation.isCreation ? "New File" : "Convert Image"
        window.contentViewController = NSHostingController(rootView: OperationView(operation: operation, close: { [weak window] in window?.close() }))
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 420, height: 320)
        window.setContentSize(NSSize(width: 448, height: height)); window.center(); window.isReleasedWhenClosed = false
        var lastAutomaticHeight = height
        operation.onFormatChanged = { [weak window, weak operation] in
            guard let window, let operation, !operation.isCreation,
                  abs((window.contentView?.bounds.height ?? 0) - lastAutomaticHeight) < 1 else { return }
            let target: CGFloat = operation.conversionOptions.format.isLossy ? 432 : 360
            window.setContentSize(NSSize(width: window.contentView?.bounds.width ?? 448, height: target))
            lastAutomaticHeight = target
        }
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { operation.cancel(); return !operation.busy }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

struct OperationView: View {
    @Bindable var operation: FileOperation
    let close: () -> Void
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeading(title: operation.isCreation ? "New file" : "Convert image",
                          subtitle: operation.isCreation ? (operation.presetTitle.map { "From “\($0)”. Review before creating." } ?? "A fresh start, right here.") : (operation.recipe.map { "From “\($0.title)”. Original preserved." } ?? "A ready-to-use copy. Original preserved."),
                          symbol: operation.isCreation ? "doc.badge.plus" : "photo.on.rectangle")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if operation.isCreation {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            GridRow {
                                Text("Name").foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    TextField("Name", text: $operation.name)
                                        .textFieldStyle(.roundedBorder).focused($nameFocused)
                                        .accessibilityLabel("File name, without extension")
                                    Text(".\(operation.source.fileExtension)").foregroundStyle(.secondary).font(.callout.monospaced())
                                }
                            }
                            GridRow {
                                Text("Type").foregroundStyle(.secondary)
                                HStack {
                                    Picker("File type or saved template", selection: $operation.selectedTemplateID) {
                                        ForEach(operation.sources) { source in
                                            Text((AppModel.shared.preferences.favoriteTemplateIDs.contains(source.id) ? "★ " : "") + source.title).tag(source.id)
                                        }
                                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                                    Button { AppModel.shared.toggleFavorite(operation.source.id) } label: {
                                        Image(systemName: AppModel.shared.preferences.favoriteTemplateIDs.contains(operation.source.id) ? "star.fill" : "star")
                                    }.buttonStyle(.borderless)
                                        .accessibilityLabel(AppModel.shared.preferences.favoriteTemplateIDs.contains(operation.source.id) ? "Remove from favorites" : "Add to favorites")
                                        .help("Favorites appear first the next time you create a file")
                                }
                            }
                        }.modifier(DialogCard()).disabled(operation.running || operation.output != nil)
                        if operation.output == nil, !AppModel.shared.visibleFileSets.isEmpty {
                            Menu("Use Saved File Set…") {
                                ForEach(AppModel.shared.visibleFileSets) { set in
                                    Button(set.title) {
                                        let folder = operation.destination
                                        close()
                                        AppModel.shared.chooseFileSetFolder(set, destination: folder)
                                    }
                                }
                            }.fixedSize().disabled(operation.busy)
                        }
                        Label(operation.source.contentDescription(using: operation.preferences), systemImage: operation.source.isPDF ? "doc.richtext" : "doc")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        ConversionOptionsCard(operation: operation)
                        Text(operation.conversionOptions.format.isLossy ? "Flattens transparency. Dimensions stay unchanged." : "Keeps transparency. Lossless compression.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !operation.conversionOptions.format.isAvailable {
                            Label("This format is unavailable on this Mac. Choose another format.", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        }
                    }
                    if let output = operation.output {
                        Label("Created \(output.lastPathComponent)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        HStack(spacing: 14) {
                            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }.buttonStyle(.link)
                            if !operation.isCreation {
                                Button("Open in Preview", action: operation.openInPreview).buttonStyle(.link)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize)
            DestinationRow(folder: operation.destination, change: operation.output == nil ? { operation.chooseDestination() } : nil).disabled(operation.busy)
            OperationFeedback(activity: operation.busy ? (operation.preparing ? "Preparing preview…" : operation.isCreation ? "Creating file…" : "Converting image…") : nil,
                              stopping: operation.stopping, cancellation: operation.cancelled ? "Cancelled. No output was published." : nil, error: operation.error)
            if !operation.busy && operation.output == nil && (operation.isCreation || operation.preparedImage == nil) {
                Text("Never replaces existing files.").font(.caption).foregroundStyle(.secondary)
            }
            DialogFooter {
                if operation.busy {
                    Button("Cancel", role: .cancel, action: operation.cancel).keyboardShortcut(.cancelAction)
                        .modifier(DialogActionStyle()).disabled(operation.stopping)
                } else if operation.output == nil {
                    Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                        .modifier(DialogActionStyle())
                }
            } actions: {
                if operation.output != nil && !operation.busy {
                    DialogDoneButton(action: close)
                } else if !operation.busy {
                    if !operation.isCreation && operation.preparedImage != nil {
                        SaveExportRecipeButton(recipe: $operation.recipe) { .image(operation.conversionOptions) }
                    }
                    Button(operation.isCreation ? "Create" : "Convert", action: operation.start).keyboardShortcut(.defaultAction)
                        .modifier(DialogActionStyle(prominent: true))
                        .disabled(operation.isCreation ? operation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : (operation.preparedImage == nil || !operation.conversionOptions.format.isAvailable))
                }
            }
        }.padding(20).frame(minWidth: 420, minHeight: 320)
            .onAppear { nameFocused = operation.isCreation }
            .onChange(of: operation.conversionOptions.format) { operation.onFormatChanged?() }
            .onChange(of: operation.selectedTemplateID) { old, _ in
                let previousName = operation.sources.first { $0.id == old }?.suggestedName ?? "Untitled"
                if operation.name == previousName { operation.name = operation.source.suggestedName }
            }
            .transaction { if reduceMotion { $0.animation = nil } }
    }
}
