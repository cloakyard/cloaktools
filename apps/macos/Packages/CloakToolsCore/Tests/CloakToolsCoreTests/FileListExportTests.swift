import Foundation
import Darwin
import Testing
@testable import CloakToolsCore

private func withListFolder(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
}
private func listed(_ name: String, size: Int64? = 12, kind: ListedItemKind = .file) -> ListedFile {
    .init(id: UUID(), url: URL(fileURLWithPath: "/tmp").appendingPathComponent(name), kind: kind, size: size, modified: Date(timeIntervalSince1970: 0))
}
@Test func fileListCapturesFileFolderAndBrokenLinkWithoutTraversal() throws {
    try withListFolder { folder in
        let file = folder.appendingPathComponent("Data.txt"), child = folder.appendingPathComponent("Nested"), link = folder.appendingPathComponent("Missing link")
        try Data("नमस्ते 🚀".utf8).write(to: file)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("secret contents".utf8).write(to: child.appendingPathComponent("Inside.txt"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.appendingPathComponent("Missing"))
        let items = try FileListExport.capture([file,child,link])
        #expect(items.map(\.kind) == [.file,.folder,.symbolicLink])
        #expect(items[0].size == Int64("नमस्ते 🚀".utf8.count) && items[1].size == nil && items[2].size == nil)
        let output = try FileListExport.prepare(items, options: .init())
        #expect(!output.text.contains("Inside") && !output.text.contains("secret") && !output.text.contains(folder.path))
        try Data("changed".utf8).write(to: file)
        #expect(try FileListExport.prepare(items, options: .init()).text == output.text)
        #expect(try FileListExport.capture([file])[0].size == 7)
    }
}
@Test func fileListQuotesCSVCommasQuotesNewlinesAndUnicode() throws {
    let output = try FileListExport.prepare([listed("hello,\"world\"\nनमस्ते.txt")], options: .init())
    #expect(output.text == "\"Name\",\"Kind\",\"Size (bytes)\"\r\n\"hello,\"\"world\"\"\nनमस्ते.txt\",\"File\",\"12\"\r\n")
    #expect(output.protectedCells == 0)
}
@Test func fileListCSVPrefixesFormulaLikeNamesIncludingLeadingWhitespace() throws {
    let names = ["=SUM(1,2)","+formula","-formula","@formula","\t =formula","\u{FEFF}\t@formula","ordinary.txt"]
    let output = try FileListExport.prepare(names.map { listed($0) }, options: .init())
    #expect(output.protectedCells == 6)
    #expect(output.text.contains("\"'=SUM(1,2)\"") && output.text.contains("\"'\t =formula\""))
    #expect(output.text.contains("\"ordinary.txt\"") && !output.text.contains("\"'ordinary.txt\""))
}
@Test func fileListColumnsDatesAndSelectedOrderAreExplicit() throws {
    var options = FileListOptions(); options.includeKind = false; options.includeSize = false
    let items = [listed("B.txt"),listed("A.txt")]
    #expect(try FileListExport.prepare(items, options: options).text == "\"Name\"\r\n\"B.txt\"\r\n\"A.txt\"\r\n")
    options.includeModified = true; options.includePath = true
    let output = try FileListExport.prepare(items, options: options)
    #expect(output.text.contains("\"Modified (UTC)\",\"Full path\""))
    #expect(output.text.contains("\"1970-01-01T00:00:00Z\",\"/tmp/B.txt\""))
}
@Test func fileListMarkdownEscapesMarkupPipesAndControlLines() throws {
    var options = FileListOptions(); options.format = .markdown
    let output = try FileListExport.prepare([listed("[link]|<img>`x`\r\nnext\tname.md"),listed("Folder",size:nil,kind:.folder)], options: options)
    #expect(output.text.contains("\\[link\\]\\|\\<img\\>\\`x\\` ↵ next ⇥ name\\.md"))
    #expect(output.text.contains("| Folder | Folder |  |\n"))
    #expect(output.text.components(separatedBy: "\n").count == 5 && output.protectedCells == 0)
}
@Test func fileListRejectsInvalidMissingDuplicateAndSpecialItems() throws {
    #expect(throws: FileListError.invalidSelection) { try FileListExport.capture([]) }
    #expect(throws: FileListError.invalidSelection) { try FileListExport.capture([URL(string:"https://example.com/file")!]) }
    #expect(throws: FileListError.invalidSelection) { try FileListExport.capture(Array(repeating: URL(fileURLWithPath:"/tmp/a"),count:201)) }
    try withListFolder { folder in
        let file=folder.appendingPathComponent("A"), fifo=folder.appendingPathComponent("Pipe")
        try Data().write(to:file)
        #expect(throws: FileListError.duplicateItem) { try FileListExport.capture([file,file]) }
        #expect(throws: FileListError.unavailable("Missing")) { try FileListExport.capture([folder.appendingPathComponent("Missing")]) }
        #expect(fifo.path.withCString { mkfifo($0,0o600) } == 0)
        #expect(throws: FileListError.unsupported("Pipe")) { try FileListExport.capture([fifo]) }
    }
}
@Test func fileListAdditionsKeepSnapshotsAndRejectFailedBatches() throws {
    try withListFolder { folder in
        let a=folder.appendingPathComponent("A"), b=folder.appendingPathComponent("B"), missing=folder.appendingPathComponent("Missing")
        try Data("old".utf8).write(to:a); try Data().write(to:b)
        let existing=try FileListExport.capture([a]); try Data("changed".utf8).write(to:a)
        let combined=try FileListExport.adding([a,b],to:existing)
        #expect(combined.count == 2 && combined[0].id == existing[0].id && combined[0].size == 3)
        #expect(throws: FileListError.duplicateItem) { try FileListExport.adding([a],to:existing) }
        #expect(throws: FileListError.unavailable("Missing")) { try FileListExport.adding([b,missing],to:existing) }
        #expect(existing.count == 1 && existing[0].size == 3)
    }
}
@Test func fileListBoundsSelectionOutputAndPreview() throws {
    #expect(throws: FileListError.invalidSelection) { try FileListExport.prepare([],options:.init()) }
    let item=listed("A")
    #expect(throws: FileListError.duplicateItem) { try FileListExport.prepare([item,item],options:.init()) }
    let items=(0..<200).map { listed(String(repeating:"🚀",count:100)+"\($0)") }
    let result=try FileListExport.prepare(items,options:.init())
    #expect(result.byteCount > 65_536)
    let long=(0..<200).map { listed(String(repeating:"A",count:12_000)+"\($0)") }
    #expect(throws: FileListError.outputTooLarge) { try FileListExport.prepare(long,options:.init()) }
    let preview=try FileListExport.prepare((0..<200).map { listed(String(repeating:"A",count:400)+"\($0)") },options:.init())
    #expect(preview.preview.count == 65_536 && preview.previewIsTruncated)
}
@Test func fileListSavesExactFullOutputWithNumberedCopiesAndSafeNames() throws {
    try withListFolder { folder in
        for format in FileListFormat.allCases {
            var options=FileListOptions();options.format=format
            let result=try FileListExport.prepare((0..<200).map { listed(String(repeating:"A",count:400)+"\($0)") },options:options)
            let first=try FileListExport.save(result,in:folder,stem:"File list"), second=try FileListExport.save(result,in:folder,stem:"File list")
            #expect(first.lastPathComponent == "File list.\(format.fileExtension)" && second.lastPathComponent == "File list 2.\(format.fileExtension)")
            #expect(try Data(contentsOf:first) == Data(result.text.utf8) && Data(contentsOf:second) == Data(result.text.utf8))
            #expect(throws: ToolError.invalidName) { try FileListExport.save(result,in:folder,stem:"../bad") }
        }
    }
}
@Test func fileListCancellationPreventsCapturePreparationAndSaving() async throws {
    let items=[listed("A")],result=try FileListExport.prepare([listed("A")],options:.init())
    await Task {
        withUnsafeCurrentTask { $0?.cancel() }
        #expect(throws: CancellationError.self) { try FileListExport.capture([URL(fileURLWithPath:"/missing")]) }
        #expect(throws: CancellationError.self) { try FileListExport.prepare(items,options:.init()) }
        #expect(throws: CancellationError.self) { try FileListExport.save(result,in:FileManager.default.temporaryDirectory,stem:UUID().uuidString) }
    }.value
}
