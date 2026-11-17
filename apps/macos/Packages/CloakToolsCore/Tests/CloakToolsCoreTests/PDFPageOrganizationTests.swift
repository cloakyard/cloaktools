import Testing
import Foundation
import CoreGraphics
import CoreText
import PDFKit
import ImageIO
@testable import CloakToolsCore

private func pagesFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsPages-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
private func pagesData(_ count: Int = 4) throws -> Data {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 300, height: 400)
    let consumer = try #require(CGDataConsumer(data: data))
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    for number in 1...count {
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
        let label = NSAttributedString(string: "Original page \(number)", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 18, nil)])
        context.textPosition = CGPoint(x: 25, y: 325)
        CTLineDraw(CTLineCreateWithAttributedString(label), context); context.endPDFPage()
    }
    context.closePDF(); return data as Data
}

@Test @MainActor func PDFPagesExportSelectionOrderRelativeRotationAndContent() async throws {
    let folder = try pagesFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Source.pdf")
    let doc = try #require(PDFDocument(data: pagesData()))
    let second = try #require(doc.page(at: 1)); second.rotation = 90
    second.setBounds(CGRect(x: 10, y: 20, width: 270, height: 360), for: .cropBox)
    let note = PDFAnnotation(bounds: CGRect(x: 30, y: 200, width: 100, height: 40), forType: .circle, withProperties: nil)
    note.contents = "Keep this annotation"; second.addAnnotation(note)
    let original = try #require(doc.dataRepresentation()); try original.write(to: source)
    let prepared = try await Task.detached { try PDFPageOrganization.prepare(source) }.value
    let choices = [PDFPageChoice(index: 3, quarterTurns: 3), PDFPageChoice(index: 1, quarterTurns: 1)]
    let result = try await Task.detached { try PDFPageOrganization.write(prepared, pages: choices, in: folder, name: "Chosen") }.value
    let output = try #require(PDFDocument(url: result))
    #expect(output.pageCount == 2)
    #expect(output.page(at: 0)?.string?.contains("Original page 4") == true)
    #expect(output.page(at: 0)?.rotation == 270)
    let exported = try #require(output.page(at: 1))
    #expect(exported.string?.contains("Original page 2") == true)
    #expect(exported.rotation == 180)
    #expect(exported.bounds(for: .mediaBox) == CGRect(x: 0, y: 0, width: 300, height: 400))
    #expect(exported.bounds(for: .cropBox) == CGRect(x: 10, y: 20, width: 270, height: 360))
    #expect(exported.annotations.contains { $0.contents == "Keep this annotation" })
    #expect(try Data(contentsOf: source) == original)
    #expect(try PDFPageOrganization.write(prepared, pages: choices, in: folder, name: "Chosen").lastPathComponent == "Chosen 2.pdf")
    // Reusing a prepared value never accumulates rotations from previous exports.
    let untouched = try PDFPageOrganization.write(prepared, pages: [.init(index: 1)], in: folder, name: "Unchanged")
    #expect(PDFDocument(url: untouched)?.page(at: 0)?.rotation == 90)
}

@Test func PDFPagesSnapshotsSurviveSourceDeletionAndNameCollision() throws {
    let folder = try pagesFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Original.pdf"), original = try pagesData()
    try original.write(to: source)
    let prepared = try PDFPageOrganization.prepare(source)
    try pagesData(1).write(to: source)
    let output = try PDFPageOrganization.write(prepared, pages: [.init(index: 3)], in: folder, name: "Original")
    #expect(output.lastPathComponent == "Original 2.pdf")
    #expect(PDFDocument(url: output)?.string?.contains("Original page 4") == true)
    try FileManager.default.removeItem(at: source)
    let second = try PDFPageOrganization.write(prepared, pages: [.init(index: 2)], in: folder, name: "After deletion")
    #expect(PDFDocument(url: second)?.string?.contains("Original page 3") == true)
}

@Test func PDFPagesRangeSelectionIsBoundedAndUnambiguous() throws {
    #expect(try PDFPageOrganization.selection("1, 3-5, 4, 8–10", pageCount: 10) == Set([0, 2, 3, 4, 7, 8, 9]))
    #expect(try PDFPageOrganization.selection(" 2 - 2 ", pageCount: 3) == [1])
    #expect(try PDFPageOrganization.selection("1-200", pageCount: 200).count == 200)
    for invalid in ["", "0", "-1", "4", "3-1", "1,", ",1", "1,,2", "1-", "1-2-3", "1.0", "1 2", "a", "２", "1\n", String(repeating: "9", count: 100), String(repeating: "1,", count: 1100)] {
        #expect(throws: PDFPageOrganizationError.self) { try PDFPageOrganization.selection(invalid, pageCount: 3) }
    }
    for count in [0, -1, 201, Int.max] {
        #expect(throws: PDFPageOrganizationError.self) { try PDFPageOrganization.selection("1", pageCount: count) }
    }
}

@Test func PDFPagesInvalidPlansNeverPublish() throws {
    let folder = try pagesFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Source.pdf"); try pagesData().write(to: source)
    let prepared = try PDFPageOrganization.prepare(source)
    for plan: [PDFPageChoice] in [[], [.init(index: -1)], [.init(index: 4)], [.init(index: Int.max)], [.init(index: 0), .init(index: 0)], [.init(index: 0, quarterTurns: -1)], [.init(index: 0, quarterTurns: 4)], [.init(index: 0, quarterTurns: Int.max)]] {
        #expect(throws: PDFPageOrganizationError.self) { try PDFPageOrganization.write(prepared, pages: plan, in: folder, name: "Invalid") }
    }
    #expect(throws: (any Error).self) { try PDFPageOrganization.write(prepared, pages: [.init(index: 0)], in: folder, name: "../Bad") }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Source.pdf"])
}

@Test @MainActor func PDFPagesRejectFormsEncryptionMalformedAndOversize() throws {
    let folder = try pagesFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Unsupported.pdf")
    let document = try #require(PDFDocument(data: pagesData(1)))
    let encrypted = try #require(document.dataRepresentation(options: [PDFDocumentWriteOption.ownerPasswordOption: "owner", PDFDocumentWriteOption.userPasswordOption: "secret"]))
    try encrypted.write(to: source)
    #expect(throws: PDFAssemblyError.self) { try PDFPageOrganization.prepare(source) }
    let widget = PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 80, height: 20), forType: .widget, withProperties: nil)
    widget.widgetFieldType = .text; widget.fieldName = "Field"; document.page(at: 0)?.addAnnotation(widget)
    try #require(document.dataRepresentation()).write(to: source)
    #expect(throws: PDFAssemblyError.self) { try PDFPageOrganization.prepare(source) }
    try Data("%PDF-broken".utf8).write(to: source)
    #expect(throws: PDFAssemblyError.self) { try PDFPageOrganization.prepare(source) }
    try pagesData(201).write(to: source)
    #expect(throws: PDFAssemblyError.self) { try PDFPageOrganization.prepare(source) }
    let handle = try FileHandle(forWritingTo: source); try handle.truncate(atOffset: 100_000_001); try handle.close()
    #expect(throws: PDFAssemblyError.self) { try PDFPageOrganization.prepare(source) }
}

@Test func PDFPagesThumbnailsRespectRotationAndBoundedSize() throws {
    let folder = try pagesFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Source.pdf")
    let document = try #require(PDFDocument(data: pagesData(2)))
    document.page(at: 1)?.rotation = 90
    try #require(document.dataRepresentation()).write(to: source)
    let prepared = try PDFPageOrganization.prepare(source)
    #expect(prepared.thumbnails.count == 2)
    for (index, data) in prepared.thumbnails.enumerated() {
        let imageSource = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        #expect(max(image.width, image.height) <= 192)
        #expect(index == 0 ? image.height > image.width : image.width > image.height)
    }
    let detail = try PDFPageOrganization.preview(prepared, index: 1)
    let detailSource = try #require(CGImageSourceCreateWithData(detail as CFData, nil))
    let detailImage = try #require(CGImageSourceCreateImageAtIndex(detailSource, 0, nil))
    #expect(detailImage.width == 768 && detailImage.width > detailImage.height)
    #expect(throws: PDFPageOrganizationError.self) { try PDFPageOrganization.preview(prepared, index: -1) }
    #expect(throws: PDFPageOrganizationError.self) { try PDFPageOrganization.preview(prepared, index: 2) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Source.pdf"])
}

@Test func PDFPagesCancellationDoesNotPrepareOrPublish() async throws {
    let folder = try pagesFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Source.pdf"); try pagesData().write(to: source)
    let prepared = try PDFPageOrganization.prepare(source)
    let preparation = Task { while !Task.isCancelled { await Task.yield() }; return try PDFPageOrganization.prepare(source) }
    preparation.cancel()
    await #expect(throws: CancellationError.self) { try await preparation.value }
    let publication = Task { while !Task.isCancelled { await Task.yield() }; return try PDFPageOrganization.write(prepared, pages: [.init(index: 0)], in: folder, name: "Cancelled") }
    publication.cancel()
    await #expect(throws: CancellationError.self) { try await publication.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Source.pdf"])
}
