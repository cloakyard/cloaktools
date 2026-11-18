import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class FileListOperation: Identifiable {
    let id = UUID()
    var options = FileListOptions() { didSet { if options != oldValue { invalidate() } } }
    var name = "File list" { didSet { if !name.utf8.elementsEqual(oldValue.utf8) { savedURL = nil; error = nil } } }
    var selectedID: UUID?
    var showExport = false
    var onSaved: (() -> Void)?
    private(set) var items: [ListedFile] = []
    private(set) var prepared: PreparedFileList?
    private(set) var activity: String?
    private(set) var error: String?
    private(set) var copied = false
    private(set) var savedURL: URL?
    private var task: Task<Void, Never>?
    private var revision = UUID()
    var busy: Bool { activity != nil }
    var saving: Bool { activity == "Saving file list…" }
    var selectedIndex: Int? { items.firstIndex { $0.id == selectedID } }
    var nameError: String? { do { try SafeOutput.validate(stem: name); return nil } catch { return error.localizedDescription } }
    var columnSummary: String {
        (["Name"] + (options.includeKind ? ["Kind"] : []) + (options.includeSize ? ["Size"] : []) + (options.includeModified ? ["Modified"] : []) + (options.includePath ? ["Full path"] : [])).joined(separator: ", ")
    }
    func cancel() { task?.cancel(); task = nil; revision = UUID(); activity = nil }
    private func invalidate() { cancel(); prepared = nil; error = nil; copied = false; savedURL = nil; showExport = false }
    func chooseItems() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Choose items for a file list"; panel.prompt = "Add Items"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.resolvesAliases = false
        panel.message = "Up to 200 selected files or folders. Only metadata is read; folders are not scanned."
        let revision = revision
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self, self.revision == revision else { return }
            self.add(panel.urls.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending })
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func add(_ urls: [URL]) {
        guard !busy, !urls.isEmpty else { return }
        let existing = items
        start("Reading selected details…", work: { try FileListExport.adding(urls, to: existing) }) { model, items in
            model.items = items; model.selectedID = items.last?.id; model.prepared = nil; model.savedURL = nil; model.copied = false; model.showExport = false
        }
    }
    func refresh() {
        guard !busy, !items.isEmpty else { return }
        let urls = items.map(\.url), selected = selectedIndex.map { items[$0].url }
        start("Refreshing selected details…", work: { try FileListExport.capture(urls) }) { model, items in
            model.items = items; model.selectedID = items.first { $0.url == selected }?.id ?? items.first?.id
            model.prepared = nil; model.savedURL = nil; model.copied = false; model.showExport = false
        }
    }
    func move(_ offset: Int) {
        guard !busy, let index = selectedIndex, items.indices.contains(index + offset) else { return }
        invalidate(); items.swapAt(index, index + offset)
    }
    func remove() {
        guard !busy, let index = selectedIndex else { return }
        invalidate(); items.remove(at: index); selectedID = items.isEmpty ? nil : items[min(index, items.count - 1)].id
    }
    func preview() {
        guard !busy, !items.isEmpty else { return }
        invalidate(); let items = items, options = options
        start("Preparing file list…", work: { try FileListExport.prepare(items, options: options) }) { model, result in model.prepared = result; model.showExport = true }
    }
    func copy() {
        guard !busy, let prepared else { return }
        let item = NSPasteboardItem()
        guard item.setString(prepared.text, forType: .string) else { error = "macOS could not prepare the list for copying."; return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return }
        copied = true; showExport = true; error = nil
    }
    func save() {
        guard !busy, let prepared else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        let panel = NSOpenPanel(); panel.title = "Save file list"; panel.prompt = "Save List"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.message = "Save \(name).\(prepared.format.fileExtension) · \(prepared.itemCount) items · \(prepared.byteCount.formatted()) bytes. Existing files get a numbered copy."
        let revision = revision, name = name
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let folder = panel.url, let self, self.revision == revision else { return }
            self.start("Saving file list…", work: { try FileListExport.save(prepared, in: folder, stem: name) }) { model, url in
                model.savedURL = url; model.showExport = true; model.onSaved?()
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    private func start<Value: Sendable>(_ activity: String, work: @escaping @Sendable () throws -> Value, finish: @escaping @MainActor (FileListOperation, Value) -> Void) {
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
final class FileListWindow: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let operation: FileListOperation
    init(operation: FileListOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 600), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "File List"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: FileListView(operation: operation, close: { [weak window] in window?.close() }))
        operation.onSaved = { [weak window] in window?.makeFirstResponder(nil) }
        window.contentMinSize = NSSize(width: 560, height: 560); window.setContentSize(NSSize(width: 620, height: 600))
        window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !operation.saving }
    func windowWillClose(_ notification: Notification) { operation.cancel(); onClose?() }
}

struct FileListView: View {
    @Bindable var operation: FileListOperation
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DialogHeading(title: "File list", subtitle: "Selected items. A useful list.", symbol: "list.bullet.rectangle")
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Format").foregroundStyle(.secondary)
                    Picker("Export format", selection: $operation.options.format) { ForEach(FileListFormat.allCases) { Text($0.title).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                    Spacer(minLength: 0)
                }
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Name is always included.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Toggle("Kind", isOn: $operation.options.includeKind).frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("Size in bytes", isOn: $operation.options.includeSize).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            Toggle("Modified date (UTC)", isOn: $operation.options.includeModified).frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("Full path", isOn: $operation.options.includePath).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.toggleStyle(.checkbox).padding(.top, 6)
                } label: {
                    Text("Columns · \(operation.columnSummary)").font(.callout).lineLimit(1).truncationMode(.tail)
                }
            }.modifier(DialogCard()).disabled(operation.busy)
            HStack {
                Text("Name").foregroundStyle(.secondary)
                TextField("Filename without extension", text: $operation.name).textFieldStyle(.roundedBorder).labelsHidden()
                Text(".\(operation.options.format.fileExtension)").font(.callout.monospaced()).foregroundStyle(.secondary)
            }.disabled(operation.busy)
            workspace
            VStack(alignment: .leading, spacing: 5) {
                if let url = operation.savedURL {
                    HStack {
                        Label("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill").lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(.link)
                    }.font(.callout).foregroundStyle(.green)
                } else if operation.copied { Label("List copied to clipboard", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                OperationFeedback(activity: operation.activity, error: operation.error ?? operation.nameError)
                Text(operation.options.includePath ? "Full paths are included. Review names and details before sharing." : "Full paths are off. Review names and details before sharing.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Metadata only · No folder scanning · Sizes omit folders and links")
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
                    } else if operation.prepared != nil {
                        Button(operation.copied ? "Copied" : "Copy List", action: operation.copy).modifier(DialogActionStyle()).disabled(operation.busy)
                        Button("Save List…", action: operation.save).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true)).disabled(operation.busy || operation.nameError != nil)
                    } else if operation.items.isEmpty {
                        Button("Choose Items…", action: operation.chooseItems).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true)).disabled(operation.busy)
                    } else {
                        Button("Preview Export", action: operation.preview).keyboardShortcut(.return, modifiers: .command).modifier(DialogActionStyle(prominent: true)).disabled(operation.busy)
                    }
                }
            }
        }.onExitCommand { if !operation.saving { close() } }
        .padding(20).frame(minWidth: 560, minHeight: 560)
    }
    private var workspace: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Picker("Review", selection: $operation.showExport) { Text("Items").tag(false); Text("Export").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().disabled(operation.prepared == nil || operation.busy)
                Spacer(minLength: 4)
                Text(operation.showExport ? "\(operation.prepared?.byteCount.formatted() ?? "0") bytes" : "\(operation.items.count) \(operation.items.count == 1 ? "item" : "items")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Group {
                if operation.showExport {
                    PlainTextEditor(text: .constant(operation.prepared?.preview ?? ""), editable: false, label: "File list export preview", rejectLargeInput: {})
                        .background(Color(nsColor: .textBackgroundColor))
                } else { itemList }
            }.clipShape(.rect(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
                .frame(minHeight: 140, maxHeight: .infinity)
            Text(footnote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxHeight: .infinity)
    }
    private var footnote: String {
        if !operation.showExport { return "Captured details stay fixed. Refresh to read them again; preview before saving." }
        let prefix = operation.prepared?.previewIsTruncated == true ? "First 65,536 characters. Copy and Save include the full list. " : ""
        if operation.options.format == .markdown { return prefix + "Markdown escapes markup; line breaks and tabs appear as ↵ and ⇥." }
        let count = operation.prepared?.protectedCells ?? 0
        return prefix + (count == 0 ? "CSV quotes every field. Copy and Save always use this export." : "\(count) formula-like \(count == 1 ? "cell is" : "cells are") prefixed with an apostrophe for spreadsheets.")
    }
    private var itemList: some View {
        VStack(spacing: 0) {
            if operation.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.doc").font(.system(size: 28)).foregroundStyle(.blue).accessibilityHidden(true)
                    Text("Choose files or folders").fontWeight(.medium)
                    Text("Up to 200 items · Names, sizes and optional details").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $operation.selectedID) {
                        ForEach(Array(operation.items.enumerated()), id: \.element.id) { index, item in
                            HStack(spacing: 10) {
                                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).lineLimit(1).truncationMode(.middle)
                                    Text("\(item.kind.rawValue) · \(item.url.deletingLastPathComponent().lastPathComponent)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(item.size.map { "\($0.formatted()) bytes" } ?? "—").font(.caption).foregroundStyle(.secondary)
                            }.tag(item.id).id(item.id).help(item.url.path)
                        }
                    }.listStyle(.inset).accessibilityLabel("Selected items in export order")
                        .onChange(of: operation.selectedIndex) { if let id = operation.selectedID { proxy.scrollTo(id) } }
                }
                Divider()
                HStack(spacing: 12) {
                    Button("Add Items…", systemImage: "plus", action: operation.chooseItems).disabled(operation.items.count >= FileListExport.maximumItems)
                    Button("Refresh", systemImage: "arrow.clockwise", action: operation.refresh).help("Read current metadata for the selected items again")
                    Spacer(minLength: 0)
                    Button("Move Up", systemImage: "arrow.up") { operation.move(-1) }.labelStyle(.iconOnly).disabled(operation.selectedIndex == nil || operation.selectedIndex == 0).help("Move selected item up")
                    Button("Move Down", systemImage: "arrow.down") { operation.move(1) }.labelStyle(.iconOnly).disabled(operation.selectedIndex == nil || operation.selectedIndex == operation.items.count - 1).help("Move selected item down")
                    Button("Remove Item", systemImage: "minus", action: operation.remove).labelStyle(.iconOnly).disabled(operation.selectedID == nil).help("Remove selected item")
                }.buttonStyle(.borderless).padding(10)
            }
        }.background(Color(nsColor: .controlBackgroundColor)).disabled(operation.busy)
    }
}
