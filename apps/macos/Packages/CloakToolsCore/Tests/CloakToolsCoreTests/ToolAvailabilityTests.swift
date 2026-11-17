import Foundation
import Testing
@testable import CloakToolsCore

@Test func freshToolsStartWithEverydayAndRetainCompletedChoice() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = PreferencesStore(url: folder.appendingPathComponent("preferences.json"))
    var preferences = try store.load()
    #expect(!preferences.developerToolsEnabled && !preferences.hasChosenTools)
    #expect(!FileManager.default.fileExists(atPath: store.url.path))
    preferences.hasChosenTools = true
    try store.save(preferences)
    let reopened = try store.load()
    #expect(reopened.hasChosenTools && !reopened.developerToolsEnabled)
}

@Test func legacyToolsMigrationKeepsCatalogAndLanguageChoices() throws {
    let data = Data(#"{"includeHelloWorld":true,"languageChoices":{"rust":false,"cpp":true},"lastCategory":"newFiles","revealCreatedFile":false,"favoriteTemplateIDs":["builtin:rust"]}"#.utf8)
    let legacy = try JSONDecoder().decode(Preferences.self, from: data)
    #expect(legacy.developerToolsEnabled && legacy.hasChosenTools)
    #expect(legacy.includeHelloWorld && legacy.languageChoices["rust"] == false)
    #expect(legacy.favoriteTemplateIDs == ["builtin:rust"] && !legacy.revealCreatedFile)
    #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(legacy)) == legacy)
}

@Test func toolCatalogSeparatesTechnicalChoicesFromEverydayUtilities() {
    let everyday = ToolAvailability(developerEnabled: false), all = ToolAvailability(developerEnabled: true)
    #expect(everyday.builtInTemplates == [.text, .markdown, .pdf])
    #expect(everyday.copyFormats == [.paths, .names, .fileURLs, .markdown])
    #expect(!everyday.categories.contains(.developer))
    #expect(everyday.categories.contains(.conversions) && everyday.categories.contains(.openWith))
    #expect(all.builtInTemplates == FileTemplate.allCases && all.copyFormats == CopyFormat.allCases)
    #expect(all.builtInTemplates.filter(\.isProgramming).count == 13)
    #expect(all.categories == SettingsCategory.allCases)
}

@Test func disablingToolsPreservesExistingOperationAndStoredChoices() throws {
    var preferences = Preferences()
    preferences.developerToolsEnabled = true; preferences.hasChosenTools = true
    preferences.includeHelloWorld = true; preferences.languageChoices["rust"] = false
    preferences.favoriteTemplateIDs = ["builtin:rust"]; preferences.lastCategory = .developer
    let snapshot = preferences
    preferences.developerToolsEnabled = false; preferences.normalizeToolSelection()
    #expect(preferences.lastCategory == .general && preferences.includeHelloWorld)
    #expect(preferences.languageChoices == snapshot.languageChoices && preferences.favoriteTemplateIDs == snapshot.favoriteTemplateIDs)
    #expect(snapshot.tools.builtInTemplates.contains(.rust) && !preferences.tools.builtInTemplates.contains(.rust))
    preferences.developerToolsEnabled = true
    #expect(!preferences.usesStarter(for: .rust) && preferences.usesStarter(for: .cpp))
    #expect(try FileTemplate.rust.contents(using: snapshot).isEmpty)
}

@Test func disabledDeveloperCategoryRestoresToGeneralOnDecode() throws {
    let data = Data(#"{"developerToolsEnabled":false,"hasChosenTools":true,"lastCategory":"developer"}"#.utf8)
    let decoded = try JSONDecoder().decode(Preferences.self, from: data)
    #expect(decoded.lastCategory == .general && !decoded.developerToolsEnabled && decoded.hasChosenTools)
}

@Test func savedWorkflowVisibilityUsesMetadataAndDoesNotMutateLibraries() throws {
    let code = try CustomTemplate(title: "Code", suggestedName: "Code", fileExtension: "TSX", content: Data("sample".utf8))
    let note = try CustomTemplate(title: "Note", suggestedName: "Note", fileExtension: "txt", content: Data("{\"code\": \"still a note\"}".utf8))
    let sources = FileTemplate.allCases.map(TemplateSource.builtIn) + [.custom(code), .custom(note)]
    let everyday = ToolAvailability(developerEnabled: false)
    #expect(!everyday.includes(.custom(code)) && everyday.includes(.custom(note)))
    #expect(everyday.includes(.notes, sources: sources))
    #expect(!everyday.includes(.sourceFiles(.rust), sources: sources))
    #expect(!everyday.includes(templateID: TemplateSource.custom(code).id, sources: sources))
    let set = FileSetDefinition(entries: [.init(path: "note.txt", templateID: TemplateSource.custom(note).id), .init(path: "src/code.tsx", templateID: TemplateSource.custom(code).id)])
    #expect(!everyday.includes(set, sources: sources))
    #expect(ToolAvailability(developerEnabled: true).includes(set, sources: sources))
    // Missing custom references remain visible for repair, not silently deleted.
    #expect(everyday.includes(templateID: "custom:missing", sources: sources))
    #expect(sources.count == 19 && set.entries.count == 2 && code.content == Data("sample".utf8))
}
