import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class MarkdownDigestOperation: Identifiable {
    let id = UUID()
    var name = "File digest" { didSet { if !name.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    var selectedID: UUID? { didSet { if selectedID != oldValue { showDigest = false } } }
    var showDigest = false
    var onSaved: (() -> Void)?
    private(set) var files: [DigestFile] = []
    private(set) var prepared: PreparedMarkdownDigest?
    private(set) var activity: String?
    private(set) var error: String?
    private(set) var copied = false
    private(set) var savedURL: URL?
    private var task: Task<Void, Never>?
    private var revision = UUID()
    var busy: Bool { activity != nil }
    var saving: Bool { activity == "Saving digest…" }
    var selectedIndex: Int? { files.firstIndex { $0.id == selectedID } }
    var selectedFile: DigestFile? { selectedIndex.map { files[$0] } }
    var totalBytes: Int { files.reduce(0) { $0 + $1.byteCount } }
    var nameError: String? { do { try SafeOutput.validate(stem: name); return nil } catch { return error.localizedDescription } }
    func cancel() { task?.cancel(); task = nil; revision = UUID(); activity = nil }
    private func invalidate() { cancel(); prepared = nil; copied = false; savedURL = nil; error = nil; showDigest = false }
    func chooseFiles() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Choose text files for a digest"; panel.prompt = "Add Files"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.message = "Up to 32 UTF-8 files · 1 MiB each · 8 MiB total. Full contents are included; folders are not scanned."
        let revision = revision
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self, self.revision == revision else { return }
            let existing = self.files
            let urls = panel.urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            self.start("Capturing selected files…", work: { try MarkdownDigest.adding(urls, to: existing) }) { model, files in
                model.files = files; model.prepared = nil; model.savedURL = nil; model.copied = false
                model.selectedID = files.last?.id; model.showDigest = false
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func move(_ offset: Int) {
        guard !busy, let index = selectedIndex, files.indices.contains(index + offset) else { return }
        invalidate(); files.swapAt(index, index + offset)
    }
    func removeSelected() {
        guard !busy, let index = selectedIndex else { return }
        invalidate(); files.remove(at: index)
        selectedID = files.isEmpty ? nil : files[min(index, files.count - 1)].id
    }
    func generate() {
        guard !files.isEmpty, !busy else { return }
        invalidate(); let files = files, title = name
        start("Preparing digest…", work: { try MarkdownDigest.prepare(files, title: title) }) { model, result in
            model.prepared = result; model.showDigest = true
        }
    }
    func copy() {
        guard let prepared, !busy else { return }
        let item = NSPasteboardItem()
        guard item.setString(prepared.text, forType: .string) else { error = "macOS could not prepare the digest for copying."; return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return }
        copied = true; showDigest = true; error = nil
    }
    func save() {
        guard let prepared, !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Save Markdown digest"; panel.prompt = "Save Digest"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "Save \(prepared.title).md · \(prepared.fileCount) files · \(prepared.byteCount.formatted()) bytes. Existing files get a numbered copy."
        let revision = revision
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let folder = panel.url, let self, self.revision == revision else { return }
            self.start("Saving digest…", work: { try MarkdownDigest.save(prepared, in: folder) }) { model, url in model.savedURL = url; model.showDigest = true; model.onSaved?() }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func start<Value: Sendable>(_ activity: String, work: @escaping @Sendable () throws -> Value, finish: @escaping @MainActor (MarkdownDigestOperation, Value) -> Void) {
        cancel(); self.activity = activity; error = nil
        let revision = revision
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated, operation: work)
            do {
                let value = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, let self, self.revision == revision else { return }
                finish(self, value); self.activity = nil; self.task = nil
            } catch {
                guard !Task.isCancelled, let self, self.revision == revision else { return }
                self.error = error.localizedDescription; self.activity = nil; self.task = nil
            }
        }
    }
}

@MainActor
final class MarkdownDigestWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let operation: MarkdownDigestOperation
    init(operation: MarkdownDigestOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 650), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Markdown Digest"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: MarkdownDigestView(operation: operation, close: { [weak window] in window?.close() }))
        operation.onSaved = { [weak window] in window?.makeFirstResponder(nil) }
        window.contentMinSize = NSSize(width: 560, height: 600)
        window.setContentSize(NSSize(width: 640, height: 650)); window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !operation.saving }
    func windowWillClose(_ notification: Notification) { operation.cancel(); onClose?() }
}

struct MarkdownDigestView: View {
    @Bindable var operation: MarkdownDigestOperation
    let close: () -> Void
    private var dismissal: ReviewDismissButton {
        ReviewDismissButton(busy: operation.busy, saving: operation.saving, cancel: operation.cancel, close: close)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DialogHeading(title: "Markdown digest", subtitle: "Selected text files. One document.", symbol: "doc.text")
            HStack(spacing: 10) {
                Text("Name").foregroundStyle(.secondary)
                TextField("Digest name", text: $operation.name).textFieldStyle(.roundedBorder).labelsHidden()
                Text(".md").font(.callout.monospaced()).foregroundStyle(.secondary)
            }.disabled(operation.busy)
            fileList
            preview
            VStack(alignment: .leading, spacing: 5) {
                if let url = operation.savedURL {
                    HStack {
                        Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        ShowInFinderButton(url: url)
                    }.font(.callout).foregroundStyle(.green)
                } else if operation.copied { Label("Digest copied to clipboard", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                OperationFeedback(activity: operation.activity, error: operation.error ?? operation.nameError)
                Text("Full file contents are included. Review before sharing.").font(.callout).foregroundStyle(.secondary)
                Text("Local only · Captured files stay unchanged · No folder scanning").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DialogFooter {
                if operation.savedURL == nil {
                    dismissal
                }
            } actions: {
                if operation.savedURL != nil {
                    DialogDoneButton(action: close)
                } else if operation.prepared != nil {
                    Button(operation.copied ? "Copied" : "Copy Digest", action: operation.copy).modifier(DialogActionStyle()).disabled(operation.busy)
                    ReviewDefaultButton(title: "Save Digest…", action: operation.save).disabled(operation.busy)
                } else if operation.files.isEmpty {
                    ReviewDefaultButton(title: "Choose Files…", action: operation.chooseFiles).disabled(operation.busy)
                } else {
                    ReviewDefaultButton(title: "Preview Digest", action: operation.generate).disabled(operation.busy || operation.nameError != nil)
                }
            }
        }.onExitCommand(perform: dismissal.perform)
        .padding(20).frame(minWidth: 560, minHeight: 600)
    }
    private var fileList: some View {
        VStack(spacing: 0) {
            if operation.files.isEmpty {
                VStack(spacing: 6) {
                    Text("Choose notes, Markdown or source files").fontWeight(.medium)
                    Text("Up to 32 UTF-8 files · 1 MiB each · 8 MiB total").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).frame(height: 110)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $operation.selectedID) {
                        ForEach(Array(operation.files.enumerated()), id: \.element.id) { index, file in
                            HStack(spacing: 10) {
                                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name).lineLimit(1).truncationMode(.middle)
                                    Text(file.url.deletingLastPathComponent().lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text("\(file.byteCount.formatted()) bytes").font(.caption).foregroundStyle(.secondary)
                            }.tag(file.id).id(file.id).help(file.url.path)
                        }
                    }.listStyle(.inset).frame(height: 124).accessibilityLabel("Digest files in document order")
                        .onChange(of: operation.selectedIndex) { if let id = operation.selectedID { proxy.scrollTo(id) } }
                }
                Divider()
                HStack(spacing: 12) {
                    Button("Add Files…", systemImage: "plus", action: operation.chooseFiles).disabled(operation.files.count >= MarkdownDigest.maximumFiles)
                    Text("\(operation.files.count) files · \(operation.totalBytes.formatted()) bytes").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Move Up", systemImage: "arrow.up") { operation.move(-1) }.labelStyle(.iconOnly).disabled(operation.selectedIndex == nil || operation.selectedIndex == 0).help("Move selected file up")
                    Button("Move Down", systemImage: "arrow.down") { operation.move(1) }.labelStyle(.iconOnly).disabled(operation.selectedIndex == nil || operation.selectedIndex == operation.files.count - 1).help("Move selected file down")
                    Button("Remove File", systemImage: "minus", action: operation.removeSelected).labelStyle(.iconOnly).disabled(operation.selectedID == nil).help("Remove selected file")
                }.buttonStyle(.borderless).padding(10)
            }
        }.background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6))).disabled(operation.busy)
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Picker("Preview", selection: $operation.showDigest) {
                    Text("File").tag(false)
                    Text("Digest").tag(true).disabled(operation.prepared == nil)
                }.pickerStyle(.segmented).labelsHidden().fixedSize().disabled(operation.prepared == nil)
                Spacer()
                Text(operation.showDigest ? "\(operation.prepared?.byteCount.formatted() ?? "0") bytes · Markdown" : operation.selectedFile?.name ?? "Read-only preview")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            PlainTextEditor(text: .constant(operation.showDigest ? operation.prepared?.preview ?? "" : operation.selectedFile?.preview ?? ""), editable: false,
                            label: operation.showDigest ? "Markdown digest preview" : "Selected file preview", rejectLargeInput: {})
                .overlay(alignment: .topLeading) {
                    if operation.files.isEmpty {
                        Text("Choose files to inspect their contents here.").font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.tertiary).padding(12).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor)).clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6))).frame(minHeight: 120, maxHeight: .infinity)
            Text((operation.showDigest ? operation.prepared?.previewIsTruncated : operation.selectedFile?.previewIsTruncated) == true
                 ? "First 65,536 characters · Copy and Save include the full digest"
                 : operation.prepared == nil ? "Reorder or remove files, then preview the digest before saving." : "Save and Copy use the digest. File headings include names only.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxHeight: .infinity)
    }
}
