import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class FileSetOperation {
    let id = UUID()
    var definition: FileSetDefinition
    let sources: [TemplateSource]
    let preferences: Preferences
    var destination: URL
    var prepared: PreparedFileSet?
    var output: URL?
    var busy = false
    var stopping = false
    var cancelled = false
    var error: String?
    var savedMessage: String?
    var completedItems = 0
    private var task: Task<Void, Never>?
    private var cancelWorker: (() -> Void)?
    init(definition: FileSetDefinition, sources: [TemplateSource], preferences: Preferences, destination: URL) {
        self.definition = definition; self.sources = sources; self.preferences = preferences; self.destination = destination
    }
    var validation: String? {
        do { try definition.validate(sources: sources); return nil } catch { return error.localizedDescription }
    }
    var fileCount: Int { definition.entries.filter { $0.templateID != nil }.count }
    var hasProgrammingFiles: Bool {
        definition.entries.contains { entry in
            if case let .builtIn(template) = source(for: entry) { return template.isProgramming }; return false
        }
    }
    var folderCount: Int {
        var paths = Set<String>()
        for entry in definition.entries {
            let parts = entry.path.components(separatedBy: "/")
            let count = entry.templateID == nil ? parts.count : parts.count - 1
            if count > 0 { for depth in 1...count { paths.insert(parts.prefix(depth).joined(separator: "/")) } }
        }
        return paths.count
    }
    func source(for entry: FileSetEntry) -> TemplateSource? { sources.first { $0.id == entry.templateID } }
    func chooseDestination() {
        let panel = NSOpenPanel(); panel.title = "Create the new folder in…"; panel.prompt = "Choose Folder"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.directoryURL = destination
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, panel] response in
            if response == .OK, let url = panel.url { self?.destination = url; self?.error = nil }
        }
        if let window = NSApp.keyWindow, window.attachedSheet == nil { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func review() {
        guard !busy else { return }
        if let validation { error = validation; return }
        error = nil; cancelled = false; busy = true; completedItems = 0
        let definition = definition, sources = sources, preferences = preferences
        let worker = Task.detached(priority: .userInitiated) { try PreparedFileSet(definition: definition, sources: sources, preferences: preferences) }
        cancelWorker = { worker.cancel() }
        task = Task { [self] in
            do {
                let value = try await worker.value
                if worker.isCancelled { throw CancellationError() }
                prepared = value
            } catch is CancellationError { cancelled = true }
            catch { self.error = error.localizedDescription }
            busy = false; stopping = false; cancelWorker = nil; task = nil
        }
    }
    func create() {
        guard !busy, let prepared, output == nil else { return }
        error = nil; cancelled = false; busy = true; completedItems = 0
        let folder = destination
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            try prepared.publish(in: folder) { [weak self] done, _ in
                Task { @MainActor [weak self] in if self?.busy == true { self?.completedItems = done } }
            }
        }
        cancelWorker = { worker.cancel() }
        task = Task { [self] in
            do {
                let url = try await worker.value; output = url
                if preferences.revealCreatedFile { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch is CancellationError { cancelled = true }
            catch { self.error = error.localizedDescription }
            busy = false; stopping = false; cancelWorker = nil; task = nil
        }
    }
    func cancel() { guard busy else { return }; stopping = true; cancelWorker?() }
    func edit() { prepared = nil; error = nil; cancelled = false }
}

@MainActor final class FileSetWindow: NSWindowController, NSWindowDelegate {
    let operation: FileSetOperation
    var onClose: (() -> Void)?
    init(operation: FileSetOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "New File Set"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: FileSetView(operation: operation, close: { [weak window] in window?.close() }))
        window.contentMinSize = NSSize(width: 500, height: 500); window.setContentSize(NSSize(width: 560, height: 560))
        window.center(); window.isReleasedWhenClosed = false
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { operation.cancel(); return !operation.busy }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

struct FileSetView: View {
    @Bindable var operation: FileSetOperation
    let close: () -> Void
    @State private var editingEntry: FileSetEntry?
    @State private var saving = false
    @State private var highlightedItem: UUID?
    @FocusState private var nameFocused: Bool
    private var reviewing: Bool { operation.prepared != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: operation.output != nil ? "Folder created" : reviewing ? "Review folder contents" : "Create a folder with a set of files",
                          subtitle: operation.output != nil ? "Your files are ready, together." : reviewing ? "Check the files and destination before creating the folder." : "Choose the folder name and the files to create inside it.", symbol: "folder.badge.plus")
            operationContent
            DestinationRow(folder: operation.output ?? operation.destination, change: operation.output == nil ? { operation.chooseDestination() } : nil).disabled(operation.busy)
            OperationFeedback(activity: operation.busy ? (reviewing ? "Creating \(operation.completedItems) of \(operation.definition.entries.count) items…" : "Preparing review…") : nil, stopping: operation.stopping,
                              cancellation: operation.cancelled ? "Cancelled. No folder was published." : nil, error: operation.error ?? (!reviewing ? operation.validation : nil))
            if let saved = operation.savedMessage { Label(saved, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary) }
            actions
        }.padding(20).frame(minWidth: 500, minHeight: 500)
            .onAppear { nameFocused = true }
            .onChange(of: operation.definition) { operation.error = nil; operation.savedMessage = nil; operation.cancelled = false }
            .sheet(item: $editingEntry) { entry in
                FileSetEntryEditor(entry: entry, sources: operation.sources, preferences: operation.definition.preferences(from: operation.preferences)) { updated in
                    if let index = operation.definition.entries.firstIndex(where: { $0.id == updated.id }) { operation.definition.entries[index] = updated }
                    else { operation.definition.entries.append(updated) }
                    highlightedItem = updated.id
                }
            }
            .sheet(isPresented: $saving) { FileSetSaveSheet(operation: operation) }
    }
    @ViewBuilder private var operationContent: some View {
            if let output = operation.output {
                VStack(alignment: .leading, spacing: 12) {
                    Label(output.lastPathComponent, systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                    Text("\(operation.fileCount) files · \(operation.prepared?.byteCount.formatted() ?? "0") bytes").foregroundStyle(.secondary)
                    Text("Existing files and folders were kept.").font(.callout).foregroundStyle(.secondary)
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }.buttonStyle(.link)
                }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 12) {
                    Text("Folder name").foregroundStyle(.secondary)
                    if reviewing { Text(operation.definition.folderName).fontWeight(.medium).textSelection(.enabled); Spacer(minLength: 0) }
                    else { TextField("Folder name", text: $operation.definition.folderName).textFieldStyle(.roundedBorder).focused($nameFocused) }
                }.modifier(DialogCard()).disabled(operation.busy)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("CONTENTS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(operation.fileCount) \(operation.fileCount == 1 ? "file" : "files") · \(operation.folderCount) \(operation.folderCount == 1 ? "folder" : "folders")").font(.caption).foregroundStyle(.secondary)
                    }.padding(.bottom, 10)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if let prepared = operation.prepared {
                                    ForEach(FileSetReviewItem.outline(prepared)) { item in
                                        HStack {
                                            Label(item.name, systemImage: item.bytes == nil ? "folder" : "doc.text")
                                            Spacer()
                                            if let bytes = item.bytes { Text("\(bytes.formatted()) bytes").foregroundStyle(.secondary) }
                                        }
                                        .padding(.leading, CGFloat(item.depth) * 18)
                                        .padding(.vertical, 6)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel(item.path)
                                        .accessibilityValue(item.bytes.map { "\($0) bytes" } ?? "Folder")
                                        .help(item.path)
                                    }
                                } else {
                                    ForEach(operation.definition.entries) { entry in entryRow(entry).id(entry.id) }
                                }
                            }.padding(.trailing, 12)
                        }.scrollBounceBehavior(.basedOnSize)
                            .onChange(of: highlightedItem) { if let highlightedItem { proxy.scrollTo(highlightedItem, anchor: .center) } }
                    }
                    if !reviewing {
                        Divider().padding(.vertical, 8)
                        HStack(spacing: 14) {
                            Button("Add File…", systemImage: "doc.badge.plus") { editingEntry = .init(path: "Untitled.txt", templateID: "builtin:text") }
                            Button("Add Folder…", systemImage: "folder.badge.plus") { editingEntry = .init(path: "New folder") }
                        }.buttonStyle(.borderless).disabled(operation.definition.entries.count >= 32)
                    }
                }.modifier(DialogCard()).disabled(operation.busy)
                if reviewing, let prepared = operation.prepared {
                    Text("\(prepared.byteCount.formatted()) bytes prepared. If the folder name exists, a numbered folder is created. Existing folders are never merged.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        if operation.hasProgrammingFiles {
                            Picker("Programming content", selection: $operation.definition.starterPolicy) {
                                ForEach(FolderStarterPolicy.allCases) { Text($0.title).tag($0) }
                            }
                            Text(operation.preferences.includeHelloWorld ? "Uses the language choices captured when this operation opened." : "Global Hello World is Off. Built-in programming files stay blank.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Saved templates keep their contents. Structured files retain a valid blank format.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.disabled(operation.busy)
                }
            }
    }
    private var actions: some View {
            DialogFooter {
                if operation.busy {
                    Button("Cancel", role: .cancel, action: operation.cancel).keyboardShortcut(.cancelAction).modifier(DialogActionStyle()).disabled(operation.stopping)
                } else if operation.output == nil {
                    Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                }
            } actions: {
                if operation.output != nil && !operation.busy {
                    DialogDoneButton(action: close)
                } else if !operation.busy {
                    if reviewing { Button("Edit Contents", action: operation.edit).modifier(DialogActionStyle()) }
                    else { Button("Save Set…") { saving = true }.modifier(DialogActionStyle()).disabled(operation.validation != nil) }
                    Button(reviewing ? "Create Folder" : "Review…") { reviewing ? operation.create() : operation.review() }
                        .keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true)).disabled(operation.validation != nil)
                }
            }
    }
    private func entryRow(_ entry: FileSetEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: entry.templateID == nil ? "folder" : "doc.text").foregroundStyle(entry.templateID == nil ? .blue : .secondary).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.path + (entry.templateID == nil ? "/" : "")).font(.callout.monospaced()).lineLimit(2).help(entry.path)
                Text(entry.templateID == nil ? "Folder" : operation.source(for: entry)?.contentDescription(using: operation.definition.preferences(from: operation.preferences)) ?? "Template unavailable · Choose another")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !reviewing {
                Button { editingEntry = entry } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).accessibilityLabel("Edit \(entry.path)").help("Edit path or file type")
                Button { operation.definition.entries.removeAll { $0.id == entry.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove \(entry.path)").help("Remove from this draft")
            }
        }.padding(.vertical, 9).accessibilityElement(children: .contain)
    }
}

private struct FileSetEntryEditor: View {
    @State var entry: FileSetEntry
    let sources: [TemplateSource]
    let preferences: Preferences
    let save: (FileSetEntry) -> Void
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var pathFocused: Bool
    private var source: TemplateSource? { sources.first { $0.id == entry.templateID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: entry.templateID == nil ? "Folder in this set" : "File in this set", subtitle: "Paths start inside the new folder.", symbol: entry.templateID == nil ? "folder.badge.plus" : "doc.badge.plus")
            VStack(alignment: .leading, spacing: 12) {
                TextField(entry.templateID == nil ? "e.g. assets/images" : "e.g. notes/Ideas.md", text: $entry.path).textFieldStyle(.roundedBorder).focused($pathFocused).accessibilityLabel("Relative path")
                if entry.templateID != nil {
                    Picker("File type", selection: Binding(get: { entry.templateID ?? "builtin:text" }, set: { id in
                        entry.templateID = id
                        if let selected = sources.first(where: { $0.id == id }) {
                            entry.path = (entry.path as NSString).deletingPathExtension + "." + selected.fileExtension
                        }
                    })) {
                        ForEach(sources) { Text($0.title).tag($0.id) }
                        if source == nil { Text("Template unavailable").tag(entry.templateID ?? "") }
                    }
                    if let source { Text(source.contentDescription(using: preferences)).font(.caption).foregroundStyle(.secondary) }
                }
                Text("Use / for subfolders. Parent folders are created automatically. Hidden names and .. are not allowed.").font(.caption).foregroundStyle(.secondary)
            }.modifier(DialogCard())
            OperationFeedback(error: error)
            DialogFooter {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                Button("Keep Item") {
                    do {
                        try FileSetDefinition(entries: [entry]).validate(sources: sources)
                        save(entry); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true)).disabled(entry.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 440).onAppear { pathFocused = true }
            .onChange(of: entry) { error = nil }
    }
}

private struct FileSetSaveSheet: View {
    let operation: FileSetOperation
    @State private var title = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    private var existing: Bool { AppModel.shared.fileSets.contains { $0.id == operation.definition.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: existing ? "Update saved set" : "Save a reusable set", subtitle: "Keep this structure for another day.", symbol: "folder.badge.gearshape")
            TextField("Set name", text: $title).textFieldStyle(.roundedBorder).focused($focused)
            Text("Saves paths, file types and the content policy. Choose a destination each time you use it. No files are created now.").font(.callout).foregroundStyle(.secondary)
            OperationFeedback(error: error)
            DialogFooter {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                Button(existing ? "Save Changes" : "Save Set") {
                    do {
                        var definition = operation.definition; definition.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        try AppModel.shared.saveFileSet(definition)
                        operation.savedMessage = "Saved “\(definition.title)” in New Files."; dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true)).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 440).onAppear {
            title = AppModel.shared.fileSets.first { $0.id == operation.definition.id }?.title ?? operation.definition.title; focused = true
        }
    }
}


/// Include the implicit parent folders that publication will create.
struct FileSetReviewItem: Identifiable {
    let components: [String]
    let bytes: Int?
    var path: String { components.joined(separator: "/") }
    var id: String { path }
    var name: String { components.last ?? path }
    var depth: Int { components.count - 1 }

    static func outline(_ prepared: PreparedFileSet) -> [Self] {
        var rows: [String: Self] = [:]
        for item in prepared.items {
            var components: [String] = []
            for segment in item.path.split(separator: "/") {
                components.append(String(segment))
                let path = components.joined(separator: "/")
                rows[path] = Self(components: components, bytes: path == item.path ? item.data?.count : nil)
            }
        }
        return rows.values.sorted { $0.components.lexicographicallyPrecedes($1.components) }
    }
}
