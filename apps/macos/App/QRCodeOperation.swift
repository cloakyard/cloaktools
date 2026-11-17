import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class QRCodeOperation: Identifiable {
    let id = UUID()
    var input = "" { didSet { if !input.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    var options = QRCodeOptions() { didSet { if options != oldValue { invalidate() } } }
    var name = "QR code" { didSet { if !name.utf8.elementsEqual(oldValue.utf8) { savedURL = nil; error = nil } } }
    var onSaved: (() -> Void)?
    private(set) var prepared: PreparedQRCode?
    private(set) var previewImage: NSImage?
    private(set) var activity: String?
    private(set) var error: String?
    private(set) var copied = false
    private(set) var savedURL: URL?
    private var task: Task<Void, Never>?
    private var revision = UUID()
    var busy: Bool { activity != nil }
    var saving: Bool { activity == "Saving QR code…" }
    var hasInput: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var nameError: String? { do { try SafeOutput.validate(stem: name); return nil } catch { return error.localizedDescription } }
    func cancel() { task?.cancel(); task = nil; revision = UUID(); activity = nil }
    private func invalidate() { cancel(); prepared = nil; previewImage = nil; error = nil; copied = false; savedURL = nil }
    func rejectLargeInput() { error = QRCodeError.inputTooLarge.localizedDescription }
    func generate() {
        guard !busy, hasInput else { return }
        invalidate(); let input = input, options = options
        start("Creating QR code…", work: { try QRCodeCreation.prepare(input, options: options) }) { model, result in
            model.prepared = result; model.previewImage = NSImage(data: result.png)
        }
    }
    func copyImage() {
        guard !busy, let prepared else { return }
        let item = NSPasteboardItem()
        guard item.setData(prepared.png, forType: .png) else { error = "macOS could not prepare the image for copying."; return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return }
        copied = true; error = nil
    }
    func save() {
        guard !busy, let prepared else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.title = "Save QR code"; panel.prompt = "Save PNG"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "Save \(name).png · \(prepared.width) × \(prepared.width) pixels. Existing files get a numbered copy."
        let revision = revision, name = name
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let folder = panel.url, let self, self.revision == revision else { return }
            self.start("Saving QR code…", work: { try QRCodeCreation.save(prepared, in: folder, stem: name) }) { model, url in
                model.savedURL = url; model.onSaved?()
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func start<Value: Sendable>(_ activity: String, work: @escaping @Sendable () throws -> Value, finish: @escaping @MainActor (QRCodeOperation, Value) -> Void) {
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
final class QRCodeWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let operation: QRCodeOperation
    private let reader = QRCodeReadOperation()
    init(operation: QRCodeOperation, reading: Bool = false) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "QR Code"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: QRCodeWorkspace(operation: operation, reader: reader, reading: reading, close: { [weak window] in window?.close() }))
        operation.onSaved = { [weak window] in window?.makeFirstResponder(nil) }
        reader.onSaved = { [weak window] in window?.makeFirstResponder(nil) }
        window.contentMinSize = NSSize(width: 600, height: 560); window.setContentSize(NSSize(width: 660, height: 600))
        window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !operation.saving && !reader.saving }
    func windowWillClose(_ notification: Notification) { operation.cancel(); reader.cancel(); onClose?() }
}

struct QRCodeWorkspace: View {
    let operation: QRCodeOperation
    let reader: QRCodeReadOperation
    @State var reading: Bool
    let close: () -> Void
    var body: some View {
        if reading { QRCodeReadView(operation: reader, reading: $reading, close: close) }
        else { QRCodeView(operation: operation, reading: $reading, close: close) }
    }
}
struct QRCodeHeading: View {
    @Binding var reading: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DialogHeading(title: "QR code", subtitle: reading ? "Read an image. Review its contents." : "A little square. Ready to share.", symbol: "qrcode")
            Spacer(minLength: 0)
            Picker("QR tool", selection: $reading) { Text("Create").tag(false); Text("Read").tag(true) }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }
}
struct QRCodeView: View {
    @Bindable var operation: QRCodeOperation
    @Binding var reading: Bool
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QRCodeHeading(reading: $reading).disabled(operation.busy)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Text or link").font(.callout.weight(.medium))
                        Spacer(minLength: 4)
                        Button(operation.input.isEmpty ? "Try Example" : "Clear") {
                            operation.input = operation.input.isEmpty ? "https://example.com/" : ""
                        }.buttonStyle(.link).font(.caption).disabled(operation.busy)
                    }
                    PlainTextEditor(text: $operation.input, editable: !operation.busy, label: "QR code text or link", rejectLargeInput: operation.rejectLargeInput, maximumInputBytes: QRCodeCreation.maximumInputBytes)
                        .overlay(alignment: .topLeading) {
                            if operation.input.isEmpty {
                                Text("Paste or type what you want to share.").font(.system(.callout, design: .monospaced)).foregroundStyle(.tertiary).padding(12).allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                        .background(Color(nsColor: .textBackgroundColor)).clipShape(.rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
                    Text("\(operation.input.utf8.count.formatted()) / 1,024 bytes · Exact text is encoded")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview").font(.callout.weight(.medium))
                    ZStack {
                        if let image = operation.previewImage {
                            Color.white
                            Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                                .accessibilityLabel("Generated QR code. Encodes the text shown beside it.")
                        } else {
                            Color(nsColor: .controlBackgroundColor)
                            VStack(spacing: 10) {
                                Image(systemName: "qrcode").font(.system(size: 38)).foregroundStyle(.tertiary).accessibilityHidden(true)
                                Text("Your code appears here").font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }.clipShape(.rect(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
                    Text(operation.prepared.map { "\($0.width) × \($0.width) px · PNG · \($0.png.count.formatted()) bytes" } ?? "Black on white · A clear border for scanning")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(minHeight: 210, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Image size").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Picker("Image size", selection: $operation.options.size) { ForEach(QRImageSize.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                }
                HStack {
                    Text("Error correction").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    Picker("Error correction", selection: $operation.options.correction) { ForEach(QRCorrection.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).labelsHidden()
                }
                Text("High tolerates more damage, but makes a denser code.").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard()).disabled(operation.busy)
            HStack {
                Text("Name").foregroundStyle(.secondary)
                TextField("Filename without extension", text: $operation.name).textFieldStyle(.roundedBorder).labelsHidden()
                Text(".png").font(.callout.monospaced()).foregroundStyle(.secondary)
            }.disabled(operation.busy)
            VStack(alignment: .leading, spacing: 5) {
                if let url = operation.savedURL {
                    HStack {
                        Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill").lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                    }.font(.callout).foregroundStyle(.green)
                } else if operation.copied { Label("QR image copied", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                OperationFeedback(activity: operation.activity, error: operation.error ?? operation.nameError)
                Text("Local only · Links aren't opened · Anyone can read a shared code")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let result = operation.prepared, result.inputByteCount > 512 {
                    Text("Dense code · Check it with your scanner before sharing.").font(.caption).foregroundStyle(.secondary)
                }
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if operation.savedURL == nil { Button(operation.busy ? "Cancel" : "Close", action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle()).disabled(operation.saving) }
                    Spacer(minLength: 0)
                    if operation.savedURL != nil {
                        Button("Done", action: close).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    } else if operation.prepared != nil {
                        Button(operation.copied ? "Copied" : "Copy Image", action: operation.copyImage).modifier(DialogActionStyle()).disabled(operation.busy)
                        Button("Save PNG…", action: operation.save).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true)).disabled(operation.busy || operation.nameError != nil)
                    } else {
                        Button("Create QR Code", action: operation.generate).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true)).disabled(operation.busy || !operation.hasInput)
                    }
                }
            }
        }.onExitCommand { if !operation.saving { close() } }
        .padding(20).frame(minWidth: 600, minHeight: 560)
    }
}
