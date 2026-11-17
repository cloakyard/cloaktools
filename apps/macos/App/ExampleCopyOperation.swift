import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class ExampleCopyOperation: Identifiable {
    let id = UUID()
    var showSource = false
    var name = "Configuration example" { didSet { if !name.utf8.elementsEqual(oldValue.utf8) { savedURL = nil; error = nil } } }
    var onSaved: (() -> Void)?
    private(set) var prepared: PreparedExampleCopy?
    private(set) var sourceName = ""
    private(set) var activity: String?
    private(set) var error: String?
    private(set) var savedURL: URL?
    private(set) var copied = false
    private var task: Task<Void, Never>?
    private var revision = UUID()
    var busy: Bool { activity != nil }
    var saving: Bool { activity == "Saving example…" }
    var nameError: String? { do { try SafeOutput.validate(stem: name); return nil } catch { return error.localizedDescription } }
    func cancel() { task?.cancel(); task = nil; revision = UUID(); activity = nil }
    func chooseFile() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Choose a file for an example"; panel.prompt = "Prepare Example"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.message = "JSON or .env files · UTF-8 · Up to 1 MiB. Values become placeholders; the original stays unchanged."
        let revision = revision
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self, self.revision == revision else { return }
            self.prepared = nil; self.savedURL = nil; self.copied = false; self.showSource = false
            self.sourceName = url.lastPathComponent
            self.start("Preparing example…", work: { try ExampleCopy.capture(url) }) { model, prepared in
                model.prepared = prepared; model.name = prepared.suggestedName
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func copy() {
        guard let prepared, !busy else { return }
        let item = NSPasteboardItem()
        guard item.setString(prepared.text, forType: .string) else { error = "macOS could not prepare the example for copying."; return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return }
        copied = true; showSource = false; error = nil
    }
    func save() {
        guard let prepared, !busy else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.title = "Save example copy"; panel.prompt = "Save Example"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "Save \(name).\(prepared.format.fileExtension). Original keys or variable names are kept. Existing files get a numbered copy."
        let revision = revision, name = name
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let folder = panel.url, let self, self.revision == revision else { return }
            self.start("Saving example…", work: { try ExampleCopy.save(prepared, in: folder, stem: name) }) { model, url in
                model.savedURL = url; model.showSource = false; model.onSaved?()
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func start<Value: Sendable>(_ activity: String, work: @escaping @Sendable () throws -> Value, finish: @escaping @MainActor (ExampleCopyOperation, Value) -> Void) {
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
final class ExampleCopyWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let operation: ExampleCopyOperation
    init(operation: ExampleCopyOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Example Copy"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: ExampleCopyView(operation: operation, close: { [weak window] in window?.close() }))
        operation.onSaved = { [weak window] in window?.makeFirstResponder(nil) }
        window.contentMinSize = NSSize(width: 520, height: 560)
        window.setContentSize(NSSize(width: 600, height: 600)); window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !operation.saving }
    func windowWillClose(_ notification: Notification) { operation.cancel(); onClose?() }
}

struct ExampleCopyView: View {
    @Bindable var operation: ExampleCopyOperation
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Example copy", subtitle: "Make a reusable example from a configuration.", symbol: "doc.on.doc")
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.title2).foregroundStyle(.teal).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(operation.sourceName.isEmpty ? "Choose a JSON or .env file" : operation.sourceName).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    Text(operation.prepared.map { "\($0.format.title) · \($0.valueCount.formatted()) values · Original unchanged" } ?? "UTF-8 · Up to 1 MiB · Hidden .env files are shown")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if !operation.sourceName.isEmpty { Button("Change…", action: operation.chooseFile).disabled(operation.busy) }
            }.modifier(DialogCard())
            if let prepared = operation.prepared {
                Text(prepared.format.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Filename without extension", text: $operation.name).textFieldStyle(.roundedBorder).labelsHidden()
                    Text(".\(prepared.format.fileExtension)").font(.callout.monospaced()).foregroundStyle(.secondary)
                }.disabled(operation.busy)
            }
            preview
            VStack(alignment: .leading, spacing: 6) {
                if let url = operation.savedURL {
                    HStack {
                        Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                    }.font(.callout).foregroundStyle(.green)
                } else if operation.copied { Label("Example copied to clipboard", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                OperationFeedback(activity: operation.activity, error: operation.error ?? (operation.prepared == nil ? nil : operation.nameError))
                Text(operation.prepared?.format.reviewNote ?? "Values become placeholders. Keys and variable names are kept.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Local only · No history · Nothing runs or saves automatically")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if operation.savedURL == nil {
                        Button(operation.busy ? "Cancel" : "Close", action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle()).disabled(operation.saving)
                    }
                    Spacer(minLength: 0)
                    if operation.savedURL != nil {
                        Button("Done", action: close).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    } else if operation.prepared != nil {
                        Button(operation.copied ? "Copied" : "Copy Example", action: operation.copy).modifier(DialogActionStyle()).disabled(operation.busy)
                            .help("Copies the full example, even while viewing Source")
                        Button("Save Example…", action: operation.save).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true))
                            .disabled(operation.busy || operation.nameError != nil)
                    } else {
                        Button("Choose File…", action: operation.chooseFile).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true)).disabled(operation.busy)
                    }
                }
            }
        }.onExitCommand { if !operation.saving { close() } }
        .padding(20).frame(minWidth: 520, minHeight: 560)
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Picker("Preview", selection: $operation.showSource) {
                    Text("Example").tag(false); Text("Source").tag(true)
                }.pickerStyle(.segmented).labelsHidden().fixedSize().disabled(operation.prepared == nil)
                Spacer()
                if let prepared = operation.prepared {
                    Text("\((operation.showSource ? prepared.sourceText : prepared.text).utf8.count.formatted()) bytes · Read-only").font(.caption).foregroundStyle(.secondary)
                }
            }
            PlainTextEditor(text: .constant(operation.showSource ? operation.prepared?.sourcePreview ?? "" : operation.prepared?.examplePreview ?? ""), editable: false,
                            label: operation.showSource ? "Original source preview" : "Example copy preview", rejectLargeInput: {})
                .overlay(alignment: .topLeading) {
                    if operation.prepared == nil {
                        Text("Choose a file to preview its example.").font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.tertiary).padding(12).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor)).clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6))).frame(minHeight: 130, maxHeight: .infinity)
            Text(operation.prepared?.previewIsTruncated(source: operation.showSource) == true ? "First 65,536 characters · Saving and copying include the full example" : "Compare with Source. Save and Copy always use the example.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxHeight: .infinity)
    }
}
