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

@MainActor @Test func subtitleCancellationNoticeReflectsWhatCanBeExported() throws {
    let review = SubtitleOperation(url: URL(fileURLWithPath: "/Clip.mp4"))
    review.spoken = "en-US"
    review.cues = [.init(start: 0, end: 1000, text: "Hello")]
    review.chooseLanguages(["es", "fr"], includeOriginal: false)
    review.cancel()
    #expect(!review.canExport)
    #expect(review.task.notice == "Translation stopped.")

    review.startTranslations()
    let spanish = try #require(review.job)
    review.complete(spanish, with: .success([.init(start: 0, end: 1000, text: "Hola")]))
    review.cancel()
    #expect(review.canExport && review.pending == ["fr"])
    #expect(review.task.notice == "Translation stopped. You can export the completed tracks.")
}
