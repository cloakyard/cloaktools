import Darwin
import Foundation
import Testing
@testable import CloakToolsCore

private func fixture(_ test: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try test(root)
}

private func folder(_ root: URL, _ path: String) throws -> URL {
    let url = root.appendingPathComponent(path, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func file(_ root: URL, _ path: String, _ bytes: String) throws -> URL {
    let url = root.appendingPathComponent(path, isDirectory: false)
    try Data(bytes.utf8).write(to: url)
    return url
}

@Test func folderStructureRecreatesSelectedEmptyFoldersAndSavesAReusableDefinition() throws {
    try fixture { root in
        let source = try folder(root, "Client A")
        for path in ["Assets/Photos", "Assets Archive", "Briefs", "Deliverables", ".hidden/Child", "Example.app/Contents"] { _ = try folder(source, path) }
        _ = try file(source, "Assets/Photos/private.jpg", "original")
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("Linked"), withDestinationURL: root)
        let tree = try FolderStructure(from: source)
        #expect(tree.paths == ["Assets", "Assets/Photos", "Assets Archive", "Briefs", "Deliverables"])
        let selected: Set<String> = ["Briefs", "Assets/Photos"]
        let result = try tree.create(named: "New Client", selected: selected, in: root)
        #expect(try FolderStructure(from: result).paths == ["Assets", "Assets/Photos", "Briefs"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: result.appendingPathComponent("Assets/Photos").path).isEmpty)
        let definition = try tree.definition(named: "New Client", selected: Set(["Assets"]).union(selected))
        let store = FileSetStore(url: root.appendingPathComponent("sets.json"))
        try store.save([definition])
        let saved = try #require(store.load().first)
        #expect(saved.entries.map(\.path) == ["Assets/Photos", "Briefs"])
        let second = try PreparedFileSet(definition: saved, sources: [], preferences: .init()).publish(in: root)
        #expect(second.lastPathComponent == "New Client 2")
        #expect(throws: FolderWorkflowError.self) { try tree.create(named: "Bad", selected: ["../escape"], in: root) }
    }
}

@Test func structureSupportsMoreFoldersThanASavedFileSet() throws {
    try fixture { root in
        let source = try folder(root, "Source")
        for i in 1...33 { _ = try folder(source, "Part \(i)") }
        let structure = try FolderStructure(from: source)
        let all = Set(structure.paths)
        #expect(throws: FileSetError.self) { try structure.definition(named: "Template", selected: all) }
        let output = try structure.create(named: "Project", selected: all, in: root)
        #expect(try FolderStructure(from: output).paths.count == 33)
    }
}

@Test func collectionAccumulatesAcrossFoldersAndResolvesCopyNames() throws {
    try fixture { root in
        let first = try file(folder(root, "Downloads"), "receipt.pdf", "first")
        let second = try file(folder(root, "Desktop"), "Receipt.pdf", "second")
        var items = try SharingCollection.adding([first], to: [])
        items = try SharingCollection.adding([second, first], to: items)
        #expect(items.map(\.name) == ["receipt.pdf", "Receipt 2.pdf"])
        items[1].name = "RECEIPT.pdf"
        #expect(throws: FolderWorkflowError.self) { try SharingCollection.validate(items) }
        items[1].name = "../escape"
        #expect(throws: FolderWorkflowError.self) { try SharingCollection.validate(items) }
        items[1].name = "Travel.pdf"
        _ = try folder(root, "Shared")
        let output = try SharingCollection.save(items, named: "Shared", in: root)
        #expect(output.lastPathComponent == "Shared 2")
        #expect(try Data(contentsOf: output.appendingPathComponent("Travel.pdf")) == Data(contentsOf: second))
        #expect(try Data(contentsOf: output.appendingPathComponent("receipt.pdf")) == Data(contentsOf: first))
    }
}

@Test func changedOrUnavailableCollectionSourceRollsBackTheFolder() throws {
    try fixture { root in
        let output = try folder(root, "Output")
        let a = try file(root, "one", "ok"), b = try file(root, "two", "before")
        let items = try SharingCollection.adding([a, b], to: [])
        try Data("after!".utf8).write(to: b)
        #expect(throws: FolderWorkflowError.self) { try SharingCollection.save(items, named: "Copies", in: output) }
        try FileManager.default.removeItem(at: b)
        try FileManager.default.createSymbolicLink(at: b, withDestinationURL: a)
        #expect(throws: FolderWorkflowError.self) { try SharingCollection.save(items, named: "Copies", in: output) }
        #expect(throws: FolderWorkflowError.self) { try SharingCollection.adding([b], to: []) }
        #expect(throws: FolderWorkflowError.self) { try SharingCollection.adding([root], to: []) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path).isEmpty)
    }
}

@Test func comparisonChecksEqualLengthContentsTypesMissingFilesAndLinkTargets() throws {
    try fixture { root in
        let a = try folder(root, "Working"), b = try folder(root, "Backup")
        for side in [a, b] {
            _ = try folder(side, "Nested/Empty")
            _ = try file(side, "Nested/Same", "same")
            _ = try file(side, "Nested/Changed", side == a ? "aa" : "ab")
            try FileManager.default.createSymbolicLink(atPath: side.appendingPathComponent("Link").path, withDestinationPath: side == a ? "missing-a" : "missing-b")
            try FileManager.default.createSymbolicLink(atPath: side.appendingPathComponent("Loop").path, withDestinationPath: ".")
        }
        _ = try folder(a, "Type")
        _ = try file(b, "Type", "")
        _ = try file(a, ".hidden", "private")
        _ = try file(b, "Extra", "extra")
        let result = try FolderComparison(a, b)
        let kinds = Dictionary(uniqueKeysWithValues: result.differences.map { ($0.path, $0.kind) })
        #expect(kinds == [".hidden": .leftOnly, "Extra": .rightOnly, "Link": .changed, "Nested/Changed": .changed, "Type": .type])
        #expect(result.checked == 9)
        #expect(throws: FolderWorkflowError.self) { try FolderComparison(a, a) }
        try FileManager.default.removeItem(at: b)
        #expect(throws: (any Error).self) { try FolderComparison(a, b) }
    }
}

@Test func comparisonReadsAndCollectionPreservesResourceForks() throws {
    try fixture { root in
        let first = try folder(root, "First"), second = try folder(root, "Second")
        let a = try file(first, "Receipt", "main"), b = try file(second, "Receipt", "main")
        func writeFork(_ url: URL, _ value: String) throws {
            let data = Data(value.utf8)
            let status = data.withUnsafeBytes { setxattr(url.path, "com.apple.ResourceFork", $0.baseAddress, $0.count, 0, 0) }
            if status != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        #expect(try FolderComparison(first, second).differences.isEmpty)
        try writeFork(a, "aaaa")
        try writeFork(b, "bbbb")
        #expect(try FolderComparison(first, second).differences.first?.kind == .changed)
        let copies = try SharingCollection.save(SharingCollection.adding([a], to: []), named: "Copies", in: root)
        #expect(try FolderComparison(first, copies).differences.isEmpty)
    }
}

@Test func comparisonRejectsSpecialFilesAndSupportsCancellation() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try folder(root, "First"), second = try folder(root, "Second")
    #expect(mkfifo(first.appendingPathComponent("Pipe").path, 0o600) == 0)
    #expect(throws: FolderWorkflowError.self) { try FolderComparison(first, second) }
    try FileManager.default.removeItem(at: first.appendingPathComponent("Pipe"))
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try FolderComparison(first, second)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func finderReviewIntentsRoundTripSpecialCharactersAndEnforceSelectionCounts() throws {
    try fixture { root in
        let a = try folder(root, "A & B"), b = try folder(root, "日本語 #2")
        let photo = try file(root, "25% + &.png", "sample")
        let intents: [FinderIntent] = [.fit(image: photo), .structure(folder: a), .collect(files: [photo]), .compare(first: a, second: b)]
        for intent in intents { #expect(try FinderIntent(url: intent.url) == intent) }
        for value in ["compare?path=/a", "compare?path=/a&path=/a", "compare?path=/a&path=/b&path=/c", "fit?path=/a&path=/b",
                      "structure?path=relative", "collect?path=/a&other=/b"] {
            let url = try #require(URL(string: "cloaktools-action://" + value))
            #expect(throws: ToolError.self) { try FinderIntent(url: url) }
        }
    }
}

@Test func contextualFinderMenuOffersOnlyActionsForTheSelection() throws {
    try fixture { root in
        let first = try folder(root, "Demo.png"), second = try folder(root, "Backup")
        let image = try file(root, "Photo.HEIC", "image"), note = try file(root, "Receipt", "receipt")
        let link = root.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: image)
        func actions(_ urls: [URL]) -> [FinderIntent] { FinderIntent.reviewActions(for: urls).map(\.intent) }
        #expect(actions([first]) == [.structure(folder: first)])
        #expect(actions([first, second]) == [.compare(first: first, second: second)])
        #expect(actions([image]) == [.fit(image: image), .collect(files: [image])])
        #expect(actions([note, image]) == [.collect(files: [note, image])])
        #expect(actions([note, first]).isEmpty)
        #expect(actions([link]).isEmpty)
        #expect(actions(Array(repeating: note, count: 201)).isEmpty)
    }
}
