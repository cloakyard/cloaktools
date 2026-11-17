import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class Base64ImageOperation {
    var decoding = false { didSet { if decoding != oldValue { invalidate() } } }
    var input = "" { didSet { if !input.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    var includeDataURL = true { didSet { if includeDataURL != oldValue { invalidate() } } }
    var name = "Decoded Image" { didSet { if !name.utf8.elementsEqual(oldValue.utf8) { savedURL = nil; error = nil } } }
    var onSaved: (() -> Void)?
    private(set) var source: Base64ImageSnapshot?
    private(set) var sourceName = ""
    private(set) var decoded: Base64ImageSnapshot?
    private(set) var encoded: String?
    private(set) var savedURL: URL?
    private(set) var activity: String?
    private(set) var error: String?
    private(set) var copied = false
    private var task: Task<Void, Never>?
    private var revision = UUID()
    var busy: Bool { activity != nil }
    var saving: Bool { activity == "Saving image…" }
    var preview: String { String((encoded ?? "").prefix(65_536)) }
    var previewTruncated: Bool { (encoded?.utf8.count ?? 0) > 65_536 }

    var nameError: String? { do { try SafeOutput.validate(stem: name); return nil } catch { return error.localizedDescription } }

    func cancel() { task?.cancel(); task = nil; revision = UUID(); activity = nil }
    func invalidate() { cancel(); encoded = nil; decoded = nil; savedURL = nil; copied = false; error = nil }
    func rejectLargeInput() { invalidate(); error = Base64ImageError.textTooLarge.localizedDescription }
    func chooseImage() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Choose an image to encode"; panel.prompt = "Choose Image"
        panel.allowedContentTypes = Base64Image.inputTypes; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "Up to 10 MiB. Original bytes, metadata and animation are preserved."
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.invalidate(); self.source = nil; self.sourceName = url.lastPathComponent
            self.start("Loading image…", work: { try Base64Image.capture(url) }) { model, image in model.source = image }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func run() {
        invalidate()
        if decoding {
            let text = input
            start("Decoding image…", work: { try Base64Image.decode(text) }) { model, image in model.decoded = image }
        } else if let source {
            let includeDataURL = includeDataURL
            start("Encoding image…", work: { try Base64Image.encode(source, includeDataURL: includeDataURL) }) { model, text in model.encoded = text }
        }
    }
    func copy() {
        guard let encoded, !busy else { return }
        let item = NSPasteboardItem()
        guard item.setString(encoded, forType: .string) else { error = "macOS could not prepare the text for copying."; return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return }
        copied = true; error = nil
    }
    func save() {
        guard let decoded, !busy else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.title = "Save decoded image"; panel.prompt = "Save Image"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "Save \(name).\(decoded.fileExtension). Existing files get a numbered copy."
        let revision = revision, name = name
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let folder = panel.url, let self, self.revision == revision else { return }
            self.start("Saving image…", work: { try Base64Image.save(decoded, in: folder, stem: name) }) { model, url in model.savedURL = url; model.onSaved?() }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func start<Value: Sendable>(_ activity: String, work: @escaping @Sendable () throws -> Value, finish: @escaping @MainActor (Base64ImageOperation, Value) -> Void) {
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

struct Base64ImageView: View {
    @Bindable var operation: Base64ImageOperation
    @Binding var showImages: Bool
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Base64Heading(showImages: $showImages).disabled(operation.busy)
            HStack {
                Picker("Image Base64 action", selection: $operation.decoding) {
                    Text("Encode").tag(false); Text("Decode").tag(true)
                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                if !operation.decoding { Toggle("Include data URL", isOn: $operation.includeDataURL).toggleStyle(.checkbox).help("Adds the detected image MIME type for web embedding") }
            }.disabled(operation.busy)
            if operation.decoding { decodeContent } else { encodeContent }
            VStack(alignment: .leading, spacing: 5) {
                if let url = operation.savedURL {
                    HStack {
                        Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill").lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                    }.font(.callout).foregroundStyle(.green)
                } else if operation.copied { Label("Copied to clipboard", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                else if operation.decoded != nil { Label("Image decoded", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                OperationFeedback(activity: operation.activity, error: operation.error ?? (operation.decoded == nil ? nil : operation.nameError))
                Text("Local only · Original image bytes, metadata and animation are kept.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if operation.savedURL == nil {
                        Button(operation.busy ? "Cancel" : "Close", action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                            .disabled(operation.saving)
                    }
                    Spacer(minLength: 0)
                    if operation.decoding {
                        if operation.savedURL != nil {
                            Button("Done", action: close).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                        } else if operation.decoded != nil {
                            Button("Save Image…", action: operation.save).keyboardShortcut(.return, modifiers: .command)
                                .modifier(DialogActionStyle(prominent: true)).disabled(operation.busy || operation.nameError != nil)
                        } else {
                            Button("Decode", action: operation.run).keyboardShortcut(.return, modifiers: .command)
                                .modifier(DialogActionStyle(prominent: true)).disabled(operation.input.isEmpty || operation.busy)
                        }
                    } else if operation.source == nil {
                        Button("Choose Image…", action: operation.chooseImage).keyboardShortcut(.return, modifiers: .command)
                            .modifier(DialogActionStyle(prominent: true)).disabled(operation.busy)
                    } else {
                        Button(operation.copied ? "Copied" : "Copy Result", action: operation.copy).modifier(DialogActionStyle())
                            .disabled(operation.encoded == nil || operation.busy).help("Copies the complete Base64, including any data URL prefix")
                        Button("Encode", action: operation.run).keyboardShortcut(.return, modifiers: .command)
                            .modifier(DialogActionStyle(prominent: true)).disabled(operation.source == nil || operation.busy)
                    }
                }
            }
        }.onExitCommand { if !operation.saving { close() } }
        .padding(20).frame(minWidth: 520, minHeight: 540)
    }

    private var encodeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Image").font(.caption).fontWeight(.medium)
                Spacer()
                if operation.source != nil { Button("Change…", action: operation.chooseImage).buttonStyle(.link).disabled(operation.busy) }
            }
            if let image = operation.source { imageCard(image, title: operation.sourceName) }
            else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 28)).foregroundStyle(.teal)
                    Text("PNG, JPEG, GIF, WebP, TIFF or HEIC").font(.callout)
                    Text("Up to 10 MiB · 40 megapixels per frame").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 104).modifier(DialogCard())
            }
            HStack {
                Text("Base64 result").fontWeight(.medium)
                Spacer()
                if operation.previewTruncated { Text("Preview: first 65,536 characters") }
                else if let encoded = operation.encoded { Text("\(encoded.utf8.count.formatted()) bytes") }
            }.font(.caption).foregroundStyle(.secondary)
            textEditor(text: .constant(operation.preview), editable: false, placeholder: "Encode the image to see its Base64 here.", label: "Image Base64 result")
        }.frame(maxHeight: .infinity)
    }

    private var decodeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Base64 or image data URL").fontWeight(.medium)
                Spacer()
                Text("Up to 14 MiB").foregroundStyle(.secondary)
                Button("Clear") { operation.input = "" }.buttonStyle(.link).disabled(operation.input.isEmpty || operation.busy)
            }.font(.caption)
            textEditor(text: $operation.input, editable: !operation.busy, placeholder: "data:image/png;base64,…", label: "Image Base64 input")
            if let image = operation.decoded {
                imageCard(image, title: "Decoded image")
                HStack {
                    Text("Name").foregroundStyle(.secondary)
                    TextField("Image name", text: $operation.name).textFieldStyle(.roundedBorder).labelsHidden()
                    Text(".\(image.fileExtension)").foregroundStyle(.secondary)
                }.disabled(operation.busy)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                    Text("Decode to preview an image before saving. Standard Base64 and image data URLs are supported.")
                        .fixedSize(horizontal: false, vertical: true)
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
            }
        }.frame(maxHeight: .infinity)
    }
    private func imageCard(_ image: Base64ImageSnapshot, title: String) -> some View {
        HStack(spacing: 14) {
            if let preview = NSImage(data: image.thumbnailPNG) {
                Image(nsImage: preview).resizable().scaledToFit().frame(width: 100, height: 88)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6)).accessibilityLabel("First frame preview")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.medium).lineLimit(1).truncationMode(.middle).help(title)
                Text("\(image.format) · \(image.width) × \(image.height)")
                Text(ByteCountFormatter.string(fromByteCount: Int64(image.bytes.count), countStyle: .file))
                if image.frameCount > 1 { Text("\(image.frameCount) frames kept · First-frame preview").font(.caption) }
            }.font(.callout)
            Spacer(minLength: 0)
        }.modifier(DialogCard())
    }
    private func textEditor(text: Binding<String>, editable: Bool, placeholder: String, label: String) -> some View {
        PlainTextEditor(text: text, editable: editable, label: label, rejectLargeInput: operation.rejectLargeInput, maximumInputBytes: Base64Image.maximumTextBytes)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty { Text(placeholder).font(.system(.callout, design: .monospaced)).foregroundStyle(.tertiary).padding(12).allowsHitTesting(false).accessibilityHidden(true) }
            }
            .background(Color(nsColor: .textBackgroundColor)).clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
            .frame(minHeight: 110, maxHeight: .infinity)
    }
}
