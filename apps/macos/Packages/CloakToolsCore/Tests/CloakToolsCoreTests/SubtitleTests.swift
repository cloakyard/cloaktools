import Foundation
import Testing
@testable import CloakToolsCore

@Test func subtitlesPreserveUnicodeAndTimeWithoutAcceptingInjectedCueBreaks() throws {
    let text = "  Hi\r\n\r\n\u{0000}👨‍👩‍👧‍👦   नमस्ते  "
    let cue = SubtitleCue(start: 3_599_999, end: 3_600_005, text: text)
    let srt = String(decoding: try Subtitles.srt([cue]), as: UTF8.self)
    #expect(srt == "1\n00:59:59,999 --> 01:00:00,005\nHi\n👨‍👩‍👧‍👦 नमस्ते\n\n")
    #expect(throws: SubtitleError.self) { try Subtitles.srt([]) }
    #expect(throws: SubtitleError.self) { try Subtitles.srt([cue, cue]) }
    #expect(throws: SubtitleError.self) { try Subtitles.srt([SubtitleCue(start: -1, end: 1, text: "Hi")]) }
    #expect(throws: SubtitleError.self) { try Subtitles.srt([SubtitleCue(start: 1, end: 1, text: "Hi")]) }
    #expect(throws: SubtitleError.self) { try Subtitles.srt([SubtitleCue(start: 0, end: 1, text: " \n ")]) }
}

@Test func subtitleExportPublishesCompleteLanguageSetsAndPreservesExistingFiles() throws {
    let fm = FileManager.default
    let parent = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fm.createDirectory(at: parent, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: parent) }
    let source = parent.appendingPathComponent("Clip.mp4")
    let cues = [SubtitleCue(start: 410, end: 1920, text: "One.")]
    let tracks = ["en": cues, "hi": [SubtitleCue(start: 410, end: 1920, text: "एक।")]]
    let first = try Subtitles.export(tracks, source: source, in: parent)
    #expect(first.lastPathComponent == "Clip subtitles")
    #expect(try Set(fm.contentsOfDirectory(atPath: first.path)) == ["Clip.en.srt", "Clip.hi.srt"])
    let second = try Subtitles.export(tracks, source: source, in: parent)
    #expect(second.lastPathComponent == "Clip subtitles 2")
    #expect(throws: ToolError.self) { try Subtitles.export(["en": cues, "../xx": cues], source: source, in: parent) }
    #expect(throws: SubtitleError.self) { try Subtitles.export(["en": cues, "fr": []], source: source, in: parent) }
    let mistimed = [SubtitleCue(start: 0, end: 1500, text: "Bonjour")]
    #expect(throws: SubtitleError.self) { try Subtitles.export(["en": cues, "fr": mistimed], source: source, in: parent) }
    #expect(try Set(fm.contentsOfDirectory(atPath: parent.path)) == ["Clip subtitles", "Clip subtitles 2"])
}

@Test func subtitleGenerationRejectsSilentVideoTracksBeforeRequestingSpeechAssets() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let video = folder.appendingPathComponent("Silent.mov")
    try await MediaFixtures.movie(video)
    await #expect(throws: SubtitleError.noAudio) { try await MediaExport.prepareForSubtitles(video) }
    let prepared = try await MediaExport.prepare(video)
    await #expect(throws: SubtitleError.noAudio) { try await Subtitles.transcribe(prepared, locale: .current) }
}

@Test func concurrentSubtitleExportsKeepEachLanguageSetTogether() async throws {
    let fm = FileManager.default
    let destination = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let existing = destination.appendingPathComponent("Clip subtitles")
    try fm.createDirectory(at: existing, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: destination) }
    let marker = existing.appendingPathComponent("keep.txt")
    try Data("Existing folder".utf8).write(to: marker)
    let source = destination.appendingPathComponent("Clip.mp4")
    let folders = try await withThrowingTaskGroup(of: URL.self) { group in
        for index in 0..<8 {
            group.addTask {
                let en = [SubtitleCue(start: 0, end: 1000, text: "Hello \(index)")]
                let fr = [SubtitleCue(start: 0, end: 1000, text: "Bonjour \(index)")]
                let folder = try Subtitles.export(["en": en, "fr": fr], source: source, in: destination)
                #expect(try Data(contentsOf: folder.appendingPathComponent("Clip.en.srt")) == Subtitles.srt(en))
                #expect(try Data(contentsOf: folder.appendingPathComponent("Clip.fr.srt")) == Subtitles.srt(fr))
                return folder
            }
        }
        var published = Set<URL>()
        for try await path in group { published.insert(path) }
        return published
    }
    #expect(folders.count == 8)
    #expect(try fm.contentsOfDirectory(atPath: destination.path).count == 9)
    #expect(try fm.contentsOfDirectory(atPath: existing.path) == ["keep.txt"])
    #expect(try Data(contentsOf: marker) == Data("Existing folder".utf8))
}
