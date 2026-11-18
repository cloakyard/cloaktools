import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class QRCodeOperation: Identifiable {
    let id = UUID()
    var reading = false
    private var eventID = UUID()
    private var eventStamp = Date()
    private var filenames: [QRContentKind: String] = [:]
    var draft = QRContentDraft() {
        didSet {
            if draft.kind == .event && !draft.describesSameEvent(as: oldValue) {
                eventID = UUID()
                eventStamp = Date()
            }
            let next: String?
            let hint: String?
            do {
                next = try draft.content.encoded(eventID: eventID, createdAt: eventStamp)
                hint = nil
            } catch {
                next = nil
                hint = error.localizedDescription
            }
            let switched = draft.kind != oldValue.kind
            // AppKit can commit an unchanged field again when Create takes focus.
            // Keep the reviewed PNG if its exact bytes and content type still apply.
            let sameBytes = next?.utf8.elementsEqual((payload ?? "").utf8) ?? (payload == nil)
            guard switched || !sameBytes || hint != fieldHint else { return }
            invalidate()
            if switched {
                filenames[oldValue.kind] = name
                name = filenames[draft.kind] ?? draft.kind.defaultFilename
            }
            payload = next
            fieldHint = hint
        }
    }
    private(set) var payload: String?
    private(set) var fieldHint: String?
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
    var nameError: String? { do { try SafeOutput.validate(stem: name); return nil } catch { return error.localizedDescription } }
    func cancel() { task?.cancel(); task = nil; revision = UUID(); activity = nil }
    private func invalidate() { cancel(); prepared = nil; previewImage = nil; error = nil; copied = false; savedURL = nil }
    func rejectLargeInput() { error = QRCodeError.inputTooLarge.localizedDescription }
    func generate() {
        guard !busy, let input = payload else { return }
        invalidate(); let options = options
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
    init(operation: QRCodeOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "QR Code"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: QRCodeWorkspace(operation: operation, reader: reader, close: { [weak window] in window?.close() }))
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
    @Bindable var operation: QRCodeOperation
    let reader: QRCodeReadOperation
    let close: () -> Void
    var body: some View {
        if operation.reading { QRCodeReadView(operation: reader, reading: $operation.reading, close: close) }
        else { QRCodeView(operation: operation, reading: $operation.reading, close: close) }
    }
}
struct QRCodeHeading: View {
    @Binding var reading: Bool
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            DialogHeading(title: "QR code", subtitle: reading ? "Read an image and review its contents." : "Choose what someone will scan.", symbol: "qrcode")
            Spacer(minLength: 0)
            Picker("QR tool", selection: $reading) { Text("Create").tag(false); Text("Read").tag(true) }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }
}
struct QRCodeView: View {
    @State private var imageSettings = false
    @Bindable var operation: QRCodeOperation
    @Binding var reading: Bool
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QRCodeHeading(reading: $reading).disabled(operation.busy)
            Picker("Content", selection: $operation.draft.kind) {
                ForEach(QRContentKind.allCases) { Text($0.rawValue).tag($0) }
            }.fixedSize().disabled(operation.busy)
            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    QRContentForm(operation: operation).id(operation.draft.kind)
                        .padding(.trailing, 5).padding(.vertical, 3)
                }.scrollBounceBehavior(.basedOnSize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).disabled(operation.busy)
                VStack(spacing: 8) {
                    Text("Preview").font(.callout.weight(.medium))
                    ZStack {
                        if let image = operation.previewImage {
                            Color.white
                            Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                                .accessibilityLabel("\(operation.draft.kind.rawValue) QR code")
                        } else {
                            Color(nsColor: .controlBackgroundColor)
                            Image(systemName: "qrcode").font(.system(size: 42)).foregroundStyle(.tertiary)
                                .accessibilityLabel("QR preview is empty")
                        }
                    }
                    .aspectRatio(1, contentMode: .fit).frame(maxWidth: 245, maxHeight: 245)
                    .clipShape(.rect(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
                    if let result = operation.prepared {
                        Text("\(result.width) × \(result.width) px · PNG · \(result.png.count.formatted()) bytes")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity)
            }.frame(minHeight: 160, maxHeight: .infinity)
            if let hint = operation.fieldHint {
                Text(hint).font(.callout).foregroundStyle(.secondary)
            } else if let payload = operation.payload {
                Text("\(payload.utf8.count.formatted()) / 1,024 encoded bytes").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Image settings", isExpanded: $imageSettings) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Image size", selection: $operation.options.size) {
                        ForEach(QRImageSize.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("Error correction", selection: $operation.options.correction) {
                        ForEach(QRCorrection.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }.padding(.top, 5)
            }.modifier(DialogCard()).disabled(operation.busy)
            if operation.prepared != nil {
                HStack {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Filename without extension", text: $operation.name).textFieldStyle(.roundedBorder).accessibilityLabel("PNG filename")
                    Text(".png").font(.callout.monospaced()).foregroundStyle(.secondary)
                }.disabled(operation.busy)
            }
            VStack(alignment: .leading, spacing: 5) {
                if let url = operation.savedURL {
                    HStack {
                        Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill").lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                    }.font(.callout).foregroundStyle(.green)
                } else if operation.copied { Label("QR image copied", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                OperationFeedback(activity: operation.activity, error: operation.error ?? operation.nameError)
                Text(operation.draft.kind == .wifi && operation.draft.security != .open ? "Anyone with this code can read the Wi-Fi password." : "Anyone with the code can read its contents.")
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
                        Button("Create QR Code", action: operation.generate).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true)).disabled(operation.busy || operation.payload == nil)
                    }
                }
            }
        }.onExitCommand { if !operation.saving { close() } }
        .padding(20).frame(minWidth: 600, minHeight: 560)
    }
}
