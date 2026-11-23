import AppKit
import SwiftUI
import CloakToolsCore

struct PDFPageDraft: Identifiable {
    let id: Int
    var included = true
    var quarterTurns = 0
}

@MainActor @Observable
final class PDFPagesOperation: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let preferences: Preferences
    var source: PreparedPDFPages?
    var pages: [PDFPageDraft] = []
    var thumbnails: [NSImage] = []
    var detailPreview: NSImage?
    var detailPageID: Int?
    var focusedPageID: Int?
    var range = ""
    var name: String
    var destination: URL
    var output: URL?
    var cancellation: String?
    var error: String?
    var activity: String?
    var stopping = false
    var busy: Bool { activity != nil }
    var includedCount: Int { pages.filter(\.included).count }
    var focusedIndex: Int? { pages.firstIndex { $0.id == focusedPageID } }
    var focusedPage: PDFPageDraft? { focusedIndex.map { pages[$0] } }
    private var preparation: Task<PreparedPDFPages, Error>?
    private var publication: Task<URL, Error>?
    private var previewWorker: Task<Data, Error>?
    private var closing = false

    init(sourceURL: URL, preferences: Preferences) {
        self.sourceURL = sourceURL; self.preferences = preferences
        let stem = sourceURL.deletingPathExtension().lastPathComponent + " pages"
        name = (try? SafeOutput.validate(stem: stem)) != nil && stem.utf8.count <= 120 ? stem : "Selected pages"
        destination = sourceURL.deletingLastPathComponent()
        activity = "Preparing pages…"
        let worker = Task.detached(priority: .userInitiated) { try PDFPageOrganization.prepare(sourceURL) }
        preparation = worker
        Task { [self] in
            do {
                let prepared = try await worker.value
                if worker.isCancelled { throw CancellationError() }
                source = prepared
                thumbnails = prepared.thumbnails.map { NSImage(data: $0) ?? NSImage() }
                reset()
                updatePreview()
            } catch is CancellationError { cancellation = "Cancelled. No copy was saved." }
            catch { self.error = error.localizedDescription }
            preparation = nil; activity = nil; stopping = false
        }
    }
    func reset() {
        guard output == nil, let source else { return }
        pages = (0..<source.pageCount).map { PDFPageDraft(id: $0) }
        focusedPageID = 0; range = ""; error = nil
    }
    func updatePreview() {
        guard !closing, output == nil, previewWorker == nil, let source, let pageID = focusedPageID, detailPageID != pageID else { return }
        let worker = Task.detached(priority: .userInitiated) { try PDFPageOrganization.preview(source, index: pageID) }
        previewWorker = worker
        Task { [self] in
            if let data = try? await worker.value, !worker.isCancelled, focusedPageID == pageID, !closing {
                detailPreview = NSImage(data: data); detailPageID = pageID
            }
            previewWorker = nil
            // Coalesce fast page changes instead of launching concurrent PDF renderers.
            if focusedPageID != pageID { updatePreview() }
        }
    }
    func finishPreview() { closing = true; previewWorker?.cancel() }
    func include(_ value: Bool, pageID: Int) {
        guard !busy, output == nil, let index = pages.firstIndex(where: { $0.id == pageID }) else { return }
        pages[index].included = value; focusedPageID = pageID; range = ""; error = nil
    }
    func includeAll(_ value: Bool) {
        guard !busy, output == nil else { return }
        for index in pages.indices { pages[index].included = value }
        range = ""; error = nil
    }
    func applyRange() {
        guard !busy, output == nil, let source else { return }
        do {
            let selected = try PDFPageOrganization.selection(range, pageCount: source.pageCount)
            for index in pages.indices { pages[index].included = selected.contains(pages[index].id) }
            focusedPageID = pages.first(where: \.included)?.id; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func rotate(_ offset: Int) {
        guard !busy, output == nil, let index = focusedIndex else { return }
        pages[index].quarterTurns = (pages[index].quarterTurns + offset + 4) % 4; error = nil
    }
    func move(_ offset: Int) {
        guard !busy, output == nil, let index = focusedIndex, pages.indices.contains(index + offset) else { return }
        pages.swapAt(index, index + offset); error = nil
    }
    func chooseDestination() {
        let panel = NSOpenPanel(); panel.title = "Save the organized PDF in…"; panel.prompt = "Choose Folder"
        panel.directoryURL = destination; panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let folder = panel.url { destination = folder }
    }
    func save() {
        guard !busy, output == nil, let source, includedCount > 0 else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        let choices = pages.filter(\.included).map { PDFPageChoice(index: $0.id, quarterTurns: $0.quarterTurns) }
        let folder = destination, name = name
        activity = "Exporting pages…"; error = nil
        let worker = Task.detached(priority: .userInitiated) { try PDFPageOrganization.write(source, pages: choices, in: folder, name: name) }
        publication = worker
        Task { [self] in
            do {
                let url = try await worker.value; output = url
                if preferences.revealCreatedFile { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                if preferences.openAfterCreation { open() }
            } catch is CancellationError { cancellation = "Cancelled. No copy was saved." }
            catch { self.error = error.localizedDescription }
            publication = nil; activity = nil; stopping = false
        }
    }
    func open() {
        guard let output else { return }
        CreatedFileOpener.open(output, inPreview: true) { [weak self] in self?.error = $0 }
    }
    func cancel() { stopping = true; preparation?.cancel(); publication?.cancel() }
}

@MainActor
final class PDFPagesWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    let operation: PDFPagesOperation
    init(operation: PDFPagesOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 570), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Organize PDF"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: PDFPagesView(operation: operation, close: { [weak window] in window?.close() }))
        window.contentMinSize = NSSize(width: 540, height: 520)
        window.setContentSize(NSSize(width: 580, height: 570)); window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if operation.busy { operation.cancel(); return false }; operation.finishPreview(); return true }
    func windowWillClose(_ notification: Notification) { operation.finishPreview(); onClose?() }
}

struct PDFPagesView: View {
    @Bindable var operation: PDFPagesOperation
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Organize a PDF", subtitle: operation.sourceURL.lastPathComponent, symbol: "square.grid.2x2")
            if operation.output == nil {
                selectionControls.disabled(operation.busy || operation.source == nil)
                editor.disabled(operation.busy).frame(minHeight: 200)
                HStack(spacing: 8) {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("File name", text: $operation.name).textFieldStyle(.roundedBorder).accessibilityLabel("PDF copy name, without extension")
                    Text(".pdf").foregroundStyle(.secondary)
                }.disabled(operation.busy)
                DestinationRow(folder: operation.destination, change: operation.chooseDestination).disabled(operation.busy)
            } else if let output = operation.output {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Exported \(operation.includedCount) \(operation.includedCount == 1 ? "page" : "pages")", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
                    Text(output.lastPathComponent).textSelection(.enabled)
                    Text(output.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack(spacing: 16) {
                        ShowInFinderButton(url: output)
                        Button("Open in Preview", action: operation.open).buttonStyle(.link)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
                Spacer(minLength: 0)
            }
            OperationFeedback(cancellation: operation.cancellation, error: operation.error)
            if let activity = operation.activity {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(operation.stopping ? "Stopping…" : activity).font(.callout) }
            }
            Text(operation.output == nil ? "\(operation.includedCount) of \(operation.pages.count) pages included" : "Original preserved.").font(.caption).foregroundStyle(.secondary)
            DialogFooter {
                if operation.busy {
                    Button("Cancel", role: .cancel, action: operation.cancel).keyboardShortcut(.cancelAction).modifier(DialogActionStyle()).disabled(operation.stopping)
                } else if operation.output == nil {
                    Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                }
            } actions: {
                if operation.output != nil && !operation.busy {
                    DialogDoneButton(action: close)
                } else if !operation.busy {
                    Button("Export Copy", action: operation.save).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                        .disabled(operation.source == nil || operation.includedCount == 0 || operation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.padding(20).frame(minWidth: 540, minHeight: 520)
            .onChange(of: operation.focusedPageID) { operation.updatePreview() }
    }
    private var selectionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Include pages").font(.callout).fontWeight(.medium)
                Button("All") { operation.includeAll(true) }.buttonStyle(.link)
                Button("None") { operation.includeAll(false) }.buttonStyle(.link)
                Spacer()
                Button("Reset", action: operation.reset).buttonStyle(.link).help("Restore original order, rotation and all pages")
            }
            HStack(spacing: 8) {
                TextField("Original pages, e.g. 1, 3–5", text: $operation.range).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Original page numbers to include").onSubmit { operation.applyRange() }
                Button("Apply", action: operation.applyRange).disabled(operation.range.isEmpty)
            }
        }
    }
    private var editor: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                  List(selection: $operation.focusedPageID) {
                    ForEach(operation.pages) { page in
                        HStack(spacing: 8) {
                            Toggle("Include page \(page.id + 1)", isOn: Binding(get: { page.included }, set: { operation.include($0, pageID: page.id) }))
                                .toggleStyle(.checkbox).labelsHidden()
                            VStack(spacing: 5) {
                                PageThumbnail(image: operation.thumbnails[page.id], quarterTurns: page.quarterTurns)
                                    .frame(width: 78, height: 66).opacity(page.included ? 1 : 0.45)
                                Text("Page \(page.id + 1)").font(.caption).foregroundStyle(page.included ? .primary : .secondary)
                            }
                        }.padding(.vertical, 5).tag(page.id).id(page.id)
                            .accessibilityElement(children: .contain).accessibilityLabel("Original page \(page.id + 1)")
                    }
                  }.listStyle(.inset).accessibilityLabel("Pages in export order")
                    .onChange(of: operation.focusedIndex) {
                        if let id = operation.focusedPageID { proxy.scrollTo(id) }
                    }
                }
                Divider()
                HStack(spacing: 16) {
                    Button("Move Page Up", systemImage: "arrow.up") { operation.move(-1) }.disabled(operation.focusedIndex == nil || operation.focusedIndex == 0)
                    Button("Move Page Down", systemImage: "arrow.down") { operation.move(1) }.disabled(operation.focusedIndex == nil || operation.focusedIndex == operation.pages.count - 1)
                }.labelStyle(.iconOnly).buttonStyle(.borderless).padding(10)
            }.frame(width: 150)
            Divider()
            VStack(spacing: 10) {
                if let page = operation.focusedPage {
                    HStack {
                        Text("Original page \(page.id + 1)").font(.callout).fontWeight(.medium)
                        Spacer()
                        Text(page.included ? "Included" : "Excluded").font(.caption).foregroundStyle(.secondary)
                    }
                    PageThumbnail(image: operation.detailPageID == page.id ? (operation.detailPreview ?? operation.thumbnails[page.id]) : operation.thumbnails[page.id], quarterTurns: page.quarterTurns)
                        .accessibilityLabel("Preview of original page \(page.id + 1), rotated \(page.quarterTurns * 90) degrees clockwise")
                    HStack(spacing: 16) {
                        Button("Rotate Page Left", systemImage: "rotate.left") { operation.rotate(-1) }
                        Text("\(page.quarterTurns * 90)°").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 34)
                        Button("Rotate Page Right", systemImage: "rotate.right") { operation.rotate(1) }
                    }.labelStyle(.iconOnly).buttonStyle(.borderless)
                } else {
                    Spacer()
                    Text(operation.busy ? "Preparing preview…" : "Choose a page to preview.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
            }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
    }
}

/// Fit the rotated bounding box, so landscape pages never clip or push the controls away.
private struct PageThumbnail: View {
    let image: NSImage
    let quarterTurns: Int
    var body: some View {
        GeometryReader { geometry in
            let size = image.size
            let odd = quarterTurns % 2 == 1
            let width = odd ? size.height : size.width, height = odd ? size.width : size.height
            let scale = min(geometry.size.width / max(width, 1), geometry.size.height / max(height, 1))
            Image(nsImage: image).resizable()
                .frame(width: size.width * scale, height: size.height * scale)
                .rotationEffect(.degrees(Double(quarterTurns * 90)))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}
