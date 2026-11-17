import Foundation
import Testing
import CoreGraphics
@testable import CloakToolsCore

private let setSources = FileTemplate.allCases.map(TemplateSource.builtIn)
private func setTestFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsSets-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func fileSetCreatesNestedFilesAndEmptyFoldersWithoutOverwriting() throws {
    let folder = try setTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let prepared = try PreparedFileSet(definition: .notes, sources: setSources, preferences: Preferences())
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    let first = try prepared.publish(in: folder)
    try Data("Keep me".utf8).write(to: first.appendingPathComponent("README.md"))
    let second = try prepared.publish(in: folder)
    #expect(first.lastPathComponent == "Notes" && second.lastPathComponent == "Notes 2")
    #expect(try String(contentsOf: first.appendingPathComponent("README.md"), encoding: .utf8) == "Keep me")
    #expect(try Data(contentsOf: second.appendingPathComponent("notes/Notes.md")).isEmpty)
    #expect(try second.appendingPathComponent("assets").resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["Notes", "Notes 2"])
}

@Test func fileSetPrecedenceAndSnapshotsPreserveExactContent() throws {
    let custom = try CustomTemplate(title: "Sample", suggestedName: "sample", fileExtension: "txt", content: Data("日本語\r\nExact\r\n".utf8))
    for master in [false, true] { for language in [false, true] { for policy in FolderStarterPolicy.allCases {
        var prefs = Preferences(); prefs.includeHelloWorld = master; prefs.languageChoices["rust"] = language
        var definition = FileSetDefinition.sourceFiles(.rust); definition.starterPolicy = policy
        definition.entries.append(.init(path: "sample.txt", templateID: TemplateSource.custom(custom).id))
        let prepared = try PreparedFileSet(definition: definition, sources: setSources + [.custom(custom)], preferences: prefs)
        definition.folderName = "Changed"; prefs.includeHelloWorld.toggle()
        #expect(prepared.folderName == "Rust files")
        #expect(prepared.items.first { $0.path == "src/main.rs" }?.data == Data((master && language && policy == .followSettings ? FileTemplate.rust.starter : "").utf8))
        #expect(prepared.items.last?.data == custom.content)
    } } }
}

@Test func fileSetRejectsUnsafeAndAmbiguousPaths() throws {
    for path in ["/absolute.txt", "../escape.txt", "a//b.txt", "a/./b.txt", "a/../b.txt", "a/.secret.txt", "a\\b.txt", "a:b.txt", "a\nb.txt", " file.txt", "file.txt ", "", String(repeating: "a/", count: 8) + "b.txt", String(repeating: "x", count: 121)] {
        let set = FileSetDefinition(entries: [.init(path: path, templateID: "builtin:text")])
        #expect(throws: (any Error).self) { try set.validate(sources: setSources) }
    }
    for entries in [
        [FileSetEntry(path: "same.txt", templateID: "builtin:text"), .init(path: "same.txt", templateID: "builtin:text")],
        [.init(path: "a.txt", templateID: "builtin:text"), .init(path: "a.txt/child.txt", templateID: "builtin:text")],
        [.init(path: "a.txt/child.txt", templateID: "builtin:text"), .init(path: "a.txt", templateID: "builtin:text")],
        [.init(path: "Source/a.txt", templateID: "builtin:text"), .init(path: "source/b.txt", templateID: "builtin:text")],
        [.init(path: "Café.txt", templateID: "builtin:text"), .init(path: "Cafe\u{301}.txt", templateID: "builtin:text")]
    ] {
        #expect(throws: FileSetError.self) { try FileSetDefinition(entries: entries).validate(sources: setSources) }
    }
    try FileSetDefinition(entries: [.init(path: "src/a.txt", templateID: "builtin:text"), .init(path: "src"), .init(path: "src/b.txt", templateID: "builtin:text")]).validate(sources: setSources)
}

@Test func fileSetRejectsMissingTemplatesAndWrongExtensions() throws {
    let missing = FileSetDefinition(entries: [.init(path: "a.txt", templateID: "custom:\(UUID())")])
    #expect(throws: FileSetError.self) { try PreparedFileSet(definition: missing, sources: setSources, preferences: Preferences()) }
    let wrong = FileSetDefinition(entries: [.init(path: "a.png", templateID: "builtin:pdf")])
    #expect(throws: FileSetError.self) { try PreparedFileSet(definition: wrong, sources: setSources, preferences: Preferences()) }
}

@Test func fileSetCreatesValidStructuredDocuments() throws {
    let folder = try setTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let definition = FileSetDefinition(entries: [.init(path: "data/config.json", templateID: "builtin:json"), .init(path: "document.pdf", templateID: "builtin:pdf")])
    let output = try PreparedFileSet(definition: definition, sources: setSources, preferences: Preferences()).publish(in: folder)
    #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("data/config.json"))) as? [String: String] == [:])
    #expect(CGPDFDocument(output.appendingPathComponent("document.pdf") as CFURL)?.numberOfPages == 1)
}

@Test func fileSetCancellationRemovesPartialStaging() async throws {
    let folder = try setTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let prepared = try PreparedFileSet(definition: .notes, sources: setSources, preferences: Preferences())
    let worker = Task.detached {
        try prepared.publish(in: folder) { completed, _ in
            if completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
        }
    }
    do { _ = try await worker.value; Issue.record("Cancelled work published a folder") } catch is CancellationError {} catch { throw error }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    let missing = folder.appendingPathComponent("unavailable")
    #expect(throws: ToolError.self) { try prepared.publish(in: missing) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
}

@Test func concurrentFileSetsAndSymlinkCollisionsNeverMerge() async throws {
    let folder = try setTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let outside = folder.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Notes"), withDestinationURL: outside)
    let prepared = try PreparedFileSet(definition: .notes, sources: setSources, preferences: Preferences())
    let names = try await withThrowingTaskGroup(of: String.self) { group in
        for _ in 0..<8 { group.addTask { try prepared.publish(in: folder).lastPathComponent } }
        var values: [String] = []; for try await name in group { values.append(name) }; return values
    }
    #expect(Set(names).count == 8 && !names.contains("Notes"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix(".cloaktools") }.isEmpty)
}

@Test func fileSetLibraryBoundsAndFailedWritesPreservePriorLibrary() throws {
    let folder = try setTestFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let store = FileSetStore(url: folder.appendingPathComponent("sets.json"))
    #expect(try store.load().isEmpty)
    let valid = FileSetDefinition.notes
    try store.save([valid]); #expect(try store.load() == [valid])
    let bytes = try Data(contentsOf: store.url)
    var invalid = valid; invalid.entries[0].path = "../escape.md"
    #expect(throws: FileSetError.self) { try store.save([invalid]) }
    #expect(throws: FileSetError.self) { try store.save([valid, valid]) }
    #expect(throws: FileSetError.self) { try store.save((0..<33).map { _ in .notes }) }
    invalid = valid; invalid.entries = []
    #expect(throws: FileSetError.self) { try store.save([invalid]) }
    invalid.entries = (0..<33).map { .init(path: "\($0).txt", templateID: "builtin:text") }
    #expect(throws: FileSetError.self) { try store.save([invalid]) }
    #expect(try Data(contentsOf: store.url) == bytes)
    try JSONEncoder().encode([invalid]).write(to: store.url)
    #expect(throws: FileSetError.self) { try store.load() }
    let custom = try CustomTemplate(title: "Large", suggestedName: "large", fileExtension: "txt", content: Data(repeating: 65, count: 1_048_576))
    let tooMuch = FileSetDefinition(entries: (0..<17).map { .init(path: "\($0).txt", templateID: TemplateSource.custom(custom).id) })
    #expect(throws: FileSetError.self) { try PreparedFileSet(definition: tooMuch, sources: [.custom(custom)], preferences: Preferences()) }
}
