import AppKit
import SwiftUI
import CloakToolsCore

enum DeveloperTextTool: String, CaseIterable, Identifiable, Sendable {
    case json, base64
    var id: String { rawValue }
    var title: String { self == .json ? "JSON" : "Base64" }
    var subtitle: String { self == .json ? "Format, minify or check your JSON." : "Encode and decode text or images." }
    var symbol: String { self == .json ? "curlybraces" : "character.cursor.ibeam" }
}

@MainActor @Observable
final class DeveloperTextOperation: Identifiable {
    let id = UUID()
    var showImages = false
    let tool: DeveloperTextTool
    var input = "" { didSet { if !input.utf8.elementsEqual(oldValue.utf8) { invalidate() } } }
    var jsonAction: JSONTextAction = .format { didSet { invalidate() } }
    var decoding = false { didSet { if decoding != oldValue { invalidate() } } }
    var alphabet: Base64Alphabet = .standard { didSet { invalidate() } }
    private(set) var result: String?
    private(set) var status: String?
    private(set) var error: String?
    private(set) var running = false
    private(set) var copied = false
    private var task: Task<Void, Never>?
    private var revision = UUID()
    var actionTitle: String { tool == .json ? jsonAction.title : decoding ? "Decode" : "Encode" }
    var preview: String { String((result ?? "").prefix(65_536)) }
    var previewTruncated: Bool { (result?.count ?? 0) > 65_536 }
    init(tool: DeveloperTextTool) { self.tool = tool }

    func invalidate() {
        task?.cancel(); task = nil; revision = UUID()
        result = nil; status = nil; error = nil; copied = false; running = false
    }
    func rejectLargeInput() { invalidate(); error = DeveloperTextError.inputTooLarge.localizedDescription }
    func run() {
        invalidate()
        let revision = revision, input = input, tool = tool, action = jsonAction, decoding = decoding, alphabet = alphabet
        running = true
        task = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) { () throws -> String? in
                if tool == .json { return try DeveloperText.json(input, action: action) }
                return try decoding ? DeveloperText.decodeBase64(input, alphabet: alphabet) : DeveloperText.encodeBase64(input, alphabet: alphabet)
            }
            do {
                let output = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, let self, self.revision == revision else { return }
                self.result = output
                self.status = tool == .json ? "Valid JSON" : decoding ? "Decoded to UTF-8 text" : "Encoded successfully"
                self.running = false; self.task = nil
            } catch {
                guard !Task.isCancelled, let self, self.revision == revision else { return }
                self.error = error.localizedDescription; self.running = false; self.task = nil
            }
        }
    }
    func copy() {
        guard let result, !result.isEmpty, !running else { return }
        let item = NSPasteboardItem()
        guard item.setString(result, forType: .string) else { error = "macOS could not prepare the text for copying."; return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return }
        copied = true; error = nil
    }
}

@MainActor
final class DeveloperTextWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let operation: DeveloperTextOperation
    private let imageOperation: Base64ImageOperation?
    init(operation: DeveloperTextOperation) {
        self.operation = operation
        let imageOperation = operation.tool == .base64 ? Base64ImageOperation() : nil
        self.imageOperation = imageOperation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = operation.tool.title; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: DeveloperToolWorkspace(operation: operation, imageOperation: imageOperation, close: { [weak window] in window?.close() }))
        imageOperation?.onSaved = { [weak window] in window?.makeFirstResponder(nil) }
        window.contentMinSize = NSSize(width: 520, height: 540)
        window.setContentSize(NSSize(width: 600, height: 600)); window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { imageOperation?.saving != true }
    func windowWillClose(_ notification: Notification) { operation.invalidate(); imageOperation?.cancel(); onClose?() }
}

struct DeveloperToolWorkspace: View {
    @Bindable var operation: DeveloperTextOperation
    let imageOperation: Base64ImageOperation?
    let close: () -> Void
    var body: some View {
        if operation.showImages, let imageOperation {
            Base64ImageView(operation: imageOperation, showImages: $operation.showImages, close: close)
        } else {
            DeveloperTextView(operation: operation, showImages: $operation.showImages, close: close)
        }
    }
}

struct Base64Heading: View {
    @Binding var showImages: Bool
    var body: some View {
        HStack(spacing: 14) {
            DialogHeading(title: "Base64", subtitle: showImages ? "Images, ready to embed or save." : "Encode and decode UTF-8 text.", symbol: showImages ? "photo" : "character.cursor.ibeam")
            Picker("Content", selection: $showImages) {
                Text("Text").tag(false); Text("Image").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 144)
        }
    }
}

struct DeveloperTextView: View {
    @Bindable var operation: DeveloperTextOperation
    @Binding var showImages: Bool
    let close: () -> Void
    private var isJSON: Bool { operation.tool == .json }
    private var inputPlaceholder: String { isJSON ? "Paste or type JSON here…" : operation.decoding ? "Paste Base64 here…" : "Paste or type text here…" }
    private var resultPlaceholder: String {
        if operation.result == "" { return "The decoded text is empty." }
        return "Your result will appear here."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isJSON { DialogHeading(title: operation.tool.title, subtitle: operation.tool.subtitle, symbol: operation.tool.symbol) }
            else { Base64Heading(showImages: $showImages) }
            HStack(spacing: 12) {
                if isJSON {
                    Picker("JSON action", selection: $operation.jsonAction) {
                        ForEach(JSONTextAction.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                } else {
                    Picker("Base64 action", selection: $operation.decoding) {
                        Text("Encode").tag(false); Text("Decode").tag(true)
                    }.pickerStyle(.segmented).labelsHidden()
                    Picker("Alphabet", selection: $operation.alphabet) {
                        ForEach(Base64Alphabet.allCases) { Text($0.title).tag($0) }
                    }.fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Input").fontWeight(.medium)
                    Text("· \(operation.input.utf8.count.formatted()) bytes").foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { operation.input = "" }.buttonStyle(.link).disabled(operation.input.isEmpty)
                }.font(.caption)
                editor(text: $operation.input, editable: true, placeholder: inputPlaceholder, label: "Input")
            }.frame(maxHeight: .infinity)
            if !isJSON || operation.jsonAction != .validate {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Result").fontWeight(.medium)
                        if let result = operation.result { Text("· \(result.utf8.count.formatted()) bytes").foregroundStyle(.secondary) }
                        Spacer()
                        if operation.previewTruncated { Text("Preview: first 65,536 characters").foregroundStyle(.secondary) }
                    }.font(.caption)
                    editor(text: .constant(operation.preview), editable: false, placeholder: resultPlaceholder, label: "Result")
                }.frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 6) {
                if let status = operation.status {
                    Label(operation.copied ? "Copied to clipboard" : status, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.callout).accessibilityElement(children: .combine)
                }
                OperationFeedback(activity: operation.running ? "Working…" : nil, error: operation.error)
                Text(isJSON ? "Local only · Up to 1 MiB · Numbers and key order are preserved." : operation.decoding ? "Local only · Up to 1 MiB · Whitespace and missing padding are accepted." : "Local only · Up to 1 MiB · URL-safe output omits padding.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DialogFooter {
                Button("Close", action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                if !isJSON || operation.jsonAction != .validate {
                    Button(operation.copied ? "Copied" : "Copy Result", action: operation.copy)
                        .modifier(DialogActionStyle()).disabled(operation.result?.isEmpty != false || operation.running)
                        .help("Copy the complete result to the clipboard")
                }
                Button(action: operation.run) {
                    HStack(spacing: 8) { Text(operation.actionTitle); Text("⌘↩").foregroundStyle(.secondary) }
                }.keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true))
                    .disabled(operation.input.isEmpty || operation.running)
            }
        }.padding(20).frame(minWidth: 520, minHeight: 540)
    }
    private func editor(text: Binding<String>, editable: Bool, placeholder: String, label: String) -> some View {
        PlainTextEditor(text: text, editable: editable, label: label, rejectLargeInput: operation.rejectLargeInput)
            .overlay(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder).font(.system(.callout, design: .monospaced)).foregroundStyle(.tertiary)
                        .padding(12).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(.rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
            .frame(minHeight: 110, maxHeight: .infinity)
    }
}

/// Native plain text editing without smart quotes, spellchecking or rich-text conversion.
struct PlainTextEditor: NSViewRepresentable {
    @Binding var text: String
    let editable: Bool
    let label: String
    let rejectLargeInput: () -> Void
    var maximumInputBytes = DeveloperText.maximumInputBytes
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        let view = NSTextView(usingTextLayoutManager: false)
        view.isEditable = editable; view.isSelectable = true; view.isRichText = false; view.allowsUndo = editable
        view.isAutomaticQuoteSubstitutionEnabled = false; view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false; view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.isContinuousSpellCheckingEnabled = false; view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false; view.isAutomaticDataDetectionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.textColor = .textColor; view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 8, height: 10)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.setAccessibilityLabel(label); view.string = text; view.delegate = context.coordinator
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        view.isEditable = editable
        view.setAccessibilityLabel(label)
        if !view.string.utf8.elementsEqual(text.utf8) { view.string = text; view.undoManager?.removeAllActions(); view.scrollRangeToVisible(NSRange(location: 0, length: 0)) }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextEditor
        init(parent: PlainTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let replacementString else { return true }
            let proposed = (textView.string as NSString).replacingCharacters(in: affectedCharRange, with: replacementString)
            guard proposed.utf8.count <= parent.maximumInputBytes else { parent.rejectLargeInput(); return false }
            return true
        }
    }
}
