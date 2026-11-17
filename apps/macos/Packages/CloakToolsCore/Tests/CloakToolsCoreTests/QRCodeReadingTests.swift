import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import CloakToolsCore

private func qrReadImage(_ data: Data) throws -> CGImage {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
}
private func qrReadFixture(_ image: CGImage, type: UTType = .png, orientation: Int = 1, frames: Int = 1) throws -> Data {
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, frames, nil))
    for _ in 0..<frames { CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary) }
    #expect(CGImageDestinationFinalize(destination)); return data as Data
}
private func qrReadCanvas(width: Int, height: Int) throws -> CGContext {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    return context
}
@Test func qrReadDecodesLiteralLinksUnicodeAndWhitespace() throws {
    for text in ["https://example.com/?a=%20&b=2#end", "mailto:hello@example.com?subject=Hello", "  नमस्ते 🌍\r\n日本語 · مرحبا\te\u{301}  "] {
        let result = try QRCodeReading.prepare(QRCodeCreation.prepare(text).png)
        #expect(result.codes.count == 1 && result.codes[0].text?.utf8.elementsEqual(text.utf8) == true)
        #expect(result.width == 512 && result.height == 512 && !result.wasReduced)
        #expect(result.codes[0].bounds.minX >= 0 && result.codes[0].bounds.maxX <= 1)
    }
}
@Test func qrReadKeepsDistinctIdenticalCodesAndPositions() throws {
    let qr = try qrReadImage(QRCodeCreation.prepare("Repeated code").png)
    let context = try qrReadCanvas(width: 1200, height: 600)
    context.draw(qr, in: CGRect(x: 20, y: 40, width: 512, height: 512))
    context.draw(qr, in: CGRect(x: 668, y: 40, width: 512, height: 512))
    let result = try QRCodeReading.prepare(qrReadFixture(#require(context.makeImage())))
    #expect(result.codes.count == 2 && result.codes.allSatisfy { $0.text == "Repeated code" })
    #expect(result.codes.map(\.id) == [0,1] && result.codes[0].bounds.midX < result.codes[1].bounds.midX)
}
@Test func qrReadRecoversDenseHighCorrectionCode() throws {
    var options = QRCodeOptions(); options.size = .medium; options.correction = .high
    let text = String(repeating: "a", count: 1024)
    let result = try QRCodeReading.prepare(QRCodeCreation.prepare(text, options: options).png)
    #expect(result.codes.count == 1 && result.codes[0].text == text)
}
@Test func qrReadSupportsStillFormatsAndOrientation() throws {
    let qr = try qrReadImage(QRCodeCreation.prepare("Image format check").png)
    let context = try qrReadCanvas(width: 700, height: 540)
    context.draw(qr, in: CGRect(x: 100, y: 14, width: 512, height: 512))
    let image = try #require(context.makeImage())
    for type in [UTType.png, .jpeg, .tiff, .gif, .heic] {
        let bytes = try qrReadFixture(image, type: type, orientation: type == .jpeg ? 6 : 1)
        let result = try QRCodeReading.prepare(bytes)
        #expect(result.codes.count == 1 && result.codes.first?.text == "Image format check")
        if type == .jpeg { #expect(result.width == 540 && result.height == 700) }
        else { #expect(result.width == 700 && result.height == 540) }
    }
}
@Test func qrReadNoCodeStillReturnsImageAndBoundsLargeScans() throws {
    let blank = try qrReadCanvas(width: 4500, height: 1000)
    let result = try QRCodeReading.prepare(qrReadFixture(#require(blank.makeImage())))
    #expect(result.codes.isEmpty && !result.thumbnailPNG.isEmpty && result.wasReduced)
    #expect(result.scanWidth == 4096 && result.scanHeight < 1000)
    let preview = try qrReadImage(result.thumbnailPNG)
    #expect(max(preview.width, preview.height) <= 768)
}
@Test func qrReadRejectsMalformedOversizedAndMultipleFrames() throws {
    #expect(throws: QRReadError.unsupportedImage) { try QRCodeReading.prepare(Data("<svg/>".utf8)) }
    #expect(throws: QRReadError.tooLarge) { try QRCodeReading.prepare(Data(count: QRCodeReading.maximumImageBytes + 1)) }
    let qr = try qrReadImage(QRCodeCreation.prepare("Still image").png)
    #expect(throws: QRReadError.multipleFrames) { try QRCodeReading.prepare(qrReadFixture(qr, type: .gif, frames: 2)) }
    let bytes = try qrReadFixture(qr)
    #expect(throws: QRReadError.unsupportedImage) { try QRCodeReading.prepare(Data(bytes.prefix(20))) }
}
@Test func qrReadReviewBoundsAndUnreadableCodesAreExplicit() throws {
    let bounds = CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.4)
    let reviewed = try QRCodeReading.reviewed([(nil,bounds),("",CGRect(x:0.6,y:0.1,width:0.3,height:0.3))])
    #expect(reviewed.count == 2 && reviewed.contains { $0.text == nil } && reviewed.contains { $0.text == "" })
    #expect(throws: QRReadError.tooManyCodes) { try QRCodeReading.reviewed(Array(repeating:("a",bounds),count:17)) }
    #expect(throws: QRReadError.textTooLarge) { try QRCodeReading.reviewed([(String(repeating:"a",count:32*1024+1),bounds)]) }
    #expect(try QRCodeReading.reviewed([("a",.null),("b",CGRect(x:2,y:2,width:1,height:1))]).isEmpty)
    let clipped = try QRCodeReading.reviewed([("a",CGRect(x:-0.1,y:-0.1,width:1.2,height:1.2))])
    #expect(clipped[0].bounds == CGRect(x:0,y:0,width:1,height:1))
}
@Test func qrReadCapturedTextSurvivesSourceRemovalAndSavesExactly() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Source.png"), text = "  Reviewed\r\nनमस्ते\t  "
    try QRCodeCreation.prepare(text).png.write(to: url)
    let result = try QRCodeReading.read(url), code = try #require(result.codes.first)
    try FileManager.default.removeItem(at: url)
    let first = try QRCodeReading.save(code, in: folder, stem: "QR text"), second = try QRCodeReading.save(code, in: folder, stem: "QR text")
    #expect(try Data(contentsOf: first) == Data(text.utf8) && Data(contentsOf: second) == Data(text.utf8))
    #expect(second.lastPathComponent == "QR text 2.txt")
    #expect(throws: (any Error).self) { try QRCodeReading.save(code, in: folder, stem: "bad/name") }
    #expect(throws: QRReadError.noText) { try QRCodeReading.save(.init(id:0,text:nil,bounds:.zero), in:folder, stem:"None") }
}
@Test func qrReadCancellationPreventsCaptureScanAndSave() async throws {
    let bytes = try QRCodeCreation.prepare("Cancellation").png
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        #expect(throws: CancellationError.self) { try QRCodeReading.prepare(bytes) }
        #expect(throws: CancellationError.self) { try QRCodeReading.read(URL(fileURLWithPath:"/tmp/unused.png")) }
        #expect(throws: CancellationError.self) { try QRCodeReading.save(.init(id:0,text:"a",bounds:.zero),in:FileManager.default.temporaryDirectory,stem:UUID().uuidString) }
    }
    await task.value
}
