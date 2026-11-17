import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CloakToolsCore

private func clipboardFixture(_ type: UTType, width: Int = 24, height: Int = 16, pages: Int = 1, properties: [CFString: Any] = [:]) throws -> Data {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.5))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, pages, nil))
    for _ in 0..<pages { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Test func clipboardTextKeepsUnicodeLineEndingsAndSafeCollisions() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    var copied = "日本語 — café\r\n\r\nHello, clipboard!\r\n"
    let expected = Data(copied.utf8)
    let document = try ClipboardDocument.prepare(.text(copied))
    copied = "The clipboard has changed"
    let first = try document.write(in: folder, name: "Note")
    let next = try document.write(in: folder, name: "Note")
    #expect(first.lastPathComponent == "Note.txt" && next.lastPathComponent == "Note 2.txt")
    #expect(try Data(contentsOf: first) == expected)
    #expect(try Data(contentsOf: next) == expected)
    #expect(document.textPreview == String(decoding: expected, as: UTF8.self))
    #expect(throws: ToolError.self) { try document.write(in: folder, name: "../escape") }
}

@Test func clipboardTextBoundsPreviewAndRejectsInvalidInput() throws {
    let text = String(repeating: "🧰", count: 5000)
    let document = try ClipboardDocument.prepare(.text(text))
    #expect(document.previewIsTruncated && document.textPreview?.count == 4096)
    #expect(document.content == Data(text.utf8))
    let empty = try ClipboardDocument.prepare(.text(""))
    #expect(empty.content.isEmpty && !empty.previewIsTruncated)
    #expect(throws: ClipboardError.self) { try ClipboardDocument.prepare(.text("a\0b")) }
    #expect(throws: ClipboardError.self) { try ClipboardInput.text(String(repeating: "é", count: 524_289)).validateSize() }
    #expect(throws: ToolError.self) { try ClipboardInput.image(Data(repeating: 0, count: 100_000_001)).validateSize() }
}

@Test(arguments: [UTType.png, .jpeg, .tiff])
func clipboardImagesBecomeValidPNG(_ type: UTType) throws {
    let source = try clipboardFixture(type)
    let original = source
    let document = try ClipboardDocument.prepare(.image(source))
    let decoded = try #require(CGImageSourceCreateWithData(document.content as CFData, nil))
    #expect(CGImageSourceGetType(decoded) as String? == UTType.png.identifier)
    let image = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
    #expect(image.width == 24 && image.height == 16 && document.width == 24 && document.height == 16)
    #expect(document.fileExtension == "png" && document.kind == .image)
    #expect(document.textPreview == nil && document.thumbnailPNG != nil && source == original)
}

@Test func clipboardPNGPreservesTransparencyAndBoundsThumbnail() throws {
    let document = try ClipboardDocument.prepare(.image(clipboardFixture(.png, width: 800, height: 600)))
    let source = try #require(CGImageSourceCreateWithData(document.content as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let context = try #require(CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 3200,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: 800, height: 600))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    #expect(pixels[3] >= 127 && pixels[3] <= 128)
    #expect(pixels[799 * 4 + 3] == 0)
    let thumbnailBytes = try #require(document.thumbnailPNG)
    let thumb = try #require(CGImageSourceCreateWithData(thumbnailBytes as CFData, nil))
    let thumbnail = try #require(CGImageSourceCreateImageAtIndex(thumb, 0, nil))
    #expect(max(thumbnail.width, thumbnail.height) <= 384)
    #expect(image.width == 800 && image.height == 600)
}

@Test func clipboardImageAppliesOrientationAndDropsSourceMetadata() throws {
    let encoded = try clipboardFixture(.jpeg, properties: [kCGImagePropertyOrientation: 6,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N"]])
    let input = try #require(CGImageSourceCreateWithData(encoded as CFData, nil))
    let before = try #require(CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any])
    #expect(before[kCGImagePropertyGPSDictionary] != nil)
    let document = try ClipboardDocument.prepare(.image(encoded))
    #expect(document.width == 16 && document.height == 24)
    let output = try #require(CGImageSourceCreateWithData(document.content as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
}

@Test func clipboardRejectsMalformedAndMultiframeImages() throws {
    #expect(throws: ClipboardError.self) { try ClipboardDocument.prepare(.image(Data("not a PNG".utf8))) }
    #expect(throws: ClipboardError.self) { try ClipboardDocument.prepare(.image(Data())) }
    let multipage = try clipboardFixture(.tiff, pages: 2)
    #expect(throws: ClipboardError.self) { try ClipboardDocument.prepare(.image(multipage)) }
    let gif = try clipboardFixture(.gif)
    #expect(throws: ClipboardError.self) { try ClipboardDocument.prepare(.image(gif)) }
}

@Test func clipboardCancellationDoesNotPublish() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let document = try ClipboardDocument.prepare(.text("Keep this in memory"))
    let task = Task { while !Task.isCancelled { await Task.yield() }; return try document.write(in: folder, name: "Cancelled") }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
}

@Test func clipboardFinderIntentOnlyCarriesDestination() throws {
    let intent = FinderIntent.clipboard(folder: URL(fileURLWithPath: "/tmp/a & ?/"))
    #expect(try FinderIntent(url: intent.url) == intent)
    for raw in ["cloaktools-action://clipboard?path=/tmp&text=secret", "cloaktools-action://clipboard?path=/a&path=/b", "cloaktools-action://clipboard?path=relative"] {
        #expect(throws: ToolError.self) { try FinderIntent(url: URL(string: raw)!) }
    }
}
