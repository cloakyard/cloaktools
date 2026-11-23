import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum OptimizedVideoFormat: String, CaseIterable, Codable, Sendable { case mp4 = "MP4", hevc = "HEVC", x265 = "HEVC (software)", webm = "WebM (VP9)", av1 = "MKV (AV1)", gif = "Animated GIF" }

enum AnimatedOptimization {
    enum Failure: LocalizedError {
        case limits, stillFormat
        var errorDescription: String? {
            switch self {
            case .limits: "Animation export supports up to 480 frames and 160 megapixels across the output. Shorten the clip or reduce its scale."
            case .stillFormat: "Choose Automatic or WebP to keep every animation frame."
            }
        }
    }

    static func image(_ source: CGImageSource, options: OptimizationOptions, in folder: URL) throws -> URL {
        let count = CGImageSourceGetCount(source)
        guard count > 0, count <= 480 else { throw Failure.limits }
        let isGIF = CGImageSourceGetType(source) as String? == UTType.gif.identifier
        let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let settings = props?[isGIF ? kCGImagePropertyGIFDictionary : kCGImagePropertyWebPDictionary] as? [CFString: Any]
        let loop = settings?[isGIF ? kCGImagePropertyGIFLoopCount : kCGImagePropertyWebPLoopCount] as? Int
        let useWebP = options.imageFormat == .webp || (options.imageFormat == .automatic && !isGIF)
        let webp = useWebP ? try AnimatedWebPWriter(loopCount: loop ?? 1) : nil
        let gif = useWebP ? nil : try destination(folder, count: count)
        if let loop, let gif { setLoop(loop, gif.1) }
        var pixelCount = 0
        for index in 0..<count {
            try Task.checkCancellation()
            try autoreleasepool {
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                guard let w = properties?[kCGImagePropertyPixelWidth] as? Int, let h = properties?[kCGImagePropertyPixelHeight] as? Int,
                      w > 0, h > 0, w <= 40_000_000 / h else { throw Failure.limits }
                let timing = properties?[isGIF ? kCGImagePropertyGIFDictionary : kCGImagePropertyWebPDictionary] as? [CFString: Any]
                let delay = timing?[isGIF ? kCGImagePropertyGIFUnclampedDelayTime : kCGImagePropertyWebPUnclampedDelayTime] as? Double
                    ?? timing?[isGIF ? kCGImagePropertyGIFDelayTime : kCGImagePropertyWebPDelayTime] as? Double ?? 0.1
                guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { throw OptimizationError.exportFailed }
                let output = try render(frame, options: options, pixels: &pixelCount)
                if let webp { try webp.append(output, delay: delay, options: options) }
                if let gif { append(output, to: gif.1, delay: delay) }
            }
        }
        if let gif { return try finish(gif.1, at: gif.0, count: count) }
        let out = folder.appendingPathComponent("result.webp")
        try webp?.write(to: out)
        guard let check = CGImageSourceCreateWithURL(out as CFURL, nil), CGImageSourceGetCount(check) == count else { throw OptimizationError.exportFailed }
        return out
    }

    static func movie(_ media: PreparedMedia, options: OptimizationOptions, in folder: URL) async throws -> URL {
        let rate = min(12, Double(media.frameRate))
        let duration = media.duration / options.playbackSpeed
        let count = Int(ceil(duration * rate))
        guard (1...480).contains(count) else { throw Failure.limits }
        let generator = AVAssetImageGenerator(asset: MediaExport.localAsset(media.playbackURL))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1 / rate, preferredTimescale: 600)
        let (url, writer) = try destination(folder, count: count)
        setLoop(0, writer)
        var pixelCount = 0
        for index in 0..<count {
            try Task.checkCancellation()
            let time = CMTime(seconds: Double(index) * media.duration / Double(count), preferredTimescale: 60000)
            let frame = try await generator.image(at: time).image
            let output = try render(frame, options: options, pixels: &pixelCount)
            append(output, to: writer, delay: duration / Double(count))
        }
        return try finish(writer, at: url, count: count)
    }

    private static func destination(_ folder: URL, count: Int) throws -> (URL, CGImageDestination) {
        let url = folder.appendingPathComponent("result.gif")
        guard let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw OptimizationError.exportFailed }
        return (url, writer)
    }
    private static func setLoop(_ count: Int, _ writer: CGImageDestination) {
        CGImageDestinationSetProperties(writer, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: count]] as CFDictionary)
    }
    private static func render(_ frame: CGImage, options: OptimizationOptions, pixels: inout Int) throws -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        guard let crop = frame.cropping(to: options.crop.centered(in: rect).integral.intersection(rect)) else { throw OptimizationError.exportFailed }
        let width = max(1, Int(Double(crop.width) * options.scale)), height = max(1, Int(Double(crop.height) * options.scale))
        pixels += width * height
        guard pixels <= 160_000_000 else { throw Failure.limits }
        return try ImageConversion.render(crop, width: width, height: height)
    }
    private static func append(_ output: CGImage, to writer: CGImageDestination, delay: Double) {
        CGImageDestinationAddImage(writer, output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: max(0.01, delay)]] as CFDictionary)
    }
    private static func finish(_ writer: CGImageDestination, at url: URL, count: Int) throws -> URL {
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(writer), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) == count else { throw OptimizationError.exportFailed }
        return url
    }
}
