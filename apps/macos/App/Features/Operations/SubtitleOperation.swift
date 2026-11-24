import AVKit
import CloakToolsCore
import Speech
import SwiftUI
import Translation

struct SubtitleLanguage: Identifiable, Sendable {
    let id: String
    let installed: Bool
    var name: String { Self.name(id) }
    static func name(_ id: String) -> String { Locale.current.localizedString(forIdentifier: id) ?? id }

    static func sorted(_ languages: [Self]) -> [Self] {
        languages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func spoken() async -> [Self] {
        guard SpeechTranscriber.isAvailable else { return [] }
        let installed = Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })
        return sorted(await SpeechTranscriber.supportedLocales.map {
            let id = $0.identifier(.bcp47)
            return Self(id: id, installed: installed.contains(id))
        })
    }

    static func translations(from code: String) async -> [Self] {
        let availability = LanguageAvailability(preferredStrategy: .highFidelity)
        let source = Locale.Language(identifier: code)
        var choices: [Self] = []
        for id in Set(await availability.supportedLanguages.map(\.minimalIdentifier)) {
            if Task.isCancelled { return [] }
            let status = await availability.status(from: source, to: .init(identifier: id))
            if status != .unsupported, id != source.minimalIdentifier {
                choices.append(Self(id: id, installed: status == .installed))
            }
        }
        return sorted(choices)
    }
}

@MainActor @Observable
final class SubtitleOperation {
    struct TranslationJob: Identifiable {
        let id = UUID()
        let target: String
    }
    let task = FolderTask()
    private(set) var url: URL
    var player: AVPlayer?
    private(set) var media: PreparedMedia?
    var spokenLanguages: [SubtitleLanguage] = []
    var spoken = ""
    var cues: [SubtitleCue] = []
    var includeOriginal = true
    var selected = Set<String>()
    var translations: [String: [SubtitleCue]] = [:]
    var failures: [String: String] = [:]
    var reviewLanguage: String?
    var output: URL?
    var partialOutput: URL?
    var job: TranslationJob?
    private var queue: [String] = []
    var busy: Bool { task.busy || job != nil }
    var sourceCode: String { Locale.Language(identifier: spoken).minimalIdentifier }
    var pending: [String] { selected.filter { translations[$0] == nil }.sorted() }
    var hasText: Bool { !cues.isEmpty && cues.allSatisfy { !Subtitles.plainText($0.text).isEmpty } }
    var exportCount: Int { (includeOriginal ? 1 : 0) + selected.filter { translations[$0] != nil }.count }

    var firstEmptyTranslation: String? {
        selected.sorted().first { code in
            translations[code]?.contains { Subtitles.plainText($0.text).isEmpty } == true
        }
    }
    var canExport: Bool { hasText && exportCount > 0 && firstEmptyTranslation == nil }

    init(url: URL) {
        self.url = url
    }

    func chooseAnotherFile() {
        guard !busy, media == nil, let file = chooseMediaSource(title: "Generate subtitles") else { return }
        url = file
        prepare()
    }

    func prepare() {
        let input = url
        task.run("Opening media…", work: {
            async let languages = SubtitleLanguage.spoken()
            let media = try await MediaExport.prepareForSubtitles(input)
            let choices = await languages
            guard !choices.isEmpty else { throw SubtitleError.unavailableLanguage }
            return (media, choices)
        }) { media, choices in
            self.media = media
            self.player = AVPlayer(playerItem: AVPlayerItem(asset: MediaExport.localAsset(media.playbackURL)))
            self.player?.allowsExternalPlayback = false
            self.spokenLanguages = choices
            let preferred = Bundle.preferredLocalizations(from: choices.map(\.id)).first
            self.spoken = preferred ?? choices[0].id
        }
    }

    func generate() {
        guard !busy, cues.isEmpty, let media, let language = spokenLanguages.first(where: { $0.id == spoken }) else { return }
        player?.pause()
        let locale = Locale(identifier: spoken)
        task.run(language.installed ? "Listening to the audio…" : "Preparing the language and listening…", work: {
            try await Subtitles.transcribe(media, locale: locale)
        }) { self.cues = $0 }
    }

    func updateSource(at index: Int, to text: String) {
        guard !busy, output == nil, cues.indices.contains(index), cues[index].text != text else { return }
        cues[index].text = text
        translations.removeAll()
        failures.removeAll()
        reviewLanguage = nil
    }

    func chooseLanguages(_ targets: Set<String>, includeOriginal: Bool) {
        guard !busy else { return }
        self.includeOriginal = includeOriginal
        selected = targets
        failures = failures.filter { targets.contains($0.key) }
        if let reviewLanguage, !targets.contains(reviewLanguage) { self.reviewLanguage = nil }
        startTranslations()
    }

    func startTranslations() {
        guard !busy, output == nil, hasText else { return }
        task.notice = nil
        task.error = nil
        queue = pending
        advance()
    }

    private func advance() {
        job = queue.isEmpty ? nil : TranslationJob(target: queue.removeFirst())
    }

    func complete(_ current: TranslationJob, with result: Result<[SubtitleCue], Error>) {
        guard job?.id == current.id else { return }
        switch result {
        case .success(let captions):
            translations[current.target] = captions
            failures[current.target] = nil
            if reviewLanguage == nil { reviewLanguage = current.target }
        case .failure(let error):
            failures[current.target] = error.localizedDescription
        }
        advance()
    }

    func cancel() {
        task.cancel()
        if job != nil {
            queue.removeAll()
            job = nil
            task.notice = canExport ? "Translation stopped. You can export the completed tracks." : "Translation stopped."
        }
    }

    func finish() {
        cancel()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }

    func export() {
        guard !busy, canExport, output == nil,
              let folder = chooseFinderFolder("Save subtitles to…", startingAt: url.deletingLastPathComponent()) else { return }
        var tracks = translations.filter { selected.contains($0.key) }
        if includeOriginal { tracks[sourceCode] = cues }
        let snapshot = tracks, sourceURL = url
        task.run("Saving subtitles…", work: {
            try Subtitles.export(snapshot, source: sourceURL, in: folder)
        }) { folder in
            if self.pending.isEmpty { self.output = folder }
            else { self.partialOutput = folder }
        }
    }
}
