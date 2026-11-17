import Foundation
import Testing
@testable import CloakToolsCore

private func withDigestFolder(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
}

@Test func digestCapturesTextAndPreparesInReviewedOrderWithoutReadingAgain() throws {
    try withDigestFolder { folder in
        let a = folder.appendingPathComponent("Notes.txt"), b = folder.appendingPathComponent("main.rs")
        try Data("नमस्ते 🚀\r\nSecond line".utf8).write(to: a)
        try Data("fn main() {}\n".utf8).write(to: b)
        let files = try MarkdownDigest.capture([a,b])
        try Data("changed later".utf8).write(to: a)
        let result = try MarkdownDigest.prepare(files.reversed(), title: "My digest")
        #expect(result.fileCount == 2 && result.text.hasPrefix("# My digest\n"))
        #expect(result.text.contains("## 1. main\\.rs\n\n```rust\nfn main() {}\n```"))
        #expect(result.text.contains("## 2. Notes\\.txt\n\n```text\nनमस्ते 🚀\r\nSecond line\n```"))
        #expect(!result.text.contains(folder.path) && !result.text.contains("changed later"))
        #expect(result.text == (try MarkdownDigest.prepare(files.reversed(), title: "My digest")).text)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }
}

@Test func digestFencesContainMarkdownHTMLAndLongEmbeddedFences() throws {
    let content = "```swift\ncode\n```\n~~~~~\n# Intruder\n<script>example()</script>\n![remote](https://example.com/image)\n"
    let file = DigestFile(id: UUID(), url: URL(fileURLWithPath: "/tmp/Readme.md"), text: content)
    let result = try MarkdownDigest.prepare([file], title: "Digest")
    #expect(result.text.contains("````markdown\n" + content + "````\n"))
    let ticks = DigestFile(id: UUID(), url: file.url, text: String(repeating: "`", count: 100_000))
    #expect(try MarkdownDigest.prepare([ticks], title: "Digest").text.contains("~~~markdown\n"))
}

@Test func digestEscapesHeadingsAndDistinguishesSameNamedFiles() throws {
    let name = "[link](https:example.com)<img>\n# title.md"
    let file = DigestFile(id: UUID(), url: URL(fileURLWithPath: "/tmp").appendingPathComponent(name), text: "content")
    let duplicateName = DigestFile(id: UUID(), url: URL(fileURLWithPath: "/another").appendingPathComponent(name), text: "other")
    let result = try MarkdownDigest.prepare([file, duplicateName], title: "Title [draft]")
    #expect(result.text.hasPrefix("# Title \\[draft\\]\n"))
    #expect(result.text.contains("## 1. \\[link\\]\\(https\\:example\\.com\\)\\<img\\> \\# title\\.md"))
    #expect(result.text.contains("## 2. \\[link\\]"))
    #expect(!result.text.contains("\n# title.md") && !result.text.contains("/another"))
}

@Test func digestRejectsBadSelectionsDirectoriesSymlinksAndBinaryText() throws {
    #expect(throws: MarkdownDigestError.invalidSelection) { try MarkdownDigest.capture([]) }
    #expect(throws: MarkdownDigestError.invalidSelection) { try MarkdownDigest.capture([URL(string: "https://example.com/file.txt")!]) }
    #expect(throws: MarkdownDigestError.invalidSelection) { try MarkdownDigest.capture(Array(repeating: URL(fileURLWithPath: "/tmp/file"), count: 33)) }
    try withDigestFolder { folder in
        let file = folder.appendingPathComponent("Text.txt"), link = folder.appendingPathComponent("Link.txt")
        try Data("valid".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: MarkdownDigestError.unsupportedFile(folder.lastPathComponent)) { try MarkdownDigest.capture([folder]) }
        #expect(throws: MarkdownDigestError.unsupportedFile("Link.txt")) { try MarkdownDigest.capture([link]) }
        #expect(throws: MarkdownDigestError.duplicateFile) { try MarkdownDigest.capture([file,file]) }
        for bytes in [Data([0]), Data([0xFF]), Data([0x7F])] {
            try bytes.write(to: file)
            #expect(throws: MarkdownDigestError.notText("Text.txt")) { try MarkdownDigest.capture([file]) }
        }
    }
}

@Test func digestEnforcesPerFileAndAggregateCaptureBounds() throws {
    try withDigestFolder { folder in
        let oversized = folder.appendingPathComponent("Large.txt")
        try Data(repeating: 65, count: MarkdownDigest.maximumFileBytes + 1).write(to: oversized)
        #expect(throws: MarkdownDigestError.fileTooLarge("Large.txt")) { try MarkdownDigest.capture([oversized]) }
        var urls: [URL] = []
        for index in 0..<9 {
            let url = folder.appendingPathComponent("File\(index).txt")
            try Data(repeating: 65, count: MarkdownDigest.maximumFileBytes).write(to: url); urls.append(url)
        }
        #expect(try MarkdownDigest.capture(Array(urls.prefix(8))).count == 8)
        #expect(throws: MarkdownDigestError.totalTooLarge) { try MarkdownDigest.capture(urls) }
    }
}

@Test func digestChecksPreparedSelectionTitleAndExpansionBounds() throws {
    let file = DigestFile(id: UUID(), url: URL(fileURLWithPath: "/tmp/A.txt"), text: "A")
    #expect(throws: MarkdownDigestError.invalidSelection) { try MarkdownDigest.prepare([], title: "Digest") }
    #expect(throws: MarkdownDigestError.duplicateFile) { try MarkdownDigest.prepare([file,file], title: "Digest") }
    #expect(throws: ToolError.invalidName) { try MarkdownDigest.prepare([file], title: "../unsafe") }
    let content = String(repeating: "`", count: 524_288) + String(repeating: "~", count: 524_288)
    let files = (0..<8).map { DigestFile(id: UUID(), url: URL(fileURLWithPath: "/tmp/\($0).txt"), text: content) }
    #expect(throws: MarkdownDigestError.outputTooLarge) { try MarkdownDigest.prepare(files, title: "Digest") }
}

@Test func digestPreviewsStayBoundedWithoutTruncatingSavedContent() throws {
    let file = DigestFile(id: UUID(), url: URL(fileURLWithPath: "/tmp/Unicode.txt"), text: String(repeating: "🚀", count: 70_000))
    let empty = DigestFile(id: UUID(), url: URL(fileURLWithPath: "/tmp/Empty.txt"), text: "")
    let result = try MarkdownDigest.prepare([file,empty], title: "Digest")
    #expect(file.preview.count == 65_536 && file.previewIsTruncated)
    #expect(result.preview.count == 65_536 && result.previewIsTruncated)
    #expect(!result.preview.contains("\u{FFFD}"))
    #expect(result.text.contains("## 2. Empty\\.txt\n\n```text\n\n```"))
    try withDigestFolder { folder in
        let first = try MarkdownDigest.save(result, in: folder), second = try MarkdownDigest.save(result, in: folder)
        #expect(first.lastPathComponent == "Digest.md" && second.lastPathComponent == "Digest 2.md")
        #expect(try Data(contentsOf: first) == Data(result.text.utf8) && Data(contentsOf: second) == Data(result.text.utf8))
        #expect(!(try FileManager.default.contentsOfDirectory(atPath: folder.path)).contains { $0.hasPrefix(".cloaktools-") })
    }
}

@Test func digestSavingCannotOverwriteAnIncludedSource() throws {
    try withDigestFolder { folder in
        let source = folder.appendingPathComponent("Digest.md"), original = Data("Original notes".utf8)
        try original.write(to: source)
        let result = try MarkdownDigest.prepare(MarkdownDigest.capture([source]), title: "Digest")
        let saved = try MarkdownDigest.save(result, in: folder)
        #expect(saved.lastPathComponent == "Digest 2.md")
        #expect(try Data(contentsOf: source) == original)
    }
}

@Test func digestCancellationPreventsCapturePreparationAndPublication() async throws {
    let files = [DigestFile(id: UUID(), url: URL(fileURLWithPath: "/tmp/Note.txt"), text: "notes")]
    let result = try MarkdownDigest.prepare(files, title: "Cancelled digest")
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        #expect(throws: CancellationError.self) { try MarkdownDigest.capture([URL(fileURLWithPath: "/nonexistent/file.txt")]) }
        #expect(throws: CancellationError.self) { try MarkdownDigest.prepare(files, title: "Digest") }
        #expect(throws: CancellationError.self) { try MarkdownDigest.save(result, in: FileManager.default.temporaryDirectory) }
    }
    await task.value
}

@Test func digestAddingPreservesCapturedFilesAndRejectsFailedBatches() throws {
    try withDigestFolder { folder in
        let a = folder.appendingPathComponent("A.txt"), b = folder.appendingPathComponent("B.txt"), bad = folder.appendingPathComponent("Bad.txt")
        try Data("captured".utf8).write(to: a); try Data("new".utf8).write(to: b); try Data([0]).write(to: bad)
        let existing = try MarkdownDigest.capture([a])
        try Data("changed".utf8).write(to: a)
        let combined = try MarkdownDigest.adding([a,b], to: existing)
        #expect(combined.count == 2 && combined[0].text == "captured" && combined[0].id == existing[0].id)
        #expect(throws: MarkdownDigestError.duplicateFile) { try MarkdownDigest.adding([a], to: existing) }
        #expect(throws: MarkdownDigestError.notText("Bad.txt")) { try MarkdownDigest.adding([b,bad], to: existing) }
        #expect(existing.count == 1 && existing[0].text == "captured")
        let full = (0..<8).map { DigestFile(id: UUID(), url: folder.appendingPathComponent("\($0).txt"), text: String(repeating: "a", count: MarkdownDigest.maximumFileBytes)) }
        #expect(throws: MarkdownDigestError.totalTooLarge) { try MarkdownDigest.adding([b], to: full) }
    }
}
