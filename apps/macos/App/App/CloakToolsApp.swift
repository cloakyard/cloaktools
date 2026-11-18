import SwiftUI
import AppKit
import CloakToolsCore

@main
struct CloakToolsApp: App {
    @StateObject private var updater = AppUpdater()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("CloakTools", id: "workbench") {
            WorkbenchView(model: AppModel.shared, navigation: AppModel.shared.workbench)
                .handlesExternalEvents(preferring: ["cloaktools-action:"], allowing: ["*"])
                .onOpenURL { url in delegate.receive(url, sourceApplication: IncomingEventSource.current()) }
        }
        .defaultSize(width: 1000, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            WorkbenchCommands(model: AppModel.shared)
            UpdateCommands(updater: updater)
            SidebarCommands()
        }
        Settings {
            SettingsView(model: AppModel.shared).environmentObject(updater)
        }
        .defaultSize(width: 640, height: 600)
    }
}

private struct WorkbenchCommands: Commands {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About CloakTools") {
                model.settingsTab = .about
                openSettings()
                NSApp.activate()
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New File…") { model.chooseCreationFolder() }.keyboardShortcut("n", modifiers: .command)
            Button("New File Set…") { model.chooseFileSetFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Markdown Digest…", action: model.presentMarkdownDigest)
            Menu("New File from Preset") {
                ForEach(model.visibleFolderPresets) { preset in
                    Button(preset.title) { model.presentPreset(preset) }
                }
                if !model.visibleFolderPresets.isEmpty { Divider() }
                Button("Manage Folder Presets…") {
                    show(.presets)
                }
            }
            Divider()
            Button("Make It Fit…") { model.chooseImageToFit() }.keyboardShortcut("k", modifiers: [.command, .option])
            Button("Export Media…") { model.chooseMediaToExport() }.keyboardShortcut("e", modifiers: [.command, .option])
            Menu("Recreate Export") {
                ForEach(model.exportRecipes) { recipe in Button(recipe.title) { model.useRecipe(recipe) } }
                if !model.exportRecipes.isEmpty { Divider() }
                Button("Manage Export Recipes…") {
                    show(.recipes)
                }
            }
            Divider()
            Menu("Finder Tools") {
                Button("Reuse Folder Structure…", action: model.chooseStructure)
                Button("Collect Copies for Sharing…") { model.collectForSharing([]) }
                Button("Compare Two Folders…", action: model.chooseComparison)
            }
            Button("File List…", action: model.presentFileList)
            Button("Copy As…") { model.chooseCopyFiles() }.keyboardShortcut("c", modifiers: [.command, .option])
            Divider()
            Menu("Text & Sharing") {
                Button("Create QR Code…", action: model.presentQRCode)
                Button("Read QR Code…", action: model.presentQRReader)
                Button("Text Cleanup…", action: model.presentTextCleanup)
                Divider()
                Button("New File from Clipboard…") { model.chooseClipboardFolder() }.keyboardShortcut("n", modifiers: [.command, .option])
            }
            Menu("Images & PDFs") {
                Button("Convert Image…") { model.chooseImage() }.keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Assemble PDF…") { model.choosePDFFiles() }.keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Organize PDF…") { model.choosePDFToOrganize() }.keyboardShortcut("p", modifiers: [.command, .option])
            }
            if model.preferences.developerToolsEnabled {
                Menu("Developer Tools") {
                    Button("JSON…") { model.presentDeveloperText(.json) }
                    Button("Base64…") { model.presentDeveloperText(.base64) }
                    Button("Sample Files…", action: model.presentSampleFiles)
                    Button("Example Copy…", action: model.presentExampleCopy)
                }
            }
            Divider()
            Button("Open a Link Once…") {
                show(.openLink)
            }.keyboardShortcut("o", modifiers: [.command, .option])
            Button("Test a Link…") {
                show(.testLink)
            }.keyboardShortcut("t", modifiers: [.command, .option])
        }
        CommandGroup(after: .textEditing) {
            Button("Find a Tool…") {
                openWindow(id: "workbench")
                model.workbench.searchRequest += 1
            }.keyboardShortcut("f", modifiers: .command)
        }
        CommandGroup(replacing: .help) {
            Link("CloakTools Support", destination: URL(string: "https://tools.cloakyard.com/support/")!)
        }
    }
    private func show(_ tool: WorkbenchTool) {
        model.workbench.show(tool)
        openWindow(id: "workbench")
        NSApp.activate()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached(priority: .utility) { TemporaryMediaRecovery.recoverAbandonedCaptures() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--appearance=dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if ProcessInfo.processInfo.arguments.contains("--appearance=light") { NSApp.appearance = NSAppearance(named: .aqua) }
        #endif
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }
    // AppKit supplies URLs that were not already delivered to an open Workbench.
    func application(_ application: NSApplication, open urls: [URL]) {
        let sourceApplication = IncomingEventSource.current()
        for url in urls { receive(url, sourceApplication: sourceApplication) }
    }

    func receive(_ url: URL, sourceApplication: String?) {
        if url.scheme == "cloaktools-action" {
            do { AppModel.shared.present(try FinderIntent(url: url)) }
            catch { AppModel.shared.showError(error) }
        } else {
            AppModel.shared.router.receive(url.absoluteString, sourceApplication: sourceApplication)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let show = AppModel.shared.workbench.showWindow else { return true }
        show()
        return false
    }
    @objc func folderActions(_ board: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = selectedURLs(board)
        guard !urls.isEmpty, urls.allSatisfy({ url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isPackage != true && values?.isSymbolicLink != true
        }) else { error.pointee = "Select ordinary folders in Finder."; return }
        Task { @MainActor in await AppModel.shared.useSelectedFolders(urls) }
    }
    private func selectedURLs(_ board: NSPasteboard) -> [URL] {
        (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    @objc func fitImage(_ board: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = selectedURLs(board)
        Task { @MainActor in
            if let url = await chooseFinderItem(urls, heading: "Which image should fit the size limit?") { AppModel.shared.present(.fit(image: url)) }
        }
    }
    @objc func readQR(_ board: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = selectedURLs(board)
        Task { @MainActor in
            if let url = await chooseFinderItem(urls, heading: "Which image contains the QR code?") { AppModel.shared.presentQRReader(image: url) }
        }
    }
    @objc func collectCopies(_ board: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = selectedURLs(board)
        guard (1...SharingCollection.maximumFiles).contains(urls.count) else { error.pointee = "Select 1–200 files."; return }
        AppModel.shared.present(.collect(files: urls))
        // Return focus after the Services callback has activated its provider.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard NSApp.isActive, let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else { return }
            NSApp.yieldActivation(to: finder)
            finder.activate(options: [])
        }
    }
    @objc func copyAs(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              (1...CopySelection.maximumItems).contains(files.count) else { error.pointee = "Select 1–200 files or folders in Finder."; return }
        AppModel.shared.present(.copy(files: files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }))
    }
}
