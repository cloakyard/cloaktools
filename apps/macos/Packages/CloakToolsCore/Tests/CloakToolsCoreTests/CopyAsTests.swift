import Testing
import Foundation
@testable import CloakToolsCore

@Test func copyAsPreservesSelectionAndEncodesURLs() throws {
    let files = [URL(fileURLWithPath: "/tmp/Z # & ?.txt"), URL(fileURLWithPath: "/tmp/日本語 folder/A.swift")]
    let selection = try CopySelection(files: files)
    #expect(try selection.text(as: .paths) == files.map(\.path).joined(separator: "\n"))
    #expect(try selection.text(as: .names) == "Z # & ?.txt\nA.swift")
    let urls = try selection.text(as: .fileURLs).split(separator: "\n").compactMap { URL(string: String($0)) }
    #expect(urls == files)
    #expect(try selection.text(as: .fileURLs).contains("%23"))
    let json = try selection.text(as: .json)
    #expect(try JSONDecoder().decode([String].self, from: Data(json.utf8)) == files.map(\.path))
}

@Test func copyAsQuotesShellArgumentsWithoutRunningCode() throws {
    let files = [URL(fileURLWithPath: "/tmp/O'Brien $(touch never-run) `echo no`.txt"), URL(fileURLWithPath: "/tmp/a\nb.txt")]
    let selection = try CopySelection(files: files)
    #expect(try selection.text(as: .shellArguments) == "'/tmp/O'\\''Brien $(touch never-run) `echo no`.txt' '/tmp/a\nb.txt'")
    // Decode the narrow POSIX single-quote grammar as data; no shell is launched.
    let quoted = try selection.text(as: .shellArguments)
    var arguments: [String] = [], current = "", inside = false
    let characters = Array(quoted); var index = 0
    while index < characters.count {
        let character = characters[index]
        if character == "'" { inside.toggle() }
        else if character == "\\" && !inside { index += 1; current.append(characters[index]) }
        else if character == " " && !inside { arguments.append(current); current = "" }
        else { current.append(character) }
        index += 1
    }
    arguments.append(current)
    #expect(!inside && arguments == files.map(\.path))
}

@Test func copyAsMarkdownEscapesLabelsAndDestinations() throws {
    let file = URL(fileURLWithPath: "/tmp/[plan]_(draft)\n<final>.md")
    let result = try CopySelection(files: [file]).text(as: .markdown)
    #expect(result.hasPrefix("- [\\[plan\\]\\_(draft)\\\\n\\<final\\>.md](<file:///"))
    #expect(result.contains("%0A") && result.hasSuffix(">)"))
    #expect(!result.contains("\n"))
}

@Test func copyAsDoesNotReadOrResolveFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsCopy-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let missing = folder.appendingPathComponent("Does not exist.txt")
    let link = folder.appendingPathComponent("Symbolic link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)
    let selection = try CopySelection(files: [link, missing, folder])
    #expect(try selection.text(as: .paths) == [link.path, missing.path, folder.path].joined(separator: "\n"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Symbolic link"])
}

@Test func copyAsRejectsInvalidAndOversizedSelections() throws {
    #expect(throws: CopyAsError.self) { try CopySelection(files: []) }
    #expect(throws: CopyAsError.self) { try CopySelection(files: [URL(string: "https://example.com/file")!]) }
    #expect(throws: CopyAsError.self) { try CopySelection(files: [URL(string: "file://server/shared/file")!]) }
    #expect(throws: CopyAsError.self) { try CopySelection(files: [URL(string: "file:///tmp/file?query=yes")!]) }
    #expect(throws: CopyAsError.self) { try CopySelection(files: Array(repeating: URL(fileURLWithPath: "/tmp/a"), count: 201)) }
    let large = URL(fileURLWithPath: "/tmp/" + String(repeating: "#", count: 4_000))
    let selection = try CopySelection(files: Array(repeating: large, count: 200))
    #expect(throws: CopyAsError.self) { try selection.text(as: .markdown) }
}

@Test func copyAsIntentValidationAndOrder() throws {
    let intent = FinderIntent.copy(files: [URL(fileURLWithPath: "/tmp/B # & ?"), URL(fileURLWithPath: "/tmp/A")])
    #expect(try FinderIntent(url: intent.url) == intent)
    for raw in ["cloaktools-action://copy", "cloaktools-action://copy?path=relative", "cloaktools-action://copy?path=/a&unknown=/b", "cloaktools-action://copy?path=/a#extra", "cloaktools-action://user@copy?path=/a"] {
        #expect(throws: ToolError.self) { try FinderIntent(url: URL(string: raw)!) }
    }
    #expect(throws: ToolError.self) { try FinderIntent(url: FinderIntent.copy(files: Array(repeating: URL(fileURLWithPath: "/tmp/a"), count: 201)).url) }
}
