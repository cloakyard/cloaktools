import SwiftUI
import AppKit
import CloakToolsCore

@MainActor @Observable
final class ClipboardOperation: Identifiable {
    let id = UUID()
    var destination: URL
    let preferences: Preferences
    var document: ClipboardDocument?
    var thumbnail: NSImage?
    var name = ""
    var preparing = true
    var running = false
    var cancelled = false
    var stopping = false
    var error: String?
    var output: URL?
    var busy: Bool { preparing || running }
    private var preparation: Task<ClipboardDocument, Error>?
    private var publication: Task<URL, Error>?

    init(input: ClipboardInput, destination: URL, preferences: Preferences) {
        self.destination = destination; self.preferences = preferences
        let worker = Task.detached(priority: .userInitiated) { try ClipboardDocument.prepare(input) }
        preparation = worker
        Task { [self] in
            do {
                let document = try await worker.value
                if worker.isCancelled { throw CancellationError() }
                self.document = document; name = document.suggestedName
                thumbnail = document.thumbnailPNG.flatMap(NSImage.init(data:))
            } catch is CancellationError { cancelled = true }
            catch { self.error = error.localizedDescription }
            preparing = false; preparation = nil; stopping = false
        }
    }
    func start() {
        guard !busy, output == nil, let document else { return }
        do { try SafeOutput.validate(stem: name) }
        catch { self.error = error.localizedDescription; return }
        running = true; cancelled = false; error = nil
        let destination = destination, name = name
        let worker = Task.detached(priority: .userInitiated) { try document.write(in: destination, name: name) }
        publication = worker
        Task { [self] in
            do {
                let url = try await worker.value; output = url
                if preferences.revealCreatedFile { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                if preferences.openAfterCreation {
                    CreatedFileOpener.open(url, inPreview: document.kind == .image) { [weak self] in self?.error = $0 }
                }
            } catch is CancellationError { cancelled = true }
            catch { self.error = error.localizedDescription }
            running = false; publication = nil; stopping = false
        }
    }
    func chooseDestination() {
        let panel = NSOpenPanel(); panel.title = "Choose output folder"; panel.prompt = "Choose Folder"
        panel.directoryURL = destination; panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let folder = panel.url { destination = folder; error = nil }
    }
    func cancel() { guard busy else { return }; stopping = true; preparation?.cancel(); publication?.cancel() }
}

@MainActor
final class ClipboardWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    let operation: ClipboardOperation
    init(operation: ClipboardOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 448, height: 408), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "New File from Clipboard"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: ClipboardView(operation: operation, close: { [weak window] in window?.close() }))
        window.contentMinSize = NSSize(width: 420, height: 380)
        window.setContentSize(NSSize(width: 448, height: 408)); window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { operation.cancel(); return !operation.busy }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

struct ClipboardView: View {
    @Bindable var operation: ClipboardOperation
    let close: () -> Void
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeading(title: "From clipboard", subtitle: "Keep what you copied.", symbol: "doc.on.clipboard")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let document = operation.document {
                        HStack(spacing: 12) {
                            Text("Name").foregroundStyle(.secondary)
                            TextField("Name", text: $operation.name).textFieldStyle(.roundedBorder).focused($nameFocused)
                                .accessibilityLabel("File name, without extension")
                            Text(".\(document.fileExtension)").font(.callout.monospaced()).foregroundStyle(.secondary)
                        }.disabled(operation.busy || operation.output != nil)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(document.kind == .text ? "Copied text" : "Copied image", systemImage: document.kind == .text ? "text.alignleft" : "photo")
                                Spacer()
                                Text(document.kind == .image ? "\(document.width ?? 0) × \(document.height ?? 0)" : "\(document.content.count.formatted()) bytes")
                                    .foregroundStyle(.secondary)
                            }.font(.caption)
                            if let text = document.textPreview {
                                ScrollView([.horizontal, .vertical]) {
                                    Text(text.isEmpty ? "Empty text" : text)
                                        .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.frame(height: 96).accessibilityLabel("Clipboard text preview")
                            } else if let image = operation.thumbnail {
                                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 96)
                                    .accessibilityLabel("Clipboard image preview, \(document.width ?? 0) by \(document.height ?? 0) pixels")
                            }
                        }.modifier(DialogCard())
                        Text(document.previewIsTruncated ? "Showing the first 4,096 characters. The complete copied text will be saved." : "Uses this copy, even if you copy something else.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let output = operation.output {
                        Label("Created \(output.lastPathComponent)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }.buttonStyle(.link)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize)
            DestinationRow(folder: operation.destination, change: operation.output == nil ? { operation.chooseDestination() } : nil).disabled(operation.busy)
            OperationFeedback(activity: operation.busy ? (operation.preparing ? "Preparing preview…" : "Creating file…") : nil,
                              stopping: operation.stopping, cancellation: operation.cancelled ? "Cancelled. No file was created." : nil, error: operation.error)
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if !operation.busy && operation.output == nil { Text("Never replaces existing files.").font(.caption).foregroundStyle(.secondary) }
                    Spacer(minLength: 4)
                    if operation.busy {
                        Button("Cancel", role: .cancel, action: operation.cancel).keyboardShortcut(.cancelAction).modifier(DialogActionStyle()).disabled(operation.stopping)
                    } else if operation.output != nil {
                        Button("Done", action: close).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    } else {
                        Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                        Button("Create", action: operation.start).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                            .disabled(operation.document == nil || operation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }.padding(20).frame(minWidth: 420, minHeight: 380)
            .onChange(of: operation.preparing) { _, preparing in if !preparing { nameFocused = true } }
            .onAppear { nameFocused = !operation.preparing }
            .transaction { if reduceMotion { $0.animation = nil } }
    }
}
