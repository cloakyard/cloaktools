import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public struct PDFAssemblyItem: Identifiable, Sendable {
    public let id = UUID()
    public let sourceURL: URL
    public let pageCount: Int
    public let isImage: Bool
    public let sourceByteCount: Int
    public let thumbnailPNG: Data
    let pdfData: Data
}

public enum PDFAssemblyError: LocalizedError, Sendable {
    case limits, invalid(String), protected(String), forms(String), encoding
    public var errorDescription: String? {
        switch self {
        case .limits: "Choose up to 32 files and 200 pages, with at most 100 MB per file and 200 MB total."
        case let .invalid(name): "“\(name)” is not a supported PDF or single-frame image. Choose another file."
        case let .protected(name): "“\(name)” is encrypted or restricts assembly. Choose an unprotected PDF."
        case let .forms(name): "“\(name)” contains forms or a document signature. Use an ordinary PDF to preserve the original form or signature."
        case .encoding: "macOS could not assemble the PDF. No output was published."
        }
    }
}

public enum PDFAssembly {
    public static let inputTypes: [UTType] = [.pdf] + ImageConversion.inputTypes
    public static let inputExtensions = ImageConversion.inputExtensions.union(["pdf"])
    public static let maximumFiles = 32
    public static let maximumPages = 200
    public static let maximumBytes = 200_000_000

    /// Capture each input once. Existing items stay immutable when files are added or reordered.
    public static func prepare(existing: [PDFAssemblyItem] = [], adding urls: [URL]) throws -> [PDFAssemblyItem] {
        guard !urls.isEmpty, existing.count + urls.count <= maximumFiles else { throw PDFAssemblyError.limits }
        var items = existing
        var sourceBytes = existing.reduce(0) { $0 + $1.sourceByteCount }
        var capturedBytes = existing.reduce(0) { $0 + $1.pdfData.count }
        var pages = existing.reduce(0) { $0 + $1.pageCount }
        for url in urls {
            try Task.checkCancellation()
            let bytes: Data
            do { bytes = try LocalFileCapture.read(url, limit: min(100_000_000, maximumBytes - sourceBytes)) }
            catch LocalFileCapture.CaptureError.tooLarge { throw PDFAssemblyError.limits }
            sourceBytes += bytes.count
            let isPDF = bytes.starts(with: Data("%PDF-".utf8))
            let data: Data
            if isPDF { data = bytes }
            else {
                do { data = try imagePDF(ImageConversion.prepare(bytes: bytes, sourceURL: url).image) }
                catch is CancellationError { throw CancellationError() }
                catch ToolError.imageTooLarge { throw ToolError.imageTooLarge }
                catch { throw PDFAssemblyError.invalid(url.lastPathComponent) }
            }
            let document = try validated(data, name: url.lastPathComponent)
            pages += document.pageCount; capturedBytes += data.count
            guard pages <= maximumPages, capturedBytes <= maximumBytes else { throw PDFAssemblyError.limits }
            let thumbnail = try thumbnail(document)
            items.append(.init(sourceURL: url, pageCount: document.pageCount, isImage: !isPDF,
                               sourceByteCount: bytes.count, thumbnailPNG: thumbnail, pdfData: data))
        }
        try Task.checkCancellation()
        return items
    }

    public static func write(_ items: [PDFAssemblyItem], in folder: URL, name: String) throws -> URL {
        try SafeOutput.validate(stem: name)
        try Task.checkCancellation()
        guard !items.isEmpty, items.count <= maximumFiles,
              items.reduce(0, { $0 + $1.pageCount }) <= maximumPages,
              items.reduce(0, { $0 + $1.pdfData.count }) <= maximumBytes else { throw PDFAssemblyError.limits }
        let output = PDFDocument()
        for item in items {
            let source = try validated(item.pdfData, name: item.sourceURL.lastPathComponent)
            for index in 0..<source.pageCount {
                try Task.checkCancellation()
                guard let page = source.page(at: index)?.copy() as? PDFPage else { throw PDFAssemblyError.encoding }
                output.insert(page, at: output.pageCount)
            }
        }
        output.documentAttributes = [PDFDocumentAttribute.creatorAttribute: "CloakTools"]
        guard let bytes = output.dataRepresentation(), bytes.count <= maximumBytes,
              let check = PDFDocument(data: bytes), check.pageCount == output.pageCount else { throw PDFAssemblyError.encoding }
        try Task.checkCancellation()
        return try SafeOutput.publish(bytes, in: folder, stem: name, extension: "pdf")
    }

    static func validated(_ data: Data, name: String) throws -> PDFDocument {
        guard let document = PDFDocument(data: data) else { throw PDFAssemblyError.invalid(name) }
        guard !document.isEncrypted, !document.isLocked, document.allowsDocumentAssembly else { throw PDFAssemblyError.protected(name) }
        guard document.pageCount <= maximumPages else { throw PDFAssemblyError.limits }
        guard document.pageCount > 0,
              let provider = CGDataProvider(data: data as CFData), let cg = CGPDFDocument(provider),
              let catalog = cg.catalog else { throw PDFAssemblyError.invalid(name) }
        var dictionary: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(catalog, "AcroForm", &dictionary) || CGPDFDictionaryGetDictionary(catalog, "Perms", &dictionary) {
            throw PDFAssemblyError.forms(name)
        }
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            guard let page = document.page(at: index) else { throw PDFAssemblyError.invalid(name) }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.origin.x.isFinite, bounds.origin.y.isFinite, bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0, bounds.width <= 14_400, bounds.height <= 14_400 else { throw PDFAssemblyError.invalid(name) }
            if page.annotations.contains(where: { $0.type == "Widget" }) { throw PDFAssemblyError.forms(name) }
        }
        return document
    }

    private static func imagePDF(_ image: CGImage) throws -> Data {
        let portrait = image.width <= image.height
        var page = CGRect(x: 0, y: 0, width: portrait ? 595.276 : 841.89, height: portrait ? 841.89 : 595.276)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &page, nil) else { throw PDFAssemblyError.encoding }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(page)
        let usable = page.insetBy(dx: 24, dy: 24)
        let scale = min(usable.width / CGFloat(image.width), usable.height / CGFloat(image.height))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        context.draw(image, in: CGRect(x: (page.width - width) / 2, y: (page.height - height) / 2, width: width, height: height))
        context.endPDFPage(); context.closePDF()
        return data as Data
    }

    private static func thumbnail(_ document: PDFDocument) throws -> Data {
        guard let page = document.page(at: 0) else { throw PDFAssemblyError.encoding }
        return try thumbnail(page, size: 192)
    }

    static func thumbnail(_ page: PDFPage, size: CGFloat) throws -> Data {
        let preview = page.thumbnail(of: CGSize(width: size, height: size), for: .cropBox)
        guard let image = preview.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw PDFAssemblyError.encoding }
        let bytes = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else { throw PDFAssemblyError.encoding }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw PDFAssemblyError.encoding }
        return bytes as Data
    }
}
