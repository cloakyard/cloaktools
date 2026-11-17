import Foundation
import Testing
@testable import CloakToolsCore

@Test func cleanupDefaultOnlyTrimsTrailingSpacesAndTabs() throws {
    let input = "  hello  \t\r\n\tworld\t\rfinal  \n"
    let result = try TextCleanup.prepare(input, options: .init())
    #expect(result.text == "  hello\r\n\tworld\rfinal\n")
    #expect(result.source == input && result.changedLines == 3 && result.removedLines == 0)
    #expect(result.sourceLineCount == 3 && result.resultLineCount == 3)
}
@Test func cleanupNoOptionsPreservesExactUnicodeAndLineEndings() throws {
    var options = TextCleanupOptions(); options.trimLineEnds = false
    let input = "\u{FEFF}  नमस्ते 🚀\t\r\n\r\n\tA\u{00A0}B\u{2028}C\u{200B}  \rfinal\t"
    let result = try TextCleanup.prepare(input, options: options)
    #expect(Data(result.text.utf8) == Data(input.utf8) && result.changedLines == 0)
    #expect(result.sourceLineCount == 4)
}
@Test func cleanupTrimsStartsAndCollapsesOnlyASCIISpacesAndTabs() throws {
    var options = TextCleanupOptions(); options.trimLineStarts = true; options.collapseSpaces = true
    let result = try TextCleanup.prepare(" \tHello\t \tworld\t\nA\u{00A0}  B\n👨‍👩‍👧‍👦  café", options: options)
    #expect(result.text == "Hello world\nA\u{00A0} B\n👨‍👩‍👧‍👦 café")
    #expect(result.changedLines == 3)
}
@Test func cleanupBlankLinePoliciesPreserveKeptLineTerminators() throws {
    var options = TextCleanupOptions(); options.emptyLines = .collapse
    let input = "\r\n \n\t\rA\r\n\n\r\nB"
    let result = try TextCleanup.prepare(input, options: options)
    #expect(result.text == "\r\nA\r\n\nB")
    #expect(result.removedLines == 3 && result.changedLines == 3 && result.resultLineCount == 4)
    options.emptyLines = .remove
    #expect(try TextCleanup.prepare(input, options: options).text == "A\r\nB")
    #expect(try TextCleanup.prepare("  \n\t\r\n", options: options).text.isEmpty)
}
@Test func cleanupEmptySingleLineAndTerminalNewlinesHaveDefinedCounts() throws {
    for (input, count) in [("",0),("A",1),("A\n",1),("A\n\n",2),("\r\n",1),("A\rB",2)] {
        let result = try TextCleanup.prepare(input, options: .init())
        #expect(result.sourceLineCount == count && result.text == input)
    }
    #expect(try TextCleanup.prepare("A  ", options: .init()).text == "A")
    let blank = try TextCleanup.prepare("  ", options: .init())
    #expect(blank.text == "" && blank.resultLineCount == 0)
    #expect(try TextCleanup.prepare("A\n  ", options: .init()).resultLineCount == 1)
}
@Test func cleanupLimitsAndBinaryControlsAreRejected() throws {
    #expect(try TextCleanup.prepare(String(repeating: "A", count: TextCleanup.maximumInputBytes), options: .init()).byteCount == TextCleanup.maximumInputBytes)
    #expect(throws: TextCleanupError.inputTooLarge) { try TextCleanup.prepare(String(repeating: "A", count: TextCleanup.maximumInputBytes + 1), options: .init()) }
    for input in ["bad\0text", "bad\u{01}", "bad\u{7F}"] {
        #expect(throws: TextCleanupError.binaryText) { try TextCleanup.prepare(input, options: .init()) }
    }
}
@Test func cleanupPreviewsAreBoundedButSavingUsesFullPreparedText() throws {
    let result = try TextCleanup.prepare(String(repeating: "🚀", count: 70_000) + "  ", options: .init())
    #expect(result.preview.count == 65_536 && result.previewIsTruncated && result.text.count == 70_000)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = try TextCleanup.save(result, in: folder, stem: "Cleaned"), b = try TextCleanup.save(result, in: folder, stem: "Cleaned")
    #expect(a.lastPathComponent == "Cleaned.txt" && b.lastPathComponent == "Cleaned 2.txt")
    #expect(try Data(contentsOf: a) == Data(result.text.utf8) && Data(contentsOf: b) == Data(result.text.utf8))
    #expect(throws: ToolError.invalidName) { try TextCleanup.save(result, in: folder, stem: "../bad") }
}
@Test func cleanupAllOptionCombinationsAreIdempotentAndNeverExpand() throws {
    let input = "\t Hello  world\t\r\n \r\n\r\n\u{00A0} 🚀\t \rLast  "
    for starts in [false,true] { for ends in [false,true] { for collapse in [false,true] { for empty in EmptyLinePolicy.allCases {
        var options = TextCleanupOptions(); options.trimLineStarts = starts; options.trimLineEnds = ends; options.collapseSpaces = collapse; options.emptyLines = empty
        let result = try TextCleanup.prepare(input, options: options)
        #expect(result.byteCount <= input.utf8.count)
        #expect(try TextCleanup.prepare(result.text, options: options).text == result.text)
        #expect(result.source == input)
    } } } }
}
@Test func cleanupCancellationStopsPreparationAndSaving() async throws {
    let result = try TextCleanup.prepare("A", options: .init())
    await Task {
        withUnsafeCurrentTask { $0?.cancel() }
        #expect(throws: CancellationError.self) { try TextCleanup.prepare("A", options: .init()) }
        #expect(throws: CancellationError.self) { try TextCleanup.save(result, in: FileManager.default.temporaryDirectory, stem: UUID().uuidString) }
    }.value
}
