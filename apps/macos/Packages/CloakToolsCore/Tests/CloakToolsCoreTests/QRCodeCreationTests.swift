import Foundation
import ImageIO
import CoreGraphics
import CoreImage
import Vision
import Testing
@testable import CloakToolsCore

private func qrPayload(_ png: Data) throws -> String? {
    let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
    try VNImageRequestHandler(data: png).perform([request])
    #expect(request.results?.count == 1)
    return request.results?.first?.payloadStringValue
}
@Test func qrRoundTripsLinksAndLiteralText() throws {
    for value in ["https://example.com/path?a=1&b=%20#part", "mailto:hello@example.com?subject=Hello", "  Line one\r\nLine two\tend  "] {
        let result = try QRCodeCreation.prepare(value)
        let decoded = try qrPayload(result.png)
        #expect(decoded?.utf8.elementsEqual(value.utf8) == true, "Input: \(Array(value.utf8)); decoded: \(decoded.map { Array($0.utf8) } ?? [])")
        #expect(result.inputByteCount == value.utf8.count && result.width == 512)
    }
}
@Test func qrRoundTripsUnicodeWithoutNormalization() throws {
    for value in ["नमस्ते 🌍 · 日本語 · مرحبا", "é", "e\u{301}", "A\u{00A0}B"] {
        let result = try QRCodeCreation.prepare(value)
        let decoded = try qrPayload(result.png)
        #expect(decoded?.utf8.elementsEqual(value.utf8) == true, "Input: \(Array(value.utf8)); decoded: \(decoded.map { Array($0.utf8) } ?? [])")
    }
    let withBOM = "\u{FEFF}A\u{00A0}B", result = try QRCodeCreation.prepare("\u{FEFF}A\u{00A0}B")
    let request = VNDetectBarcodesRequest(); request.symbologies = [.qr]
    try VNImageRequestHandler(data: result.png).perform([request])
    // Vision's display string omits a leading BOM. Its QR descriptor retains the actual codewords.
    let descriptor = try #require(request.results?.first?.barcodeDescriptor as? CIQRCodeDescriptor)
    let words = Array(descriptor.errorCorrectedPayload)
    var bit = 0
    func read(_ count: Int) -> Int {
        var value = 0
        for _ in 0..<count { value = (value << 1) | Int((words[bit / 8] >> (7 - bit % 8)) & 1); bit += 1 }
        return value
    }
    #expect(read(4) == 4) // QR byte mode.
    let length = read(descriptor.symbolVersion < 10 ? 8 : 16)
    #expect(length == withBOM.utf8.count)
    #expect(Data((0..<length).map { _ in UInt8(read(8)) }) == Data(withBOM.utf8))
}
@Test func qrSizesAndCorrectionLevelsRemainReadable() throws {
    for size in QRImageSize.allCases {
        for correction in QRCorrection.allCases {
            var options = QRCodeOptions(); options.size = size; options.correction = correction
            let result = try QRCodeCreation.prepare("CloakTools · Local QR", options: options)
            let source = try #require(CGImageSourceCreateWithData(result.png as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == size.rawValue && image.height == size.rawValue)
            #expect(result.correction == correction && result.margin >= 4 * result.pixelsPerModule)
            #expect(try qrPayload(result.png) == "CloakTools · Local QR")
        }
    }
}
@Test func qrPixelsStayOpaqueBinaryWithWhiteQuietZone() throws {
    let result = try QRCodeCreation.prepare("Pixel check")
    let source = try #require(CGImageSourceCreateWithData(result.png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let side = result.width
    let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    var binary = true, quiet = true, blackCount = 0
    for y in 0..<side { for x in 0..<side {
        let offset = (y * side + x) * 4, v = pixels[offset]
        binary = binary && (v == 0 || v == 255) && pixels[offset + 1] == v && pixels[offset + 2] == v && pixels[offset + 3] == 255
        if x < result.margin || y < result.margin || x >= side - result.margin || y >= side - result.margin { quiet = quiet && v == 255 }
        if v == 0 { blackCount += 1 }
    } }
    #expect(binary && quiet && blackCount > 0)
}
@Test func qrInputBoundsCountUTF8BytesAndPreserveBoundary() throws {
    #expect(throws: QRCodeError.empty) { try QRCodeCreation.prepare("") }
    #expect(throws: QRCodeError.empty) { try QRCodeCreation.prepare(" \t\r\n") }
    #expect(throws: QRCodeError.inputTooLarge) { try QRCodeCreation.prepare(String(repeating: "a", count: 1025)) }
    #expect(throws: QRCodeError.inputTooLarge) { try QRCodeCreation.prepare(String(repeating: "🌍", count: 257)) }
    var options = QRCodeOptions(); options.correction = .high
    let text = String(repeating: "a", count: 1024)
    #expect(throws: QRCodeError.tooDense) { try QRCodeCreation.prepare(text, options: options) }
    options.size = .medium
    let result = try QRCodeCreation.prepare(text, options: options)
    #expect(result.inputByteCount == 1024 && result.pixelsPerModule >= 4)
    // Vision does not detect this dense version on the test host. Core Image's independent QR
    // detector verifies the complete payload; physical scanner coverage is documented separately.
    let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
    let image = try #require(CIImage(data: result.png))
    let detected = detector.features(in: image).compactMap { $0 as? CIQRCodeFeature }
    #expect(detected.count == 1 && detected.first?.messageString == text)
}
@Test func qrRejectsBinaryControlsWithoutExposingPayload() throws {
    for control in ["\0", "\u{01}", "\u{1B}", "\u{7F}"] {
        #expect(throws: QRCodeError.unsupportedControl) { try QRCodeCreation.prepare("Private" + control + "text") }
    }
    #expect(!QRCodeError.unsupportedControl.localizedDescription.contains("Private"))
}
@Test func qrSavesExactPreparedPNGWithSafeNumberedCollisions() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let code = try QRCodeCreation.prepare("Reviewed output")
    let first = try QRCodeCreation.save(code, in: folder, stem: "QR code")
    let second = try QRCodeCreation.save(code, in: folder, stem: "QR code")
    #expect(first.lastPathComponent == "QR code.png" && second.lastPathComponent == "QR code 2.png")
    #expect(try Data(contentsOf: first) == code.png && Data(contentsOf: second) == code.png)
    #expect(throws: (any Error).self) { try QRCodeCreation.save(code, in: folder, stem: "bad/name") }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
}
@Test func qrCancellationPreventsGenerationAndPublication() async throws {
    let code = try QRCodeCreation.prepare("Cancellation fixture")
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        #expect(throws: CancellationError.self) { try QRCodeCreation.prepare("Cancelled") }
        #expect(throws: CancellationError.self) { try QRCodeCreation.save(code, in: FileManager.default.temporaryDirectory, stem: UUID().uuidString) }
    }
    await task.value
}
