import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ScannedPDFOptimization {
    enum Failure: LocalizedError {
        case noScans, resolution
        var errorDescription: String? {
            switch self {
            case .noScans: "No image-only scan pages were found. Choose Standard to optimize this PDF."
            case .resolution: "This scan exceeds the processing limit at this resolution. Choose a lower DPI."
            }
        }
    }

    private final class PageContent {
        let box: CGRect
        init(_ box: CGRect) { self.box = box }
        var image = false
        var preserve = false
    }

    // Only rewrite pages with directly painted images. Leave text (including invisible OCR),
    // nested forms, transparency patterns, vector artwork and annotations in the source PDF.
    private static func isScan(_ page: PDFPage) -> Bool {
        guard page.annotations.isEmpty, let ref = page.pageRef, let table = CGPDFOperatorTableCreate() else { return false }
        defer { CGPDFOperatorTableRelease(table) }
        for op in ["BT", "sh", "SCN", "scn", "S", "s", "B", "B*", "b", "b*", "BI", "BDC", "m", "l", "c", "v", "y"] {
            CGPDFOperatorTableSetCallback(table, op) { _, info in
                if let info { Unmanaged<PageContent>.fromOpaque(info).takeUnretainedValue().preserve = true }
            }
        }
        CGPDFOperatorTableSetCallback(table, "re") { scanner, info in
            guard let info else { return }
            let flag = Unmanaged<PageContent>.fromOpaque(info).takeUnretainedValue()
            var h: CGFloat = 0, w: CGFloat = 0, y: CGFloat = 0, x: CGFloat = 0
            guard CGPDFScannerPopNumber(scanner, &h), CGPDFScannerPopNumber(scanner, &w),
                  CGPDFScannerPopNumber(scanner, &y), CGPDFScannerPopNumber(scanner, &x),
                  CGRect(x: x, y: y, width: w, height: h).insetBy(dx: -0.5, dy: -0.5).contains(flag.box)
            else { flag.preserve = true; return }
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            guard let info else { return }
            let flag = Unmanaged<PageContent>.fromOpaque(info).takeUnretainedValue()
            var name: UnsafePointer<CChar>?
            var stream: CGPDFStreamRef?
            var type: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let object = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner), "XObject", name),
                  CGPDFObjectGetValue(object, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream), CGPDFDictionaryGetName(dictionary, "Subtype", &type),
                  let type, String(cString: type) == "Image" else { flag.preserve = true; return }
            flag.image = true
        }
        let content = CGPDFContentStreamCreateWithPage(ref)
        defer { CGPDFContentStreamRelease(content) }
        let flags = PageContent(ref.getBoxRect(.mediaBox))
        let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(flags).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        return CGPDFScannerScan(scanner) && flags.image && !flags.preserve
    }

    static func encode(_ document: PDFDocument, dpi: Int, limit: Int?, stronger: Bool) throws -> Data {
        let scanned = (0..<document.pageCount).filter { document.page(at: $0).map(isScan) == true }
        guard !scanned.isEmpty else { throw Failure.noScans }
        let originals = try scanned.map { i in
            guard let page = document.page(at: i) else { throw PDFAssemblyError.encoding }
            return page
        }
        let qualities = limit == nil ? [stronger ? 0.52 : 0.78] : (stronger ? [0.52, 0.35, 0.2] : [0.78, 0.55, 0.35, 0.2])
        for quality in qualities {
            var totalPixels = 0
            for (i, original) in zip(scanned, originals) {
                try Task.checkCancellation()
                let replacement = try autoreleasepool { try rasterPage(original, dpi: dpi, quality: quality, pixels: &totalPixels) }
                document.removePage(at: i)
                document.insert(replacement, at: i)
            }
            guard let bytes = document.dataRepresentation(), bytes.count <= PDFAssembly.maximumBytes else { throw PDFAssemblyError.encoding }
            guard bytes.count <= limit ?? Int.max else { continue }
            guard let check = PDFDocument(data: bytes), check.pageCount == document.pageCount else { throw PDFAssemblyError.encoding }
            return bytes
        }
        throw OptimizationError.overBudget
    }

    private static func rasterPage(_ page: PDFPage, dpi: Int, quality: Double, pixels: inout Int) throws -> PDFPage {
        guard let ref = page.pageRef else { throw PDFAssemblyError.encoding }
        var box = ref.getBoxRect(.mediaBox)
        let width = max(1, Int(ceil(box.width * CGFloat(dpi) / 72)))
        let height = max(1, Int(ceil(box.height * CGFloat(dpi) / 72)))
        pixels += width * height
        guard width * height <= 20_000_000, pixels <= 250_000_000 else { throw Failure.resolution }
        let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: rgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw PDFAssemblyError.encoding }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(rect)
        bitmap.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        bitmap.translateBy(x: -box.minX, y: -box.minY)
        bitmap.drawPDFPage(ref)
        let mask = try textMask(bitmap)
        guard var image = bitmap.makeImage() else { throw PDFAssemblyError.encoding }
        if mask != nil {
            image = try ImageConversion.render(image, width: max(1, width / 2), height: max(1, height / 2))
        }
        let jpeg = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else { throw PDFAssemblyError.encoding }
        CGImageDestinationAddImage(encoder, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(encoder), let provider = CGDataProvider(data: jpeg as CFData),
              let background = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw PDFAssemblyError.encoding }
        let pdf = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdf), let canvas = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw PDFAssemblyError.encoding }
        canvas.beginPDFPage(nil)
        canvas.draw(background, in: box)
        if let mask {
            canvas.clip(to: box, mask: mask)
            canvas.setFillColor(CGColor(gray: 0, alpha: 1))
            canvas.fill(box)
        }
        canvas.endPDFPage()
        canvas.closePDF()
        guard let output = PDFDocument(data: pdf as Data)?.page(at: 0) else { throw PDFAssemblyError.encoding }
        for type in [PDFDisplayBox.cropBox, .artBox, .bleedBox, .trimBox] { output.setBounds(page.bounds(for: type), for: type) }
        output.rotation = page.rotation
        return output
    }

    // For mostly white scans, retain dark neutral ink in a full-resolution one-bit
    // mask. Color and paper texture go in a separate lower-resolution JPEG.
    private static func textMask(_ bitmap: CGContext) throws -> CGImage? {
        guard let raw = bitmap.data else { return nil }
        let data = raw.assumingMemoryBound(to: UInt8.self)
        let n = bitmap.width * bitmap.height
        var white = 0, dark = 0, samples = 0
        for i in stride(from: 0, to: n, by: max(1, n / 8191)) {
            let p = data + i * 4
            if min(p[0], p[1], p[2]) > 222 { white += 1 }
            if max(p[0], p[1], p[2]) < 80 { dark += 1 }
            samples += 1
        }
        guard white * 100 > samples * 68, dark * 100 > samples, dark * 100 < samples * 26 else { return nil }
        let stride = (bitmap.width + 7) / 8
        var bits = Data(repeating: 255, count: stride * bitmap.height)
        try bits.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
            let mask = buf.bindMemory(to: UInt8.self)
            for y in 0..<bitmap.height {
                try Task.checkCancellation()
                for x in 0..<bitmap.width {
                    let p = data + y * bitmap.bytesPerRow + x * 4
                    let hi = max(p[0], p[1], p[2]), lo = min(p[0], p[1], p[2])
                    if hi < 100 && hi - lo < 24 {
                        mask[y * stride + x / 8] &= ~(128 >> UInt8(x % 8))
                        p[0] = 255; p[1] = 255; p[2] = 255
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: bits as CFData),
              let mask = CGImage(maskWidth: bitmap.width, height: bitmap.height, bitsPerComponent: 1, bitsPerPixel: 1,
                                 bytesPerRow: stride, provider: provider, decode: nil, shouldInterpolate: false) else { throw PDFAssemblyError.encoding }
        return mask
    }
}
