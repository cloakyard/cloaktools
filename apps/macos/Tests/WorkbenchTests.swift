import SwiftUI
import Testing
import CloakToolsCore
@testable import CloakTools

@Test func workbenchCatalogFindsOutcomesAndHonorsToolSelection() {
    #expect(WorkbenchTool.matching("shrink photo", developerEnabled: false) == [.fit])
    #expect(WorkbenchTool.matching("MERGE pdf", developerEnabled: false) == [.pdf])
    #expect(!WorkbenchTool.matching("json", developerEnabled: false).contains(.json))
    #expect(WorkbenchTool.matching("shell arguments", developerEnabled: false).isEmpty)
    #expect(WorkbenchTool.matching("shell arguments", developerEnabled: true) == [.copy])
    #expect(WorkbenchTool.matching("pretty print", developerEnabled: true) == [.json])
    #expect(Set(WorkbenchCategory.allCases.flatMap(\.tools)) == Set(WorkbenchTool.allCases))
}

@MainActor @Test func independentFinderRequestsPreserveAnOpenDraft() {
    let navigation = WorkbenchNavigation()
    var busy = true
    var finishes = 0
    navigation.showWindow = {}
    navigation.browse(.media)
    #expect(navigation.present(.pdf, busy: { busy }, finish: { finishes += 1 }) { _ in Text("First selection") })
    #expect(navigation.category == .media)
    #expect(navigation.page == .pdf)
    navigation.browse(.files)
    #expect(navigation.drafts[.pdf] != nil)
    #expect(!navigation.present(.pdf) { _ in Text("Second selection") })
    #expect(navigation.page == nil)
    #expect(navigation.hasBusyDraft)
    navigation.close(.pdf)
    #expect(finishes == 0)
    busy = false
    navigation.show(.pdf)
    navigation.close(.pdf)
    #expect(navigation.drafts.isEmpty)
    #expect(navigation.page == nil)
    #expect(finishes == 1)
}

@Test func folderReviewIncludesImplicitParentsAndExactSizes() throws {
    let prepared = try PreparedFileSet(definition: .notes, sources: [.builtIn(.markdown)], preferences: Preferences())
    let rows = FileSetReviewItem.outline(prepared)
    #expect(rows.map(\.path) == ["README.md", "assets", "notes", "notes/Notes.md"])
    #expect(rows.map(\.depth) == [0, 0, 0, 1])
    #expect(rows.map(\.bytes) == [0, nil, nil, 0])
}
