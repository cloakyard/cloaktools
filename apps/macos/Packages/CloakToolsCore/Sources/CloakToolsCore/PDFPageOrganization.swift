import Foundation
import PDFKit

/// Values cross tasks; PDFKit objects never do. The source is read exactly once.
public struct PreparedPDFPages: Sendable {
    public let sourceURL: URL
    public let thumbnails: [Data]
    public var pageCount: Int { thumbnails.count }
    let bytes: Data
}

public struct PDFPageChoice: Equatable, Sendable {
    public let index: Int
    public let quarterTurns: Int
    public init(index: Int, quarterTurns: Int = 0) {
        self.index = index; self.quarterTurns = quarterTurns
    }
}

public enum PDFPageOrganizationError: LocalizedError, Sendable {
    case selection, range, previews
    public var errorDescription: String? {
        switch self {
        case .selection: "Include at least one page. Each page can appear once, with a rotation of 0, 90, 180 or 270 degrees."
        case .range: "Enter original page numbers, such as 1, 3–5. Use numbers within this PDF and ascending ranges."
        case .previews: "This PDF needs too much preview memory. Choose a smaller document."
        }
    }
}

public enum PDFPageOrganization {
    public static func prepare(_ url: URL) throws -> PreparedPDFPages {
        try Task.checkCancellation()
        let bytes: Data
        do { bytes = try LocalFileCapture.read(url, limit: 100_000_000) }
        catch LocalFileCapture.CaptureError.tooLarge { throw PDFAssemblyError.limits }
        let document = try PDFAssembly.validated(bytes, name: url.lastPathComponent)
        var thumbnails: [Data] = []
        var thumbnailBytes = 0
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let data = try autoreleasepool {
                guard let page = document.page(at: index) else { throw PDFAssemblyError.invalid(url.lastPathComponent) }
                return try PDFAssembly.thumbnail(page, size: 192)
            }
            thumbnailBytes += data.count
            guard thumbnailBytes <= 32_000_000 else { throw PDFPageOrganizationError.previews }
            thumbnails.append(data)
        }
        try Task.checkCancellation()
        return PreparedPDFPages(sourceURL: url, thumbnails: thumbnails, bytes: bytes)
    }

    /// One larger preview at a time in the host; do not retain a full-size image for every page.
    public static func preview(_ source: PreparedPDFPages, index: Int) throws -> Data {
        try Task.checkCancellation()
        guard (0..<source.pageCount).contains(index), let document = PDFDocument(data: source.bytes),
              let page = document.page(at: index) else { throw PDFPageOrganizationError.selection }
        let data = try PDFAssembly.thumbnail(page, size: 768)
        try Task.checkCancellation()
        return data
    }

    /// Original, one-based page numbers; applying a range does not reorder the draft.
    public static func selection(_ text: String, pageCount: Int) throws -> Set<Int> {
        guard (1...PDFAssembly.maximumPages).contains(pageCount), !text.isEmpty, text.utf8.count <= 2048 else {
            throw PDFPageOrganizationError.range
        }
        let normalized = text.replacingOccurrences(of: "–", with: "-")
        func number(_ token: Substring) throws -> Int {
            let value = token.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(value), (1...pageCount).contains(number) else { throw PDFPageOrganizationError.range }
            return number
        }
        var result = Set<Int>()
        for token in normalized.split(separator: ",", omittingEmptySubsequences: false) {
            let bounds = token.split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count) else { throw PDFPageOrganizationError.range }
            let first = try number(bounds[0]), last = try bounds.count == 2 ? number(bounds[1]) : first
            guard first <= last else { throw PDFPageOrganizationError.range }
            result.formUnion((first...last).map { $0 - 1 })
        }
        return result
    }

    /// The order of choices is the output order. Rotation is relative to the captured original.
    public static func write(_ source: PreparedPDFPages, pages: [PDFPageChoice], in folder: URL, name: String) throws -> URL {
        try SafeOutput.validate(stem: name)
        try Task.checkCancellation()
        guard !pages.isEmpty, pages.count <= source.pageCount, Set(pages.map(\.index)).count == pages.count,
              pages.allSatisfy({ (0..<source.pageCount).contains($0.index) && (0...3).contains($0.quarterTurns) }) else {
            throw PDFPageOrganizationError.selection
        }
        let document = try PDFAssembly.validated(source.bytes, name: source.sourceURL.lastPathComponent)
        let output = PDFDocument()
        for choice in pages {
            try Task.checkCancellation()
            guard let page = document.page(at: choice.index)?.copy() as? PDFPage else { throw PDFAssemblyError.encoding }
            // Normalize before addition to avoid overflow from unusual source rotation values.
            page.rotation = ((page.rotation % 360 + 360) % 360 + choice.quarterTurns * 90) % 360
            output.insert(page, at: output.pageCount)
        }
        output.documentAttributes = [PDFDocumentAttribute.creatorAttribute: "CloakTools"]
        guard let bytes = output.dataRepresentation(), bytes.count <= PDFAssembly.maximumBytes,
              let check = PDFDocument(data: bytes), check.pageCount == pages.count else { throw PDFAssemblyError.encoding }
        try Task.checkCancellation()
        return try SafeOutput.publish(bytes, in: folder, stem: name, extension: "pdf")
    }
}
