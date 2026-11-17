import SwiftUI
import AppKit
import CloakToolsCore

@main
struct CloakToolsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("CloakTools", id: "settings") {
            SettingsView(model: AppModel.shared)
                .onAppear { AppDelegate.showMain = { openWindow(id: "settings") } }
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 900, height: 650)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { openWindow(id: "settings"); NSApp.activate() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New File…") { AppModel.shared.chooseCreationFolder() }.keyboardShortcut("n", modifiers: .command)
                Button("New File Set…") { AppModel.shared.chooseFileSetFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Markdown Digest…", action: AppModel.shared.presentMarkdownDigest)
                Menu("New File from Preset") {
                    ForEach(AppModel.shared.visibleFolderPresets) { preset in
                        Button(preset.title) { AppModel.shared.presentPreset(preset) }
                    }
                    if !AppModel.shared.visibleFolderPresets.isEmpty { Divider() }
                    Button("Manage Folder Presets…") {
                        AppModel.shared.update { $0.lastCategory = .newFiles }
                        AppModel.shared.settingsNavigationID = UUID()
                        openWindow(id: "settings"); NSApp.activate()
                    }
                }
                Divider()
                Button("Make It Fit…") { AppModel.shared.chooseImageToFit() }.keyboardShortcut("k", modifiers: [.command, .option])
                Button("Export Media…") { AppModel.shared.chooseMediaToExport() }.keyboardShortcut("e", modifiers: [.command, .option])
                Menu("Recreate Export") {
                    ForEach(AppModel.shared.exportRecipes) { recipe in Button(recipe.title) { AppModel.shared.useRecipe(recipe) } }
                    if !AppModel.shared.exportRecipes.isEmpty { Divider() }
                    Button("Manage Export Recipes…") {
                        AppModel.shared.update { $0.lastCategory = .conversions }; AppModel.shared.settingsNavigationID = UUID()
                        openWindow(id: "settings"); NSApp.activate()
                    }
                }
                Divider()
                Button("File List…", action: AppModel.shared.presentFileList)
                Button("Copy As…") { AppModel.shared.chooseCopyFiles() }.keyboardShortcut("c", modifiers: [.command, .option])
                Divider()
                Menu("Text & Sharing") {
                    Button("Create QR Code…", action: AppModel.shared.presentQRCode)
                    Button("Read QR Code…", action: AppModel.shared.presentQRReader)
                    Button("Text Cleanup…", action: AppModel.shared.presentTextCleanup)
                    Divider()
                    Button("New File from Clipboard…") { AppModel.shared.chooseClipboardFolder() }.keyboardShortcut("n", modifiers: [.command, .option])
                }
                Menu("Images & PDFs") {
                    Button("Convert Image…") { AppModel.shared.chooseImage() }.keyboardShortcut("k", modifiers: [.command, .shift])
                    Button("Assemble PDF…") { AppModel.shared.choosePDFFiles() }.keyboardShortcut("p", modifiers: [.command, .shift])
                    Button("Organize PDF…") { AppModel.shared.choosePDFToOrganize() }.keyboardShortcut("p", modifiers: [.command, .option])
                }
                if AppModel.shared.preferences.developerToolsEnabled {
                    Menu("Developer Tools") {
                        Button("JSON…") { AppModel.shared.presentDeveloperText(.json) }
                        Button("Base64…") { AppModel.shared.presentDeveloperText(.base64) }
                        Button("Sample Files…", action: AppModel.shared.presentSampleFiles)
                        Button("Example Copy…", action: AppModel.shared.presentExampleCopy)
                    }
                }
                Divider()
                Button("Open a Link Once…") {
                    AppModel.shared.update { $0.lastCategory = .openWith }
                    openWindow(id: "settings"); AppModel.shared.routing.showingOneTime = true
                }.keyboardShortcut("o", modifiers: [.command, .option])
                Button("Test a Link…") {
                    AppModel.shared.update { $0.lastCategory = .openWith }
                    openWindow(id: "settings"); AppModel.shared.routing.showingTester = true
                }.keyboardShortcut("t", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) {
                Link("CloakTools Support", destination: URL(string: "https://tools.cloakyard.com/support/")!)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var showMain: (() -> Void)?
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached(priority: .utility) { TemporaryMediaRecovery.recoverAbandonedCaptures() }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--appearance=dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if ProcessInfo.processInfo.arguments.contains("--appearance=light") { NSApp.appearance = NSAppearance(named: .aqua) }
        #endif
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        let sourceApplication = IncomingEventSource.current()
        for url in urls {
            if url.scheme == "cloaktools-action" {
                do { AppModel.shared.present(try FinderIntent(url: url)) }
                catch { AppModel.shared.showError(error) }
            } else {
                AppModel.shared.router.receive(url.absoluteString, sourceApplication: sourceApplication)
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Self.showMain?() }
        return true
    }
    @objc func createFile(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let url = serviceURL(pasteboard), (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            error.pointee = "Select exactly one folder in Finder."; return
        }
        AppModel.shared.present(.create(folder: url, template: .text))
    }
    @objc func convertImage(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let url = serviceURL(pasteboard) else { error.pointee = "Select exactly one image in Finder."; return }
        AppModel.shared.present(.convert(image: url))
    }
    private func serviceURL(_ pasteboard: NSPasteboard) -> URL? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard urls?.count == 1 else { return nil }
        return urls?.first
    }
    @objc func assemblePDF(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              (1...PDFAssembly.maximumFiles).contains(files.count) else { error.pointee = "Select 1–32 PDFs or images in Finder."; return }
        AppModel.shared.present(.assemble(files: files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }))
    }
    @objc func copyAs(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let files = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              (1...CopySelection.maximumItems).contains(files.count) else { error.pointee = "Select 1–200 files or folders in Finder."; return }
        AppModel.shared.present(.copy(files: files.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }))
    }
}
