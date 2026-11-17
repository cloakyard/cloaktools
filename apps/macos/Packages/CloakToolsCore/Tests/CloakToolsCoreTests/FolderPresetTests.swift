import Foundation
import Testing
import CoreGraphics
@testable import CloakToolsCore

private func presetFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsPresets-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
}

@Test func folderPresetHonorsEveryHelloWorldPrecedence() throws {
    let folder = try presetFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    for master in [false, true] { for language in [false, true] { for policy in FolderStarterPolicy.allCases {
        var prefs = Preferences(); prefs.includeHelloWorld = master; prefs.languageChoices["rust"] = language
        let preset = FolderPreset(title: "Rust", folder: folder, templateID: "builtin:rust", name: "main", starterPolicy: policy)
        let request = try preset.request(preferences: prefs, templates: [])
        let contents = try Data(contentsOf: request.perform())
        #expect(contents == Data((master && language && policy == .followSettings ? FileTemplate.rust.starter : "").utf8))
        #expect(prefs.includeHelloWorld == master && prefs.languageChoices["rust"] == language)
    } } }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 8)
}

@Test func folderPresetSnapshotsContentNameAndSettings() throws {
    let folder = try presetFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let custom = try CustomTemplate(title: "Note", suggestedName: "Original", fileExtension: "md", content: Data("# Exact\r\n日本語\r\n".utf8))
    var preset = FolderPreset(title: "Notes", folder: folder, templateID: TemplateSource.custom(custom).id, name: "Review", starterPolicy: .blank)
    let request = try preset.request(preferences: Preferences(), templates: [custom])
    preset.name = "Changed"; preset.folder = folder.appendingPathComponent("missing")
    let output = try request.perform()
    #expect(output.lastPathComponent == "Review.md")
    #expect(try Data(contentsOf: output) == custom.content)
    #expect(throws: FolderPresetError.self) { try preset.request(preferences: Preferences(), templates: []) }
}

@Test func folderPresetStructuredFilesStayValid() throws {
    let folder = try presetFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let pdf = FolderPreset(title: "PDF", folder: folder, templateID: "builtin:pdf", starterPolicy: .blank)
    let document = try #require(CGPDFDocument(pdf.request(preferences: Preferences(), templates: []).perform() as CFURL))
    #expect(document.numberOfPages == 1)
    let json = FolderPreset(title: "JSON", folder: folder, templateID: "builtin:json", starterPolicy: .blank)
    let bytes = try Data(contentsOf: json.request(preferences: Preferences(), templates: []).perform())
    #expect((try JSONSerialization.jsonObject(with: bytes) as? [String: String]) == [:])
}

@Test func folderPresetLibraryRoundTripsAndRejectsUnsafeChanges() throws {
    let folder = try presetFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let store = FolderPresetStore(url: folder.appendingPathComponent("presets.json"))
    #expect(try store.load().isEmpty)
    let valid = FolderPreset(title: "Scratchpad", folder: folder, templateID: "builtin:cpp", name: "main")
    try store.save([valid]); #expect(try store.load() == [valid])
    let bytes = try Data(contentsOf: store.url)
    var invalid = valid; invalid.name = "../escape"
    #expect(throws: ToolError.self) { try store.save([invalid]) }
    invalid = valid; invalid.folder = URL(string: "https://example.com/folder")!
    #expect(throws: FolderPresetError.self) { try store.save([invalid]) }
    invalid = valid; invalid.templateID = "builtin:unknown"
    #expect(throws: FolderPresetError.self) { try store.save([invalid]) }
    invalid = valid; invalid.title = "\nUnsafe"
    #expect(throws: FolderPresetError.self) { try store.save([invalid]) }
    #expect(throws: FolderPresetError.self) { try store.save([valid, valid]) }
    #expect(throws: FolderPresetError.self) { try store.save((0..<33).map { FolderPreset(title: "Preset \($0)", folder: folder) }) }
    #expect(try Data(contentsOf: store.url) == bytes)
    try JSONEncoder().encode([invalid]).write(to: store.url)
    #expect(throws: FolderPresetError.self) { try store.load() }
}

@Test func missingPresetFolderIsReviewableButCannotPublish() throws {
    let folder = try presetFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let preset = FolderPreset(title: "Unavailable", folder: folder.appendingPathComponent("missing"))
    let request = try preset.request(preferences: Preferences(), templates: [])
    #expect(throws: ToolError.self) { try request.perform() }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
}
