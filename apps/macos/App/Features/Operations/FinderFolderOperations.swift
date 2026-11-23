import AppKit
import CloakToolsCore
import SwiftUI

@MainActor @Observable
final class FolderTask {
    let id = UUID()
    private(set) var activity: String?
    var error: String?
    var notice: String?
    private var cancelWorker: (() -> Void)?
    var busy: Bool { activity != nil }

    func run<Value: Sendable>(_ label: String, work: @escaping @Sendable () async throws -> Value,
                              success: @escaping (Value) -> Void, finished: @escaping () -> Void = {}) {
        guard !busy else { return }
        error = nil
        notice = nil
        activity = label
        let worker = Task.detached(priority: .userInitiated, operation: work)
        cancelWorker = { worker.cancel() }
        Task {
            do { success(try await worker.value) }
            catch is CancellationError { notice = "Cancelled." }
            catch { self.error = error.localizedDescription }
            activity = nil
            cancelWorker = nil
            finished()
        }
    }

    func cancel() { cancelWorker?() }
}

@MainActor @Observable
final class StructureReview {
    let task = FolderTask()
    let source: URL
    var destination: URL
    var name: String
    private var savedName: String?
    private var savedSelection = Set<String>()
    var hasSavedSet: Bool { savedName != nil }
    var matchesSavedSet: Bool { savedName == name && savedSelection == selection }
    var structure: FolderStructure?
    var selection = Set<String>()
    var output: URL?

    init(_ source: URL) {
        self.source = source
        destination = source.deletingLastPathComponent()
        name = source.lastPathComponent + " Copy"
        load()
    }

    func load() {
        let root = source
        task.run("Reading subfolders…", work: { try FolderStructure(from: root) }) { result in
            self.structure = result
            self.selection = Set(result.paths)
        }
    }

    func toggle(_ path: String, included: Bool) {
        guard let structure else { return }
        let prefix = path + "/"
        if included {
            selection.formUnion(structure.paths.filter { $0 == path || $0.hasPrefix(prefix) || path.hasPrefix($0 + "/") })
        } else {
            selection = selection.filter { $0 != path && !$0.hasPrefix(prefix) }
        }
        task.notice = nil
    }

    func create() {
        guard let structure else { return }
        let selected = selection, name = name, parent = destination
        task.run("Creating folders…", work: { try structure.create(named: name, selected: selected, in: parent) }) { self.output = $0 }
    }

    func saveSet(using save: (FileSetDefinition) throws -> Void) {
        guard let structure else { return }
        do {
            var set = try structure.definition(named: name, selected: selection)
            set.id = task.id
            try save(set)
            savedName = name
            savedSelection = selection
            task.error = nil
            task.notice = "“\(name)” is in Saved File Sets."
        } catch { task.error = error.localizedDescription }
    }
}

@MainActor @Observable
final class SharingReview {
    let task = FolderTask()
    var files: [SharingFile] = []
    var name = "Shared Copies"
    var output: URL?
    var onChange: (() -> Void)?
    private var pending: [[URL]] = []

    func add(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        pending.append(urls)
        loadNext()
    }

    private func loadNext() {
        guard !task.busy, !pending.isEmpty else { return }
        let urls = pending.removeFirst()
        let existing = output == nil ? files : []
        task.run("Adding files…", work: { try SharingCollection.adding(urls, to: existing) }, success: { items in
            self.files = items
            self.output = nil
        }, finished: { self.onChange?(); self.loadNext() })
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Collect files for sharing"
        panel.prompt = "Add Files"
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func save(in folder: URL) {
        let items = files, name = name
        task.run("Copying files…", work: { try SharingCollection.save(items, named: name, in: folder) },
                 success: { self.output = $0 }, finished: { self.onChange?(); self.loadNext() })
    }
}

@MainActor @Observable
final class ComparisonReview {
    let task = FolderTask()
    let first: URL
    let second: URL
    var result: FolderComparison?

    init(_ first: URL, _ second: URL) {
        self.first = first
        self.second = second
        compare()
    }

    func compare() {
        result = nil
        let first = first, second = second
        task.run("Comparing folder contents…", work: { try FolderComparison(first, second) }) { self.result = $0 }
    }
}

@MainActor
func chooseFinderFolder(_ title: String, startingAt folder: URL? = nil, prompt: String = "Choose Folder") -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.message = title
    panel.prompt = prompt
    panel.directoryURL = folder
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
final class FinderReviewWindow: NSWindowController, NSWindowDelegate, OperationPanel {
    var onClose: (() -> Void)?
    let task: FolderTask
    let finish: () -> Void

    init<Content: View>(_ title: String, task: FolderTask, finish: @escaping () -> Void,
                        @ViewBuilder content: (@escaping () -> Void) -> Content) {
        self.task = task
        self.finish = finish
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 520),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.contentViewController = NSHostingController(rootView: content { [weak window] in window?.performClose(nil) })
        window.contentMinSize = NSSize(width: 440, height: 420)
        window.setContentSize(NSSize(width: 610, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !task.busy }
    func windowWillClose(_ notification: Notification) { finish(); onClose?() }
}
