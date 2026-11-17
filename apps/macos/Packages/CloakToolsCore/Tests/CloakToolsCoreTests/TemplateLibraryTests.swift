import Testing
import Foundation
import CoreGraphics
@testable import CloakToolsCore

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func migratesExistingPreferencesWithoutLosingChoices() throws {
    let previous = Data(#"{"includeHelloWorld":true,"languageChoices":{"rust":false},"lastCategory":"newFiles","revealCreatedFile":false,"revealConvertedFile":true}"#.utf8)
    let decoded = try JSONDecoder().decode(Preferences.self, from: previous)
    #expect(decoded.includeHelloWorld && !decoded.openAfterCreation)
    #expect(decoded.languageChoices["rust"] == false && decoded.favoriteTemplateIDs.isEmpty)
    #expect(decoded.lastCategory == .newFiles && !decoded.revealCreatedFile)
    var changed = decoded; changed.favoriteTemplateIDs.insert("builtin:pdf"); changed.openAfterCreation = true
    #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(changed)) == changed)
}

@Test func structuredDocumentsAreValidWithEitherMasterSetting() throws {
    let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    for master in [false, true] {
        var prefs = Preferences(); prefs.includeHelloWorld = master
        let pdfURL = try CreationRequest(folder: folder, template: .pdf, preferences: prefs).perform()
        let document = try #require(CGPDFDocument(pdfURL as CFURL))
        #expect(document.numberOfPages == 1)
        let page = try #require(document.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        #expect(abs(box.width - 595.276) < 0.01 && abs(box.height - 841.89) < 0.01)
        let jsonURL = try CreationRequest(folder: folder, template: .json, preferences: prefs).perform()
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any]
        #expect(object?.isEmpty == true)
    }
}

@Test func importsExactContentAndSnapshotsSurviveEditsAndRemoval() throws {
    let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("Daily note.md")
    let bytes = Data("# Daily note\r\n\r\n日本語 — café\r\n".utf8)
    try bytes.write(to: input)
    let original = try CustomTemplate.importing(input)
    #expect(original.content == bytes && original.fileExtension == "md")
    let store = TemplateLibraryStore(url: folder.appendingPathComponent("library.json"))
    try store.save([original])
    let snapshot = try #require(store.load().first)
    let request = CreationRequest(folder: folder, source: .custom(snapshot), preferences: Preferences(), name: "Created note")
    try Data("external source changed".utf8).write(to: input)
    var renamed = original; renamed.title = "Renamed"; renamed.suggestedName = "Other"
    try store.save([renamed]); #expect(try store.load().first?.title == "Renamed")
    try store.save([])
    #expect(try Data(contentsOf: request.perform()) == bytes)
    #expect(try String(contentsOf: input, encoding: .utf8) == "external source changed")
}

@Test func rejectsUnsafeAndOversizedTemplatesBeforeSaving() throws {
    #expect(throws: TemplateError.self) { try CustomTemplate(title: "Binary", suggestedName: "File", fileExtension: "txt", content: Data([0xff, 0x00])) }
    #expect(throws: TemplateError.self) { try CustomTemplate(title: "Large", suggestedName: "File", fileExtension: "txt", content: Data(repeating: 65, count: 1_048_577)) }
    #expect(throws: TemplateError.self) { try CustomTemplate(title: "Escape", suggestedName: "../escape", fileExtension: "txt", content: Data()) }
    #expect(throws: TemplateError.self) { try CustomTemplate(title: "Escape", suggestedName: "File", fileExtension: "../sh", content: Data()) }
    let folder = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let store = TemplateLibraryStore(url: folder.appendingPathComponent("library.json"))
    let valid = try CustomTemplate(title: "Valid", suggestedName: "File", fileExtension: "txt", content: Data())
    try store.save([valid])
    #expect(throws: TemplateError.self) { try store.save([valid, valid]) }
    #expect(try store.load() == [valid])
    var invalid = valid; invalid.suggestedName = "bad/name"
    // Decoder must not bypass validation for modified library files.
    try JSONEncoder().encode([invalid]).write(to: store.url)
    #expect(throws: TemplateError.self) { try store.load() }
}

@Test func templateFinderIntentRoundTrips() throws {
    let intent = FinderIntent.templates(folder: URL(fileURLWithPath: "/tmp/a & ?/"))
    #expect(try FinderIntent(url: intent.url) == intent)
    #expect(throws: ToolError.self) { try FinderIntent(url: URL(string: "cloaktools-action://templates?path=/tmp&template=python")!) }
}
