import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum QRImageSize: Int, CaseIterable, Identifiable, Sendable {
    case small = 512, medium = 1024, large = 2048
    public var id: Int { rawValue }
    public var title: String { "\(rawValue) px" }
}
public enum QRCorrection: String, CaseIterable, Identifiable, Sendable {
    case standard = "M", high = "H"
    public var id: String { rawValue }
    public var title: String { self == .standard ? "Standard" : "High" }
}
public struct QRCodeOptions: Equatable, Sendable {
    public var size: QRImageSize = .small
    public var correction: QRCorrection = .standard
    public init() {}
}
public enum QRCodeError: LocalizedError, Equatable {
    case empty, inputTooLarge, unsupportedControl, tooDense, generationFailed
    public var errorDescription: String? {
        switch self {
        case .empty: "Enter text or a link to create a QR code."
        case .inputTooLarge: "The code can hold up to 1,024 encoded bytes. Shorten the content or remove an optional detail."
        case .unsupportedControl: "Use plain text without binary control characters. Tabs and line breaks are supported."
        case .tooDense: "Choose a larger image or shorter text to keep this code easy to scan."
        case .generationFailed: "macOS could not create this QR code. Try shorter text or Standard error correction."
        }
    }
}
public struct PreparedQRCode: Sendable {
    public let png: Data
    public let width: Int
    public let inputByteCount: Int
    public let correction: QRCorrection
    let pixelsPerModule: Int
    let margin: Int
}

/// Generates an opaque PNG locally. Input bytes are never trimmed, normalized or opened as a URL.
public enum QRCodeCreation {
    public static let maximumInputBytes = 1024

    static func validate(_ text: String) throws {
        guard text.utf8.count <= maximumInputBytes else { throw QRCodeError.inputTooLarge }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QRCodeError.empty }
        guard !text.unicodeScalars.contains(where: { ($0.value < 32 && ![9,10,13].contains($0.value)) || $0.value == 127 }) else { throw QRCodeError.unsupportedControl }
    }

    public static func prepare(_ text: String, options: QRCodeOptions = .init()) throws -> PreparedQRCode {
        try Task.checkCancellation()
        try validate(text)
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = options.correction.rawValue
        guard let output = filter.outputImage,
              output.extent.width == output.extent.height,
              output.extent.width >= 21, output.extent.width <= 185,
              let symbol = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent) else { throw QRCodeError.generationFailed }
        try Task.checkCancellation()
        let side = options.size.rawValue
        // Keep every module an integer pixel square and add at least four white modules on every side.
        let scale = side / (symbol.width + 8), symbolPixels = symbol.width * scale
        let margin = (side - symbolPixels) / 2
        guard scale >= 4 else { throw QRCodeError.tooDense }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw QRCodeError.generationFailed }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .none; context.setShouldAntialias(false)
        context.draw(symbol, in: CGRect(x: margin, y: margin, width: symbolPixels, height: symbolPixels))
        guard let image = context.makeImage() else { throw QRCodeError.generationFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw QRCodeError.generationFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw QRCodeError.generationFailed }
        try Task.checkCancellation()
        return .init(png: data as Data, width: side, inputByteCount: text.utf8.count, correction: options.correction,
                     pixelsPerModule: scale, margin: margin)
    }
    public static func save(_ code: PreparedQRCode, in folder: URL, stem: String) throws -> URL {
        try Task.checkCancellation()
        return try SafeOutput.publish(code.png, in: folder, stem: stem, extension: "png")
    }
}
