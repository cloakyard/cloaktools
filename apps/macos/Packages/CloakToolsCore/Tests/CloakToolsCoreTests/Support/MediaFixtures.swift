import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import CoreText

// Synthetic media only. Shared by core tests and the local UI-verification fixture script.
enum MediaFixtures {
    enum Failure: Error { case writing }
    static func audio(_ url: URL, seconds: Int = 2) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.writing }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for i in 0..<48_000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 48_000) * 0.15) }
        for _ in 0..<seconds { try file.write(from: buffer) }
    }
    static func movie(_ url: URL, width: Int = 320, height: Int = 180, seconds: Int = 2,
                      codec: AVVideoCodecType = .h264, rotated: Bool = false) async throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw Failure.writing }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height])
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0) }
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
        try writer.start(); writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 30) {
            var raw: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &raw) == kCVReturnSuccess,
                let buffer = raw else { throw Failure.writing }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
            context.setFillColor(CGColor(red: 0.035, green: 0.08, blue: 0.16, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(CGColor(red: 0.07, green: 0.36, blue: 0.92, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height / 3))
            let x = CGFloat(frame % 120) / 120 * CGFloat(width) * 0.55 + CGFloat(width) * 0.1
            context.setFillColor(CGColor(red: 1, green: 0.68, blue: 0.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: x, y: CGFloat(height) * 0.2, width: CGFloat(height) * 0.42, height: CGFloat(height) * 0.42))
            context.textPosition = CGPoint(x: CGFloat(width) * 0.07, y: CGFloat(height) * 0.79)
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(height) * 0.085, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1)]
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "CloakTools · Motion study", attributes: attributes)), context)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try await receiver.append(CVReadOnlyPixelBuffer(unsafeBuffer: buffer), with: CMTime(value: Int64(frame), timescale: 30))
        }
        receiver.finish(); writer.endSession(atSourceTime: CMTime(value: Int64(seconds), timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.writing }
    }
    static func combine(video: URL, audio: URL, output: URL, extraAudio: Bool = false) async throws {
        let composition = AVMutableComposition()
        let va = AVURLAsset(url: video), aa = AVURLAsset(url: audio)
        let vt = try await va.loadTracks(withMediaType: .video)[0]
        let at = try await aa.loadTracks(withMediaType: .audio)[0]
        let vr = try await vt.load(.timeRange), ar = try await at.load(.timeRange)
        let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try v.insertTimeRange(vr, of: vt, at: .zero); v.preferredTransform = try await vt.load(.preferredTransform)
        for _ in 0..<(extraAudio ? 2 : 1) {
            try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(ar, of: at, at: .zero)
        }
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        let title = AVMutableMetadataItem(); title.identifier = .commonIdentifierTitle; title.value = "Synthetic source title" as NSString
        export.metadata = [title]
        try await export.export(to: output, as: .mov)
    }
}
