import AppIntents
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import CloakTools
import CloakToolsCore

private func automationFixture() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CloakTools-Automation-Test-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    return folder
}

@Test func fitIntentReturnsValidBoundedImageWithoutWriting() async throws {
    let folder = try automationFixture(); defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("Source.png")
    let context = try #require(CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
    let encoder = try #require(CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(encoder, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(encoder))
    let original = try Data(contentsOf: input)
    var intent = FitImageIntent()
    intent.image = IntentFile(fileURL: input); intent.format = .jpeg; intent.kilobytes = 50
    intent.width = 320; intent.height = 240; intent.quality = 60; intent.reduceDimensions = true
    let file = try #require(try await intent.perform().value)
    #expect(file.filename == "Source fit.jpg")
    #expect(file.data.count <= 50_000)
    let decoder = try #require(CGImageSourceCreateWithData(file.data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
    #expect(image.width == 320 && image.height == 240)
    #expect(try Data(contentsOf: input) == original)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Source.png"])
}

@Test func fitIntentRejectsVariableOverflowBeforeReadingInput() async throws {
    var intent = FitImageIntent()
    intent.image = IntentFile(data: Data(), filename: "Missing.png", type: .png)
    intent.kilobytes = Int.max; intent.quality = 60
    await #expect(throws: ImageFitError.self) { _ = try await intent.perform() }
}

@Test func digestIntentPreservesInputOrderAndUnicodeWithoutWriting() async throws {
    let folder = try automationFixture(); defer { try? FileManager.default.removeItem(at: folder) }
    let one = folder.appendingPathComponent("First.txt"), two = folder.appendingPathComponent("Second.md")
    try Data("नमस्ते 🧰\r\n".utf8).write(to: one)
    try Data("```\n**literal**\n```".utf8).write(to: two)
    var intent = MakeMarkdownDigestIntent()
    intent.files = [IntentFile(fileURL: two), IntentFile(fileURL: one)]; intent.name = "Review"
    let file = try #require(try await intent.perform().value)
    let expected = try MarkdownDigest.prepare(MarkdownDigest.capture([two, one]), title: "Review")
    #expect(file.data == Data(expected.text.utf8)); #expect(file.filename == "Review.md")
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
}

@Test func digestIntentRejectsMissingSelectionAndUnsafeNames() async {
    var intent = MakeMarkdownDigestIntent(); intent.files = []; intent.name = "Review"
    await #expect(throws: MarkdownDigestError.self) { _ = try await intent.perform() }
    intent.files = [IntentFile(data: Data(), filename: "Text.txt", type: .plainText)]; intent.name = "../outside"
    await #expect(throws: ToolError.self) { _ = try await intent.perform() }
}

@Test func digestIntentAcceptsAnInMemoryShortcutFile() async throws {
    var intent = MakeMarkdownDigestIntent()
    intent.files = [IntentFile(data: Data("In-memory content 🧰".utf8), filename: "Memory.txt", type: .plainText)]
    intent.name = "Memory digest"
    let file = try #require(try await intent.perform().value)
    let text = try #require(String(data: file.data, encoding: .utf8))
    #expect(text.contains("Memory\\.txt"))
    #expect(text.contains("In-memory content 🧰"))
}

@Test func cancelledAutomationDoesNotProduceOutput() async throws {
    let folder = try automationFixture(); defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("Input.txt"); try Data("Test".utf8).write(to: file)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        var intent = MakeMarkdownDigestIntent(); intent.files = [IntentFile(fileURL: file)]; intent.name = "Review"
        return try await intent.perform()
    }
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Input.txt"])
}

@Test func optimizationIntentKeepsTheNameOfAnInMemoryImage() async throws {
    let source = try QRCodeCreation.prepare("Automation audit").png
    let decoded = try #require(CGImageSourceCreateWithData(source as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(decoded, 0, nil))
    let bytes = NSMutableData()
    let tiff = try #require(CGImageDestinationCreateWithData(bytes, UTType.tiff.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(tiff, image, nil)
    try #require(CGImageDestinationFinalize(tiff))
    var intent = OptimizeMediaIntent()
    intent.file = IntentFile(data: bytes as Data, filename: "Handout.tiff", type: .tiff)
    intent.aggressive = false
    let response = try await intent.perform()
    let output = try #require(response.value)
    #expect(output.filename == "Handout optimized.png")
    #expect(output.data.count > 0 && output.data.count < bytes.length)
    #expect(CGImageSourceCreateWithData(output.data as CFData, nil) != nil)
}
