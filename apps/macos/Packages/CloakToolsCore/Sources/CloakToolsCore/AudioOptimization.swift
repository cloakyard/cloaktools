import AVFoundation
import Foundation

public enum OptimizedAudioFormat: String, CaseIterable, Codable, Sendable {
    case automatic = "Automatic", aac = "AAC", flac = "FLAC", wav = "WAV", aiff = "AIFF"
    var ext: String {
        switch self {
        case .automatic, .aac: "m4a"
        default: rawValue.lowercased()
        }
    }
}

enum AudioOptimization {
    static func encode(_ url: URL, in folder: URL, options: OptimizationOptions) throws -> (URL, Int) {
        let capture = try MediaCapture(url, acceptedExtensions: MediaOptimization.audioExtensions)
        let input = try AVAudioFile(forReading: capture.url)
        let format = input.processingFormat
        let seconds = Double(input.length) / format.sampleRate
        guard input.length > 0, seconds.isFinite, seconds > 0, seconds <= 1800, (1...2).contains(format.channelCount),
              format.sampleRate > 0, format.sampleRate <= 96000 else { throw MediaExportError.limits }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else { throw OptimizationError.exportFailed }
        var gain: Float = 1
        if options.normalizeAudio {
            var peak: Float = 0
            try chunks(input, buffer: buffer) {
                guard let samples = buffer.floatChannelData else { throw MediaExportError.unsupported }
                for channel in 0..<Int(format.channelCount) {
                    for value in UnsafeBufferPointer(start: samples[channel], count: Int(buffer.frameLength)) {
                        peak = max(peak, abs(value))
                    }
                }
            }
            gain = peak > 0 ? 0.89125 / peak : 1
            input.framePosition = 0
        }
        let output = folder.appendingPathComponent("result." + options.audioFormat.ext)
        var settings: [String: Any] = [AVNumberOfChannelsKey: format.channelCount, AVSampleRateKey: format.sampleRate]
        switch options.audioFormat {
        case .automatic, .aac:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            let sourceRate = Double(capture.byteCount) * 8 / seconds
            var bitrate = min(Double(options.audioBitrate) * 1000, sourceRate)
            if options.aggressive { bitrate *= 0.75 }
            if let limit = options.maximumBytes { bitrate = min(bitrate, Double(max(0, limit - 4096)) * 7.6 / seconds) }
            guard bitrate >= 16_000 || options.maximumBytes == nil else { throw OptimizationError.overBudget }
            settings[AVEncoderBitRateKey] = max(16_000, Int(bitrate))
        case .flac:
            settings[AVFormatIDKey] = kAudioFormatFLAC
            settings[AVEncoderBitDepthHintKey] = 24
        case .wav, .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 24
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = options.audioFormat == .aiff
            settings[AVLinearPCMIsNonInterleaved] = false
        }
        do {
            let writer = try AVAudioFile(forWriting: output, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            try chunks(input, buffer: buffer) {
                if gain != 1, let channels = buffer.floatChannelData {
                    for channel in 0..<Int(format.channelCount) {
                        for frame in 0..<Int(buffer.frameLength) { channels[channel][frame] *= gain }
                    }
                }
                try writer.write(from: buffer)
            }
            writer.close()
        }
        let check = try AVAudioFile(forReading: output)
        let duration = Double(check.length) / check.processingFormat.sampleRate
        guard duration.isFinite, abs(duration - seconds) <= 0.12,
              check.processingFormat.channelCount == format.channelCount else { throw OptimizationError.exportFailed }
        return (output, capture.byteCount)
    }

    private static func chunks(_ file: AVAudioFile, buffer: AVAudioPCMBuffer, process: () throws -> Void) throws {
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(Int64(buffer.frameCapacity), file.length - file.framePosition)))
            guard buffer.frameLength > 0 else { throw OptimizationError.exportFailed }
            try process()
        }
    }
}
