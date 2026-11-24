import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import Darwin

public enum MediaExportPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case video720, video1080, audio
    public var id: String { rawValue }
    public var title: String {
        switch self { case .video720: "MP4 · Up to 720p"; case .video1080: "MP4 · Up to 1080p"; case .audio: "M4A · Audio only" }
    }
    public var detail: String {
        switch self {
        case .video720: "H.264 video with AAC audio when present. Keeps proportions and does not enlarge."
        case .video1080: "H.264 video with AAC audio when present. Keeps proportions and does not enlarge."
        case .audio: "AAC audio in an M4A file. Video is excluded."
        }
    }
    public var fileExtension: String { self == .audio ? "m4a" : "mp4" }
    var identifier: String {
        switch self { case .video720: AVAssetExportPreset1280x720; case .video1080: AVAssetExportPreset1920x1080; case .audio: AVAssetExportPresetAppleM4A }
    }
    var fileType: AVFileType { self == .audio ? .m4a : .mp4 }
}

public enum MediaExportError: LocalizedError, Sendable {
    case unsupported, limits, changed, unavailable, invalidOutput
    public var errorDescription: String? {
        switch self {
        case .unsupported: "Choose a self-contained movie with H.264/HEVC SDR video, or AAC, MP3 or PCM audio. Protected media, HDR, spatial video and multiple video/audio tracks are unsupported."
        case .limits: "Choose media up to 1 GB and 30 minutes, with video up to 4096 × 2160 at 60 fps and mono/stereo audio up to 96 kHz."
        case .changed: "The source changed while it was being copied. Wait for it to finish saving, then choose it again."
        case .unavailable: "macOS cannot use that output preset for this media. Choose another available format."
        case .invalidOutput: "The exported file could not be verified. No copy was published."
        }
    }
}

/// Owns a private disk capture until the last operation/playback reference is released.
final class MediaCapture: Sendable {
    private let workspace: MediaWorkspace
    let url: URL
    let byteCount: Int
    init(_ source: URL, acceptedExtensions: Set<String> = MediaExport.inputExtensions) throws {
        try Task.checkCancellation()
        guard source.isFileURL, acceptedExtensions.contains(source.pathExtension.lowercased()) else { throw MediaExportError.unsupported }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var before = stat()
        guard fstat(input.fileDescriptor, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG else { throw MediaExportError.unsupported }
        guard before.st_size > 0, before.st_size <= MediaExport.maximumInputBytes else { throw MediaExportError.limits }
        let workspace = try MediaWorkspace()
        let target = workspace.folder.appendingPathComponent("source.\(source.pathExtension.lowercased())")
        guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        var count = 0
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            count += chunk.count
            guard count <= MediaExport.maximumInputBytes else { throw MediaExportError.limits }
            try handle.write(contentsOf: chunk)
        }
        var after = stat()
        guard fstat(input.fileDescriptor, &after) == 0, before.st_size == after.st_size, count == before.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw MediaExportError.changed }
        try Task.checkCancellation()
        self.workspace = workspace
        url = target
        byteCount = count
    }
}

public struct PreparedMedia: Sendable {
    public let sourceURL: URL
    public let duration: Double
    public let width: Int
    public let height: Int
    public let frameRate: Float
    public let hasAudio: Bool
    public let presets: [MediaExportPreset]
    let capture: MediaCapture
    public var hasVideo: Bool { width > 0 }
    public var sourceByteCount: Int { capture.byteCount }
    /// Only for explicit in-app playback; callers must retain this capture while playing it.
    public var playbackURL: URL { capture.url }
}

public enum MediaExport {
    public static let maximumInputBytes = 1_000_000_000
    public static let maximumOutputBytes = 2_000_000_000
    public static let inputExtensions: Set<String> = ["mov", "mp4", "m4v", "m4a", "mp3", "wav", "aif", "aiff", "caf"]

    public static func localAsset(_ url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue,
                                     AVURLAssetPreferPreciseDurationAndTimingKey: true])
    }

    public static func prepare(_ url: URL) async throws -> PreparedMedia {
        let capture = try MediaCapture(url)
        let asset = localAsset(capture.url)
        let (playable, protected, duration) = try await asset.load(.isPlayable, .hasProtectedContent, .duration)
        guard playable, !protected else { throw MediaExportError.unsupported }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0, seconds <= 1800 else { throw MediaExportError.limits }
        let video = try await asset.loadTracks(withMediaType: .video), audio = try await asset.loadTracks(withMediaType: .audio)
        guard video.count <= 1, audio.count <= 1, !video.isEmpty || !audio.isEmpty else { throw MediaExportError.unsupported }
        var width = 0, height = 0, fps: Float = 0
        if let track = video.first {
            let (size, transform, frameRate, formats, characteristics) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions, .mediaCharacteristics)
            guard !formats.isEmpty, formats.allSatisfy({ [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC].contains(CMFormatDescriptionGetMediaSubType($0)) }),
                  !characteristics.contains(.containsHDRVideo), !characteristics.contains(.usesWideGamutColorSpace),
                  !characteristics.contains(.containsAlphaChannel), !characteristics.contains(.containsStereoMultiviewVideo),
                  !characteristics.contains(.carriesVideoStereoMetadata) else { throw MediaExportError.unsupported }
            let displayed = CGRect(origin: .zero, size: size).applying(transform).size
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
                  max(size.width, size.height) <= 4096, min(size.width, size.height) <= 2160,
                  displayed.width.isFinite, displayed.height.isFinite, displayed.width > 0, displayed.height > 0,
                  max(displayed.width, displayed.height) <= 4096, min(displayed.width, displayed.height) <= 2160,
                  frameRate.isFinite, frameRate > 0, frameRate <= 60.01 else { throw MediaExportError.limits }
            width = Int(displayed.width.rounded()); height = Int(displayed.height.rounded()); fps = frameRate
        }
        if let track = audio.first {
            let formats = try await track.load(.formatDescriptions)
            guard !formats.isEmpty else { throw MediaExportError.unsupported }
            for format in formats {
                guard let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                      [kAudioFormatMPEG4AAC, kAudioFormatMPEGLayer3, kAudioFormatLinearPCM].contains(description.mFormatID) else { throw MediaExportError.unsupported }
                guard (1...2).contains(description.mChannelsPerFrame), description.mSampleRate.isFinite,
                      description.mSampleRate > 0, description.mSampleRate <= 96000 else { throw MediaExportError.limits }
            }
        }
        var presets: [MediaExportPreset] = []
        for preset in MediaExportPreset.allCases where preset == .audio ? !audio.isEmpty : !video.isEmpty {
            try Task.checkCancellation()
            let composition = try await composition(asset, audioOnly: preset == .audio)
            if await AVAssetExportSession.compatibility(ofExportPreset: preset.identifier, with: composition, outputFileType: preset.fileType) { presets.append(preset) }
        }
        guard !presets.isEmpty else { throw MediaExportError.unavailable }
        try Task.checkCancellation()
        return PreparedMedia(sourceURL: url, duration: seconds, width: width, height: height, frameRate: fps,
                             hasAudio: !audio.isEmpty, presets: presets, capture: capture)
    }

    public static func export(_ source: PreparedMedia, preset: MediaExportPreset, in folder: URL, name: String,
                              adjustments: OptimizationOptions? = nil,
                              progress: @escaping @Sendable (Double) async -> Void = { _ in }) async throws -> URL {
        try SafeOutput.validate(stem: name)
        try Task.checkCancellation()
        guard source.presets.contains(preset) else { throw MediaExportError.unavailable }
        guard folder.isFileURL, (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw ToolError.unavailableFolder }
        try adjustments?.validate()
        let muted = preset != .audio && adjustments?.muteVideo == true
        let composition = try await composition(localAsset(source.capture.url), audioOnly: preset == .audio, muted: muted)
        if source.hasVideo, let speed = adjustments?.playbackSpeed, speed != 1 {
            let duration = try await composition.load(.duration)
            composition.scaleTimeRange(CMTimeRange(start: .zero, duration: duration), toDuration: CMTimeMultiplyByFloat64(duration, multiplier: 1 / speed))
        }
        let expectedDuration = try await composition.load(.duration).seconds
        guard let session = AVAssetExportSession(asset: composition, presetName: preset.identifier), session.supportedFileTypes.contains(preset.fileType) else { throw MediaExportError.unavailable }
        if let adjustments, preset != .audio, adjustments.crop.aspect != nil || adjustments.scale != 1 {
            session.videoComposition = try await geometry(composition, source: source, preset: preset, options: adjustments)
        }
        if let limit = adjustments?.maximumBytes { session.fileLengthLimit = Int64(limit) }
        session.metadata = []
        session.shouldOptimizeForNetworkUse = preset != .audio
        let directory = folder.appendingPathComponent(".cloaktools-media-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let staged = directory.appendingPathComponent("export.\(preset.fileExtension)")
        let states = session.states(updateInterval: 0.15)
        let observer = Task {
            for await state in states {
                if Task.isCancelled { break }
                if case let .exporting(value) = state { await progress(min(0.99, max(0, value.fractionCompleted))) }
            }
        }
        defer { observer.cancel() }
        do { try await session.export(to: staged, as: preset.fileType) }
        catch { if Task.isCancelled { throw CancellationError() }; throw error }
        try Task.checkCancellation()
        let count = try staged.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard count > 0, count <= maximumOutputBytes else { throw MediaExportError.invalidOutput }
        let check = localAsset(staged)
        let (playable, duration) = try await check.load(.isPlayable, .duration)
        let video = try await check.loadTracks(withMediaType: .video), audio = try await check.loadTracks(withMediaType: .audio)
        guard playable, duration.seconds.isFinite, duration.seconds > 0,
              abs(duration.seconds - expectedDuration) <= max(0.25, expectedDuration * 0.001),
              preset == .audio ? (video.isEmpty && audio.count == 1) : (video.count == 1 && audio.count == (source.hasAudio && !muted ? 1 : 0)) else { throw MediaExportError.invalidOutput }
        if let track = video.first {
            let (formats, size, transform) = try await track.load(.formatDescriptions, .naturalSize, .preferredTransform)
            let displayed = CGRect(origin: .zero, size: size).applying(transform).size
            let longEdge: CGFloat = preset == .video720 ? 1280 : 1920, shortEdge: CGFloat = preset == .video720 ? 720 : 1080
            guard !formats.isEmpty, formats.allSatisfy({ CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }),
                  displayed.width.isFinite, displayed.height.isFinite, displayed.width > 0, displayed.height > 0,
                  max(displayed.width, displayed.height) <= longEdge + 2, min(displayed.width, displayed.height) <= shortEdge + 2,
                  displayed.width <= CGFloat(source.width) + 2, displayed.height <= CGFloat(source.height) + 2 else { throw MediaExportError.invalidOutput }
        }
        if let track = audio.first {
            let formats = try await track.load(.formatDescriptions)
            guard !formats.isEmpty, formats.allSatisfy({ CMFormatDescriptionGetMediaSubType($0) == kAudioFormatMPEG4AAC }) else { throw MediaExportError.invalidOutput }
        }
        try Task.checkCancellation()
        let output = try SafeOutput.publishStagedFile(staged, in: folder, stem: name, extension: preset.fileExtension)
        await progress(1)
        return output
    }

    private static func geometry(_ composition: AVComposition, source: PreparedMedia, preset: MediaExportPreset,
                                 options: OptimizationOptions) async throws -> AVVideoComposition {
        guard let track = try await composition.loadTracks(withMediaType: .video).first else { throw MediaExportError.unavailable }
        let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
        let display = CGRect(origin: .zero, size: natural).applying(transform)
        let crop = options.crop.centered(in: display)
        let longEdge = preset == .video720 ? 1280.0 : 1920.0
        let shortEdge = preset == .video720 ? 720.0 : 1080.0
        let scale = min(options.scale, longEdge / max(crop.width, crop.height), shortEdge / min(crop.width, crop.height))
        let width = max(2, (crop.width * scale / 2).rounded(.down) * 2)
        let height = max(2, (crop.height * scale / 2).rounded(.down) * 2)
        var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: track)
        layer.setTransform(transform.concatenating(.init(translationX: -crop.minX, y: -crop.minY))
            .concatenating(.init(scaleX: width / crop.width, y: height / crop.height)), at: .zero)
        let range = CMTimeRange(start: .zero, duration: try await composition.load(.duration))
        let instruction = AVVideoCompositionInstruction(configuration: .init(layerInstructions: [.init(configuration: layer)], timeRange: range))
        let frame = CMTime(value: 1, timescale: Int32(max(1, min(60, source.frameRate.rounded()))))
        return AVVideoComposition(configuration: .init(frameDuration: frame, instructions: [instruction], renderSize: CGSize(width: width, height: height)))
    }

    /// Include only the chosen media tracks; don't copy chapters, subtitle or timed metadata tracks.
    private static func composition(_ asset: AVAsset, audioOnly: Bool, muted: Bool = false) async throws -> AVMutableComposition {
        let output = AVMutableComposition()
        for type in audioOnly ? [AVMediaType.audio] : (muted ? [.video] : [.video, .audio]) {
            for source in try await asset.loadTracks(withMediaType: type) {
                try Task.checkCancellation()
                let range = try await source.load(.timeRange)
                guard let track = output.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw MediaExportError.unavailable }
                try track.insertTimeRange(range, of: source, at: range.start)
                if type == .video { track.preferredTransform = try await source.load(.preferredTransform) }
            }
        }
        return output
    }
}
