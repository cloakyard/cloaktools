import Foundation
import CoreGraphics

public enum BlankDocuments {
    /// A real, one-page A4 PDF made by the platform renderer, not an empty file.
    public static func pdf() throws -> Data {
        let output = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 595.276, height: 841.89)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw CocoaError(.fileWriteUnknown) }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(bounds)
        context.endPDFPage(); context.closePDF()
        return output as Data
    }
}
