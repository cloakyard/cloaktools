import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import CloakToolsCore

private func fitFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsFit-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}
private func fitFixture(_ folder: URL, width: Int = 640, height: Int = 480, transparent: Bool = false, orientation: Int? = nil) throws -> URL {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    var state: UInt32 = 12_345
    for index in 0..<(width * height) {
        if transparent && index % width < width / 2 {
            for channel in 0..<4 { pixels[index * 4 + channel] = 0 }
        } else {
            for channel in 0..<3 { state = state &* 1_664_525 &+ 1_013_904_223; pixels[index * 4 + channel] = UInt8(truncatingIfNeeded: state >> 24) }
            pixels[index * 4 + 3] = 255
        }
    }
    let image = try #require(context.makeImage())
    let url = folder.appendingPathComponent("source.png")
    let encoder = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    var properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.3], kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Synthetic metadata"]]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(encoder, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(encoder))
    return url
}
private func inspectFit(_ result: FittedImage) throws -> CGImage {
    let decoder = try #require(CGImageSourceCreateWithData(result.bytes as CFData, nil))
    #expect(CGImageSourceGetType(decoder) as String? == result.options.format.type.identifier)
    #expect(CGImageSourceGetCount(decoder) == 1)
    let image = try #require(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
    #expect(image.width == result.width && image.height == result.height)
    #expect(result.byteCount == result.bytes.count)
    #expect(result.encodingAttempts <= ImageFit.maximumEncodingAttempts)
    return image
}
private func firstPixel(_ image: CGImage) throws -> [UInt8] {
    let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: bytes, count: 4))
}

@Test func fitUsesMaximumDimensionsWithoutEnlargingOrDistorting() throws {
    let folder = try fitFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let prepared = try ImageConversion.prepare(fitFixture(folder, width: 200, height: 100))
    let result = try ImageFit.preview(prepared, options: .init(format: .png, maximumWidth: 110, maximumHeight: 70))
    #expect(result.width == 110 && result.height == 55 && result.fits)
    _ = try inspectFit(result)
    let unchanged = try ImageFit.preview(prepared, options: .init(format: .png, maximumWidth: 1000, maximumHeight: 1000))
    #expect(unchanged.width == 200 && unchanged.height == 100)
    let thin = try ImageFit.preview(prepared, options: .init(format: .png, maximumWidth: 1, maximumHeight: 1))
    #expect(thin.width == 1 && thin.height == 1)
}

@Test func fitTriesQualityBeforeFurtherReductionAndHonorsFloor() throws {
    let folder = try fitFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let prepared = try ImageConversion.prepare(fitFixture(folder, width: 192, height: 128))
    let high = try ImageConversion.encode(prepared.image, options: .init(format: .jpeg, quality: 1))
    let low = try ImageConversion.encode(prepared.image, options: .init(format: .jpeg, quality: 0.3))
    let limit = (high.count + low.count) / 2
    let result = try ImageFit.preview(prepared, options: .init(format: .jpeg, maximumBytes: limit, minimumQuality: 0.3, allowSmallerDimensions: false))
    #expect(result.fits && result.byteCount <= limit && result.width == 192 && result.height == 128)
    #expect(try result.exportData() == result.bytes)
    #expect(try #require(result.quality) >= 0.3 && result.quality! < 1)
    _ = try inspectFit(result)
}

@Test func fitCanReducePNGToMeasuredBudgetWithoutWriting() throws {
    let folder = try fitFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let input = try fitFixture(folder)
    let before = try Data(contentsOf: input)
    let result = try ImageFit.preview(ImageConversion.prepare(input), options: .init(format: .png, maximumBytes: 300_000))
    #expect(result.fits && result.width < 640 && result.width >= 320 && result.quality == nil)
    #expect(result.width * 3 == result.height * 4 || abs(Double(result.width) / Double(result.height) - 4.0 / 3.0) < 0.01)
    _ = try inspectFit(result)
    #expect(try Data(contentsOf: input) == before)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.png"])
}

@Test func fitImpossibleBudgetIsReviewableButCannotBePublished() throws {
    let folder = try fitFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let prepared = try ImageConversion.prepare(fitFixture(folder))
    let result = try ImageFit.preview(prepared, options: .init(format: .png, maximumBytes: 1000))
    #expect(!result.fits && result.width >= 320 && !result.thumbnailPNG.isEmpty)
    #expect(result.encodingAttempts <= ImageFit.maximumEncodingAttempts)
    #expect(throws: ImageFitError.self) { try ImageFit.save(result) }
    #expect(throws: ImageFitError.self) { try result.exportData() }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.png"])
}

@Test func fitDisablingFurtherReductionKeepsInitialFitWithinDimensions() throws {
    let folder = try fitFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let prepared = try ImageConversion.prepare(fitFixture(folder))
    let result = try ImageFit.preview(prepared, options: .init(format: .png, maximumBytes: 1000, maximumWidth: 500, maximumHeight: 500, allowSmallerDimensions: false))
    #expect(!result.fits && result.width == 500 && result.height == 375 && result.encodingAttempts == 1)
    let small = try ImageFit.preview(prepared, options: .init(format: .png, maximumBytes: 1000, maximumWidth: 200, maximumHeight: 200))
    #expect(!small.fits && small.width == 200 && small.height == 150)
}

@Test func fitPNGTransparencyAndLossyBackgroundsUseActualEncodedPixels() throws {
    let folder = try fitFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let prepared = try ImageConversion.prepare(fitFixture(folder, width: 128, height: 96, transparent: true))
    let png = try ImageFit.preview(prepared, options: .init(format: .png))
    #expect(try firstPixel(inspectFit(png))[3] == 0)
    for format in [ImageOutputFormat.jpeg, .heic] where format.isAvailable {
        for background in ImageBackground.allCases {
            let fitted = try ImageFit.preview(prepared, options: .init(format: format, background: background))
            let pixel = try firstPixel(inspectFit(fitted))
            #expect(fitted.fits && pixel[3] == 255)
            #expect(pixel.prefix(3).allSatisfy { abs(Int($0) - (background == .white ? 255 : 0)) < 15 })
        }
    }
}

@Test func fitPreservesPreparedOrientationAndStripsSourceMetadata() throws {
    let folder = try fitFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let prepared = try ImageConversion.prepare(fitFixture(folder, width: 128, height: 96, orientation: 6))
    #expect(prepared.width == 96 && prepared.height == 128)
    for format in ImageOutputFormat.allCases where format.isAvailable {
        let result = try ImageFit.preview(prepared, options: .init(format: format, maximumWidth: 64, maximumHeight: 64))
        #expect(result.width == 48 && result.height == 64)
        let source = try #require(CGImageSourceCreateWithData(result.bytes as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
    }
}

@Test func fitPublishesExactPreviewBytesAfterSourceChangesWithSafeCollisions() throws {
    let folder = try fitFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let input = try fitFixture(folder, width: 128, height: 96)
    var options = ImageFitOptions(format: .jpeg)
    let result = try ImageFit.preview(ImageConversion.prepare(input), options: options)
    options.format = .png; options.maximumBytes = 1000
    try Data("Changed after capture".utf8).write(to: input)
    let first = try ImageFit.save(result)
    try FileManager.default.removeItem(at: input)
    let second = try ImageFit.save(result)
    #expect(first.lastPathComponent == "source fit.jpg" && second.lastPathComponent == "source fit 2.jpg")
    #expect(try Data(contentsOf: first) == result.bytes)
    #expect(try Data(contentsOf: second) == result.bytes)
    #expect(result.options.format == .jpeg && result.byteCount <= result.options.maximumBytes)
}

@Test func fitRejectsInvalidBoundsAndNonFiniteQuality() throws {
    for value in [0, 999, 100_000_001, Int.max] { #expect(throws: ImageFitError.self) { try ImageFitOptions(maximumBytes: value).validate() } }
    for value in [0, -1, 20_001, Int.max] {
        #expect(throws: ImageFitError.self) { try ImageFitOptions(maximumWidth: value).validate() }
        #expect(throws: ImageFitError.self) { try ImageFitOptions(maximumHeight: value).validate() }
    }
    for value in [Double.nan, .infinity, 0.09, 1.01] { #expect(throws: ImageFitError.self) { try ImageFitOptions(minimumQuality: value).validate() } }
}

@Test func fitCancellationDoesNotPublishPreviewOrSavedOutput() async throws {
    let folder = try fitFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let prepared = try ImageConversion.prepare(fitFixture(folder, width: 128, height: 96))
    let previewTask = Task { while !Task.isCancelled { await Task.yield() }; return try ImageFit.preview(prepared, options: .init()) }
    previewTask.cancel()
    await #expect(throws: CancellationError.self) { try await previewTask.value }
    let result = try ImageFit.preview(prepared, options: .init())
    let saveTask = Task { while !Task.isCancelled { await Task.yield() }; return try ImageFit.save(result) }
    saveTask.cancel()
    await #expect(throws: CancellationError.self) { try await saveTask.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["source.png"])
}

@Test func imageOutputsCanRecoverToAnotherFolderWithoutRecapturing() throws {
    let sourceFolder = try fitFolder(), destination = try fitFolder()
    defer { try? FileManager.default.removeItem(at: sourceFolder); try? FileManager.default.removeItem(at: destination) }
    let input = try fitFixture(sourceFolder, width: 80, height: 40)
    let prepared = try ImageConversion.prepare(input)
    let fitted = try ImageFit.preview(prepared, options: .init(format: .png, maximumWidth: 40, maximumHeight: 40))
    // A moved/deleted source must not invalidate the captured preview or redirect the output.
    try FileManager.default.removeItem(at: input)
    let missing = destination.appendingPathComponent("missing")
    #expect(throws: ToolError.self) { try ImageConversion.copy(prepared, options: .init(), in: missing) }
    #expect(throws: ToolError.self) { try ImageFit.save(fitted, in: missing) }
    let converted = try ImageConversion.copy(prepared, options: .init(), in: destination)
    let saved = try ImageFit.save(fitted, in: destination)
    #expect(converted.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL)
    #expect(saved.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL)
    #expect(try Data(contentsOf: saved) == fitted.bytes)
    let decoder = try #require(CGImageSourceCreateWithURL(converted as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
    #expect(image.width == 80 && image.height == 40)
    let collision = try ImageFit.save(fitted, in: destination)
    #expect(collision != saved)
    #expect(try Data(contentsOf: collision) == fitted.bytes)
    #expect(try FileManager.default.contentsOfDirectory(atPath: sourceFolder.path).isEmpty)
}
