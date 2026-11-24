import Testing
import Foundation
import AVFoundation
import AudioToolbox
@testable import CloakToolsCore

private func mediaFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsMediaTests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true); return folder
}

@Test func mediaAudioExportKeepsCaptureAndResolvesCollisions() async throws {
    let folder = try mediaFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let sourceURL = folder.appendingPathComponent("Tone.wav"); try MediaFixtures.audio(sourceURL)
    let original = try Data(contentsOf: sourceURL)
    let source = try await MediaExport.prepare(sourceURL)
    #expect(!source.hasVideo && source.hasAudio && source.presets == [.audio])
    #expect(abs(source.duration - 2) < 0.01)
    #expect(source.sourceByteCount == original.count)
    let mode = try FileManager.default.attributesOfItem(atPath: source.playbackURL.deletingLastPathComponent().path)[.posixPermissions] as? Int
    #expect(mode == 0o700)
    let fileMode = try FileManager.default.attributesOfItem(atPath: source.playbackURL.path)[.posixPermissions] as? Int
    #expect(fileMode == 0o600)
    try Data("changed".utf8).write(to: sourceURL)
    try FileManager.default.removeItem(at: sourceURL)
    let first = try await MediaExport.export(source, preset: .audio, in: folder, name: "Tone")
    let bytes = try Data(contentsOf: first)
    let second = try await MediaExport.export(source, preset: .audio, in: folder, name: "Tone")
    #expect(first.lastPathComponent == "Tone.m4a" && second.lastPathComponent == "Tone 2.m4a")
    #expect(try Data(contentsOf: first) == bytes)
    let audio = try AVAudioFile(forReading: first)
    let decoded = try #require(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4096))
    try audio.read(into: decoded)
    #expect(decoded.frameLength > 0)
    let values = try #require(decoded.floatChannelData?[0])
    #expect((0..<Int(decoded.frameLength)).contains { abs(values[$0]) > 0.05 })
    #expect(abs(Double(audio.length) / audio.processingFormat.sampleRate - 2) < 0.1)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["Tone 2.m4a", "Tone.m4a"])
}

@Test func mediaVideoMatrixPreservesOrientationAndDecodesOutput() async throws {
    let folder = try mediaFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    for codec in [AVVideoCodecType.h264, .hevc] {
        let url = folder.appendingPathComponent("\(codec.rawValue).mov")
        try await MediaFixtures.movie(url, codec: codec, rotated: true)
        let original = try Data(contentsOf: url)
        let source = try await MediaExport.prepare(url)
        #expect(source.width == 180 && source.height == 320 && source.hasVideo && !source.hasAudio)
        #expect(source.presets == [.video720, .video1080])
        for preset in source.presets {
            let result = try await MediaExport.export(source, preset: preset, in: folder, name: "\(codec.rawValue)-\(preset.rawValue)")
            let output = AVURLAsset(url: result)
            let video = try await output.loadTracks(withMediaType: .video)
            let track = try #require(video.first)
            let descriptions = try await track.load(.formatDescriptions)
            #expect(descriptions.allSatisfy { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 })
            let generator = AVAssetImageGenerator(asset: output); generator.appliesPreferredTrackTransform = true
            let frame = try await generator.image(at: .zero).image
            #expect(frame.width == 180 && frame.height == 320)
            #expect(abs(try await output.load(.duration).seconds - 2) < 0.1)
        }
        #expect(try Data(contentsOf: url) == original)
    }
}

@Test func mediaMovieWithAudioExportsBothVideoAndAudioOnly() async throws {
    let folder = try mediaFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let v = folder.appendingPathComponent("Video.mov"), a = folder.appendingPathComponent("Tone.wav"), combined = folder.appendingPathComponent("Combined.mov")
    try await MediaFixtures.movie(v); try MediaFixtures.audio(a)
    try await MediaFixtures.combine(video: v, audio: a, output: combined)
    let source = try await MediaExport.prepare(combined)
    #expect(source.presets == MediaExportPreset.allCases)
    for preset in source.presets {
        let output = try await MediaExport.export(source, preset: preset, in: folder, name: preset.rawValue)
        let asset = AVURLAsset(url: output)
        #expect(try await asset.loadTracks(withMediaType: .video).count == (preset == .audio ? 0 : 1))
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.count == 1)
        #expect(try await audio[0].load(.formatDescriptions).allSatisfy { CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC })
        #expect(try await asset.load(.commonMetadata).allSatisfy { $0.identifier != .commonIdentifierTitle })
    }
}

@Test func mediaInvalidSourcesAndUnavailablePresetsPublishNothing() async throws {
    let folder = try mediaFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Invalid.mov"); try Data("not a movie".utf8).write(to: url)
    await #expect(throws: (any Error).self) { try await MediaExport.prepare(url) }
    await #expect(throws: (any Error).self) { try await MediaExport.prepare(folder) }
    await #expect(throws: MediaExportError.self) { try await MediaExport.prepare(URL(string: "https://example.com/movie.mp4")!) }
    let large = folder.appendingPathComponent("Large.mov"); try Data().write(to: large)
    let handle = try FileHandle(forWritingTo: large); try handle.truncate(atOffset: UInt64(MediaExport.maximumInputBytes + 1)); try handle.close()
    await #expect(throws: MediaExportError.self) { try await MediaExport.prepare(large) }
    let audio = folder.appendingPathComponent("Tone.wav"); try MediaFixtures.audio(audio)
    let source = try await MediaExport.prepare(audio)
    await #expect(throws: MediaExportError.self) { try await MediaExport.export(source, preset: .video720, in: folder, name: "Invalid") }
    await #expect(throws: ToolError.self) { try await MediaExport.export(source, preset: .audio, in: folder, name: "../Invalid") }
    await #expect(throws: ToolError.self) { try await MediaExport.export(source, preset: .audio, in: folder.appendingPathComponent("Missing"), name: "Invalid") }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["Invalid.mov", "Large.mov", "Tone.wav"])
}

@Test func mediaCaptureLifetimeAndCancellationCleanup() async throws {
    let folder = try mediaFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Tone.wav"); try MediaFixtures.audio(url)
    var source: PreparedMedia? = try await MediaExport.prepare(url)
    let snapshot = try #require(source?.playbackURL)
    #expect(FileManager.default.fileExists(atPath: snapshot.path))
    source = nil
    #expect(!FileManager.default.fileExists(atPath: snapshot.deletingLastPathComponent().path))
    let prepared = try await MediaExport.prepare(url)
    let task = Task { while !Task.isCancelled { await Task.yield() }; return try await MediaExport.export(prepared, preset: .audio, in: folder, name: "Cancelled") }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    let capture = Task { while !Task.isCancelled { await Task.yield() }; return try await MediaExport.prepare(url) }
    capture.cancel()
    await #expect(throws: CancellationError.self) { try await capture.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Tone.wav"])
    #expect(MediaExport.localAsset(prepared.playbackURL).referenceRestrictions == .forbidAll)
}

@Test func mediaDownsizes1080VideoTo720AndChecksProgress() async throws {
    let folder = try mediaFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Large.mov")
    try await MediaFixtures.movie(url, width: 1920, height: 1080, seconds: 1)
    let source = try await MediaExport.prepare(url)
    actor ProgressLog {
        var values: [Double] = []
        func record(_ value: Double) { values.append(value) }
    }
    let progress = ProgressLog()
    let output = try await MediaExport.export(source, preset: .video720, in: folder, name: "720") { value in await progress.record(value) }
    let asset = AVURLAsset(url: output)
    let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
    let frame = try await generator.image(at: .zero).image
    #expect(frame.width == 1280 && frame.height == 720)
    let values = await progress.values
    #expect(values.contains(1) && values.allSatisfy { $0.isFinite && (0...1).contains($0) })
}

@Test func mediaRejectsMultipleAudioTracks() async throws {
    let folder = try mediaFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let v = folder.appendingPathComponent("Video.mov"), a = folder.appendingPathComponent("Tone.wav"), combined = folder.appendingPathComponent("Multiple.mov")
    try await MediaFixtures.movie(v, seconds: 1); try MediaFixtures.audio(a, seconds: 1)
    try await MediaFixtures.combine(video: v, audio: a, output: combined, extraAudio: true)
    #expect(try await AVURLAsset(url: combined).loadTracks(withMediaType: .audio).count == 2)
    await #expect(throws: MediaExportError.self) { try await MediaExport.prepare(combined) }
}

@Test func mediaAACInputCanExportAgain() async throws {
    let folder = try mediaFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("Tone.wav"); try MediaFixtures.audio(url)
    let first = try await MediaExport.export(MediaExport.prepare(url), preset: .audio, in: folder, name: "First")
    let source = try await MediaExport.prepare(first)
    let second = try await MediaExport.export(source, preset: .audio, in: folder, name: "Second")
    #expect(try AVAudioFile(forReading: second).length > 0)
}
