import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CloakToolsCore

private func imageFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsImages-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func imageFixture(transparent: Bool = false) throws -> CGImage {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: 128, height: 96, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.clear(CGRect(x: 0, y: 0, width: 128, height: 96))
    for x in stride(from: transparent ? 32 : 0, to: transparent ? 96 : 128, by: 4) {
        for y in stride(from: transparent ? 32 : 0, to: transparent ? 64 : 96, by: 4) {
            context.setFillColor(CGColor(red: CGFloat(x % 23) / 23, green: CGFloat(y % 31) / 31, blue: 0.75, alpha: 1))
            context.fill(CGRect(x: x, y: y, width: 4, height: 4))
        }
    }
    return try #require(context.makeImage())
}

private func writeFixture(_ image: CGImage, to url: URL, type: UTType = .png, count: Int = 1, properties: [CFString: Any] = [:]) throws {
    let encoder = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, count, nil))
    for _ in 0..<count { CGImageDestinationAddImage(encoder, image, properties as CFDictionary) }
    #expect(CGImageDestinationFinalize(encoder))
}

private func decoded(_ url: URL) throws -> (CGImageSource, CGImage) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (source, image)
}

private func pixels(_ image: CGImage) throws -> [UInt8] {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = try #require(context.data)
    return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
}

@Test func nativeImageFormatMatrix() throws {
    let folder = try imageFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let image = try imageFixture()
    for inputType in [UTType.png, .jpeg, .tiff, .heic] {
        let input = folder.appendingPathComponent("input-\(inputType.preferredFilenameExtension!).\(inputType.preferredFilenameExtension!)")
        try writeFixture(image, to: input, type: inputType)
        let before = try Data(contentsOf: input)
        let prepared = try ImageConversion.prepare(input)
        #expect(prepared.width == 128 && prepared.height == 96)
        for format in ImageOutputFormat.allCases {
            #expect(format.isAvailable)
            let output = try ImageConversion.copy(prepared, options: .init(format: format))
            let (source, result) = try decoded(output)
            #expect(CGImageSourceGetType(source) as String? == format.type.identifier)
            #expect(result.width == 128 && result.height == 96)
            #expect(output.pathExtension == format.fileExtension)
            let collision = try ImageConversion.copy(prepared, options: .init(format: format))
            #expect(collision.lastPathComponent.hasSuffix(" converted 2.\(format.fileExtension)"))
        }
        #expect(try Data(contentsOf: input) == before)
    }
}

@Test func imageTransparencyAndLossyBackgrounds() throws {
    let folder = try imageFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("transparent.png")
    try writeFixture(imageFixture(transparent: true), to: input)
    let prepared = try ImageConversion.prepare(input)
    let png = try ImageConversion.copy(prepared, options: .init())
    let (_, pngImage) = try decoded(png)
    #expect(try pixels(pngImage)[3] == 0)
    for format in [ImageOutputFormat.jpeg, .heic] {
        for background in ImageBackground.allCases {
            let output = try ImageConversion.copy(prepared, options: .init(format: format, background: background))
            let (_, image) = try decoded(output)
            let rgba = try pixels(image)
            #expect(rgba[3] == 255)
            for channel in rgba.prefix(3) {
                #expect(abs(Int(channel) - (background == .white ? 255 : 0)) < 12)
            }
        }
    }
}

@Test func imageOrientationAndMetadataRemoval() throws {
    let folder = try imageFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("rotated.jpg")
    try writeFixture(imageFixture(), to: input, type: .jpeg, properties: [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.3, kCGImagePropertyGPSLatitudeRef: "N"],
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Synthetic private metadata"]
    ])
    let prepared = try ImageConversion.prepare(input)
    #expect(prepared.width == 96 && prepared.height == 128)
    for format in ImageOutputFormat.allCases {
        let output = try ImageConversion.copy(prepared, options: .init(format: format))
        let (source, image) = try decoded(output)
        #expect(image.width == 96 && image.height == 128)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifUserComment] == nil)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }
}

@Test func preparedImageDoesNotRereadChangedOrDeletedSource() throws {
    let folder = try imageFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("captured.png")
    try writeFixture(imageFixture(), to: input)
    let prepared = try ImageConversion.prepare(input)
    let before = try ImageConversion.copy(prepared, options: .init())
    try Data("The source has changed.".utf8).write(to: input)
    let changed = try ImageConversion.copy(prepared, options: .init())
    try FileManager.default.removeItem(at: input)
    let deleted = try ImageConversion.copy(prepared, options: .init())
    #expect(try Data(contentsOf: before) == Data(contentsOf: changed))
    #expect(try Data(contentsOf: before) == Data(contentsOf: deleted))
}

@Test func imageQualityValidationAndEncoding() throws {
    let folder = try imageFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("quality.png")
    try writeFixture(imageFixture(), to: input)
    let prepared = try ImageConversion.prepare(input)
    for value in [Double.nan, .infinity, -0.1, 0, 1.01] {
        #expect(throws: ImageConversionError.self) { try ImageConversion.copy(prepared, options: .init(format: .jpeg, quality: value)) }
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["quality.png"])
    for format in [ImageOutputFormat.jpeg, .heic] {
        let low = try ImageConversion.copy(prepared, options: .init(format: format, quality: 0.1))
        let high = try ImageConversion.copy(prepared, options: .init(format: format, quality: 1))
        #expect(try Data(contentsOf: low) != Data(contentsOf: high))
        _ = try decoded(low); _ = try decoded(high)
    }
}

@Test func imageRejectsMalformedAndMultipleFrames() throws {
    let folder = try imageFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let image = try imageFixture()
    let multiple = folder.appendingPathComponent("multiple.tiff")
    try writeFixture(image, to: multiple, type: .tiff, count: 2)
    #expect(throws: ToolError.self) { try ImageConversion.prepare(multiple) }
    let gif = folder.appendingPathComponent("animated.gif")
    try writeFixture(image, to: gif, type: .gif, count: 2)
    #expect(throws: ToolError.self) { try ImageConversion.prepare(gif) }
    let malformed = folder.appendingPathComponent("broken.heic")
    try Data("invalid".utf8).write(to: malformed)
    #expect(throws: ToolError.self) { try ImageConversion.prepare(malformed) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 3)
}

@Test func imagePreferencesMigrationAndSnapshot() throws {
    let old = Data(#"{"includeHelloWorld":true,"languageChoices":{"rust":false},"openAfterCreation":true}"#.utf8)
    var preferences = try JSONDecoder().decode(Preferences.self, from: old)
    #expect(preferences.imageConversion == ImageConversionOptions())
    #expect(preferences.includeHelloWorld && preferences.openAfterCreation && preferences.languageChoices["rust"] == false)
    let captured = preferences.imageConversion
    preferences.imageConversion = .init(format: .heic, quality: 0.65, background: .black)
    #expect(captured == ImageConversionOptions())
    let saved = try JSONEncoder().encode(preferences)
    #expect(try JSONDecoder().decode(Preferences.self, from: saved) == preferences)
    let invalid = Data(#"{"imageConversion":{"format":"jpeg","quality":2,"background":"white"}}"#.utf8)
    #expect(throws: ImageConversionError.self) { try JSONDecoder().decode(Preferences.self, from: invalid) }
}

@Test func imageCancellationDoesNotPublish() async throws {
    let folder = try imageFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("cancel.png")
    try writeFixture(imageFixture(), to: input)
    let prepared = try ImageConversion.prepare(input)
    let prepareTask = Task { while !Task.isCancelled { await Task.yield() }; return try ImageConversion.prepare(input) }
    prepareTask.cancel()
    await #expect(throws: CancellationError.self) { try await prepareTask.value }
    let copyTask = Task { while !Task.isCancelled { await Task.yield() }; return try ImageConversion.copy(prepared, options: .init(format: .heic)) }
    copyTask.cancel()
    await #expect(throws: CancellationError.self) { try await copyTask.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["cancel.png"])
}
