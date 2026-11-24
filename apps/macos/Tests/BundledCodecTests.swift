import Foundation
import Testing
import CloakToolsCore

@Test func bundledCodecsProduceReopenableVideoAndAudio() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let audio = folder.appendingPathComponent("tone.wav")
    try MediaFixtures.audio(audio)
    for format in [OptimizedAudioFormat.mp3, .ogg] {
        var options = OptimizationOptions()
        options.audioFormat = format
        options.loudnessTarget = -16
        let encoded = try await MediaOptimization.prepare(audio, options: options)
        #expect(encoded.outputBytes > 0)
        let copy = try encoded.save(in: folder)
        options.audioFormat = .flac
        let decoded = try await MediaOptimization.prepare(copy, options: options)
        #expect(decoded.previewURL.pathExtension == "flac")
    }
    let movie = folder.appendingPathComponent("motion.mov")
    try await MediaFixtures.movie(movie)
    for format in [OptimizedVideoFormat.hevc, .x265, .av1, .webm] {
        var options = OptimizationOptions()
        options.videoFormat = format
        let encoded = try await MediaOptimization.prepare(movie, options: options)
        #expect(encoded.outputBytes > 0)
        if format == .webm {
            let copy = try encoded.save(in: folder)
            options.videoFormat = .gif
            let gif = try await MediaOptimization.prepare(copy, options: options)
            #expect(gif.previewURL.pathExtension == "gif")
        }
    }
}

@Test func bundledJPEGXLRestoresTheExactOriginalJPEG() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try QRCodeCreation.save(QRCodeCreation.prepare("JPEG XL test"), in: folder, stem: "Fixture")
    var options = OptimizationOptions()
    options.imageFormat = .jpeg
    let jpeg = try await MediaOptimization.prepare(input, options: options).save(in: folder)
    options.imageFormat = .jxl
    let jxl = try await MediaOptimization.prepare(jpeg, options: options).save(in: folder)
    options.imageFormat = .originalJPEG
    let result = try await MediaOptimization.prepare(jxl, options: options)
    #expect(try Data(contentsOf: result.previewURL) == Data(contentsOf: jpeg))
}
