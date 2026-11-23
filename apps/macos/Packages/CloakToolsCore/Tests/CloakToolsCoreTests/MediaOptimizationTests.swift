import AVFoundation
import Foundation
import ImageIO
import PDFKit
import Testing
import UniformTypeIdentifiers
@testable import CloakToolsCore

private func temporaryFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    return folder
}

@Test func optimizationImageFormatsAndMeasuredCopies() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let image = try QRCodeCreation.prepare("CloakTools optimization fixture")
    let url = try QRCodeCreation.save(image, in: folder, stem: "Source")
    let original = try Data(contentsOf: url)
    for format in OptimizedImageFormat.allCases where format != .automatic && format != .originalJPEG && (format != .jxl || format.available) {
        var options = OptimizationOptions()
        options.imageFormat = format
        options.crop = .landscape
        options.scale = 0.5
        options.maximumBytes = 100_000
        let result = try await MediaOptimization.prepare(url, options: options)
        let expected = try Data(contentsOf: result.previewURL)
        #expect(result.outputBytes == expected.count && expected.count <= 100_000)
        let out = try result.save(in: folder)
        let another = try result.save(in: folder)
        #expect(out != another && out != url)
        #expect(try Data(contentsOf: another) == expected)
        let source = try #require(CGImageSourceCreateWithData(expected as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == format.type?.identifier)
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 256 && decoded.height == 144)
    }
    #expect(try Data(contentsOf: url) == original)
    var options = OptimizationOptions()
    options.imageFormat = .webp
    options.losslessWebP = true
    let snapshot = try await MediaOptimization.prepare(url, options: options)
    try FileManager.default.removeItem(at: url)
    #expect(try Data(contentsOf: snapshot.save(in: folder)) == Data(contentsOf: snapshot.previewURL))
}

@Test func optimizationAudioEncodesEveryNativeFormat() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Recording.caf")
    try MediaFixtures.audio(url)
    for format in [OptimizedAudioFormat.automatic, .aac, .flac, .wav, .aiff] {
        var options = OptimizationOptions()
        options.audioFormat = format
        options.normalizeAudio = true
        options.audioBitrate = 64
        let result = try await MediaOptimization.prepare(url, options: options)
        let check = try AVAudioFile(forReading: result.previewURL)
        #expect(check.processingFormat.channelCount == 1)
        #expect(abs(Double(check.length) / check.processingFormat.sampleRate - 2) < 0.12)
        if format == .automatic { #expect(result.outputBytes < result.inputBytes) }
    }
    var options = OptimizationOptions()
    options.maximumBytes = 1_000
    await #expect(throws: OptimizationError.overBudget) { try await MediaOptimization.prepare(url, options: options) }
}

@Test func optimizationCropsPDFAndRestoresMediaBox() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Document.pdf")
    let original = try BlankDocuments.pdf()
    try original.write(to: url)
    var options = OptimizationOptions()
    options.crop = .square
    let result = try await MediaOptimization.prepare(url, options: options)
    let page = try #require(PDFDocument(url: result.previewURL)?.page(at: 0))
    #expect(page.bounds(for: .mediaBox).height > page.bounds(for: .cropBox).height)
    #expect(abs(page.bounds(for: .cropBox).width - page.bounds(for: .cropBox).height) < 1)
    options.crop = .fullPage
    let expanded = try await MediaOptimization.prepare(result.previewURL, options: options)
    let restored = try #require(PDFDocument(url: expanded.previewURL)?.page(at: 0))
    #expect(restored.bounds(for: .cropBox) == restored.bounds(for: .mediaBox))
    #expect(try Data(contentsOf: url) == original)
}

@Test func optimizationScalesRotatedVideoChangesSpeedMutesAndExportsGIF() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let video = folder.appendingPathComponent("Portrait.mov"), audio = folder.appendingPathComponent("Sound.caf")
    try await MediaFixtures.movie(video, rotated: true)
    try MediaFixtures.audio(audio)
    let source = folder.appendingPathComponent("Clip.mov")
    try await MediaFixtures.combine(video: video, audio: audio, output: source)
    var options = OptimizationOptions()
    options.crop = .square
    options.scale = 0.5
    options.playbackSpeed = 2
    options.muteVideo = true
    let result = try await MediaOptimization.prepare(source, options: options)
    let asset = AVURLAsset(url: result.previewURL)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let size = try await track.load(.naturalSize)
    #expect(size.width == 90 && size.height == 90)
    #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
    #expect(abs(try await asset.load(.duration).seconds - 1) < 0.1)
    options.videoFormat = .gif
    let gif = try await MediaOptimization.prepare(video, options: options)
    let frames = try #require(CGImageSourceCreateWithURL(gif.previewURL as CFURL, nil))
    #expect(CGImageSourceGetCount(frames) == 12)
    let smaller = try await MediaOptimization.prepare(gif.previewURL, options: .fixtureAnimationScale)
    let reencoded = try #require(CGImageSourceCreateWithURL(smaller.previewURL as CFURL, nil))
    #expect(CGImageSourceGetCount(reencoded) == 12)
    let first = try #require(CGImageSourceCreateImageAtIndex(reencoded, 0, nil))
    #expect(first.width == 45 && first.height == 45)
    var animation = OptimizationOptions()
    animation.imageFormat = .webp
    let webp = try await MediaOptimization.prepare(gif.previewURL, options: animation)
    let webpFrames = try #require(CGImageSourceCreateWithURL(webp.previewURL as CFURL, nil))
    #expect(CGImageSourceGetCount(webpFrames) == 12)
    #expect(CGImageSourceGetType(webpFrames) as String? == UTType.webP.identifier)
    let timing = try #require(CGImageSourceCopyPropertiesAtIndex(webpFrames, 1, nil) as? [CFString: Any])
    let info = try #require(timing[kCGImagePropertyWebPDictionary] as? [CFString: Any])
    #expect(abs((info[kCGImagePropertyWebPUnclampedDelayTime] as? Double ?? 0) - 1.0 / 12) < 0.015)
    animation.imageFormat = .gif
    let gifCopy = try await MediaOptimization.prepare(webp.previewURL, options: animation)
    let gifFrames = try #require(CGImageSourceCreateWithURL(gifCopy.previewURL as CFURL, nil))
    #expect(CGImageSourceGetCount(gifFrames) == 12)
    #expect(CGImageSourceGetType(gifFrames) as String? == UTType.gif.identifier)
}

private extension OptimizationOptions {
    static var fixtureAnimationScale: Self {
        var options = Self()
        options.scale = 0.5
        return options
    }
}

@Test func watchedFolderHandlesStableNewFilesOnceAndSkipsItsOwnOutputs() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let old = folder.appendingPathComponent("Old.jpg")
    try Data([1]).write(to: old)
    var watch = WatchedMedia(baseline: try WatchedMedia.snapshot(in: folder))
    let new = folder.appendingPathComponent("New.png")
    try Data([1]).write(to: new)
    #expect(watch.stableAdditions(try WatchedMedia.snapshot(in: folder)).isEmpty)
    try Data([1, 2]).write(to: new)
    #expect(watch.stableAdditions(try WatchedMedia.snapshot(in: folder)).isEmpty)
    #expect(watch.stableAdditions(try WatchedMedia.snapshot(in: folder)) == [new])
    let output = try WatchedMedia.outputFolder(for: folder)
    try Data([1]).write(to: output.appendingPathComponent("New optimized.png"))
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Link.png"), withDestinationURL: new)
    #expect(watch.stableAdditions(try WatchedMedia.snapshot(in: folder)).isEmpty)
    #expect(Set(try WatchedMedia.snapshot(in: folder).keys) == Set([new, old]))
}

@Test func replacingAndRestoringOriginalGuardsBothFiles() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let image = try QRCodeCreation.prepare("Replace and restore fixture")
    let url = try QRCodeCreation.save(image, in: folder, stem: "Source")
    let original = try Data(contentsOf: url)
    let preview = try await MediaOptimization.prepare(url, options: .fixtureAnimationScale)
    let encoded = try Data(contentsOf: preview.previewURL)
    let backup = try preview.replaceOriginal()
    #expect(try Data(contentsOf: url) == encoded)
    #expect(try Data(contentsOf: backup.backupURL) == original)
    try OptimizationBackup(backupFile: backup.backupURL).restore()
    #expect(try Data(contentsOf: url) == original)
    #expect(try Data(contentsOf: backup.backupURL) == encoded)
    #expect(throws: OriginalFileError.changed) { try backup.restore() }
    try Data([42]).write(to: url)
    #expect(throws: OriginalFileError.changed) { try preview.replaceOriginal() }
    let saved = try preview.save(in: folder)
    try Data([1]).write(to: saved)
    #expect(throws: OriginalFileError.changed) { try preview.trashOriginal(afterSaving: saved) }
    #expect(try Data(contentsOf: url) == Data([42]))
}
