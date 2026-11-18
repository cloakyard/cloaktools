import AppKit
import SwiftUI
import CloakToolsCore

struct ImageFitDraft: Equatable {
    var format: ImageOutputFormat = .jpeg
    var kilobytes = "500"
    var width = "1600"
    var height = "1600"
    var minimumQuality = 0.6
    var background: ImageBackground = .white
    var allowSmaller = true
    init(options: ImageFitOptions = .init()) {
        format = options.format; kilobytes = String(options.maximumBytes / 1000)
        width = String(options.maximumWidth); height = String(options.maximumHeight)
        minimumQuality = options.minimumQuality; background = options.background; allowSmaller = options.allowSmallerDimensions
    }
    func options() throws -> ImageFitOptions {
        func number(_ value: String) throws -> Int {
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let result = Int(value) else { throw ImageFitError.invalidOptions }
            return result
        }
        let kb = try number(kilobytes)
        guard (1...100_000).contains(kb) else { throw ImageFitError.invalidOptions }
        let options = ImageFitOptions(format: format, maximumBytes: kb * 1000, maximumWidth: try number(width), maximumHeight: try number(height),
                                      minimumQuality: minimumQuality, background: background, allowSmallerDimensions: allowSmaller)
        try options.validate(); return options
    }
}

@MainActor @Observable
final class ImageFitOperation: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let revealOutput: Bool
    var destination: URL
    var draft = ImageFitDraft()
    var recipe: ExportRecipe?
    var source: PreparedImage?
    var sourceThumbnail: NSImage?
    var result: FittedImage?
    var resultThumbnail: NSImage?
    var output: URL?
    var cancellation: String?
    var error: String?
    var activity: String?
    var stopping = false
    var busy: Bool { activity != nil }
    private var preparation: Task<PreparedImage, Error>?
    private var fitting: Task<FittedImage, Error>?
    private var publication: Task<URL, Error>?

    init(sourceURL: URL, revealOutput: Bool, recipe: ExportRecipe? = nil) {
        self.sourceURL = sourceURL; self.revealOutput = revealOutput
        self.recipe = recipe
        if case let .fit(options) = recipe?.options { draft = ImageFitDraft(options: options) }
        destination = sourceURL.deletingLastPathComponent()
        activity = "Preparing image…"
        let worker = Task.detached(priority: .userInitiated) { try ImageConversion.prepare(sourceURL) }
        preparation = worker
        Task { [self] in
            do {
                let image = try await worker.value
                if worker.isCancelled { throw CancellationError() }
                source = image; sourceThumbnail = NSImage(data: image.thumbnailPNG)
            } catch is CancellationError { cancellation = "Cancelled. No copy was saved." }
            catch { self.error = error.localizedDescription }
            preparation = nil; activity = nil; stopping = false
        }
    }
    func invalidatePreview() {
        guard !busy, output == nil else { return }
        result = nil; resultThumbnail = nil; error = nil
    }
    func preview() {
        guard !busy, output == nil, let source else { return }
        let options: ImageFitOptions
        do { options = try draft.options() }
        catch { self.error = error.localizedDescription; return }
        error = nil; cancellation = nil; result = nil; resultThumbnail = nil; activity = "Finding a fit…"
        let worker = Task.detached(priority: .userInitiated) { try ImageFit.preview(source, options: options) }
        fitting = worker
        Task { [self] in
            do {
                let fitted = try await worker.value
                if worker.isCancelled { throw CancellationError() }
                result = fitted; resultThumbnail = NSImage(data: fitted.thumbnailPNG)
            } catch is CancellationError { cancellation = "Cancelled. No copy was saved." }
            catch { self.error = error.localizedDescription }
            fitting = nil; activity = nil; stopping = false
        }
    }
    func save() {
        guard !busy, output == nil, let result, result.fits else { return }
        // Even if a view edit has not yet invalidated its preview, stale bytes cannot be saved.
        guard (try? draft.options()) == result.options else { invalidatePreview(); return }
        error = nil; cancellation = nil; activity = "Saving copy…"
        let folder = destination
        let worker = Task.detached(priority: .userInitiated) { try ImageFit.save(result, in: folder) }
        publication = worker
        Task { [self] in
            do {
                let url = try await worker.value; output = url
                if revealOutput { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch is CancellationError { cancellation = "Cancelled. No copy was saved." }
            catch { self.error = error.localizedDescription }
            publication = nil; activity = nil; stopping = false
        }
    }
    func chooseDestination() {
        let panel = NSOpenPanel(); panel.title = "Choose output folder"; panel.prompt = "Choose Folder"
        panel.directoryURL = destination; panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let folder = panel.url { destination = folder; error = nil }
    }
    func cancel() { stopping = true; preparation?.cancel(); fitting?.cancel(); publication?.cancel() }
    func open() {
        guard let output else { return }
        CreatedFileOpener.open(output, inPreview: true) { [weak self] in self?.error = $0 }
    }
}

@MainActor
final class ImageFitWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    let operation: ImageFitOperation
    init(operation: ImageFitOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Make It Fit"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: ImageFitView(operation: operation, close: { [weak window] in window?.close() }))
        window.contentMinSize = NSSize(width: 440, height: 460)
        window.setContentSize(NSSize(width: 480, height: 520)); window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if operation.busy { operation.cancel(); return false }; return true }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

struct ImageFitView: View {
    @Bindable var operation: ImageFitOperation
    let close: () -> Void
    @State private var advanced = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Make it fit", subtitle: operation.recipe.map { "From “\($0.title)”. Preview before saving." } ?? "A smaller copy, with limits you choose.", symbol: "arrow.down.right.and.arrow.up.left")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    previews
                    if operation.output == nil { controls.disabled(operation.busy) }
                    if let output = operation.output {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved \(output.lastPathComponent)").font(.callout).fontWeight(.medium)
                            HStack(spacing: 16) {
                                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }.buttonStyle(.link)
                                Button("Open in Preview", action: operation.open).buttonStyle(.link)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize)
            if let result = operation.result {
                VStack(alignment: .leading, spacing: 5) {
                    Label(result.fits ? "Fits your limit · \(result.byteCount.formatted()) bytes" : "Over limit · \(result.byteCount.formatted()) bytes",
                          systemImage: result.fits ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(result.fits ? .green : .orange).font(.callout).fontWeight(.medium)
                    if !result.fits {
                        Text("Increase the limit or choose another format. This result cannot be saved.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if operation.output == nil { DestinationRow(folder: operation.destination, change: operation.chooseDestination).disabled(operation.busy) }
            OperationFeedback(cancellation: operation.cancellation, error: operation.error)
            if let activity = operation.activity {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(operation.stopping ? "Stopping…" : activity).font(.callout) }
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if !operation.busy, operation.source != nil {
                        SaveExportRecipeButton(recipe: $operation.recipe) { .fit(try operation.draft.options()) }
                    }
                    Spacer(minLength: 0)
                    if operation.busy {
                        Button("Cancel", role: .cancel, action: operation.cancel).keyboardShortcut(.cancelAction).modifier(DialogActionStyle()).disabled(operation.stopping)
                    } else if operation.output != nil {
                        Button("Done", action: close).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    } else {
                        Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                        Button(operation.result == nil ? "Preview Fit" : "Save Copy") { if operation.result == nil { operation.preview() } else { operation.save() } }
                            .keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                            .disabled(operation.source == nil || operation.result?.fits == false || !operation.draft.format.isAvailable)
                    }
                }
            }
        }.padding(20).frame(minWidth: 440, minHeight: 460)
            .onChange(of: operation.draft) { operation.invalidatePreview() }
    }
    private var previews: some View {
        HStack(spacing: 14) {
            previewImage(operation.sourceThumbnail, title: "Original", detail: operation.source.map { "\($0.width) × \($0.height) · \(size($0.sourceByteCount))" } ?? "Preparing…")
            Image(systemName: "arrow.right").foregroundStyle(.tertiary).accessibilityHidden(true)
            previewImage(operation.resultThumbnail, title: operation.result?.options.format.title ?? "Preview", detail: operation.result.map {
                "\($0.width) × \($0.height) · \(size($0.byteCount))" + ($0.quality.map { " · \(Int(($0 * 100).rounded()))%" } ?? "")
            } ?? "Set limits below")
        }.frame(maxWidth: .infinity).modifier(DialogCard())
    }
    private func previewImage(_ image: NSImage?, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer(minLength: 0)
                if let image { Image(nsImage: image).resizable().scaledToFit().frame(height: 64).accessibilityLabel("\(title) image preview") }
                else { Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary).frame(height: 64).accessibilityHidden(true) }
                Spacer(minLength: 0)
            }
            Text(title).font(.caption).fontWeight(.semibold)
            Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow { Text("Format").foregroundStyle(.secondary); ImageFormatPicker(selection: $operation.draft.format).labelsHidden() }
                GridRow {
                    Text("Maximum size").foregroundStyle(.secondary)
                    HStack { TextField("500", text: $operation.draft.kilobytes).textFieldStyle(.roundedBorder).accessibilityLabel("Maximum size in kilobytes"); Text("KB").foregroundStyle(.secondary).help("1 KB = 1,000 bytes") }
                }
                GridRow {
                    Text("Fit within").foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        TextField("1600", text: $operation.draft.width).textFieldStyle(.roundedBorder).accessibilityLabel("Maximum width in pixels")
                        Text("×").foregroundStyle(.secondary)
                        TextField("1600", text: $operation.draft.height).textFieldStyle(.roundedBorder).accessibilityLabel("Maximum height in pixels")
                        Text("px").foregroundStyle(.secondary)
                    }
                }
            }
            Toggle("Reduce further to meet size", isOn: $operation.draft.allowSmaller).controlSize(.small)
            Text(operation.draft.allowSmaller ? "Keeps proportions, never enlarges. Further reduction stops at a 320 px long edge, or your smaller starting size." : "Keeps proportions, never enlarges. Only the Fit within dimensions can reduce the image.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if operation.draft.format.isLossy {
                DisclosureGroup(isExpanded: $advanced) {
                    VStack(spacing: 10) {
                        LabeledContent("Quality floor") {
                            Slider(value: $operation.draft.minimumQuality, in: 0.1...1, step: 0.05).accessibilityLabel("Minimum encoding quality").accessibilityValue("\(Int((operation.draft.minimumQuality * 100).rounded())) percent")
                            Text("\(Int((operation.draft.minimumQuality * 100).rounded()))%").font(.callout.monospacedDigit()).frame(width: 36)
                        }
                        Picker("Transparent areas", selection: $operation.draft.background) { ForEach(ImageBackground.allCases) { Text($0.title).tag($0) } }
                    }.padding(.top, 8)
                } label: {
                    HStack {
                        Text("Quality & background")
                        Spacer(minLength: 4)
                        Text("≥\(Int((operation.draft.minimumQuality * 100).rounded()))% · \(operation.draft.background.title)").foregroundStyle(.secondary)
                    }
                }.font(.callout)
            } else { Text("PNG keeps transparency. File size changes through dimensions, with lossless encoding.").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
    }
    private func size(_ count: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file) }
}
