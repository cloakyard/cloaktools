import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class SampleFileOperation: Identifiable {
    enum Activity {
        case generating, saving, copying
        var title: String { switch self { case .generating: "Generating preview…"; case .saving: "Saving file…"; case .copying: "Preparing text to copy…" } }
    }
    let id = UUID()
    var format: SampleFileFormat = .json {
        didSet {
            guard format != oldValue else { return }
            if ["Sample data", "Sample file"].contains(name) { name = format.usesRecords ? "Sample data" : "Sample file" }
            invalidate()
        }
    }
    var records = "10" { didSet { if !records.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    var size = "1" { didSet { if !size.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    var unit: SampleByteUnit = .kibibytes { didSet { if unit != oldValue { invalidate() } } }
    var name = "Sample data" { didSet { if !name.utf8.elementsEqual(oldValue.utf8) { savedURL = nil; error = nil } } }
    var onSaved: (() -> Void)?
    private(set) var prepared: PreparedSampleFile?
    private(set) var activity: Activity?
    private(set) var error: String?
    private(set) var copied = false
    private(set) var savedURL: URL?
    private var task: Task<Void, Never>?
    private var revision = UUID()
    var busy: Bool { activity != nil }
    var saving: Bool { activity == .saving }
    var inputError: String? { do { _ = try request(); return nil } catch { return error.localizedDescription } }
    var nameError: String? { do { try SafeOutput.validate(stem: name); return nil } catch { return error.localizedDescription } }

    private func request() throws -> SampleFileRequest {
        try SampleFileRequest(format: format, recordsText: records, sizeText: size, unit: unit)
    }
    func cancel() { task?.cancel(); task = nil; revision = UUID(); activity = nil }
    private func invalidate() { cancel(); prepared = nil; error = nil; copied = false; savedURL = nil }
    func generate() {
        invalidate()
        do {
            let request = try request()
            start(.generating, work: { try SampleFiles.generate(request) }) { model, output in model.prepared = output }
        } catch { self.error = error.localizedDescription }
    }
    func copy() {
        guard let prepared, prepared.canCopyText, !busy else { return }
        start(.copying, work: { String(decoding: prepared.data, as: UTF8.self) }) { model, text in
            let item = NSPasteboardItem()
            guard item.setString(text, forType: .string) else { model.error = "macOS could not prepare the text for copying."; return }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.writeObjects([item]) else { model.error = "macOS could not write to the clipboard. Try copying again."; return }
            model.copied = true
        }
    }
    func save() {
        guard let prepared, !busy else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.title = "Save sample file"; panel.prompt = "Save File"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "Save \(name).\(prepared.fileExtension) · \(prepared.data.count.formatted()) bytes. Existing files get a numbered copy."
        let revision = revision, name = name
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let folder = panel.url, let self, self.revision == revision else { return }
            self.start(.saving, work: { try SampleFiles.save(prepared, in: folder, stem: name) }) { model, url in model.savedURL = url; model.onSaved?() }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func start<Value: Sendable>(_ activity: Activity, work: @escaping @Sendable () throws -> Value, finish: @escaping @MainActor (SampleFileOperation, Value) -> Void) {
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
final class SampleFileWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let operation: SampleFileOperation
    init(operation: SampleFileOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 570), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Sample Files"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: SampleFileView(operation: operation, close: { [weak window] in window?.close() }))
        operation.onSaved = { [weak window] in window?.makeFirstResponder(nil) }
        window.contentMinSize = NSSize(width: 500, height: 540)
        window.setContentSize(NSSize(width: 560, height: 570)); window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !operation.saving }
    func windowWillClose(_ notification: Notification) { operation.cancel(); onClose?() }
}

struct SampleFileView: View {
    @Bindable var operation: SampleFileOperation
    let close: () -> Void
    var dismissal: ReviewDismissButton {
        ReviewDismissButton(busy: operation.busy, saving: operation.saving, cancel: operation.cancel, close: close)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Sample files", subtitle: "Synthetic data for trying things out.", symbol: "doc.badge.gearshape")
            Picker("File format", selection: $operation.format) {
                ForEach(SampleFileFormat.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().disabled(operation.busy)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if operation.format.usesRecords {
                        Text("Records").foregroundStyle(.secondary)
                        TextField("Record count", text: $operation.records).textFieldStyle(.roundedBorder).labelsHidden().frame(width: 100)
                        Spacer()
                        Text("1–10,000 records").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Size").foregroundStyle(.secondary)
                        TextField("File size", text: $operation.size).textFieldStyle(.roundedBorder).labelsHidden().frame(width: 100)
                        Picker("Size unit", selection: $operation.unit) {
                            ForEach(SampleByteUnit.allCases) { Text($0.title).tag($0) }
                        }.labelsHidden().frame(width: 100)
                        Spacer()
                        Text("Up to 32 MiB").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(operation.format.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.modifier(DialogCard()).disabled(operation.busy)
            HStack(spacing: 10) {
                Text("Name").foregroundStyle(.secondary)
                TextField("Filename without extension", text: $operation.name).textFieldStyle(.roundedBorder).labelsHidden()
                Text(".\(operation.format.fileExtension)").font(.callout.monospaced()).foregroundStyle(.secondary)
            }.disabled(operation.busy)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Preview").fontWeight(.medium)
                    Spacer()
                    if let prepared = operation.prepared { Text(prepared.summary).foregroundStyle(.secondary) }
                }.font(.caption)
                PlainTextEditor(text: .constant(operation.prepared?.preview ?? ""), editable: false, label: "Sample file preview", rejectLargeInput: {})
                    .overlay(alignment: .topLeading) {
                        if operation.prepared == nil {
                            Text("Generate to preview your sample file.")
                                .font(.system(.callout, design: .monospaced)).foregroundStyle(.tertiary)
                                .padding(12).allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .background(Color(nsColor: .textBackgroundColor)).clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
                    .frame(minHeight: 110, maxHeight: .infinity)
                Text(operation.prepared?.previewDetail ?? "Nothing is written until you choose Save File.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                if let url = operation.savedURL {
                    HStack {
                        Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        ShowInFinderButton(url: url)
                    }.font(.callout).foregroundStyle(.green)
                } else if operation.copied { Label("Copied to clipboard", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                OperationFeedback(activity: operation.activity?.title, error: operation.error ?? operation.inputError ?? (operation.prepared == nil ? nil : operation.nameError))
                Text("Local only · No real personal data · Same settings, same content")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DialogFooter {
                if operation.savedURL == nil {
                    dismissal
                }
            } actions: {
                if operation.savedURL != nil {
                    DialogDoneButton(action: close)
                } else if let prepared = operation.prepared {
                    if prepared.canCopyText {
                        Button(operation.copied ? "Copied" : "Copy Text", action: operation.copy).modifier(DialogActionStyle()).disabled(operation.busy)
                            .help("Copy the full text, including content beyond the preview")
                    }
                    ReviewDefaultButton(title: "Save File…", action: operation.save).disabled(operation.busy || operation.nameError != nil)
                } else {
                    ReviewDefaultButton(title: "Generate", action: operation.generate).disabled(operation.busy || operation.inputError != nil)
                }
            }
        }.onExitCommand(perform: dismissal.perform)
        .padding(20).frame(minWidth: 500, minHeight: 540)
    }
}
