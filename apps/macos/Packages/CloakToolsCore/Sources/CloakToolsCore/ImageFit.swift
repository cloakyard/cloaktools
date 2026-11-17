import Foundation
import CoreGraphics
import ImageIO

public struct ImageFitOptions: Codable, Equatable, Sendable {
    public var format: ImageOutputFormat
    public var maximumBytes: Int
    public var maximumWidth: Int
    public var maximumHeight: Int
    public var minimumQuality: Double
    public var background: ImageBackground
    public var allowSmallerDimensions: Bool
    public init(format: ImageOutputFormat = .jpeg, maximumBytes: Int = 500_000, maximumWidth: Int = 1600,
                maximumHeight: Int = 1600, minimumQuality: Double = 0.6, background: ImageBackground = .white,
                allowSmallerDimensions: Bool = true) {
        self.format = format; self.maximumBytes = maximumBytes; self.maximumWidth = maximumWidth; self.maximumHeight = maximumHeight
        self.minimumQuality = minimumQuality; self.background = background; self.allowSmallerDimensions = allowSmallerDimensions
    }
    public func validate() throws {
        guard (1_000...100_000_000).contains(maximumBytes), (1...20_000).contains(maximumWidth), (1...20_000).contains(maximumHeight),
              minimumQuality.isFinite, (0.1...1).contains(minimumQuality) else { throw ImageFitError.invalidOptions }
    }
}

public enum ImageFitError: LocalizedError, Sendable {
    case invalidOptions, limitNotMet
    public var errorDescription: String? {
        switch self {
        case .invalidOptions: "Use 1–100,000 KB, dimensions from 1–20,000 px, and minimum quality from 10–100%."
        case .limitNotMet: "This preview exceeds the size limit. Increase the limit or choose another format before saving."
        }
    }
}

/// Exact encoded output, captured before Save. No public initializer allows unverified bytes.
public struct FittedImage: Sendable {
    public let sourceURL: URL
    public let options: ImageFitOptions
    public let width: Int
    public let height: Int
    public let quality: Double?
    public let thumbnailPNG: Data
    public let encodingAttempts: Int
    let bytes: Data
    public var byteCount: Int { bytes.count }
    public var fits: Bool { byteCount <= options.maximumBytes }
    public var filename: String { outputStem + "." + options.format.fileExtension }
    /// Exact measured output for automation. A failed fit never becomes a file result.
    public func exportData() throws -> Data {
        try Task.checkCancellation()
        guard fits else { throw ImageFitError.limitNotMet }
        return bytes
    }
    var outputStem: String {
        let original = sourceURL.deletingPathExtension().lastPathComponent
        let stem = (try? SafeOutput.validate(stem: original)) != nil && original.utf8.count <= 116 ? original : "Image"
        return stem + " fit"
    }
}

public enum ImageFit {
    public static let minimumLongEdge = 320
    public static let maximumEncodingAttempts = 21
    private struct Candidate {
        let bytes: Data
        let width: Int
        let height: Int
        let quality: Double?
    }

    /// Bounded native encoding search. Preserves aspect ratio (rounded to pixels), never enlarges.
    /// Every size is rendered from the original capture, not from an earlier lossy candidate.
    public static func preview(_ prepared: PreparedImage, options: ImageFitOptions) throws -> FittedImage {
        try options.validate(); try Task.checkCancellation()
        guard options.format.isAvailable else { throw ImageConversionError.unavailableEncoder(options.format) }
        let scale = min(1, Double(options.maximumWidth) / Double(prepared.width), Double(options.maximumHeight) / Double(prepared.height))
        let initialWidth = max(1, Int((Double(prepared.width) * scale).rounded(.down)))
        let initialHeight = max(1, Int((Double(prepared.height) * scale).rounded(.down)))
        let initialEdge = max(initialWidth, initialHeight)
        let smallestEdge = min(minimumLongEdge, initialEdge)
        var edge = initialEdge
        var attempts = 0
        var closest: Candidate?
        func encode(_ image: CGImage, quality: Double) throws -> Candidate {
            try Task.checkCancellation()
            let bytes = try ImageConversion.encode(image, options: .init(format: options.format, quality: quality, background: options.background))
            attempts += 1
            try Task.checkCancellation()
            let result = Candidate(bytes: bytes, width: image.width, height: image.height, quality: options.format.isLossy ? quality : nil)
            if closest == nil || bytes.count < closest!.bytes.count { closest = result }
            return result
        }
        func finish(_ candidate: Candidate) throws -> FittedImage {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(candidate.bytes as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 384
                  ] as CFDictionary) else { throw ToolError.encodingFailed }
            let preview = try ImageConversion.encode(thumbnail, options: .init())
            try Task.checkCancellation()
            return FittedImage(sourceURL: prepared.sourceURL, options: options, width: candidate.width, height: candidate.height,
                               quality: candidate.quality, thumbnailPNG: preview, encodingAttempts: attempts, bytes: candidate.bytes)
        }
        for step in 0..<8 {
            try Task.checkCancellation()
            let ratio = Double(edge) / Double(initialEdge)
            let width = max(1, Int((Double(initialWidth) * ratio).rounded(.down)))
            let height = max(1, Int((Double(initialHeight) * ratio).rounded(.down)))
            let image = try ImageConversion.render(prepared.image, width: width, height: height,
                                                    background: options.format.isLossy ? options.background : nil)
            let high = try encode(image, quality: 1)
            if high.bytes.count <= options.maximumBytes { return try finish(high) }
            var smallest = high
            if options.format.isLossy && options.minimumQuality < 1 {
                let low = try encode(image, quality: options.minimumQuality)
                if low.bytes.count < smallest.bytes.count { smallest = low }
                if low.bytes.count <= options.maximumBytes {
                    var best = low, lower = options.minimumQuality, upper = 1.0
                    // Only measured passing candidates are accepted; size need not be monotonic.
                    for _ in 0..<5 {
                        let quality = (lower + upper) / 2
                        let candidate = try encode(image, quality: quality)
                        if candidate.bytes.count <= options.maximumBytes { best = candidate; lower = quality }
                        else { upper = quality }
                    }
                    return try finish(best)
                }
            }
            guard options.allowSmallerDimensions, edge > smallestEdge else { break }
            let factor = min(0.85, max(0.25, sqrt(Double(options.maximumBytes) / Double(smallest.bytes.count)) * 0.9))
            edge = step == 6 ? smallestEdge : max(smallestEdge, min(edge - 1, Int(Double(edge) * factor)))
        }
        // A failed fit is still reviewable, but cannot be published through this API.
        guard let closest else { throw ToolError.encodingFailed }
        return try finish(closest)
    }

    public static func save(_ result: FittedImage, in folder: URL? = nil) throws -> URL {
        try Task.checkCancellation()
        guard result.fits else { throw ImageFitError.limitNotMet }
        return try SafeOutput.publish(result.bytes, in: folder ?? result.sourceURL.deletingLastPathComponent(),
                                      stem: result.outputStem, extension: result.options.format.fileExtension)
    }
}
