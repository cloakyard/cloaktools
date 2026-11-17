import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class TextCleanupOperation: Identifiable {
    let id = UUID()
    var input = "" { didSet { if !input.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    var options = TextCleanupOptions() { didSet { if options != oldValue { invalidate() } } }
    var name = "Cleaned text" { didSet { if !name.utf8.elementsEqual(oldValue.utf8) { savedURL = nil; error = nil } } }
    var showResult = false
    var onSaved: (() -> Void)?
    private(set) var prepared: PreparedTextCleanup?
    private(set) var activity: String?
    private(set) var error: String?
    private(set) var copied = false
    private(set) var savedURL: URL?
    private var task: Task<Void, Never>?
    private var revision = UUID()
    var busy: Bool { activity != nil }
    var saving: Bool { activity == "Saving text…" }
    var nameError: String? { do { try SafeOutput.validate(stem: name); return nil } catch { return error.localizedDescription } }
    func cancel() { task?.cancel(); task = nil; revision = UUID(); activity = nil }
    private func invalidate() { cancel(); prepared = nil; error = nil; copied = false; savedURL = nil; showResult = false }
    func rejectLargeInput() { invalidate(); error = TextCleanupError.inputTooLarge.localizedDescription }
    func preview() {
        guard !busy, !input.isEmpty else { return }
        invalidate(); let input = input, options = options
        start("Preparing text…", work: { try TextCleanup.prepare(input, options: options) }) { model, result in
            model.prepared = result; model.showResult = true
        }
    }
    func copy() {
        guard let prepared, !prepared.text.isEmpty, !busy else { return }
        let item = NSPasteboardItem()
        guard item.setString(prepared.text, forType: .string) else { error = "macOS could not prepare the text for copying."; return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return }
        copied = true; showResult = true; error = nil
    }
    func save() {
        guard let prepared, !busy else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.title = "Save cleaned text"; panel.prompt = "Save Text"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "Save \(name).txt · \(prepared.byteCount.formatted()) bytes. Existing files get a numbered copy."
        let revision = revision, name = name
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let folder = panel.url, let self, self.revision == revision else { return }
            self.start("Saving text…", work: { try TextCleanup.save(prepared, in: folder, stem: name) }) { model, url in
                model.savedURL = url; model.showResult = true; model.onSaved?()
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func start<Value: Sendable>(_ activity: String, work: @escaping @Sendable () throws -> Value, finish: @escaping @MainActor (TextCleanupOperation, Value) -> Void) {
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
final class TextCleanupWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let operation: TextCleanupOperation
    init(operation: TextCleanupOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Text Cleanup"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: TextCleanupView(operation: operation, close: { [weak window] in window?.close() }))
        operation.onSaved = { [weak window] in window?.makeFirstResponder(nil) }
        window.contentMinSize = NSSize(width: 540, height: 570); window.setContentSize(NSSize(width: 600, height: 620))
        window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !operation.saving }
    func windowWillClose(_ notification: Notification) { operation.cancel(); onClose?() }
}

struct TextCleanupView: View {
    @Bindable var operation: TextCleanupOperation
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DialogHeading(title: "Text cleanup", subtitle: "Tidy the spacing. Keep your words.", symbol: "text.alignleft")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    Toggle("Trim line ends", isOn: $operation.options.trimLineEnds)
                    Toggle("Trim line starts", isOn: $operation.options.trimLineStarts)
                    Spacer(minLength: 0)
                }.toggleStyle(.checkbox)
                Toggle("Collapse spaces & tabs", isOn: $operation.options.collapseSpaces).toggleStyle(.checkbox)
                    .help("Replace each run of ordinary spaces or tabs with one space")
                HStack {
                    Text("Empty lines").font(.callout).foregroundStyle(.secondary)
                    Picker("Empty lines", selection: $operation.options.emptyLines) {
                        ForEach(EmptyLinePolicy.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                        .help("Keep one retains the first line in each run of empty lines. Only ordinary spaces and tabs count as empty.")
                }
            }.modifier(DialogCard()).disabled(operation.busy)
            editor
            if operation.prepared != nil {
                HStack {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Filename without extension", text: $operation.name).textFieldStyle(.roundedBorder).labelsHidden()
                    Text(".txt").font(.callout.monospaced()).foregroundStyle(.secondary)
                }.disabled(operation.busy)
            }
            VStack(alignment: .leading, spacing: 5) {
                if let url = operation.savedURL {
                    HStack {
                        Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill").lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                    }.font(.callout).foregroundStyle(.green)
                } else if operation.copied { Label("Result copied to clipboard", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                else if let result = operation.prepared {
                    Label(result.changedLines == 0 ? "No changes needed" : "\(result.changedLines.formatted()) \(result.changedLines == 1 ? "line changed" : "lines changed") · \(result.removedLines.formatted()) removed",
                          systemImage: result.changedLines == 0 ? "checkmark.circle" : "text.badge.checkmark").font(.callout).foregroundStyle(.secondary)
                }
                OperationFeedback(activity: operation.activity, error: operation.error ?? (operation.prepared == nil ? nil : operation.nameError))
                Text("Only ordinary spaces and tabs are cleaned. Kept line endings stay unchanged.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Local only · Up to 1 MiB · No history or automatic clipboard access")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if operation.savedURL == nil {
                        Button(operation.busy ? "Cancel" : "Close", action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle()).disabled(operation.saving)
                    }
                    Spacer(minLength: 0)
                    if operation.savedURL != nil {
                        Button("Done", action: close).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    } else if let result = operation.prepared {
                        Button(operation.copied ? "Copied" : "Copy Result", action: operation.copy).modifier(DialogActionStyle()).disabled(operation.busy || result.text.isEmpty)
                            .help("Copy the complete cleaned result, including text beyond the preview")
                        Button("Save Text…", action: operation.save).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true))
                            .disabled(operation.busy || operation.nameError != nil)
                    } else {
                        Button("Preview Changes", action: operation.preview).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true))
                            .disabled(operation.busy || operation.input.isEmpty)
                    }
                }
            }
        }.onExitCommand { if !operation.saving { close() } }
        .padding(20).frame(minWidth: 540, minHeight: 570)
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Picker("Text view", selection: $operation.showResult) { Text("Input").tag(false); Text("Result").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().disabled(operation.prepared == nil || operation.busy)
                Spacer(minLength: 4)
                Text("\((operation.showResult ? operation.prepared?.byteCount ?? 0 : operation.input.utf8.count).formatted()) bytes")
                    .font(.caption).foregroundStyle(.secondary)
                if !operation.showResult {
                    if operation.input.isEmpty {
                        Button("Try Example") { operation.input = "  A little   extra space.  \n\n\n\tA second line.\t\n" }.buttonStyle(.link).font(.caption).disabled(operation.busy)
                    } else {
                        Button("Clear") { operation.input = "" }.buttonStyle(.link).font(.caption).disabled(operation.busy)
                    }
                }
            }
            PlainTextEditor(text: operation.showResult ? .constant(operation.prepared?.preview ?? "") : $operation.input,
                            editable: !operation.showResult && !operation.busy, label: operation.showResult ? "Cleaned text preview" : "Text cleanup input",
                            rejectLargeInput: operation.rejectLargeInput, maximumInputBytes: TextCleanup.maximumInputBytes)
                .overlay(alignment: .topLeading) {
                    if operation.showResult ? operation.prepared?.text.isEmpty == true : operation.input.isEmpty {
                        Text(operation.showResult ? "The cleaned result is empty. You can save a blank text file." : "Paste or type text here, then preview your changes.")
                            .font(.system(.callout, design: .monospaced)).foregroundStyle(.tertiary).padding(12).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor)).clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6))).frame(minHeight: 130, maxHeight: .infinity)
            Text(operation.showResult && operation.prepared?.previewIsTruncated == true
                 ? "First 65,536 characters · Copy and Save include the full result"
                 : operation.prepared == nil ? "Your input stays intact. Preview before copying or saving." : "Compare with Input. Copy and Save always use the cleaned result.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxHeight: .infinity)
    }
}
