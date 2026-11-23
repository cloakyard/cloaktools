import AppKit
import SwiftUI
import FinderSync
import CloakToolsCore
import UniformTypeIdentifiers

@MainActor @Observable
final class AppModel {
    static let shared = AppModel(history: RecentOptimizations(file: PreferencesStore.standard.url.deletingLastPathComponent().appendingPathComponent("recent-optimizations.json")))
    let recentOptimizations: RecentOptimizations
    private let store = PreferencesStore.standard
    var preferences: Preferences
    var customTemplates: [CustomTemplate] = []
    private let library = TemplateLibraryStore.standard
    private let presetStore = FolderPresetStore.standard
    var folderPresets: [FolderPreset] = []
    var presetError: String?
    private let fileSetStore = FileSetStore.standard
    var fileSets: [FileSetDefinition] = []
    var fileSetError: String?
    private let recipeStore = ExportRecipeStore.standard
    var exportRecipes: [ExportRecipe] = []
    var recipeError: String?
    private(set) var dropZone: OptimizationDropZone?
    let automaticOptimization = AutomaticOptimization()
    private let dropZoneShortcut = DropZoneShortcut()
    private(set) var dropZoneShortcutError: String?
    let workbench = WorkbenchNavigation()
    var settingsTab: SettingsCategory = .general
    var persistenceError: String?
    var templateLibraryError: String?
    var finderEnabled = FIFinderSyncController.isExtensionEnabled
    let router = LinkRouter()
    let routing = RoutingSettings()
    let defaultHandlers = DefaultHandlerSettings()
    let finderScopes = FinderScopeSettings()
    private(set) var sharingReview: SharingReview?
    private(set) var optimizer: OptimizationReview?
    private(set) weak var lastOptimizer: OptimizationReview?
    private(set) var finderCollectionActive = false
    private var sharingStatus: SharingStatus?
    private var operationWindows: [UUID: NSWindowController] = [:]
    private func hasRoomForOperation() -> Bool {
        let backgroundCollection = sharingReview.map { workbench.drafts[.collect] == nil && operationWindows[$0.task.id] == nil } ?? false
        guard operationWindows.count + workbench.drafts.count + (backgroundCollection ? 1 : 0) < 8 else {
            showError(NSError(domain: "CloakTools", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Finish or close an open task before starting another. You can resume a task from In Progress."
            ]))
            return false
        }
        return true
    }
    init(history: RecentOptimizations = RecentOptimizations()) {
        recentOptimizations = history
        do { preferences = try store.load() }
        catch { preferences = Preferences(); persistenceError = "Settings could not be read: \(error.localizedDescription)" }
        do { customTemplates = try library.load() }
        catch { templateLibraryError = "Saved templates could not be read: \(error.localizedDescription)" }
        reloadPresets()
        reloadFileSets()
        reloadRecipes()
        automaticOptimization.didSave = { output, _, _ in history.add(output, batch: UUID()) }
    }
    var allTemplateSources: [TemplateSource] { FileTemplate.allCases.map(TemplateSource.builtIn) + customTemplates.map(TemplateSource.custom) }
    var visibleCustomTemplates: [CustomTemplate] { customTemplates.filter { preferences.tools.includes(.custom($0)) } }
    var visibleFolderPresets: [FolderPreset] { folderPresets.filter { preferences.tools.includes(templateID: $0.templateID, sources: allTemplateSources) } }
    var visibleFileSets: [FileSetDefinition] { fileSets.filter { preferences.tools.includes($0, sources: allTemplateSources) } }
    var templateSources: [TemplateSource] {
        allTemplateSources.filter { preferences.tools.includes($0) }.sorted {
            let left = preferences.favoriteTemplateIDs.contains($0.id), right = preferences.favoriteTemplateIDs.contains($1.id)
            if left != right { return left }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    func reloadPresets() {
        do { folderPresets = try presetStore.load(); presetError = nil }
        catch { presetError = "Folder presets could not be read: \(error.localizedDescription)" }
    }
    func reloadRecipes() {
        do { exportRecipes = try recipeStore.load(); recipeError = nil }
        catch { recipeError = "Export recipes could not be read: \(error.localizedDescription)" }
    }
    func saveRecipe(_ recipe: ExportRecipe, replacing original: ExportRecipe?) throws {
        exportRecipes = try recipeStore.upsert(recipe, replacing: original); recipeError = nil
        configureAutomaticOptimization()
    }
    func removeRecipe(_ recipe: ExportRecipe) {
        do {
            let updated = try recipeStore.load().filter { $0.id != recipe.id }
            try recipeStore.save(updated); exportRecipes = updated; recipeError = nil
            configureAutomaticOptimization()
        } catch { recipeError = error.localizedDescription }
    }
    func useRecipe(_ selected: ExportRecipe) {
        guard hasRoomForOperation() else { return }
        do {
            guard let recipe = try recipeStore.load().first(where: { $0.id == selected.id }) else { throw ExportRecipeError.changed }
            let snapshot = try store.load()
            let panel = NSOpenPanel(); panel.title = "Use “\(recipe.title)”"; panel.prompt = "Review Source"
            panel.message = "\(recipe.options.summary). Choose a fresh source; nothing exports until you confirm."
            panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
            switch recipe.options {
            case .optimize:
                panel.allowsMultipleSelection = true
                panel.allowedContentTypes = MediaOptimization.extensions.sorted().compactMap { UTType(filenameExtension: $0) }
            case .image, .fit: panel.allowedContentTypes = ImageConversion.inputTypes
            case .media: panel.allowedContentTypes = MediaExport.inputExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
            }
            let completion: (NSApplication.ModalResponse) -> Void = { [weak self, panel] response in
                guard let self, response == .OK, let source = panel.url else { return }
                // Recheck the limit when an asynchronous picker returns.
                guard self.hasRoomForOperation() else { return }
                switch recipe.options {
                case .optimize:
                    self.presentOptimizer(files: panel.urls, recipe: recipe)
                case .image:
                    let operation = FileOperation(intent: .convert(image: source), preferences: snapshot, sources: [], recipe: recipe)
                    self.display(operation)
                case .fit:
                    let operation = ImageFitOperation(sourceURL: source, revealOutput: snapshot.revealConvertedFile, recipe: recipe)
                    self.display(operation)
                case .media:
                    let operation = MediaOperation(sourceURL: source, revealOutput: snapshot.revealConvertedFile, recipe: recipe)
                    self.display(operation)
                }
            }
            NSApp.activate()
            if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil { panel.beginSheetModal(for: window, completionHandler: completion) }
            else { panel.begin(completionHandler: completion) }
        } catch { showError(error) }
    }
    private func presentEditor<Panel: NSWindowController & OperationPanel, Content: View>(
        _ tool: WorkbenchTool, id: UUID, busy: @escaping () -> Bool = { false },
        finish: @escaping () -> Void = {}, panel makePanel: @autoclosure () -> Panel,
        @ViewBuilder content: (@escaping () -> Void) -> Content
    ) {
        if workbench.present(tool, busy: busy, finish: finish, content: content) { return }
        let controller = makePanel()
        operationWindows[id] = controller
        controller.onClose = { [weak self] in self?.operationWindows[id] = nil }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func display(_ operation: FileOperation) {
        let tool: WorkbenchTool = operation.isCreation ? .newFile : .convert
        presentEditor(tool, id: operation.id, busy: { operation.busy }, panel: OperationWindow(operation: operation)) { close in
            OperationView(operation: operation, close: close)
        }
    }

    private func display(_ operation: ImageFitOperation) {
        presentEditor(.fit, id: operation.id, busy: { operation.busy }, panel: ImageFitWindow(operation: operation)) { close in
            ImageFitView(inWorkbench: true, operation: operation, close: close)
        }
    }

    private func display(_ operation: MediaOperation) {
        presentEditor(.exportMedia, id: operation.id, busy: { operation.busy }, finish: operation.finish, panel: MediaWindow(operation: operation)) { close in
            MediaOperationView(operation: operation, close: close)
                .onDisappear { operation.player?.pause() }
        }
    }

    func reloadFileSets() {
        do { fileSets = try fileSetStore.load(); fileSetError = nil }
        catch { fileSetError = "File sets could not be read: \(error.localizedDescription)" }
    }
    func saveFileSet(_ set: FileSetDefinition) throws {
        let sources = FileTemplate.allCases.map(TemplateSource.builtIn) + (try library.load()).map(TemplateSource.custom)
        try set.validate(sources: sources)
        var updated = try fileSetStore.load()
        if let index = updated.firstIndex(where: { $0.id == set.id }) { updated[index] = set } else { updated.append(set) }
        updated.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        try fileSetStore.save(updated); fileSets = updated; fileSetError = nil
    }
    func removeFileSet(_ set: FileSetDefinition) {
        do {
            let updated = try fileSetStore.load().filter { $0.id != set.id }
            try fileSetStore.save(updated); fileSets = updated; fileSetError = nil
        } catch { fileSetError = error.localizedDescription }
    }
    func chooseFileSetFolder(_ definition: FileSetDefinition = .notes, destination: URL? = nil) {
        guard hasRoomForOperation() else { return }
        do {
            let preferences = try store.load()
            let allSources = FileTemplate.allCases.map(TemplateSource.builtIn) + (try library.load()).map(TemplateSource.custom)
            guard preferences.tools.includes(definition, sources: allSources) else { throw ToolAvailabilityError.developerToolsOff }
            let sources = allSources.filter { preferences.tools.includes($0) }
            func review(in folder: URL) {
                guard self.hasRoomForOperation() else { return }
                let operation = FileSetOperation(definition: definition, sources: sources, preferences: preferences, destination: folder)
                self.presentEditor(.fileSet, id: operation.id, busy: { operation.busy }, panel: FileSetWindow(operation: operation)) { close in
                    FileSetView(operation: operation, close: close)
                }
            }
            if let destination { review(in: destination); return }
            let panel = NSOpenPanel(); panel.title = "Create a file set in…"; panel.prompt = "Choose Folder"
            panel.message = "A new folder will hold the files you review next. Existing folders are never merged."
            panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                if response == .OK, let folder = panel.url { review(in: folder) }
            }
            NSApp.activate()
            if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
            } else { panel.begin(completionHandler: completion) }
        } catch { showError(error) }
    }
    func savePreset(_ preset: FolderPreset) throws {
        _ = try preset.request(preferences: try store.load(), templates: try library.load())
        var updated = try presetStore.load()
        if let index = updated.firstIndex(where: { $0.id == preset.id }) { updated[index] = preset } else { updated.append(preset) }
        updated.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        try presetStore.save(updated); folderPresets = updated; presetError = nil
    }
    func removePreset(_ preset: FolderPreset) {
        do { let updated = try presetStore.load().filter { $0.id != preset.id }; try presetStore.save(updated); folderPresets = updated; presetError = nil }
        catch { presetError = error.localizedDescription }
    }
    func presentPreset(_ preset: FolderPreset) {
        guard hasRoomForOperation() else { return }
        do {
            let templates = try library.load()
            let request = try preset.request(preferences: try store.load(), templates: templates)
            guard request.preferences.tools.includes(request.source) else { throw ToolAvailabilityError.developerToolsOff }
            let sources = (FileTemplate.allCases.map(TemplateSource.builtIn) + templates.map(TemplateSource.custom)).filter { request.preferences.tools.includes($0) }
            let operation = FileOperation(intent: .create(folder: request.folder, template: .text), preferences: request.preferences, sources: sources)
            operation.selectedTemplateID = request.source.id; operation.name = request.name; operation.presetTitle = preset.title
            display(operation)
        } catch { showError(error) }
    }
    func update(_ edit: (inout Preferences) -> Void) {
        var updated = preferences; edit(&updated); updated.normalizeToolSelection()
        do {
            try store.save(updated)
            let visibilityChanged = preferences.showMenuBarTools != updated.showMenuBarTools
            preferences = updated
            configureAutomaticOptimization()
            if visibilityChanged { updateSharingStatus() }
            persistenceError = nil
        }
        catch { persistenceError = "Settings could not be saved: \(error.localizedDescription)" }
    }
    func restoreOptimizationBackup() {
        let picker = NSOpenPanel()
        picker.title = "Choose an original from a CloakTools Backup folder"
        picker.prompt = "Review Backup"
        guard picker.runModal() == .OK, let file = picker.url else { return }
        do {
            let backup = try OptimizationBackup(backupFile: file)
            let review = NSAlert()
            review.messageText = "Restore “\(backup.originalURL.lastPathComponent)”?"
            review.informativeText = "The original will return to \(backup.originalURL.path). The current optimized version will move into the backup folder."
            review.addButton(withTitle: "Restore Original")
            review.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
            if review.runModal() == .alertFirstButtonReturn {
                try backup.restore()
                recentOptimizations.restored(backup.backupURL)
                NSWorkspace.shared.activateFileViewerSelecting([backup.originalURL])
            }
        } catch { showError(error) }
    }

    func showDropZone() {
        if dropZone == nil {
            let zone = OptimizationDropZone(model: self)
            zone.onClose = { [weak self] in self?.dropZone = nil }
            dropZone = zone
        }
        dropZone?.showAtPointer()
    }

    func configureAutomaticOptimization() {
        let available = dropZoneShortcut.configure(preferences.dropZoneKey) { [weak self] in self?.showDropZone() }
        dropZoneShortcutError = available ? nil : "This shortcut is unavailable. Record a different combination."
        automaticOptimization.configure(clipboard: preferences.optimizeCopiedImages && !preferences.automationPaused,
                                        rules: preferences.automationPaused ? [] : preferences.folderRules, recipes: exportRecipes)
    }
    func saveFolderRule(_ rule: OptimizationFolderRule) throws {
        try rule.validate(alongside: preferences.folderRules)
        var value = preferences
        if let i = value.folderRules.firstIndex(where: { $0.id == rule.id }) { value.folderRules[i] = rule }
        else { value.folderRules.append(rule) }
        try store.save(value)
        preferences = value
        configureAutomaticOptimization()
    }
    func completeToolSelection(developerEnabled: Bool) throws {
        var updated = preferences
        updated.developerToolsEnabled = developerEnabled; updated.hasChosenTools = true
        updated.normalizeToolSelection()
        try store.save(updated)
        preferences = updated; persistenceError = nil
    }
    var workspace: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("CloakTools Files", isDirectory: true) }
    func openWorkspace() {
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            NSWorkspace.shared.open(workspace)
        } catch { showError(error) }
    }
    func refreshFinder() { finderEnabled = FIFinderSyncController.isExtensionEnabled; finderScopes.reload() }
    func chooseCreationFolder() {
        let panel = NSOpenPanel(); panel.title = "Create a file in…"; panel.prompt = "Choose Folder"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let folder = panel.url { present(.create(folder: folder, template: .text)) }
    }
    func chooseImage() {
        let panel = NSOpenPanel(); panel.title = "Convert an image"; panel.prompt = "Choose Image"
        panel.allowedContentTypes = ImageConversion.inputTypes; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let input = panel.url { present(.convert(image: input)) }
    }
    func chooseImageToFit() {
        guard hasRoomForOperation() else { return }
        let panel = NSOpenPanel(); panel.title = "Make an image fit"; panel.prompt = "Choose Image"
        panel.allowedContentTypes = ImageConversion.inputTypes; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let input = panel.url else { return }
        present(.fit(image: input))
    }
    func present(_ intent: FinderIntent) {
        switch intent {
        case let .fit(image):
            guard hasRoomForOperation() else { return }
            display(ImageFitOperation(sourceURL: image, revealOutput: preferences.revealConvertedFile))
            return
        case let .structure(folder):
            guard hasRoomForOperation() else { return }
            let review = StructureReview(folder)
            showReview(.structure, task: review.task) { close in
                StructureReviewView(review: review, saveSet: self.saveFileSet, close: close)
            }
            return
        case let .compare(first, second):
            guard hasRoomForOperation() else { return }
            guard let second else {
                let panel = NSOpenPanel()
                panel.title = "Compare “\(first.lastPathComponent)” with…"
                panel.message = panel.title
                panel.prompt = "Compare Folders"
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.directoryURL = first.deletingLastPathComponent()
                NSApp.activate()
                panel.begin { [weak self] response in
                    if response == .OK, let folder = panel.url { self?.present(.compare(first: first, second: folder)) }
                }
                return
            }
            let review = ComparisonReview(first, second)
            showReview(.compare, task: review.task) { ComparisonReviewView(review: review, close: $0) }
            return
        case let .collect(files):
            collectForSharing(files)
            return
        case let .clipboard(folder): createFromClipboard(in: folder); return
        case let .assemble(files): presentPDF(files); return
        case let .copy(files): presentCopy(files); return
        case .create, .templates, .convert: break
        }
        guard hasRoomForOperation() else { return }
        do {
            // Read once at ingress. A later settings edit cannot change this operation.
            let snapshot = try store.load()
            if case let .create(_, template) = intent, !snapshot.tools.includes(.builtIn(template)) { throw ToolAvailabilityError.developerToolsOff }
            let templates: [CustomTemplate]
            if case .convert = intent { templates = [] } else { templates = try library.load() }
            let sources = (FileTemplate.allCases.map(TemplateSource.builtIn) + templates.map(TemplateSource.custom)).filter { snapshot.tools.includes($0) }.sorted {
                let left = snapshot.favoriteTemplateIDs.contains($0.id), right = snapshot.favoriteTemplateIDs.contains($1.id)
                if left != right { return left }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            let operation = FileOperation(intent: intent, preferences: snapshot, sources: sources)
            display(operation)
        } catch { showError(error) }
    }
    func chooseClipboardFolder() { createFromClipboard(in: nil) }
    func beginPDFReview() { presentPDF([]) }

    func choosePDFFiles() {
        let panel = PDFOperation.filePanel()
        if panel.runModal() == .OK { presentPDF(panel.urls) }
    }
    func choosePDFToOrganize() {
        guard hasRoomForOperation() else { return }
        let panel = NSOpenPanel(); panel.title = "Organize a PDF"; panel.prompt = "Choose PDF"
        panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose an ordinary PDF with up to 200 pages and 100 MB. The original stays unchanged."
        guard panel.runModal() == .OK, let input = panel.url, hasRoomForOperation() else { return }
        do {
            let operation = PDFPagesOperation(sourceURL: input, preferences: try store.load())
            presentEditor(.pages, id: operation.id, busy: { operation.busy }, finish: operation.finishPreview, panel: PDFPagesWindow(operation: operation)) { close in
                PDFPagesView(operation: operation, close: close)
            }
        } catch { showError(error) }
    }
    func chooseMediaToExport() {
        guard hasRoomForOperation() else { return }
        let panel = NSOpenPanel(); panel.title = "Export media"; panel.prompt = "Choose Media"
        panel.allowedContentTypes = MediaExport.inputExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose a local movie or audio file, up to 1 GB and 30 minutes. The original stays unchanged."
        guard panel.runModal() == .OK, let input = panel.url, hasRoomForOperation() else { return }
        let operation = MediaOperation(sourceURL: input, revealOutput: preferences.revealConvertedFile)
        display(operation)
    }
    func chooseCopyFiles() {
        let panel = NSOpenPanel(); panel.title = "Copy names and paths"; panel.prompt = "Choose Items"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.message = "Choose up to 200 files or folders. Only their names and paths are used."
        if panel.runModal() == .OK { presentCopy(panel.urls) }
    }
    func presentDeveloperText(_ tool: DeveloperTextTool) {
        guard hasRoomForOperation() else { return }
        do {
            guard try store.load().developerToolsEnabled else { throw ToolAvailabilityError.developerToolsOff }
            let operation = DeveloperTextOperation(tool: tool)
            let page: WorkbenchTool = tool == .json ? .json : .base64
            let image = tool == .base64 ? Base64ImageOperation() : nil
            image?.onSaved = workbench.endEditingAfterSave(on: page)
            presentEditor(page, id: operation.id, busy: { image?.saving == true }, finish: {
                operation.invalidate()
                image?.cancel()
            }, panel: DeveloperTextWindow(operation: operation)) { close in
                DeveloperToolWorkspace(operation: operation, imageOperation: image, close: close)
            }
        } catch { showError(error) }
    }
    func presentSampleFiles() {
        guard hasRoomForOperation() else { return }
        do {
            guard try store.load().developerToolsEnabled else { throw ToolAvailabilityError.developerToolsOff }
            let operation = SampleFileOperation()
            operation.onSaved = workbench.endEditingAfterSave(on: .sample)
            presentEditor(.sample, id: operation.id, busy: { operation.saving }, finish: operation.cancel, panel: SampleFileWindow(operation: operation)) { close in
                SampleFileView(operation: operation, close: close)
            }
        } catch { showError(error) }
    }
    func presentQRCode() { presentQRWindow(reading: false) }
    func presentQRReader() { presentQRWindow(reading: true) }
    func presentQRReader(image: URL) { presentQRWindow(reading: true, image: image) }
    private func presentQRWindow(reading: Bool, image: URL? = nil) {
        guard hasRoomForOperation() else { return }
        let operation = QRCodeOperation()
        operation.reading = reading
        let page: WorkbenchTool = reading ? .readQR : .createQR
        let reader = QRCodeReadOperation()
        if let image { reader.read(image) }
        operation.onSaved = workbench.endEditingAfterSave(on: page)
        reader.onSaved = operation.onSaved
        presentEditor(page, id: operation.id, busy: { operation.saving || reader.saving }, finish: {
            operation.cancel()
            reader.cancel()
        }, panel: QRCodeWindow(operation: operation, reader: reader)) { close in
            QRCodeWorkspace(operation: operation, reader: reader, close: close)
        }
    }
    func presentFileList() { presentFileList([]) }
    func presentFileList(_ urls: [URL]) {
        guard hasRoomForOperation() else { return }
        let operation = FileListOperation()
        operation.add(urls)
        operation.onSaved = workbench.endEditingAfterSave(on: .fileList)
        presentEditor(.fileList, id: operation.id, busy: { operation.saving }, finish: operation.cancel, panel: FileListWindow(operation: operation)) { close in
            FileListView(operation: operation, close: close)
        }
    }
    func presentTextCleanup() {
        guard hasRoomForOperation() else { return }
        let operation = TextCleanupOperation()
        operation.onSaved = workbench.endEditingAfterSave(on: .cleanup)
        presentEditor(.cleanup, id: operation.id, busy: { operation.saving }, finish: operation.cancel, panel: TextCleanupWindow(operation: operation)) { close in
            TextCleanupView(operation: operation, close: close)
        }
    }
    func presentMarkdownDigest() {
        guard hasRoomForOperation() else { return }
        let operation = MarkdownDigestOperation()
        operation.onSaved = workbench.endEditingAfterSave(on: .digest)
        presentEditor(.digest, id: operation.id, busy: { operation.saving }, finish: operation.cancel, panel: MarkdownDigestWindow(operation: operation)) { close in
            MarkdownDigestView(operation: operation, close: close)
        }
    }
    func presentExampleCopy() {
        guard hasRoomForOperation() else { return }
        do {
            guard try store.load().developerToolsEnabled else { throw ToolAvailabilityError.developerToolsOff }
            let operation = ExampleCopyOperation()
            operation.onSaved = workbench.endEditingAfterSave(on: .example)
            presentEditor(.example, id: operation.id, busy: { operation.saving }, finish: operation.cancel, panel: ExampleCopyWindow(operation: operation)) { close in
                ExampleCopyView(operation: operation, close: close)
            }
        } catch { showError(error) }
    }
    private func presentCopy(_ files: [URL]) {
        guard hasRoomForOperation() else { return }
        do {
            let operation = try CopyOperation(selection: CopySelection(files: files), preferences: try store.load())
            presentEditor(.copy, id: operation.id, panel: CopyOperationWindow(operation: operation)) { close in
                CopyOperationView(operation: operation, close: close)
            }
        } catch { showError(error) }
    }
    private func presentPDF(_ files: [URL]) {
        guard hasRoomForOperation() else { return }
        do {
            let operation = PDFOperation(files: files, preferences: try store.load())
            presentEditor(.pdf, id: operation.id, busy: { operation.busy }, panel: PDFOperationWindow(operation: operation)) { close in
                PDFOperationView(operation: operation, close: close)
            }
        } catch { showError(error) }
    }
    private func createFromClipboard(in destination: URL?) {
        guard hasRoomForOperation() else { return }
        do {
            // Capture at the explicit action, before the folder picker; no background reads.
            let input = try ClipboardCapture.read()
            let snapshot = try store.load()
            let folder: URL
            if let destination { folder = destination }
            else {
                let panel = NSOpenPanel(); panel.title = "Save clipboard contents in…"; panel.prompt = "Choose Folder"
                panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let selection = panel.url, hasRoomForOperation() else { return }
                folder = selection
            }
            let operation = ClipboardOperation(input: input, destination: folder, preferences: snapshot)
            presentEditor(.clipboard, id: operation.id, busy: { operation.busy }, panel: ClipboardWindow(operation: operation)) { close in
                ClipboardView(operation: operation, close: close)
            }
        } catch { showError(error) }
    }
    func importTemplate() {
        let panel = NSOpenPanel()
        panel.title = "Import a text template"; panel.prompt = "Import Template"
        panel.message = "Choose a UTF-8 text or source file up to 1 MB. CloakTools keeps its own copy."
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try CustomTemplate.importing(url)
            guard preferences.tools.includes(.custom(imported)) else { throw ToolAvailabilityError.developerToolsOff }
            var updated = try library.load(); updated.append(imported)
            try library.save(updated); customTemplates = updated; templateLibraryError = nil
        } catch { showError(error) }
    }
    func saveTemplate(_ template: CustomTemplate) throws {
        try template.validate()
        var updated = try library.load()
        guard let index = updated.firstIndex(where: { $0.id == template.id }) else { throw CocoaError(.fileNoSuchFile) }
        updated[index] = template; try library.save(updated); customTemplates = updated; templateLibraryError = nil
    }
    func removeTemplate(_ template: CustomTemplate) {
        do {
            let updated = try library.load().filter { $0.id != template.id }
            try library.save(updated); customTemplates = updated; templateLibraryError = nil
            update { $0.favoriteTemplateIDs.remove(TemplateSource.custom(template).id) }
        } catch { showError(error) }
    }
    func toggleFavorite(_ id: String) {
        update { prefs in
            if prefs.favoriteTemplateIDs.contains(id) { prefs.favoriteTemplateIDs.remove(id) }
            else { prefs.favoriteTemplateIDs.insert(id) }
        }
    }
    func showError(_ error: Error) {
        let alert = NSAlert(); alert.messageText = "CloakTools couldn’t complete this action"
        alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "OK")
        NSApp.activate(); alert.runModal()
    }
}

extension AppModel {
    private func showReview<Content: View>(_ tool: WorkbenchTool, task: FolderTask,
                                           finish: @escaping () -> Void = {},
                                           @ViewBuilder content: (@escaping () -> Void) -> Content) {
        presentEditor(tool, id: task.id, busy: { task.busy }, finish: finish,
                      panel: FinderReviewWindow(tool.rawValue, task: task, finish: finish, content: content), content: content)
    }

    func chooseStructure() {
        if let folder = chooseFinderFolder("Choose the folder whose structure you want to reuse") { present(.structure(folder: folder)) }
    }

    func chooseComparison() {
        if let first = chooseFinderFolder("Choose the first folder to compare") { present(.compare(first: first, second: nil)) }
    }

    private func updateSharingStatus() {
        guard finderCollectionActive, !preferences.showMenuBarTools, let review = sharingReview else {
            sharingStatus?.remove()
            sharingStatus = nil
            return
        }
        if sharingStatus == nil { sharingStatus = SharingStatus { [weak self] in self?.collectForSharing([]) } }
        sharingStatus?.update(count: review.files.count, error: review.task.error)
    }

    func presentOptimizer(files: [URL] = [], paste: Bool = false, recipe: ExportRecipe? = nil) {
        if let recipe, case let .optimize(options) = recipe.options, optimizer != nil {
            guard hasRoomForOperation() else { return }
            let independent = OptimizationReview(history: recentOptimizations)
            lastOptimizer = independent
            independent.options = options
            independent.recipe = recipe
            independent.add(files)
            let panel = FinderReviewWindow("Optimize Media", task: independent.task, finish: {}) { close in
                OptimizationView(review: independent, close: close)
            }
            operationWindows[independent.task.id] = panel
            panel.onClose = { [weak self] in self?.operationWindows[independent.task.id] = nil }
            panel.showWindow(nil)
            panel.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        if optimizer == nil {
            guard hasRoomForOperation() else { return }
            optimizer = OptimizationReview(history: recentOptimizations)
        }
        guard let review = optimizer else { return }
        lastOptimizer = review
        if let recipe, case let .optimize(options) = recipe.options { review.recipe = recipe; review.options = options }
        review.add(files)
        if paste { review.addClipboard() }
        if let controller = operationWindows[review.task.id] {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else if workbench.drafts[.optimize] != nil {
            workbench.show(.optimize)
            workbench.showWindow?()
        } else {
            showReview(.optimize, task: review.task, finish: { [weak self] in self?.optimizer = nil }) { close in
                OptimizationView(review: review, close: close)
            }
        }
    }

    func collectForSharing(_ files: [URL]) {
        if sharingReview == nil {
            guard hasRoomForOperation() else { return }
            sharingReview = SharingReview()
        }
        guard let review = sharingReview else { return }
        if !files.isEmpty {
            if !finderCollectionActive {
                finderCollectionActive = true
                review.onChange = { [weak self] in self?.updateSharingStatus() }
                updateSharingStatus()
            }
            review.add(files)
            return
        }
        if let controller = operationWindows[review.task.id] {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else if workbench.drafts[.collect] != nil {
            workbench.show(.collect); workbench.showWindow?()
        } else {
            showReview(.collect, task: review.task, finish: { [weak self] in
                self?.finderCollectionActive = false
                self?.sharingStatus?.remove()
                self?.sharingStatus = nil
                self?.sharingReview = nil
            }) { close in SharingReviewView(review: review, close: close) }
        }
    }
}
