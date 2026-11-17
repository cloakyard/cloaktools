import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum Base64ImageError: LocalizedError, Equatable, Sendable {
    case tooLarge, textTooLarge, unsupportedImage, invalidDataURL, invalidBase64, mismatchedType, tooManyFrames
    public var errorDescription: String? {
        switch self {
        case .tooLarge: "Choose an image up to 10 MiB and 40 megapixels per frame."
        case .textTooLarge: "Paste up to 14 MiB of Base64 text, representing an image up to 10 MiB."
        case .unsupportedImage: "Use a valid PNG, JPEG, GIF, WebP, TIFF or HEIC image. SVG and other file types are not supported."
        case .invalidDataURL: "Use a Base64 image data URL such as data:image/png;base64,…, or paste the Base64 alone."
        case .invalidBase64: "Invalid image Base64. Check its characters and padding. Use the standard alphabet (+ and /)."
        case .mismatchedType: "The data URL's image type does not match its contents. Check the prefix, or paste just the Base64."
        case .tooManyFrames: "This image has more than 512 frames. Choose a shorter animation or a single image."
        }
    }
}

/// Exact captured file bytes, plus a small first-frame preview. No transcoding or metadata stripping.
public struct Base64ImageSnapshot: Sendable {
    public let bytes: Data
    public let thumbnailPNG: Data
    public let mimeType: String
    public let fileExtension: String
    public let format: String
    public let width: Int
    public let height: Int
    public let frameCount: Int
}

public enum Base64Image {
    public static let maximumImageBytes = 10 * 1_048_576
    public static let maximumTextBytes = 14 * 1_048_576
    public static let inputTypes: [UTType] = [.png, .jpeg, .gif, .webP, .tiff, .heic, .heif]

    public static func capture(_ url: URL) throws -> Base64ImageSnapshot {
        do { return try prepare(LocalFileCapture.read(url, limit: maximumImageBytes)) }
        catch LocalFileCapture.CaptureError.tooLarge { throw Base64ImageError.tooLarge }
    }

    public static func prepare(_ bytes: Data) throws -> Base64ImageSnapshot {
        try Task.checkCancellation()
        guard bytes.count <= maximumImageBytes else { throw Base64ImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let identifier = CGImageSourceGetType(source) as String?,
              let type = inputTypes.first(where: { $0.identifier == identifier }),
              let mime = type.preferredMIMEType, let ext = type.preferredFilenameExtension,
              CGImageSourceGetCount(source) > 0 else { throw Base64ImageError.unsupportedImage }
        let count = CGImageSourceGetCount(source)
        guard count <= 512 else { throw Base64ImageError.tooManyFrames }
        for frame in 0..<count {
            try Task.checkCancellation()
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 40_000_000 / height else { throw Base64ImageError.tooLarge }
        }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 384,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw Base64ImageError.unsupportedImage }
        let png = try ImageConversion.encode(ImageConversion.render(thumbnail, width: thumbnail.width, height: thumbnail.height), options: .init())
        try Task.checkCancellation()
        let rotated = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
        let format = type == .jpeg ? "JPEG" : type == .webP ? "WebP" : ext.uppercased()
        return .init(bytes: bytes, thumbnailPNG: png, mimeType: mime, fileExtension: ext, format: format, width: rotated ? height : width, height: rotated ? width : height, frameCount: count)
    }

    public static func encode(_ image: Base64ImageSnapshot, includeDataURL: Bool = true) throws -> String {
        try Task.checkCancellation()
        let payload = DeveloperText.encodeBase64Bytes(image.bytes, alphabet: .standard)
        return includeDataURL ? "data:\(image.mimeType);base64,\(payload)" : payload
    }

    public static func decode(_ input: String) throws -> Base64ImageSnapshot {
        try Task.checkCancellation()
        guard input.utf8.count <= maximumTextBytes else { throw Base64ImageError.textTooLarge }
        var payload = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var declaredType: String?
        if payload.prefix(5).lowercased() == "data:" {
            guard let comma = payload.firstIndex(of: ",") else { throw Base64ImageError.invalidDataURL }
            let header = payload[..<comma].lowercased()
            guard header.utf8.count < 128, header.hasSuffix(";base64") else { throw Base64ImageError.invalidDataURL }
            let mime = String(header.dropFirst(5).dropLast(7))
            guard inputTypes.contains(where: { $0.preferredMIMEType == mime }) || mime == "image/jpg" else { throw Base64ImageError.invalidDataURL }
            declaredType = mime == "image/jpg" ? "image/jpeg" : mime
            payload = String(payload[payload.index(after: comma)...])
        }
        let bytes: Data
        do { bytes = try DeveloperText.decodeBase64Bytes(payload, alphabet: .standard) }
        catch DeveloperTextError.invalidBase64 { throw Base64ImageError.invalidBase64 }
        let image = try prepare(bytes)
        guard declaredType == nil || declaredType == image.mimeType else { throw Base64ImageError.mismatchedType }
        return image
    }

    public static func save(_ image: Base64ImageSnapshot, in folder: URL, stem: String) throws -> URL {
        try Task.checkCancellation()
        return try SafeOutput.publish(image.bytes, in: folder, stem: stem, extension: image.fileExtension)
    }
}
