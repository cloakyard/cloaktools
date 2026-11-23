import AppKit
import SwiftUI
import CloakToolsCore

private extension QRReadFileFormat {
    var suggestedName: String {
        switch self { case .text: "QR text"; case .vCard: "Contact card"; case .calendar: "Calendar event" }
    }
}

@MainActor @Observable
final class QRCodeReadOperation {
    var name = "QR text" { didSet { if !name.utf8.elementsEqual(oldValue.utf8) { savedURL = nil; error = nil } } }
    var selectedID: Int? {
        didSet {
            if selectedID != oldValue {
                savedURL = nil; copied = false; error = nil; revealsWiFi = false
                format = .text
            }
        }
    }
    var format: QRReadFileFormat = .text {
        didSet {
            guard format != oldValue else { return }
            if name == oldValue.suggestedName { name = format.suggestedName }
            savedURL = nil
            error = nil
        }
    }
    var saveTitle: String {
        switch format { case .text: "Save Text"; case .vCard: "Save vCard"; case .calendar: "Save Calendar File" }
    }
    var revealsWiFi = false
    var onSaved: (() -> Void)?
    private(set) var prepared: PreparedQRReading?
    private(set) var previewImage: NSImage?
    private(set) var sourceName = ""
    private(set) var activity: String?
    private(set) var error: String?
    private(set) var savedURL: URL?
    private(set) var copied = false
    private var task: Task<Void, Never>?
    private var revision = UUID()
    var busy: Bool { activity != nil }
    var saving: Bool { activity == "Saving decoded text…" }
    var selectedCode: ReadQRCode? { prepared?.codes.first { $0.id == selectedID } }
    var contentKind: QRContentKind? { selectedCode?.text.map(QRContentKind.recognizing) }
    var concealsWiFi: Bool { contentKind == .wifi && !revealsWiFi }
    var nameError: String? { do { try SafeOutput.validate(stem: name); return nil } catch { return error.localizedDescription } }
    func cancel() { task?.cancel(); task = nil; revision = UUID(); activity = nil }
    func chooseImage() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Read QR codes from an image"; panel.prompt = "Read Image"
        panel.allowedContentTypes = QRCodeReading.inputTypes; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "One still image, up to 10 MiB and 40 megapixels. Links are never opened."
        let revision = revision
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self, self.revision == revision else { return }
            self.read(url)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func read(_ url: URL) {
        guard !saving else { return }
        cancel(); prepared = nil; previewImage = nil; selectedID = nil
        savedURL = nil; copied = false; sourceName = url.lastPathComponent
        start("Reading QR codes…", work: { try QRCodeReading.read(url) }) { model, result in
            model.prepared = result; model.previewImage = NSImage(data: result.thumbnailPNG); model.selectedID = result.codes.first?.id
        }
    }
    func copyText() {
        guard !busy, let text = selectedCode?.text, !text.isEmpty else { return }
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else { error = "macOS could not prepare the text for copying."; return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return }
        copied = true; error = nil
    }
    func save() {
        guard !busy, let code = selectedCode, code.text != nil else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.title = saveTitle; panel.prompt = saveTitle
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "Save \(name).\(format.rawValue) · Code \(code.id + 1) · \(code.text?.utf8.count ?? 0) bytes. Existing files get a numbered copy."
        let revision = revision, name = name, format = format
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let folder = panel.url, let self, self.revision == revision else { return }
            self.start("Saving decoded text…", work: { try QRCodeReading.save(code, in: folder, stem: name, format: format) }) { model, url in
                model.savedURL = url; model.onSaved?()
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func start<Value: Sendable>(_ activity: String, work: @escaping @Sendable () throws -> Value, finish: @escaping @MainActor (QRCodeReadOperation, Value) -> Void) {
        cancel(); self.activity = activity; error = nil
        let revision = revision
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated, operation: work)
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, let self, self.revision == revision else { return }
                finish(self, result); self.activity = nil; self.task = nil
            } catch {
                guard !Task.isCancelled, let self, self.revision == revision else { return }
                self.error = error.localizedDescription; self.activity = nil; self.task = nil
            }
        }
    }
}

struct QRCodeReadView: View {
    @Bindable var operation: QRCodeReadOperation
    @Binding var reading: Bool
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QRCodeHeading(reading: $reading).disabled(operation.busy)
            if !operation.sourceName.isEmpty {
                HStack {
                    Label(operation.sourceName, systemImage: "photo").lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    Button("Choose Another…", action: operation.chooseImage).buttonStyle(.link).disabled(operation.busy)
                }.font(.callout)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image").font(.callout.weight(.medium)).frame(height: 24)
                    imagePreview
                    Text(operation.prepared.map { "\($0.width) × \($0.height) px · \($0.codes.count) \($0.codes.count == 1 ? "code" : "codes") found" } ?? "PNG, JPEG, GIF, WebP, TIFF or HEIC")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(operation.contentKind?.rawValue ?? "Decoded text").font(.callout.weight(.medium))
                        Spacer(minLength: 4)
                        if let result = operation.prepared, result.codes.count > 1 {
                            Picker("Selected QR code", selection: $operation.selectedID) {
                                ForEach(result.codes) { Text("Code \($0.id + 1)").tag(Optional($0.id)) }
                            }.labelsHidden().fixedSize().disabled(operation.busy)
                        }
                    }.frame(height: 24)
                    if operation.concealsWiFi {
                        VStack(spacing: 10) {
                            Image(systemName: "wifi").font(.title).foregroundStyle(.secondary)
                            Text("Network details are hidden").font(.callout)
                            Button("Show encoded text") { operation.revealsWiFi = true }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
                    } else {
                        PlainTextEditor(text: .constant(operation.selectedCode?.text ?? ""), editable: false, label: "Decoded QR text", rejectLargeInput: {})
                            .overlay(alignment: .topLeading) {
                                if operation.selectedCode?.text?.isEmpty != false {
                                    Text(emptyMessage).font(.callout).foregroundStyle(.secondary).padding(12).allowsHitTesting(false).accessibilityHidden(true)
                                }
                            }
                            .background(Color(nsColor: .textBackgroundColor)).clipShape(.rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
                    }
                    if operation.contentKind == .wifi {
                        if operation.revealsWiFi { Button("Hide encoded text") { operation.revealsWiFi = false }.buttonStyle(.link) }
                        Text("Copy and Save include the full network details.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(operation.selectedCode?.text.map { "\($0.utf8.count.formatted()) bytes · Selectable text" } ?? "Nothing is copied or opened automatically")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }.frame(minHeight: 240, maxHeight: .infinity)
            if operation.selectedCode?.text != nil {
                HStack {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Filename without extension", text: $operation.name).textFieldStyle(.roundedBorder).labelsHidden()
                    if let document = operation.selectedCode?.documentFormat {
                        Picker("File format", selection: $operation.format) {
                            Text("Plain text (.txt)").tag(QRReadFileFormat.text)
                            Text(document == .vCard ? "Contact (.vcf)" : "Calendar (.ics)").tag(document)
                        }.labelsHidden().fixedSize()
                    } else { Text(".txt").font(.callout.monospaced()).foregroundStyle(.secondary) }
                }.disabled(operation.busy)
            }
            VStack(alignment: .leading, spacing: 5) {
                if let url = operation.savedURL {
                    HStack {
                        Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill").lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                    }.font(.callout).foregroundStyle(.green)
                } else if operation.copied { Label("Decoded text copied", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                if let result = operation.prepared, result.codes.isEmpty {
                    Label("No QR code found. Try a sharper image or a closer crop.", systemImage: "viewfinder").font(.callout).foregroundStyle(.secondary)
                } else if operation.selectedCode != nil, operation.selectedCode?.text == nil {
                    Text(QRReadError.noText.localizedDescription).font(.callout).foregroundStyle(.secondary)
                }
                OperationFeedback(activity: operation.activity, error: operation.error ?? (operation.selectedCode?.text == nil ? nil : operation.nameError))
                if operation.prepared?.wasReduced == true {
                    Text("Large image reduced for reading. Crop closer if a code is missed.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Local only · Review decoded text · Links are never opened")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DialogFooter {
                if operation.savedURL == nil { Button(operation.busy ? "Cancel" : "Close", action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle()).disabled(operation.saving) }
            } actions: {
                if operation.savedURL != nil {
                    DialogDoneButton(action: close)
                } else if operation.selectedCode?.text != nil {
                    Button(operation.copied ? "Copied" : "Copy Text", action: operation.copyText).modifier(DialogActionStyle()).disabled(operation.busy || operation.selectedCode?.text?.isEmpty != false)
                    Button(operation.saveTitle + "…", action: operation.save).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true)).disabled(operation.busy || operation.nameError != nil)
                } else {
                    Button("Choose Image…", action: operation.chooseImage).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true)).disabled(operation.busy)
                }
            }
        }.onExitCommand { if !operation.saving { close() } }
        .padding(20).frame(minWidth: 600, minHeight: 560)
    }
    private var emptyMessage: String {
        if operation.prepared == nil { return "Choose an image to read its QR codes." }
        if operation.prepared?.codes.isEmpty == true { return "No decoded text yet." }
        return operation.selectedCode?.text == nil ? "This code does not provide readable text." : "This code contains empty text. You can save a blank file."
    }
    private var imagePreview: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .controlBackgroundColor)
                if let image = operation.previewImage, let result = operation.prepared {
                    let scale = min(proxy.size.width / CGFloat(result.scanWidth), proxy.size.height / CGFloat(result.scanHeight))
                    let width = CGFloat(result.scanWidth) * scale, height = CGFloat(result.scanHeight) * scale
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: width, height: height).accessibilityLabel("Selected image with numbered QR code locations")
                        ForEach(result.codes) { code in
                            let b = code.bounds
                            Button { operation.selectedID = code.id } label: {
                                Rectangle().strokeBorder(operation.selectedID == code.id ? Color.accentColor : .secondary, lineWidth: operation.selectedID == code.id ? 3 : 1)
                                    .overlay(alignment: .topLeading) {
                                        Text("\(code.id + 1)").font(.caption.bold()).foregroundStyle(.white).padding(4).background(Color.accentColor, in: .rect(cornerRadius: 4))
                                    }
                            }.buttonStyle(.plain).frame(width: b.width * width, height: b.height * height)
                                .offset(x: b.minX * width, y: (1 - b.maxY) * height)
                                .accessibilityLabel("Select QR code \(code.id + 1)").disabled(operation.busy)
                        }
                    }.frame(width: width, height: height)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "viewfinder").font(.system(size: 34)).foregroundStyle(.tertiary).accessibilityHidden(true)
                        Text("Choose a still image").font(.callout).foregroundStyle(.secondary)
                        Text("Up to 10 MiB · 40 megapixels").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(.rect(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
        }
    }
}
