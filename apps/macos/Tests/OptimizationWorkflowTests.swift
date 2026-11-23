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
