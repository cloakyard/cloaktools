import Foundation

/// The helper is built from pinned sources, has only the file protocol, and lives in the app bundle.
/// Input demuxers are fixed by media type. No argument is interpreted by a shell.
enum ExtendedMediaEncoding {
    static let movies: Set<String> = ["mov", "mp4", "m4v", "webm", "mkv", "avi", "mpg", "mpeg", "m2v"]
    static let audio: Set<String> = ["ogg", "opus", "m4a", "mp3", "flac", "wav", "caf", "aiff", "aif"]
    static func handles(_ ext: String, options: OptimizationOptions) -> Bool {
        if movies.contains(ext) { return (options.maximumBytes != nil && options.videoFormat != .gif) || !["mov", "mp4", "m4v"].contains(ext) || [.hevc, .x265, .webm, .av1].contains(options.videoFormat) }
        return audio.contains(ext) && (options.loudnessTarget != nil || ["ogg", "opus"].contains(ext) || [.mp3, .ogg].contains(options.audioFormat))
    }
    private enum Failure: LocalizedError {
        case unavailable, invalidStreams, failed, invalidOutput
        case encoder(String)
        var errorDescription: String? {
            switch self {
            case .unavailable: "The bundled media encoders could not be found. Rebuild or reinstall CloakTools."
            case .invalidStreams: "Choose a self-contained file with one video or audio stream, up to one additional audio stream, and a duration under 30 minutes."
            case .failed: "The media encoder could not complete this conversion."
            case let .encoder(message): "The media encoder could not complete this conversion. " + message
            case .invalidOutput: "The encoded streams or duration could not be verified."
            }
        }
    }
    struct Probe: Decodable, Sendable {
        struct Stream: Decodable, Sendable {
            let codec_type: String
            let codec_name: String?
            let width: Int?
            let height: Int?
            let channels: Int?
            let sample_rate: String?
            let avg_frame_rate: String?
            let r_frame_rate: String?
            let color_transfer: String?
        }
        struct Format: Decodable { let duration: String? }
        let streams: [Stream]
        let format: Format
        var seconds: Double { format.duration.flatMap(Double.init) ?? 0 }
        var video: Stream? { streams.first { $0.codec_type == "video" } }
        var sound: Stream? { streams.first { $0.codec_type == "audio" } }
        func validate() throws {
            guard seconds.isFinite, seconds > 0, seconds <= 1800,
                  !streams.isEmpty, streams.count <= 2,
                  streams.allSatisfy({ $0.codec_type == "video" || $0.codec_type == "audio" }),
                  streams.filter({ $0.codec_type == "video" }).count <= 1,
                  streams.filter({ $0.codec_type == "audio" }).count <= 1 else { throw Failure.invalidStreams }
            if let video {
                let w = video.width ?? 0, h = video.height ?? 0
                let rate = [video.avg_frame_rate, video.r_frame_rate].compactMap { value -> Double? in
                    guard let value else { return nil }
                    let parts = value.split(separator: "/").compactMap { Double($0) }
                    guard parts.count == 2, parts[1] > 0, parts[0] > 0 else { return nil }
                    return parts[0] / parts[1]
                }.first
                guard w > 0, h > 0, max(w, h) <= 4096, min(w, h) <= 2160, let rate, (0.1...60.1).contains(rate),
                      !["smpte2084", "arib-std-b67"].contains(video.color_transfer ?? "") else { throw MediaExportError.limits }
            }
            if let sound {
                guard (1...2).contains(sound.channels ?? 0), (1...96_000).contains(Int(sound.sample_rate ?? "") ?? 0) else { throw MediaExportError.limits }
            }
        }
    }

    static var helperDirectory: URL {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Media")
        }
        let executable = Bundle.main.executableURL ?? Bundle.main.bundleURL
        return executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Helpers/Media")
    }

    static func encode(_ url: URL, in folder: URL, options: OptimizationOptions, helpers: URL? = nil) async throws -> (URL, Int) {
        let tools = helpers ?? helperDirectory
        let capture = try MediaCapture(url, acceptedExtensions: movies.union(audio))
        let probe = try await inspect(capture.url, tools: tools, folder: folder)
        try probe.validate()
        let video = probe.video != nil
        let suffix: String
        let encoding: [String]
        if video {
            (suffix, encoding) = try videoArguments(probe, options: options)
        } else {
            (suffix, encoding) = try audioArguments(probe, options: options)
        }
        let output = folder.appendingPathComponent("result." + suffix)
        var filters = encoding
        if !video, let target = options.loudnessTarget {
            let sampleRate = probe.sound?.sample_rate ?? "48000"
            var filter = "loudnorm=I=\(target):TP=-1.5:LRA=11,aresample=\(sampleRate)"
            if options.audioFormat == .flac { filter += ",asetnsamples=n=4096:p=0" }
            filters += ["-af", filter, "-ar", sampleRate]
        } else if !video && options.normalizeAudio {
            let stats = folder.appendingPathComponent("peak.log")
            defer { try? FileManager.default.removeItem(at: stats) }
            try await run(tools.appendingPathComponent("ffmpeg"), args: ["-hide_banner", "-nostdin"] + input(capture.url)
                + ["-vn", "-af", "volumedetect", "-f", "null", "-"], output: nil, diagnostics: stats)
            let log = String(decoding: try LocalFileCapture.read(stats, limit: 262_144), as: UTF8.self)
            guard let line = log.components(separatedBy: "max_volume: ").last,
                  let value = line.split(separator: " ").first, let peak = Double(value), peak.isFinite else { throw Failure.failed }
            filters += ["-af", "volume=\(-1 - peak)dB"]
        }
        let args = ["-hide_banner", "-loglevel", "error", "-nostdin", "-n", "-threads", "2"] + input(capture.url)
            + ["-map_metadata", "-1", "-map_chapters", "-1", "-sn", "-dn"] + filters
            + ["-threads", "4", "-fs", String(MediaExport.maximumOutputBytes), output.path]
        let diagnostic = folder.appendingPathComponent("encoder.log")
        defer { try? FileManager.default.removeItem(at: diagnostic) }
        do {
            try await run(tools.appendingPathComponent("ffmpeg"), args: args, output: nil, diagnostics: diagnostic)
        } catch Failure.failed {
            let data = try? LocalFileCapture.read(diagnostic, limit: 65_536)
            let line = data.flatMap { String(decoding: $0, as: UTF8.self).split(separator: "\n").first }
            if let line { throw Failure.encoder(String(line.prefix(240))) }
            throw Failure.failed
        }
        let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...MediaExport.maximumOutputBytes).contains(bytes) else { throw Failure.invalidOutput }
        let check = try await inspect(output, tools: tools, folder: folder)
        let expectedDuration = probe.seconds / (video ? options.playbackSpeed : 1)
        let expectedAudio = probe.sound != nil && (!video || (!options.muteVideo && suffix != "gif"))
        guard check.seconds.isFinite, abs(check.seconds - expectedDuration) <= max(0.25, expectedDuration * 0.003),
              (check.video != nil) == video, (check.sound != nil) == expectedAudio else { throw Failure.invalidOutput }
        return (output, capture.byteCount)
    }

    private static func input(_ url: URL) -> [String] {
        let demux = switch url.pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "m4a": "mov"
        case "webm", "mkv": "matroska"
        case "opus", "ogg": "ogg"
        case "aif", "aiff": "aiff"
        case "mpeg", "mpg": "mpeg"
        case "m2v": "mpegvideo"
        default: url.pathExtension.lowercased()
        }
        return ["-protocol_whitelist", "file", "-f", demux, "-i", url.path]
    }

    private static func videoArguments(_ probe: Probe, options: OptimizationOptions) throws -> (String, [String]) {
        var args = ["-map", "0:v:0"]
        let codec: String, ext: String
        switch options.videoFormat {
        case .mp4: (codec, ext) = ("h264_videotoolbox", "mp4")
        case .hevc: (codec, ext) = ("hevc_videotoolbox", "mp4")
        case .x265: (codec, ext) = ("libx265", "mp4")
        case .webm: (codec, ext) = ("libvpx-vp9", "webm")
        case .av1: (codec, ext) = ("libsvtav1", "mkv")
        case .gif: (codec, ext) = ("gif", "gif")
        }
        args += ["-c:v", codec, "-pix_fmt", ext == "gif" ? "rgb8" : "yuv420p"]
        let rate = try targetRate(probe, options, audio: false)
        if codec.hasSuffix("videotoolbox") || options.maximumBytes != nil {
            args += ["-b:v", String(rate)]
        } else if ext != "gif" {
            args += ["-crf", options.aggressive ? "35" : "28"]
            if codec == "libvpx-vp9" { args += ["-b:v", "0", "-cpu-used", "4"] }
        }
        if codec == "libx265" { args += ["-preset", "fast", "-x265-params", "pools=4:frame-threads=2:log-level=error"] }
        if codec == "libsvtav1" { args += ["-preset", "9"] }
        if codec == "libx265" || codec == "hevc_videotoolbox" { args += ["-tag:v", "hvc1"] }
        var filters: [String] = []
        if let aspect = options.crop.aspect {
            filters.append("crop=w='min(iw,ih*\(aspect))':h='min(ih,iw/\(aspect))'")
        }
        filters.append("scale=w='max(2,trunc(iw*\(options.scale)/2)*2)':h='max(2,trunc(ih*\(options.scale)/2)*2)'")
        if options.playbackSpeed != 1 { filters.append("setpts=PTS/\(options.playbackSpeed)") }
        if ext == "gif" {
            let frames = ceil(probe.seconds / options.playbackSpeed * 12)
            let pixels = Double((probe.video?.width ?? 0) * (probe.video?.height ?? 0)) * options.scale * options.scale
            guard frames <= 480, frames * pixels <= 160_000_000 else { throw MediaExportError.limits }
            filters.append("fps=12")
        }
        args += ["-vf", filters.joined(separator: ",")]
        if probe.sound != nil, !options.muteVideo, ext != "gif" {
            args += ["-map", "0:a:0", "-c:a", ext == "mp4" ? "aac" : "libopus", "-b:a", "64k"]
            if options.playbackSpeed != 1 { args += ["-af", "atempo=\(options.playbackSpeed)"] }
        } else { args.append("-an") }
        return (ext, args)
    }
    private static func targetRate(_ probe: Probe, _ options: OptimizationOptions, audio: Bool) throws -> Int {
        let normal = audio ? options.audioBitrate * 1000 : (options.aggressive ? 1_200_000 : 2_800_000)
        guard let limit = options.maximumBytes else { return normal }
        let available = Double(limit) * 7.5 / (probe.seconds / (audio ? 1 : options.playbackSpeed))
        let rate = Int(min(available, Double(normal + 64_000))) - (!audio && probe.sound != nil && !options.muteVideo ? 64_000 : 0)
        guard rate >= (audio ? 12_000 : 40_000) else { throw OptimizationError.overBudget }
        return min(normal, rate)
    }
    private static func audioArguments(_ probe: Probe, options: OptimizationOptions) throws -> (String, [String]) {
        let codec: String
        switch options.audioFormat {
        case .automatic, .aac: codec = "aac"
        case .ogg: codec = "libopus"
        case .mp3: codec = "libmp3lame"
        case .wav: codec = "pcm_s24le"
        case .aiff: codec = "pcm_s24be"
        case .flac: codec = "flac"
        }
        var args = ["-map", "0:a:0", "-vn", "-c:a", codec]
        if [.aac, .automatic, .mp3, .ogg].contains(options.audioFormat) {
            args += ["-b:a", String(try targetRate(probe, options, audio: true))]
        }
        return (options.audioFormat.ext, args)
    }

    private static func inspect(_ url: URL, tools: URL, folder: URL) async throws -> Probe {
        let json = folder.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: json) }
        let entries = "stream=codec_name,codec_type,width,height,channels,sample_rate,avg_frame_rate,r_frame_rate,color_transfer:format=duration"
        try await run(tools.appendingPathComponent("ffprobe"), args: ["-v", "error", "-show_entries", entries, "-of", "json"] + input(url), output: json)
        return try JSONDecoder().decode(Probe.self, from: LocalFileCapture.read(json, limit: 65_536))
    }

    static func run(_ executable: URL, args: [String], output: URL?, diagnostics: URL? = nil) async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw Failure.unavailable }
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        process.environment = ["LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        let diagnosticHandle: FileHandle?
        if let diagnostics {
            guard FileManager.default.createFile(atPath: diagnostics.path, contents: nil) else { throw Failure.failed }
            diagnosticHandle = try FileHandle(forWritingTo: diagnostics)
        } else { diagnosticHandle = nil }
        defer { try? diagnosticHandle?.close() }
        process.standardError = diagnosticHandle ?? FileHandle.nullDevice
        var handle: FileHandle?
        if let output {
            guard FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw Failure.failed }
            handle = try FileHandle(forWritingTo: output)
        }
        defer { try? handle?.close() }
        process.standardOutput = handle ?? FileHandle.nullDevice
        let done = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { child in done.continuation.yield(child.terminationStatus); done.continuation.finish() }
        try Task.checkCancellation()
        try process.run()
        await withTaskCancellationHandler {
            for await _ in done.stream { break }
        } onCancel: { if process.isRunning { process.terminate() } }
        // A cancelled AsyncStream iterator can finish before the child. Keep its workspace alive until exit.
        if process.isRunning { if Task.isCancelled { process.terminate() }; process.waitUntilExit() }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw Failure.failed }
    }
}
