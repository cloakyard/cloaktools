import AVFoundation
import Foundation
import Speech

/// Speech limits how many locales an app can reserve. Release after the last draft using a locale finishes.
private actor SubtitleSpeechAssets {
    static let shared = SubtitleSpeechAssets()
    private var users: [Locale: Int] = [:]
    private var releases: [Locale: Task<Void, Never>] = [:]

    func using<Value: Sendable>(_ locale: Locale, run: @Sendable () async throws -> Value) async rethrows -> Value {
        users[locale, default: 0] += 1
        await releases[locale]?.value
        defer {
            if users[locale] == 1 {
                users[locale] = nil
                releases[locale] = Task { _ = await AssetInventory.release(reservedLocale: locale) }
            } else {
                users[locale, default: 1] -= 1
            }
        }
        return try await run()
    }
}

extension Subtitles {
    public static func transcribe(_ media: PreparedMedia, locale: Locale) async throws -> [SubtitleCue] {
        guard media.hasAudio else { throw SubtitleError.noAudio }
        return try await SubtitleSpeechAssets.shared.using(locale) {
            try Task.checkCancellation()
            return try await recognize(media, locale: locale)
        }
    }

    private static func recognize(_ media: PreparedMedia, locale: Locale) async throws -> [SubtitleCue] {
        let module = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await withTaskCancellationHandler {
                try await installation.downloadAndInstall()
            } onCancel: { installation.progress.cancel() }
        }
        try Task.checkCancellation()
        let asset = MediaExport.localAsset(media.playbackURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw SubtitleError.noAudio }
        let input = try await AssetInputSequenceProvider.provider(from: asset, track: track, compatibleWith: [module])
        let analyzer = SpeechAnalyzer(modules: [module])
        return try await withTaskCancellationHandler {
            async let captions = collect(module, duration: media.duration)
            do {
                if let end = try await analyzer.analyzeSequence(input.analyzerInputs) {
                    try await analyzer.finalizeAndFinish(through: end)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let result = try await captions
                try Task.checkCancellation()
                guard !result.isEmpty else { throw SubtitleError.noSpeech }
                return result
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: { Task { await analyzer.cancelAndFinishNow() } }
    }

    private static func collect(_ module: SpeechTranscriber, duration: Double) async throws -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let limit = Int((duration * 1000).rounded())
        for try await result in module.results where result.isFinal {
            try Task.checkCancellation()
            var group = ""
            var first = 0, last = 0
            func flush() {
                let text = plainText(group)
                let start = max(cues.last?.end ?? 0, first)
                let end = min(last, limit)
                if !text.isEmpty, end > start { cues.append(.init(start: start, end: end, text: text)) }
                group = ""
            }
            var hasTime = false
            for run in result.text.runs {
                let part = String(result.text[run.range].characters)
                guard let time = run.audioTimeRange, time.start.seconds.isFinite, time.end.seconds.isFinite else {
                    group += part
                    continue
                }
                let start = Int((time.start.seconds * 1000).rounded())
                let end = Int((time.end.seconds * 1000).rounded())
                if hasTime && (start - last >= 800 || end - first > 6000 || group.count + part.count > 80) {
                    flush()
                    hasTime = false
                }
                if !hasTime { first = start }
                hasTime = true
                last = end
                group += part
            }
            if !hasTime, result.range.start.seconds.isFinite, result.range.end.seconds.isFinite {
                first = Int((result.range.start.seconds * 1000).rounded())
                last = Int((result.range.end.seconds * 1000).rounded())
            }
            flush()
        }
        return cues
    }
}
