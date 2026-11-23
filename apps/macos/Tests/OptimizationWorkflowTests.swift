import AppKit
import CloakToolsCore
import Foundation
import Testing
@testable import CloakTools

@MainActor @Test func optimizerClipboardIgnoresConcealedItemsAndNewerCopies() async throws {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let fixture = try QRCodeCreation.prepare("Clipboard fixture only")
    let tiff = try #require(NSImage(data: fixture.png)?.tiffRepresentation)
    let item = NSPasteboardItem()
    item.setData(tiff, forType: .tiff)
    item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    #expect(board.writeObjects([item]))
    let automation = AutomaticOptimization()
    let first = board.changeCount
    #expect(try await !automation.optimizeClipboard(board, generation: first))
    #expect(board.changeCount == first)
    board.clearContents()
    board.setData(tiff, forType: .tiff)
    #expect(try await !automation.optimizeClipboard(board, generation: first))
    #expect(try await automation.optimizeClipboard(board, generation: board.changeCount))
    let optimized = try #require(board.data(forType: .png))
    #expect(optimized.count < tiff.count)
    let after = board.changeCount
    #expect(try await !automation.optimizeClipboard(board, generation: after))
    #expect(board.changeCount == after)
}

@MainActor @Test func optimizerKeepsIndependentFailuresAndSavesReviewedBytes() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let good = try QRCodeCreation.save(QRCodeCreation.prepare("Hosted review"), in: folder, stem: "Fixture")
    let bad = folder.appendingPathComponent("Broken.png")
    try Data([0, 1]).write(to: bad)
    let model = AppModel()
    model.workbench.showWindow = {}
    model.presentOptimizer(files: [good, bad, good])
    let review = try #require(model.optimizer)
    #expect(model.workbench.page == .optimize && review.rows.count == 2)
    review.options.imageFormat = .webp
    review.preview()
    func wait() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while review.task.busy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!review.task.busy)
    }
    try await wait()
    #expect(review.rows[1].message != nil && review.readyCount == 1)
    let data = try Data(contentsOf: #require(review.rows[0].result?.previewURL))
    try FileManager.default.removeItem(at: good)
    review.save(in: folder)
    try await wait()
    #expect(try Data(contentsOf: #require(review.rows[0].output)) == data)
    review.options.aggressive.toggle()
    #expect(review.readyCount == 0 && review.rows[0].result == nil)
    model.workbench.close(.optimize)
    #expect(model.optimizer == nil)
}

@MainActor @Test func dragResultKeepsItsBytesAfterTheReviewCloses() async throws {
    let fixture = try QRCodeCreation.prepare("Drag fixture")
    var options = OptimizationOptions()
    options.imageFormat = .webp
    var original: OptimizedMedia? = try await MediaOptimization.clipboardImage(fixture.png, options: options)
    let expected = try Data(contentsOf: #require(original).previewURL)
    let provider = OptimizationDragHandle.copyProvider(for: try #require(original))
    original = nil
    #expect(provider.hasItemConformingToTypeIdentifier("org.webmproject.webp"))
    #expect(provider.suggestedName?.hasSuffix(".webp") == true)
    let bytes: Data = try await withCheckedThrowingContinuation { continuation in
        _ = provider.loadFileRepresentation(forTypeIdentifier: "org.webmproject.webp") { file, error in
            do {
                if let error { throw error }
                guard let file else { throw CocoaError(.fileReadUnknown) }
                continuation.resume(returning: try Data(contentsOf: file))
            } catch { continuation.resume(throwing: error) }
        }
    }
    #expect(bytes == expected)
}

@MainActor @Test func folderRulesMigrateAndProcessStableInputsOnceAfterRestart() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let one = root.appendingPathComponent("Screenshots", isDirectory: true)
    let two = root.appendingPathComponent("Incoming", isDirectory: true)
    for folder in [one, two] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
    defer { try? fm.removeItem(at: root) }
    let store = PreferencesStore(url: root.appendingPathComponent("settings.json"))
    try JSONEncoder().encode(["optimizationFolder": one.absoluteString]).write(to: store.url)
    var preferences = try store.load()
    #expect(preferences.folderRules.count == 1 && preferences.folderRules[0].folder == one)
    var options = OptimizationOptions()
    options.steps = [.resize(percent: 50), .image(.webp), .fit(bytes: 100_000)]
    let recipe = ExportRecipe(title: "Small WebP", options: .optimize(options))
    preferences.folderRules[0].kind = .image
    preferences.folderRules[0].recipeID = recipe.id
    preferences.folderRules.append(.init(folder: two, kind: .image, recipeID: recipe.id))
    try store.save(preferences)
    let rules = try store.load().folderRules
    #expect(rules == preferences.folderRules)
    #expect(throws: OptimizationFolderRule.RuleError.overlap) { try OptimizationFolderRule(folder: two).validate(alongside: rules) }
    let image = try QRCodeCreation.prepare("Watched folder test")
    _ = try QRCodeCreation.save(image, in: one, stem: "Old")
    let watcher = AutomaticOptimization()
    defer { watcher.configure(clipboard: false, rules: [], recipes: []) }
    var outputs: [URL] = []
    watcher.didSave = { out, _, _ in outputs.append(out) }
    func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        try #require(condition())
    }
    watcher.configure(clipboard: false, rules: rules, recipes: [recipe])
    try await waitFor { watcher.activeRules.count == 2 }
    for folder in [one, two] { _ = try QRCodeCreation.save(image, in: folder, stem: "Fresh") }
    try Data([1]).write(to: two.appendingPathComponent("Skip.pdf"))
    try await waitFor { outputs.count == 2 }
    #expect(outputs.allSatisfy { $0.pathExtension == "webp" && $0.lastPathComponent.contains("Fresh") })
    watcher.configure(clipboard: false, rules: [], recipes: [])
    _ = try QRCodeCreation.save(image, in: two, stem: "Paused")
    watcher.configure(clipboard: false, rules: try store.load().folderRules, recipes: [recipe])
    try await waitFor { watcher.activeRules.count == 2 }
    _ = try QRCodeCreation.save(image, in: one, stem: "After restart")
    try await waitFor { outputs.count == 3 }
    #expect(outputs.last?.lastPathComponent.contains("After restart") == true)
    #expect(try fm.contentsOfDirectory(atPath: two.appendingPathComponent("Optimized Copies").path).count == 1)
    watcher.configure(clipboard: false, rules: rules, recipes: [])
    #expect(watcher.activeRules.isEmpty && watcher.ruleStatus.count == 2)
}

@MainActor @Test func batchUndoSurvivesRelaunchAndPreservesEditedReplacements() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let file = root.appendingPathComponent("recent.json")
    let history = RecentOptimizations(file: file)
    let model = AppModel(history: history)
    model.workbench.showWindow = {}
    let image = try QRCodeCreation.prepare("Batch restore")
    let files = try ["First", "Second"].map { try QRCodeCreation.save(image, in: root, stem: $0) }
    var options = OptimizationOptions()
    options.steps = [.resize(percent: 50), .image(.png)]
    model.presentOptimizer(files: files, recipe: .init(title: "Half size", options: .optimize(options)))
    let review = try #require(model.optimizer)
    func wait() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while review.task.busy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!review.task.busy)
    }
    review.preview()
    try await wait()
    try #require(review.replaceable.count == 2)
    review.replaceOriginals(review.replaceable)
    try await wait()
    let reload = RecentOptimizations(file: file)
    try #require(reload.lastReplacements.count == 2)
    let revised = Data("User edit".utf8)
    try revised.write(to: files[1])
    let problems = await reload.undo(reload.lastReplacements)
    #expect(problems.count == 1 && problems[0].contains("Second"))
    #expect(try Data(contentsOf: files[0]) == image.png && Data(contentsOf: files[1]) == revised)
    #expect(RecentOptimizations(file: file).lastReplacements.count == 1)
    let backup = try #require(reload.lastReplacements.first?.backup)
    reload.clear()
    #expect(RecentOptimizations(file: file).entries.isEmpty)
    #expect(try Data(contentsOf: backup) == image.png)
}

@MainActor @Test func finderOptimizationServiceReceivesFilesAndPreviewsAPipeline() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = try QRCodeCreation.save(QRCodeCreation.prepare("Service fixture"), in: folder, stem: "Service source")
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let delegate = AppDelegate()
    var message: NSString = ""
    delegate.optimizeMedia(board, userData: nil, error: &message)
    #expect(message.length > 0)
    message = ""
    try #require(board.writeObjects([file as NSURL]))
    delegate.optimizeMedia(board, userData: nil, error: &message)
    #expect(message.length == 0)
    let model = AppModel.shared
    let review = try #require(model.optimizer)
    defer { model.workbench.close(.optimize) }
    try #require(review.rows.count == 1 && review.rows.first?.input.name == file.lastPathComponent)
    review.options.steps = [.resize(percent: 50), .image(.webp), .fit(bytes: 100_000)]
    review.preview()
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while review.task.busy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(review.readyCount == 1 && review.rows[0].result?.previewURL.pathExtension == "webp")
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
}

@MainActor @Test func standardDropKeepsARecipeDraftAndSkippedBatchCanFinish() async throws {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: folder) }
    let input = try QRCodeCreation.save(QRCodeCreation.prepare("Drop Zone audit"), in: folder, stem: "Original")
    let other = folder.appendingPathComponent("New.png")
    try fm.copyItem(at: input, to: other)
    let model = AppModel()
    model.workbench.showWindow = {}
    var options = OptimizationOptions()
    options.steps = [.fit(bytes: 100_000)]
    let recipe = ExportRecipe(title: "Below 100 KB", options: .optimize(options))
    model.presentOptimizer(files: [input], recipe: recipe)
    let first = try #require(model.optimizer)
    #expect(throws: ExportRecipeError.changed) { try model.presentDropZoneFiles([other], recipeID: UUID()) }
    let windowsBeforeDrop = Set(NSApp.windows.map(ObjectIdentifier.init))
    try model.presentDropZoneFiles([other], recipeID: nil)
    let window = NSApp.windows.first { !windowsBeforeDrop.contains(ObjectIdentifier($0)) && $0.windowController is FinderReviewWindow }
    defer { window?.close() }
    let standard = try #require(model.lastOptimizer)
    #expect(first !== standard && first.rows.count == 1 && first.options == options)
    #expect(standard.rows.count == 1 && standard.options == OptimizationOptions() && standard.recipe == nil)
    func wait() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while first.task.busy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!first.task.busy)
    }
    first.preview()
    try await wait()
    #expect(first.isComplete && first.rows[0].skipped && first.rows[0].output == nil)
    first.options.imageFormat = .webp
    first.options.steps = nil
    #expect(!first.isComplete && first.pendingCount == 1)
    first.preview()
    try await wait()
    let old = try #require(first.rows[0].result)
    let fresh = try QRCodeCreation.prepare("A different source for the current preview")
    try fresh.png.write(to: input)
    first.refreshPreview(first.rows[0].id)
    try await wait()
    let updated = try #require(first.rows[0].result)
    #expect(updated.previewURL != old.previewURL && updated.inputBytes == fresh.png.count)
    model.workbench.close(.optimize)
}

@MainActor @Test func replacingAWatchedDirectoryAtTheSamePathStopsItsRule() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let watched = root.appendingPathComponent("Watched", isDirectory: true)
    let substitute = root.appendingPathComponent("Unrelated", isDirectory: true)
    for folder in [watched, substitute] { try fm.createDirectory(at: folder, withIntermediateDirectories: true) }
    defer { try? fm.removeItem(at: root) }
    let rule = OptimizationFolderRule(folder: watched)
    let automation = AutomaticOptimization()
    defer { automation.configure(clipboard: false, rules: [], recipes: []) }
    automation.configure(clipboard: false, rules: [rule], recipes: [])
    let initial = ContinuousClock.now.advanced(by: .seconds(3))
    while !automation.activeRules.contains(rule.id), ContinuousClock.now < initial { try await Task.sleep(for: .milliseconds(20)) }
    try #require(automation.activeRules.contains(rule.id))
    let status = watched.withUnsafeFileSystemRepresentation { first in
        substitute.withUnsafeFileSystemRepresentation { second in renamex_np(first!, second!, UInt32(RENAME_SWAP)) }
    }
    try #require(status == 0)
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while automation.activeRules.contains(rule.id), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    #expect(!automation.activeRules.contains(rule.id))
    let failure = try #require(automation.ruleStatus[rule.id])
    automation.configure(clipboard: false, rules: [rule], recipes: [])
    #expect(automation.ruleStatus[rule.id] == failure)
    #expect(!fm.fileExists(atPath: watched.appendingPathComponent("Optimized Copies").path))
    automation.retryStoppedRule(rule.id)
    automation.configure(clipboard: false, rules: [rule], recipes: [])
    let retry = ContinuousClock.now.advanced(by: .seconds(3))
    while !automation.activeRules.contains(rule.id), ContinuousClock.now < retry { try await Task.sleep(for: .milliseconds(20)) }
    #expect(automation.activeRules.contains(rule.id))
}
