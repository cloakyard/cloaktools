import AppKit
import CloakToolsCore

@MainActor
private func chooseIndex(_ titles: [String], heading: String, detail: String) async -> Int? {
    let alert = NSAlert()
    alert.messageText = heading
    alert.informativeText = detail
    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
    picker.addItems(withTitles: titles)
    picker.setAccessibilityLabel(heading)
    alert.accessoryView = picker
    alert.addButton(withTitle: "Continue")
    alert.addButton(withTitle: "Cancel")
    NSApp.activate()
    let response: NSApplication.ModalResponse
    if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
        response = await alert.beginSheetModal(for: window)
    } else {
        response = alert.runModal()
    }
    guard response == .alertFirstButtonReturn else { return nil }
    return picker.indexOfSelectedItem
}

@MainActor
func chooseFinderItem(_ urls: [URL], heading: String) async -> URL? {
    guard !urls.isEmpty else { return nil }
    if urls.count == 1 { return urls[0] }
    // Paths disambiguate equal names in Finder search results.
    let titles = urls.map { ($0.path as NSString).abbreviatingWithTildeInPath }
    return await chooseIndex(titles, heading: heading, detail: "Choose from your Finder selection.").map { urls[$0] }
}

extension AppModel {
    func useSelectedFolders(_ folders: [URL]) async {
        if folders.count == 2 {
            present(.compare(first: folders[0], second: folders[1]))
            return
        }
        guard let folder = await chooseFinderItem(folders, heading: "Choose a folder to work with") else { return }
        let sets = visibleFileSets
        let actions = ["Reuse Folder Structure", "Compare with Another Folder", "New File from Template", "New File from Clipboard"]
        let names = actions + sets.map { "Use file set · " + $0.title }
        guard let index = await chooseIndex(names, heading: "Folder actions", detail: folder.path) else { return }
        switch index {
        case 0: present(.structure(folder: folder))
        case 1:
            if folders.count > 2 {
                guard let second = await chooseFinderItem(folders.filter { $0 != folder }, heading: "Compare with which folder?") else { return }
                present(.compare(first: folder, second: second))
            } else { present(.compare(first: folder, second: nil)) }
        case 2: present(.templates(folder: folder))
        case 3: present(.clipboard(folder: folder))
        default: chooseFileSetFolder(sets[index - actions.count], destination: folder)
        }
    }
}

/// Exists only while there is a collection started or extended from Finder.
@MainActor
final class SharingStatus {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let review: () -> Void
    init(review: @escaping () -> Void) {
        self.review = review
        item.button?.target = self
        item.button?.action = #selector(openReview)
        item.button?.imagePosition = .imageLeading
    }
    func update(count: Int, error: String?) {
        let description = error ?? "\(count) \(count == 1 ? "file" : "files") collected"
        let button = item.button
        button?.image = NSImage(systemSymbolName: error == nil ? "tray.full" : "exclamationmark.triangle", accessibilityDescription: nil)
        button?.title = " \(count)"
        button?.toolTip = description + " · Review collection"
        button?.setAccessibilityLabel(description + ". Review collection")
    }
    func remove() { NSStatusBar.system.removeStatusItem(item) }
    @objc private func openReview() { review() }
}
