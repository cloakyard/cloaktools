import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ClipboardError: LocalizedError, Sendable {
    case unsupported, multipleItems, changed, unavailable, accessDenied, textTooLarge, invalidText, unsupportedImage
    public var errorDescription: String? {
        switch self {
        case .unsupported: "Copy text or an image, then choose New File from Clipboard again. Copied files and rich-text-only content are not supported."
        case .multipleItems: "Copy one text selection or one image. Multiple clipboard items aren’t supported yet."
        case .changed: "The clipboard changed while it was being read. Try the action again."
        case .unavailable: "The clipboard contents couldn’t be read. Copy the text or image again, then retry."
        case .accessDenied: "Clipboard access is denied for CloakTools. Review its clipboard access in System Settings, then try again."
        case .textTooLarge: "Clipboard text can contain up to 1 MiB. Copy a smaller selection."
        case .invalidText: "Clipboard text contains null characters. Copy a plain-text selection instead."
        case .unsupportedImage: "Copy a single-frame PNG, JPEG or TIFF image. This clipboard image could not be read."
        }
    }
}

/// A one-time host capture. Neither this type nor the prepared document reads the system clipboard.
public enum ClipboardInput: Sendable {
    case text(String)
    case image(Data)
    public func validateSize() throws {
        switch self {
        case let .text(text):
            guard text.utf8.count <= 1_048_576 else { throw ClipboardError.textTooLarge }
            guard !text.contains("\0") else { throw ClipboardError.invalidText }
        case let .image(data):
            guard data.count <= 100_000_000 else { throw ToolError.imageTooLarge }
            guard !data.isEmpty else { throw ClipboardError.unsupportedImage }
        }
    }
}

public struct ClipboardDocument: Sendable {
    public enum Kind: Equatable, Sendable { case text, image }
    public let kind: Kind
    public let content: Data
    public let textPreview: String?
    public let thumbnailPNG: Data?
    public let width: Int?
    public let height: Int?
    public var fileExtension: String { kind == .text ? "txt" : "png" }
    public var suggestedName: String { kind == .text ? "Clipboard text" : "Clipboard image" }
    public let previewIsTruncated: Bool

    /// Run on a worker task. Decode limits are checked before image rasterization.
    public static func prepare(_ input: ClipboardInput) throws -> Self {
        try Task.checkCancellation()
        try input.validateSize()
        switch input {
        case let .text(text):
            return Self(kind: .text, content: Data(text.utf8), textPreview: String(text.prefix(4096)), thumbnailPNG: nil, width: nil, height: nil, previewIsTruncated: text.count > 4096)
        case let .image(data):
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let type = CGImageSourceGetType(source) as String?,
                  [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier].contains(type),
                  CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ClipboardError.unsupportedImage }
            guard width > 0, height > 0, width <= 40_000_000 / height else { throw ToolError.imageTooLarge }
            func decode(maximum: Int) throws -> CGImage {
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximum
                ] as CFDictionary) else { throw ClipboardError.unsupportedImage }
                return image
            }
            let image = try decode(maximum: max(width, height))
            try Task.checkCancellation()
            let png = try encodePNG(image)
            let thumbnail = try encodePNG(decode(maximum: 384))
            try Task.checkCancellation()
            return Self(kind: .image, content: png, textPreview: nil, thumbnailPNG: thumbnail, width: image.width, height: image.height, previewIsTruncated: false)
        }
    }
    private static func encodePNG(_ image: CGImage) throws -> Data {
        let bytes = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { throw ToolError.encodingFailed }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw ToolError.encodingFailed }
        return bytes as Data
    }
    public func write(in folder: URL, name: String) throws -> URL {
        try Task.checkCancellation()
        return try SafeOutput.publish(content, in: folder, stem: name, extension: fileExtension)
    }
}
