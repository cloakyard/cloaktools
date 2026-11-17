import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import CloakToolsCore

private func base64ImageFixture(type: UTType = .png, frames: Int = 1) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 1, alpha: 0.75))
    context.fill(CGRect(x: 2, y: 2, width: 12, height: 8))
    let image = try #require(context.makeImage())
    let bytes = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(bytes, type.identifier as CFString, frames, nil))
    for _ in 0..<frames { CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary) }
    #expect(CGImageDestinationFinalize(destination))
    return bytes as Data
}

@Test func imageBase64PreservesExactBytesAndDetectedMIME() throws {
    for type in [UTType.png, .jpeg, .gif, .tiff, .heic] {
        let bytes = try base64ImageFixture(type: type)
        let image = try Base64Image.prepare(bytes)
        #expect(image.mimeType == type.preferredMIMEType && image.bytes == bytes)
        #expect(image.width * image.height == 192 && image.frameCount == 1)
        if type == .jpeg { #expect(image.width == 12 && image.height == 16) }
        #expect(!image.thumbnailPNG.isEmpty)
        let dataURL = try Base64Image.encode(image)
        #expect(dataURL.hasPrefix("data:\(image.mimeType);base64,"))
        #expect(try Base64Image.decode(dataURL).bytes == bytes)
        let plain = try Base64Image.encode(image, includeDataURL: false)
        #expect(plain == bytes.base64EncodedString())
        #expect(try Base64Image.decode(plain).bytes == bytes)
    }
}

@Test func imageBase64KeepsAnimationAndPreviewsFirstFrame() throws {
    let bytes = try base64ImageFixture(type: .gif, frames: 3)
    let image = try Base64Image.decode(bytes.base64EncodedString())
    #expect(image.frameCount == 3 && image.bytes == bytes)
    let preview = try #require(CGImageSourceCreateWithData(image.thumbnailPNG as CFData, nil))
    #expect(CGImageSourceGetCount(preview) == 1)
    #expect(try Base64Image.decode(Base64Image.encode(image)).bytes == bytes)
}

@Test func imageBase64RecognizesWebPWithoutTranscoding() throws {
    // Generated locally with cwebp from the synthetic verification image, resized to 3 × 2.
    let bytes = try #require(Data(base64Encoded: "UklGRkIAAABXRUJQVlA4IDYAAADwAQCdASoDAAIAAgA0JagCdLoAAro6vQAA/gbySyBywsKYk2//LgR5/fI4dq//gN18Wy+AAAA="))
    let image = try Base64Image.prepare(bytes)
    #expect(image.mimeType == "image/webp" && image.fileExtension == "webp")
    #expect(image.width == 3 && image.height == 2)
    #expect(try Base64Image.decode(Base64Image.encode(image)).bytes == bytes)
}

@Test func imageBase64AcceptsWrappedPayloadAndRejectsWrongMIME() throws {
    let image = try Base64Image.prepare(base64ImageFixture())
    let plain = try Base64Image.encode(image, includeDataURL: false)
    let wrapped = " \nDATA:IMAGE/PNG;BASE64," + plain.prefix(40) + "\r\n " + plain.dropFirst(40) + "\n"
    #expect(try Base64Image.decode(wrapped).bytes == image.bytes)
    #expect(throws: Base64ImageError.mismatchedType) { try Base64Image.decode("data:image/jpeg;base64," + plain) }
    for header in ["data:image/svg+xml;base64,", "data:text/plain;base64,", "data:image/png,", "data:image/png;charset=utf-8;base64,"] {
        #expect(throws: Base64ImageError.invalidDataURL) { try Base64Image.decode(header + plain) }
    }
}

@Test func imageBase64RejectsNonImagesCorruptionAndInvalidBase64() throws {
    #expect(throws: Base64ImageError.unsupportedImage) { try Base64Image.decode(Data("plain text".utf8).base64EncodedString()) }
    #expect(throws: Base64ImageError.invalidBase64) { try Base64Image.decode("not base64!") }
    let bytes = try base64ImageFixture()
    #expect(throws: Base64ImageError.self) { try Base64Image.prepare(Data(bytes.prefix(24))) }
    #expect(throws: Base64ImageError.unsupportedImage) { try Base64Image.prepare(Data()) }
}

@Test func imageBase64BoundsBytesTextAndFrames() throws {
    #expect(throws: Base64ImageError.tooLarge) { try Base64Image.prepare(Data(repeating: 0, count: Base64Image.maximumImageBytes + 1)) }
    #expect(throws: Base64ImageError.textTooLarge) { try Base64Image.decode(String(repeating: "a", count: Base64Image.maximumTextBytes + 1)) }
    #expect(throws: Base64ImageError.tooManyFrames) { try Base64Image.prepare(base64ImageFixture(type: .gif, frames: 513)) }
}

@Test func imageBase64CaptureAndSaveUseImmutableBytesAndSafeNames() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.png"), bytes = try base64ImageFixture()
    try bytes.write(to: source)
    let image = try Base64Image.capture(source)
    try Data("changed source".utf8).write(to: source)
    let first = try Base64Image.save(image, in: folder, stem: "Decoded Image")
    let second = try Base64Image.save(image, in: folder, stem: "Decoded Image")
    #expect(first.lastPathComponent == "Decoded Image.png" && second.lastPathComponent == "Decoded Image 2.png")
    #expect(try Data(contentsOf: first) == bytes && Data(contentsOf: second) == bytes)
    #expect(throws: ToolError.self) { try Base64Image.save(image, in: folder, stem: "../outside") }
    #expect(!(try FileManager.default.contentsOfDirectory(atPath: folder.path)).contains { $0.hasPrefix(".cloaktools-") })
}
