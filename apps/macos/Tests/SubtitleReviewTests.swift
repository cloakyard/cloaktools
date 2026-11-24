import CloakToolsCore
import Foundation
import Testing
@testable import CloakTools

@MainActor @Test func subtitleReviewKeepsCompletedLanguagesOnFailureAndIgnoresCancelledReplies() throws {
    #expect(WorkbenchTool.matching("srt", developerEnabled: false) == [.subtitles])
    let operation = SubtitleOperation(url: URL(fileURLWithPath: "/Clip.mp4"))
    operation.spoken = "en-US"
    operation.cues = [.init(start: 0, end: 2000, text: "Hello")]
    operation.chooseLanguages(["fr", "es"], includeOriginal: true)
    let spanish = try #require(operation.job)
    #expect(spanish.target == "es")
    operation.complete(spanish, with: .success([.init(start: 0, end: 2000, text: "Hola")]))
    let french = try #require(operation.job)
    operation.complete(french, with: .failure(SubtitleError.incompleteTranslation))
    #expect(operation.pending == ["fr"] && operation.canExport && operation.exportCount == 2)
    operation.startTranslations()
    let retry = try #require(operation.job)
    operation.cancel()
    operation.complete(retry, with: .success(operation.cues))
    #expect(operation.translations["fr"] == nil && operation.translations["es"] != nil)
    operation.chooseLanguages(["es"], includeOriginal: false)
    #expect(operation.exportCount == 1 && operation.canExport && operation.job == nil)
    operation.translations["es"]?[0].text = ""
    #expect(!operation.canExport && operation.firstEmptyTranslation == "es")
    operation.updateSource(at: 0, to: "Hello again")
    #expect(operation.translations.isEmpty && operation.pending == ["es"])
    #expect(operation.reviewLanguage == nil && !operation.canExport)
}
