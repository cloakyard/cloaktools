import Testing
import Foundation
import CoreGraphics
import CoreText
import PDFKit
import ImageIO
import UniformTypeIdentifiers
@testable import CloakToolsCore

private func pdfFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsPDF-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func textPDF(_ labels: [String]) throws -> Data {
    let bytes = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 300, height: 400)
    let consumer = try #require(CGDataConsumer(data: bytes))
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    for label in labels {
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(box)
        let text = NSAttributedString(string: label, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 24, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ])
        context.textPosition = CGPoint(x: 30, y: 330); CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage()
    }
    context.closePDF(); return bytes as Data
}

@Test @MainActor func PDFAssemblyPreservesPageOrderTextRotationAndAnnotations() async throws {
    let folder = try pdfFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Two pages.pdf")
    let document = try #require(PDFDocument(data: textPDF(["First page", "Second page"])))
    let second = try #require(document.page(at: 1)); second.rotation = 90
    second.setBounds(CGRect(x: 10, y: 20, width: 270, height: 360), for: .cropBox)
    let annotation = PDFAnnotation(bounds: CGRect(x: 30, y: 230, width: 100, height: 50), forType: .circle, withProperties: nil)
    annotation.contents = "Preserved annotation"; second.addAnnotation(annotation)
    let input = try #require(document.dataRepresentation()); try input.write(to: source)
    let other = folder.appendingPathComponent("Cover.pdf"); try textPDF(["Cover page"]).write(to: other)
    let items = try await Task.detached { try PDFAssembly.prepare(adding: [source, other]) }.value
    #expect(items.map(\.pageCount) == [2, 1])
    let result = try await Task.detached { try PDFAssembly.write([items[1], items[0]], in: folder, name: "Combined") }.value
    let output = try #require(PDFDocument(url: result))
    #expect(output.pageCount == 3)
    #expect(output.page(at: 0)?.string?.contains("Cover page") == true)
    #expect(output.page(at: 1)?.string?.contains("First page") == true)
    let rotated = try #require(output.page(at: 2))
    #expect(rotated.rotation == 90)
    #expect(rotated.bounds(for: .mediaBox) == CGRect(x: 0, y: 0, width: 300, height: 400))
    #expect(rotated.bounds(for: .cropBox) == CGRect(x: 10, y: 20, width: 270, height: 360))
    #expect(rotated.annotations.contains { $0.contents == "Preserved annotation" })
    #expect(try Data(contentsOf: source) == input)
    #expect(try PDFAssembly.write(items, in: folder, name: "Combined").lastPathComponent == "Combined 2.pdf")
}

@Test func PDFAssemblyCapturesBeforeChangesAndAddsAtomically() throws {
    let folder = try pdfFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Source.pdf"); try textPDF(["Original capture"]).write(to: source)
    let items = try PDFAssembly.prepare(adding: [source])
    try textPDF(["Changed later"]).write(to: source)
    let more = try PDFAssembly.prepare(existing: items, adding: [source])
    #expect(more[0].id == items[0].id)
    try FileManager.default.removeItem(at: source)
    let result = try PDFAssembly.write(more, in: folder, name: "Snapshots")
    let output = try #require(PDFDocument(url: result))
    #expect(output.page(at: 0)?.string?.contains("Original capture") == true)
    #expect(output.page(at: 1)?.string?.contains("Changed later") == true)
    #expect(throws: (any Error).self) { try PDFAssembly.prepare(existing: items, adding: [source]) }
    #expect(items.count == 1)
}

@Test func PDFAssemblyImagesUseOrientedA4Pages() throws {
    let folder = try pdfFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let image = folder.appendingPathComponent("Image.png")
    let context = try #require(CGContext(data: nil, width: 240, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0, green: 0.4, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 20, y: 20, width: 200, height: 80))
    let pixels = try #require(context.makeImage())
    let encoder = try #require(CGImageDestinationCreateWithURL(image as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(encoder, pixels, nil); #expect(CGImageDestinationFinalize(encoder))
    let items = try PDFAssembly.prepare(adding: [image])
    #expect(items[0].isImage && items[0].pageCount == 1)
    let result = try PDFAssembly.write(items, in: folder, name: "Image page")
    let output = try #require(PDFDocument(url: result))
    let page = try #require(output.page(at: 0))
    #expect(abs(page.bounds(for: .mediaBox).width - 841.89) < 0.01)
    #expect(abs(page.bounds(for: .mediaBox).height - 595.276) < 0.01)
    let previewSource = try #require(CGImageSourceCreateWithData(items[0].thumbnailPNG as CFData, nil))
    let preview = try #require(CGImageSourceCreateImageAtIndex(previewSource, 0, nil))
    #expect(preview.width <= 192 && preview.height <= 192 && max(preview.width, preview.height) >= 190)
}

@Test @MainActor func PDFAssemblyRejectsEncryptedAndForms() throws {
    let folder = try pdfFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let document = try #require(PDFDocument(data: textPDF(["Protected page"])))
    let encrypted = try #require(document.dataRepresentation(options: [PDFDocumentWriteOption.ownerPasswordOption: "owner", PDFDocumentWriteOption.userPasswordOption: "secret"]))
    let source = folder.appendingPathComponent("Encrypted.pdf"); try encrypted.write(to: source)
    #expect(throws: PDFAssemblyError.self) { try PDFAssembly.prepare(adding: [source]) }
    let annotation = PDFAnnotation(bounds: CGRect(x: 20, y: 20, width: 100, height: 20), forType: .widget, withProperties: nil)
    annotation.widgetFieldType = .text; annotation.fieldName = "Test field"
    document.page(at: 0)?.addAnnotation(annotation)
    let form = try #require(document.dataRepresentation()); let formURL = folder.appendingPathComponent("Form.pdf"); try form.write(to: formURL)
    #expect(throws: PDFAssemblyError.self) { try PDFAssembly.prepare(adding: [formURL]) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
}

@Test func PDFAssemblyBoundsMalformedAndEmptyInputs() throws {
    let folder = try pdfFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Source.pdf"); try textPDF(["Page"]).write(to: source)
    #expect(throws: PDFAssemblyError.self) { try PDFAssembly.prepare(adding: []) }
    #expect(throws: PDFAssemblyError.self) { try PDFAssembly.prepare(adding: Array(repeating: source, count: 33)) }
    #expect(throws: PDFAssemblyError.self) { try PDFAssembly.write([], in: folder, name: "Empty") }
    let tooMany = folder.appendingPathComponent("Many.pdf"); try textPDF(Array(repeating: "Page", count: 201)).write(to: tooMany)
    #expect(throws: PDFAssemblyError.self) { try PDFAssembly.prepare(adding: [tooMany]) }
    let oversized = folder.appendingPathComponent("Large.pdf"); try Data().write(to: oversized)
    let handle = try FileHandle(forWritingTo: oversized); try handle.truncate(atOffset: 100_000_001); try handle.close()
    #expect(throws: PDFAssemblyError.self) { try PDFAssembly.prepare(adding: [oversized]) }
    let bad = folder.appendingPathComponent("Broken.pdf"); try Data("%PDF-invalid".utf8).write(to: bad)
    #expect(throws: PDFAssemblyError.self) { try PDFAssembly.prepare(adding: [bad]) }
}

@Test func PDFAssemblyCancellationDoesNotPublish() async throws {
    let folder = try pdfFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("Source.pdf"); try textPDF(["Page"]).write(to: source)
    let items = try PDFAssembly.prepare(adding: [source])
    let task = Task { while !Task.isCancelled { await Task.yield() }; return try PDFAssembly.write(items, in: folder, name: "Cancelled") }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Source.pdf"])
}

@Test func PDFAssemblyIntentPreservesOrderAndRejectsInvalidPaths() throws {
    let intent = FinderIntent.assemble(files: [URL(fileURLWithPath: "/tmp/B # &.pdf"), URL(fileURLWithPath: "/tmp/A.png")])
    #expect(try FinderIntent(url: intent.url) == intent)
    for raw in ["cloaktools-action://assemble", "cloaktools-action://assemble?path=relative", "cloaktools-action://assemble?path=/a&other=/b", "cloaktools-action://assemble/extra?path=/a", "cloaktools-action://assemble?path=/a#hidden"] {
        #expect(throws: ToolError.self) { try FinderIntent(url: URL(string: raw)!) }
    }
    #expect(throws: ToolError.self) { try FinderIntent(url: FinderIntent.assemble(files: Array(repeating: URL(fileURLWithPath: "/tmp/a"), count: 33)).url) }
}
