import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageOutputFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case png, jpeg, heic
    public var id: String { rawValue }
    public var title: String { switch self { case .png: "PNG"; case .jpeg: "JPEG"; case .heic: "HEIC" } }
    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    public var isLossy: Bool { self != .png }
    public var type: UTType { switch self { case .png: .png; case .jpeg: .jpeg; case .heic: .heic } }
    public var isAvailable: Bool { Self.encoderTypes.contains(type.identifier) }
    private static let encoderTypes = Set(CGImageDestinationCopyTypeIdentifiers() as! [String])
}

public enum ImageBackground: String, CaseIterable, Codable, Sendable, Identifiable {
    case white, black
    public var id: String { rawValue }
    public var title: String { self == .white ? "White" : "Black" }
    fileprivate var color: CGColor { CGColor(gray: self == .white ? 1 : 0, alpha: 1) }
}

public struct ImageConversionOptions: Codable, Equatable, Sendable {
    public var format: ImageOutputFormat = .png
    public var quality: Double = 0.9
    public var background: ImageBackground = .white
    public init(format: ImageOutputFormat = .png, quality: Double = 0.9, background: ImageBackground = .white) {
        self.format = format; self.quality = quality; self.background = background
    }
    public func validate() throws {
        guard quality.isFinite, (0.1...1).contains(quality) else { throw ImageConversionError.invalidOptions }
    }
}

public enum ImageConversionError: LocalizedError, Sendable {
    case invalidOptions, unavailableEncoder(ImageOutputFormat)
    public var errorDescription: String? {
        switch self {
        case .invalidOptions: "Choose an image quality between 10% and 100%."
        case let .unavailableEncoder(format): "\(format.title) encoding is unavailable on this Mac. Choose another output format."
        }
    }
}

/// Immutable, orientation-applied 8-bit sRGB pixels. The preview and output use this same capture.
public struct PreparedImage: Sendable {
    public let sourceURL: URL
    public let sourceFormat: String
    public let sourceByteCount: Int
    public let thumbnailPNG: Data
    let image: CGImage
    public var width: Int { image.width }
    public var height: Int { image.height }
    public func outputFilename(for format: ImageOutputFormat) -> String { outputStem + "." + format.fileExtension }
    fileprivate var outputStem: String {
        let original = sourceURL.deletingPathExtension().lastPathComponent
        let stem = (try? SafeOutput.validate(stem: original)) != nil && original.utf8.count <= 108 ? original : "Image"
        return stem + " converted"
    }
}

public enum ImageConversion {
    public static let inputTypes: [UTType] = [.png, .jpeg, .tiff, .heic, .heif]
    public static let inputExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "heic", "heif"]

    /// Run on a worker. Source bytes are bounded before decoding; no file is written here.
    public static func prepare(_ input: URL) throws -> PreparedImage {
        do { return try prepare(bytes: LocalFileCapture.read(input, limit: 100_000_000), sourceURL: input) }
        catch LocalFileCapture.CaptureError.tooLarge { throw ToolError.imageTooLarge }
    }

    static func prepare(bytes: Data, sourceURL input: URL) throws -> PreparedImage {
        try Task.checkCancellation()
        guard bytes.count <= 100_000_000 else { throw ToolError.imageTooLarge }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source) as String?,
              inputTypes.contains(where: { $0.identifier == identifier }), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ToolError.unsupportedImage }
        guard width > 0, height > 0, width <= 40_000_000 / height else { throw ToolError.imageTooLarge }
        guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ] as CFDictionary) else { throw ToolError.unsupportedImage }
        try Task.checkCancellation()
        let image = try render(oriented, width: oriented.width, height: oriented.height)
        let scale = min(1, 384.0 / Double(max(image.width, image.height)))
        let thumbnail = try render(image, width: max(1, Int(Double(image.width) * scale)), height: max(1, Int(Double(image.height) * scale)))
        let preview = try encode(thumbnail, options: .init())
        try Task.checkCancellation()
        let format = identifier == UTType.jpeg.identifier ? "JPEG" : identifier == UTType.png.identifier ? "PNG" : identifier == UTType.tiff.identifier ? "TIFF" : "HEIC"
        return PreparedImage(sourceURL: input, sourceFormat: format, sourceByteCount: bytes.count, thumbnailPNG: preview, image: image)
    }

    /// Publish from already captured pixels; never reread the source after confirmation.
    public static func copy(_ prepared: PreparedImage, options: ImageConversionOptions, in folder: URL? = nil) throws -> URL {
        try options.validate()
        try Task.checkCancellation()
        guard options.format.isAvailable else { throw ImageConversionError.unavailableEncoder(options.format) }
        let image = options.format.isLossy ? try render(prepared.image, width: prepared.width, height: prepared.height, background: options.background) : prepared.image
        let bytes = try encode(image, options: options)
        try Task.checkCancellation()
        return try SafeOutput.publish(bytes, in: folder ?? prepared.sourceURL.deletingLastPathComponent(), stem: prepared.outputStem, extension: options.format.fileExtension)
    }
    public static func copy(of input: URL, options: ImageConversionOptions) throws -> URL {
        try options.validate()
        return try copy(prepare(input), options: options)
    }
    /// Retained convenience for callers requiring PNG explicitly.
    public static func pngCopy(of input: URL) throws -> URL { try copy(of: input, options: .init()) }

    static func render(_ image: CGImage, width: Int, height: Int, background: ImageBackground? = nil) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: (background == nil ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue) else { throw ToolError.encodingFailed }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        if let background { context.setFillColor(background.color); context.fill(rect) }
        else { context.clear(rect) }
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        guard let output = context.makeImage() else { throw ToolError.encodingFailed }
        return output
    }
    static func encode(_ image: CGImage, options: ImageConversionOptions) throws -> Data {
        let bytes = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(bytes, options.format.type.identifier as CFString, 1, nil) else { throw ImageConversionError.unavailableEncoder(options.format) }
        let properties: [CFString: Any] = options.format.isLossy ? [kCGImageDestinationLossyCompressionQuality: options.quality] : [:]
        CGImageDestinationAddImage(encoder, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(encoder) else { throw ToolError.encodingFailed }
        return bytes as Data
    }
}
