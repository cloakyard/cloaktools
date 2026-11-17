import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

public enum QRReadError: LocalizedError, Equatable {
    case tooLarge, unsupportedImage, multipleFrames, tooManyCodes, textTooLarge, noText, scanUnavailable
    public var errorDescription: String? {
        switch self {
        case .tooLarge: "Choose an image up to 10 MiB and 40 megapixels."
        case .unsupportedImage: "Choose a valid PNG, JPEG, GIF, WebP, TIFF or HEIC image. PDF and SVG are not supported."
        case .multipleFrames: "Choose a single still image. Export a frame from this animation or multi-page image first."
        case .tooManyCodes: "This image contains more than 16 QR codes. Crop it to a smaller group and try again."
        case .textTooLarge: "The decoded text exceeds 32 KiB. Choose another code."
        case .noText: "This QR code has no text this reader can decode."
        case .scanUnavailable: "macOS could not read this image. Try a clear PNG or JPEG copy."
        }
    }
}
public struct ReadQRCode: Identifiable, Sendable {
    public let id: Int
    public let text: String?
    /// Normalized image coordinates, with origin at bottom left.
    public let bounds: CGRect
}
public struct PreparedQRReading: Sendable {
    public let thumbnailPNG: Data
    public let width: Int
    public let height: Int
    public let scanWidth: Int
    public let scanHeight: Int
    public let codes: [ReadQRCode]
    public var wasReduced: Bool { width != scanWidth || height != scanHeight }
}

public enum QRCodeReading {
    public static let maximumImageBytes = 10 * 1_048_576
    public static let maximumTextBytes = 32 * 1024
    public static let inputTypes: [UTType] = [.png, .jpeg, .gif, .webP, .tiff, .heic, .heif]
    public static func read(_ url: URL) throws -> PreparedQRReading {
        do { return try prepare(LocalFileCapture.read(url, limit: maximumImageBytes)) }
        catch LocalFileCapture.CaptureError.tooLarge { throw QRReadError.tooLarge }
    }
    public static func prepare(_ bytes: Data) throws -> PreparedQRReading {
        try Task.checkCancellation()
        guard bytes.count <= maximumImageBytes else { throw QRReadError.tooLarge }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let type = CGImageSourceGetType(source) as String?, inputTypes.contains(where: { $0.identifier == type }),
              CGImageSourceGetCount(source) > 0 else { throw QRReadError.unsupportedImage }
        guard CGImageSourceGetCount(source) == 1 else { throw QRReadError.multipleFrames }
        guard let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = info[kCGImagePropertyPixelWidth] as? Int, let height = info[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw QRReadError.unsupportedImage }
        guard width <= 40_000_000 / height else { throw QRReadError.tooLarge }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(4096, max(width, height)), kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary), CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw QRReadError.unsupportedImage }
        try Task.checkCancellation()
        var candidates: [(text: String?, bounds: CGRect)] = []
        let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
        var visionSucceeded = false
        do {
            try VNImageRequestHandler(cgImage: image).perform([request]); visionSucceeded = true
            candidates = (request.results ?? []).map { ($0.payloadStringValue, $0.boundingBox) }
        } catch { /* The second native detector can recover dense codes and Vision failures. */ }
        try Task.checkCancellation()
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(options: [.useSoftwareRenderer: true]), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        guard visionSucceeded || detector != nil else { throw QRReadError.scanUnavailable }
        if let detector {
            for feature in detector.features(in: CIImage(cgImage: image)).compactMap({ $0 as? CIQRCodeFeature }) {
                try Task.checkCancellation()
                let bounds = CGRect(x: feature.bounds.minX / CGFloat(image.width), y: feature.bounds.minY / CGFloat(image.height),
                                    width: feature.bounds.width / CGFloat(image.width), height: feature.bounds.height / CGFloat(image.height))
                if let index = candidates.firstIndex(where: { overlap($0.bounds, bounds) > 0.5 }) {
                    if candidates[index].text == nil { candidates[index].text = feature.messageString }
                } else { candidates.append((feature.messageString, bounds)) }
            }
        }
        let codes = try reviewed(candidates)
        let factor = min(1, 768.0 / Double(max(image.width, image.height)))
        let thumbnail = try ImageConversion.render(image, width: max(1, Int(Double(image.width) * factor)), height: max(1, Int(Double(image.height) * factor)))
        let png = try ImageConversion.encode(thumbnail, options: .init())
        try Task.checkCancellation()
        let rotated = (5...8).contains(info[kCGImagePropertyOrientation] as? Int ?? 1)
        return .init(thumbnailPNG: png, width: rotated ? height : width, height: rotated ? width : height,
                     scanWidth: image.width, scanHeight: image.height, codes: codes)
    }
    static func reviewed(_ candidates: [(text: String?, bounds: CGRect)]) throws -> [ReadQRCode] {
        guard candidates.count <= 16 else { throw QRReadError.tooManyCodes }
        guard candidates.allSatisfy({ ($0.text?.utf8.count ?? 0) <= maximumTextBytes }) else { throw QRReadError.textTooLarge }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let valid = candidates.compactMap { candidate -> (text: String?, bounds: CGRect)? in
            let b = candidate.bounds
            guard b.minX.isFinite, b.minY.isFinite, b.width.isFinite, b.height.isFinite, b.width > 0, b.height > 0 else { return nil }
            let bounded = b.intersection(unit); guard !bounded.isNull, !bounded.isEmpty else { return nil }
            return (candidate.text, bounded)
        }.sorted {
            let lhs = Int(((1 - $0.bounds.midY) * 20).rounded()), rhs = Int(((1 - $1.bounds.midY) * 20).rounded())
            return lhs == rhs ? $0.bounds.minX < $1.bounds.minX : lhs < rhs
        }
        return valid.enumerated().map { .init(id: $0.offset, text: $0.element.text, bounds: $0.element.bounds) }
    }
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let common = intersection.width * intersection.height, union = a.width * a.height + b.width * b.height - common
        return union > 0 ? common / union : 0
    }
    public static func save(_ code: ReadQRCode, in folder: URL, stem: String) throws -> URL {
        try Task.checkCancellation()
        guard let text = code.text else { throw QRReadError.noText }
        guard text.utf8.count <= maximumTextBytes else { throw QRReadError.textTooLarge }
        return try SafeOutput.publish(Data(text.utf8), in: folder, stem: stem, extension: "txt")
    }
}
