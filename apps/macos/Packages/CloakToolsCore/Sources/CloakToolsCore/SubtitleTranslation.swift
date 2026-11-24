import Foundation
import Translation

extension Subtitles {
    /// Translate bounded batches and match replies by cue ID, preserving the source timeline.
    public static func translate(_ cues: [SubtitleCue], using session: TranslationSession) async throws -> [SubtitleCue] {
        var result = cues
        for start in stride(from: 0, to: cues.count, by: 32) {
            try Task.checkCancellation()
            let range = start..<min(start + 32, cues.count)
            let requests = range.map { TranslationSession.Request(sourceText: cues[$0].text, clientIdentifier: String($0)) }
            let responses = try await session.translations(from: requests)
            try Task.checkCancellation()
            var remaining = Set(range)
            for response in responses {
                guard let id = response.clientIdentifier.flatMap(Int.init), remaining.remove(id) != nil else {
                    throw SubtitleError.incompleteTranslation
                }
                let text = plainText(response.targetText)
                guard !text.isEmpty else { throw SubtitleError.incompleteTranslation }
                result[id].text = text
            }
            guard remaining.isEmpty else { throw SubtitleError.incompleteTranslation }
        }
        return result
    }
}
