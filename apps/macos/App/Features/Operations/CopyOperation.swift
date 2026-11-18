import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class CopyOperation: Identifiable {
    let id = UUID()
    let selection: CopySelection
    let formats: [CopyFormat]
    var format: CopyFormat = .paths { didSet { refresh() } }
    var content = ""
    var error: String?
    var copied = false
    var copyTitle: String {
        let count = selection.files.count
        switch format {
        case .names: return count == 1 ? "Copy Name" : "Copy \(count) Names"
        case .paths: return count == 1 ? "Copy Path" : "Copy \(count) Paths"
        default: return "Copy \(format.title)"
        }
    }
    var preview: String { String(content.prefix(8_192)) }
    var truncated: Bool { content.count > 8_192 }
    init(selection: CopySelection, preferences: Preferences) { self.selection = selection; formats = preferences.tools.copyFormats; refresh() }
    private func refresh() {
        copied = false; error = nil
        do { content = try selection.text(as: format) }
        catch { content = ""; self.error = error.localizedDescription }
    }
    func copy() {
        guard !content.isEmpty, error == nil else { return }
        let item = NSPasteboardItem()
        guard item.setString(content, forType: .string) else { error = "macOS could not prepare the text for copying."; return }
        let clipboard = NSPasteboard.general
        clipboard.clearContents()
        guard clipboard.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return }
        copied = true
    }
}

@MainActor
final class CopyOperationWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    init(operation: CopyOperation) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 448, height: 408), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Copy As"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: CopyOperationView(operation: operation, close: { [weak window] in window?.close() }))
        window.contentMinSize = NSSize(width: 420, height: 360)
        window.setContentSize(NSSize(width: 448, height: 408)); window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

struct CopyOperationView: View {
    @Bindable var operation: CopyOperation
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeading(title: "Copy file names or paths", subtitle: "Choose what to put on the clipboard.", symbol: "list.clipboard")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Text("Copy as").foregroundStyle(.secondary)
                        Picker("Copy format", selection: $operation.format) {
                            ForEach(operation.formats) { format in Text(format.title).tag(format) }
                        }.labelsHidden()
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Clipboard preview · \(operation.selection.files.count) selected \(operation.selection.files.count == 1 ? "item" : "items")")
                            Spacer()
                            Text("\(operation.content.utf8.count.formatted()) bytes")
                        }.font(.caption).foregroundStyle(.secondary)
                        ScrollView([.horizontal, .vertical]) {
                            Text(operation.preview).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 112).accessibilityLabel("Text to copy")
                    }.modifier(DialogCard())
                    Text(operation.truncated ? "Preview shows the first 8,192 characters. Copy includes the full text." : operation.format.detail)
                        .font(.caption).foregroundStyle(.secondary)
                    if operation.copied { Label("Copied to clipboard.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    if let error = operation.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if !operation.copied { Text("Replaces current clipboard.").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 4)
                    Button(operation.copied ? "Done" : "Cancel", role: .cancel, action: close)
                        .keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                    Button(operation.copyTitle, action: operation.copy).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                        .disabled(operation.content.isEmpty || operation.error != nil)
                }
            }
        }.padding(20).frame(minWidth: 420, minHeight: 360)
    }
}
