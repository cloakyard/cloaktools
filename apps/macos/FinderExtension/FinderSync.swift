import AppKit
import FinderSync
import CloakToolsCore
import Darwin
import OSLog

/// Menu construction only creates small intent values. The host confirms and executes all work.
final class FinderSync: FIFinderSync {
    private var intents: [Int: URL] = [:]
    private var nextTag = 1
    private var workspace: URL?
    private var scopedFolders: [URL] = []
    private func bind(_ item: NSMenuItem, intent: FinderIntent) {
        item.target = self; item.tag = nextTag; intents[nextTag] = intent.url; nextTag += 1
        if intents.count > 100 { intents = intents.filter { $0.key > nextTag - 50 } }
    }
    override init() {
        super.init()
        // NSHomeDirectory points at the extension sandbox. getpwuid gives the local account's home.
        if let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir {
            let folder = URL(fileURLWithPath: String(cString: path), isDirectory: true).appendingPathComponent("CloakTools Files", isDirectory: true)
            workspace = folder
        }
        reloadScopes()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(reloadScopes), name: FinderScopeStore.changeNotification, object: nil)
    }
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        scopedFolders.forEach { $0.stopAccessingSecurityScopedResource() }
    }
    @objc private func reloadScopes() {
        var next: [URL] = []
        if let store = FinderScopeStore.authorized() {
            do {
                for folder in try store.load() {
                    guard let url = try? folder.resolve(), url.startAccessingSecurityScopedResource() else { continue }
                    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { url.stopAccessingSecurityScopedResource(); continue }
                    next.append(url)
                }
            } catch {
                Logger(subsystem: "com.cloakyard.cloaktools.finder", category: "scope").error("Finder folder settings need attention. Using the default workspace.")
            }
        }
        // Start new leases before ending old ones. Each extension instance owns its leases.
        FIFinderSyncController.default().directoryURLs = Set(next + [workspace].compactMap { $0 })
        scopedFolders.forEach { $0.stopAccessingSecurityScopedResource() }; scopedFolders = next
    }
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        guard let target = controller.targetedURL() else { return nil }
        let selected = controller.selectedItemURLs() ?? []
        let menu = NSMenu(title: "CloakTools")
        func action(_ title: String, _ intent: FinderIntent) {
            let item = NSMenuItem(title: title, action: #selector(send(_:)), keyEquivalent: "")
            bind(item, intent: intent)
            menu.addItem(item)
        }
        var folder: URL?
        switch menuKind {
        case .contextualMenuForContainer: folder = target
        case .contextualMenuForItems, .contextualMenuForSidebar:
            if selected.count == 1, let item = selected.first,
               (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { folder = item }
        default: break
        }
        if let folder {
            let parent = NSMenuItem(title: "New File with CloakTools", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for template in ToolAvailability(developerEnabled: false).builtInTemplates {
                let item = NSMenuItem(title: template.title, action: #selector(send(_:)), keyEquivalent: "")
                bind(item, intent: .create(folder: folder, template: template))
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
            let saved = NSMenuItem(title: "Choose File Type or Template…", action: #selector(send(_:)), keyEquivalent: "")
            bind(saved, intent: .templates(folder: folder)); submenu.addItem(saved)
            let clipboard = NSMenuItem(title: "New File from Clipboard…", action: #selector(send(_:)), keyEquivalent: "")
            bind(clipboard, intent: .clipboard(folder: folder)); submenu.addItem(clipboard)
            parent.submenu = submenu; menu.addItem(parent)
            if menuKind == .contextualMenuForContainer || menuKind == .contextualMenuForSidebar {
                action("Reuse Folder Structure…", .structure(folder: folder))
            }
        }
        if menuKind == .contextualMenuForItems, selected.count == 1, let image = selected.first,
           ImageConversion.inputExtensions.contains(image.pathExtension.lowercased()) {
            let item = NSMenuItem(title: "Convert Image with CloakTools…", action: #selector(send(_:)), keyEquivalent: "")
            bind(item, intent: .convert(image: image)); menu.addItem(item)
        }
        if menuKind == .contextualMenuForItems, (1...PDFAssembly.maximumFiles).contains(selected.count),
           selected.allSatisfy({ PDFAssembly.inputExtensions.contains($0.pathExtension.lowercased()) }) {
            let item = NSMenuItem(title: "Assemble PDF with CloakTools…", action: #selector(send(_:)), keyEquivalent: "")
            let files = selected.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            bind(item, intent: .assemble(files: files)); menu.addItem(item)
        }
        if menuKind == .contextualMenuForItems {
            for entry in FinderIntent.reviewActions(for: selected) { action(entry.title, entry.intent) }
        }
        let copyFiles = menuKind == .contextualMenuForContainer ? [target] : selected
        if [.contextualMenuForContainer, .contextualMenuForItems, .contextualMenuForSidebar].contains(menuKind),
           (1...CopySelection.maximumItems).contains(copyFiles.count) {
            let item = NSMenuItem(title: "Copy As with CloakTools…", action: #selector(send(_:)), keyEquivalent: "")
            let files = copyFiles.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            bind(item, intent: .copy(files: files)); menu.addItem(item)
        }
        return menu.items.isEmpty ? nil : menu
    }
    @objc private func send(_ sender: NSMenuItem) {
        guard let request = intents[sender.tag] else { return }
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.open([request], withApplicationAt: host, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                Logger(subsystem: "com.cloakyard.cloaktools.finder", category: "handoff").error("Host handoff failed. Open CloakTools and retry.")
            }
        }
    }
}
