import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class PDFOperation: Identifiable {
    let id = UUID()
    let preferences: Preferences
    var items: [PDFAssemblyItem] = []
    var thumbnails: [UUID: NSImage] = [:]
    var selectedID: UUID?
    var destination: URL
    var name = "Combined"
    var stopping = false
    var cancellation: String?
    var preparing = false
    var running = false
    var busy: Bool { preparing || running }
    var error: String?
    var output: URL?
    private var preparation: Task<[PDFAssemblyItem], Error>?
    private var publication: Task<URL, Error>?
    private var useFirstSourceFolder: Bool
    var pageCount: Int { items.reduce(0) { $0 + $1.pageCount } }
    var selectedIndex: Int? { items.firstIndex { $0.id == selectedID } }

    init(files: [URL], preferences: Preferences) {
        self.preferences = preferences
        useFirstSourceFolder = files.isEmpty
        destination = files.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
        add(files)
    }
    func add(_ files: [URL]) {
        guard !busy, output == nil, !files.isEmpty else { return }
        preparing = true; error = nil; cancellation = nil
        let captured = items
        let worker = Task.detached(priority: .userInitiated) { try PDFAssembly.prepare(existing: captured, adding: files) }
        preparation = worker
        Task { [self] in
            do {
                let prepared = try await worker.value
                if worker.isCancelled { throw CancellationError() }
                if useFirstSourceFolder, let first = prepared.first {
                    destination = first.sourceURL.deletingLastPathComponent()
                    useFirstSourceFolder = false
                }
                items = prepared
                thumbnails = Dictionary(uniqueKeysWithValues: items.compactMap { item in NSImage(data: item.thumbnailPNG).map { (item.id, $0) } })
                selectedID = items.last?.id
            } catch is CancellationError { cancellation = "Cancelled. Your existing selection is unchanged." }
            catch { self.error = error.localizedDescription }
            preparing = false; preparation = nil; stopping = false
        }
    }
    func chooseFiles() {
        let panel = Self.filePanel()
        if panel.runModal() == .OK { add(panel.urls) }
    }
    static func filePanel() -> NSOpenPanel {
        let panel = NSOpenPanel(); panel.title = "Choose PDFs and images"; panel.prompt = "Add Files"
        panel.allowedContentTypes = PDFAssembly.inputTypes; panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.message = "Add up to 32 files. You can change their order before creating the PDF."
        return panel
    }
    func move(_ offset: Int) {
        guard !busy, output == nil, let index = selectedIndex, items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
    }
    func removeSelected() {
        guard !busy, output == nil, let index = selectedIndex else { return }
        thumbnails[items[index].id] = nil; items.remove(at: index)
        selectedID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
    }
    func chooseDestination() {
        let panel = NSOpenPanel(); panel.title = "Save the combined PDF in…"; panel.prompt = "Choose Folder"
        panel.directoryURL = destination; panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let folder = panel.url {
            destination = folder
            useFirstSourceFolder = false
        }
    }
    func start() {
        guard !busy, output == nil, !items.isEmpty else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        running = true; error = nil; cancellation = nil
        let items = items, destination = destination, name = name
        let worker = Task.detached(priority: .userInitiated) { try PDFAssembly.write(items, in: destination, name: name) }
        publication = worker
        Task { [self] in
            do {
                let url = try await worker.value; output = url
                if preferences.revealCreatedFile { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                if preferences.openAfterCreation { open() }
            } catch is CancellationError { cancellation = "Cancelled. No PDF was published." }
            catch { self.error = error.localizedDescription }
            running = false; publication = nil; stopping = false
        }
    }
    func open() {
        guard let output else { return }
        CreatedFileOpener.open(output, inPreview: true) { [weak self] in self?.error = $0 }
    }
    func cancel() { guard busy else { return }; stopping = true; preparation?.cancel(); publication?.cancel() }
}

@MainActor
final class PDFOperationWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    let operation: PDFOperation
    init(operation: PDFOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 504), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Assemble PDF"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: PDFOperationView(operation: operation, close: { [weak window] in window?.close() }))
        window.contentMinSize = NSSize(width: 440, height: 460)
        window.setContentSize(NSSize(width: 480, height: 504)); window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { operation.cancel(); return !operation.busy }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

struct PDFOperationView: View {
    @Bindable var operation: PDFOperation
    let close: () -> Void
    @FocusState private var nameFocused: Bool
    var body: some View {
        if operation.items.isEmpty && operation.output == nil && !operation.busy {
            VStack(alignment: .leading, spacing: 16) {
                ContentUnavailableView("Combine files into a PDF", systemImage: "doc.on.doc",
                    description: Text("Choose up to 32 PDFs or images. You can arrange their order before creating the PDF."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                OperationFeedback(cancellation: operation.cancellation, error: operation.error)
                DialogFooter {
                    Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                } actions: {
                    Button("Choose Files…", action: operation.chooseFiles)
                        .keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                }
            }.padding(20)
        } else {
            editor
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeading(title: operation.output == nil ? "Combine files into a PDF" : "PDF created", subtitle: operation.output == nil ? "Arrange the files in reading order, then choose a name and destination." : "Your combined document is ready.", symbol: "doc.on.doc")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if operation.output == nil {
                        HStack(spacing: 10) {
                            Text("Name").foregroundStyle(.secondary)
                            TextField("Name", text: $operation.name).textFieldStyle(.roundedBorder).focused($nameFocused).accessibilityLabel("PDF file name, without extension")
                            Text(".pdf").font(.callout.monospaced()).foregroundStyle(.secondary)
                        }.disabled(operation.busy)
                        VStack(spacing: 0) {
                            ScrollViewReader { proxy in
                            List(selection: $operation.selectedID) {
                                ForEach(Array(operation.items.enumerated()), id: \.element.id) { index, item in
                                    HStack(spacing: 10) {
                                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 16)
                                        if let image = operation.thumbnails[item.id] { Image(nsImage: image).resizable().scaledToFit().frame(width: 32, height: 40).accessibilityHidden(true) }
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.sourceURL.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                            Text(item.isImage ? "Image · A4 page" : "PDF · \(item.pageCount) \(item.pageCount == 1 ? "page" : "pages")").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.padding(.vertical, 3).tag(item.id).id(item.id).help(item.sourceURL.path)
                                }
                            }.listStyle(.inset).frame(height: 174).accessibilityLabel("PDF source files in page order")
                                .onChange(of: operation.selectedIndex) { if let id = operation.selectedID { proxy.scrollTo(id) } }
                            }
                            Divider()
                            HStack(spacing: 12) {
                                Button("Add Files…", systemImage: "plus", action: operation.chooseFiles).buttonStyle(.borderless)
                                Spacer()
                                Button("Move Up", systemImage: "arrow.up") { operation.move(-1) }.labelStyle(.iconOnly).disabled(operation.selectedIndex == nil || operation.selectedIndex == 0).help("Move selected file up")
                                Button("Move Down", systemImage: "arrow.down") { operation.move(1) }.labelStyle(.iconOnly).disabled(operation.selectedIndex == nil || operation.selectedIndex == operation.items.count - 1).help("Move selected file down")
                                Button("Remove File", systemImage: "minus", action: operation.removeSelected).labelStyle(.iconOnly).disabled(operation.selectedID == nil).help("Remove selected file")
                            }.buttonStyle(.borderless).padding(10)
                        }.background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.1)))
                            .disabled(operation.busy)
                        Text("\(operation.items.count) files · \(operation.pageCount) pages. Images fit A4; PDF pages keep their size.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let output = operation.output {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Created \(output.lastPathComponent)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("\(operation.pageCount) pages · \(operation.items.count) source files").foregroundStyle(.secondary)
                            Text(output.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack(spacing: 16) {
                                ShowInFinderButton(url: output)
                                Button("Open in Preview", action: operation.open).buttonStyle(.link)
                            }
                        }.modifier(DialogCard())
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize)
            if operation.output == nil { DestinationRow(folder: operation.destination, change: operation.chooseDestination).disabled(operation.busy) }
            OperationFeedback(activity: operation.busy ? (operation.preparing ? "Preparing files…" : "Assembling PDF…") : nil,
                              stopping: operation.stopping, cancellation: operation.cancellation, error: operation.error)
            if !operation.busy && operation.output == nil { Text("Originals stay unchanged.").font(.caption).foregroundStyle(.secondary) }
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
                    Button("Create PDF", action: operation.start).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true)).disabled(operation.items.isEmpty || operation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.padding(20).frame(minWidth: 440, minHeight: 460)
            .onAppear { nameFocused = true }
    }
}
