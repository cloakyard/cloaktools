import Foundation

public struct SubtitleCue: Sendable, Equatable, Identifiable {
    public let start: Int
    public let end: Int
    public var text: String
    public var id: Int { start }

    public init(start: Int, end: Int, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    public var needsShortening: Bool {
        let length = text.count
        return length > 84 || (length > 20 && Double(length) > Double(end - start) * 0.020)
    }
}

public enum SubtitleError: LocalizedError {
    case noAudio, noSpeech, invalidCue, incompleteTranslation, unavailableLanguage
    public var errorDescription: String? {
        switch self {
        case .noAudio: "This file has no audio track. Choose a file with speech."
        case .noSpeech: "No speech was recognized. Check the spoken language or try another file."
        case .invalidCue: "Each caption needs text and a valid time range."
        case .incompleteTranslation: "Some captions could not be translated. Try this language again."
        case .unavailableLanguage: "This language is unavailable on this Mac."
        }
    }
}

public enum Subtitles {
    private static let spacing = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{0}"..."\u{1F}"))

    public static func plainText(_ text: String) -> String {
        text.components(separatedBy: spacing)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func timestamp(_ milliseconds: Int) -> String {
        String(format: "%02d:%02d:%02d,%03d", milliseconds / 3_600_000, milliseconds / 60_000 % 60,
               milliseconds / 1000 % 60, milliseconds % 1000)
    }

    public static func srt(_ cues: [SubtitleCue]) throws -> Data {
        guard !cues.isEmpty else { throw SubtitleError.noSpeech }
        var output = ""
        var previousEnd = 0
        for (index, cue) in cues.enumerated() {
            try Task.checkCancellation()
            let text = cue.text.components(separatedBy: .newlines).map(plainText).filter { !$0.isEmpty }.joined(separator: "\n")
            guard !text.isEmpty, previousEnd <= cue.start, cue.start < cue.end else { throw SubtitleError.invalidCue }
            output += "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(text)\n\n"
            previousEnd = cue.end
        }
        return Data(output.utf8)
    }

    /// Publish the complete reviewed set together, including when two exports use the same name.
    public static func export(_ tracks: [String: [SubtitleCue]], source: URL, in folder: URL) throws -> URL {
        guard let original = tracks.values.first, !original.isEmpty else { throw SubtitleError.noSpeech }
        for cues in tracks.values {
            guard original.elementsEqual(cues, by: { $0.start == $1.start && $0.end == $1.end }) else {
                throw SubtitleError.invalidCue
            }
        }
        let proposed = source.deletingPathExtension().lastPathComponent
        let stem = (try? SafeOutput.validate(stem: proposed + " subtitles")) != nil ? proposed : "Media"
        return try SafeOutput.publishFolder(named: stem + " subtitles", in: folder) { stage in
            for (code, cues) in tracks {
                guard !code.isEmpty, code.utf8.count <= 40, code.utf8.allSatisfy({
                    (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
                }) else { throw ToolError.invalidName }
                let url = stage.appendingPathComponent("\(stem).\(code).srt")
                try srt(cues).write(to: url, options: .withoutOverwriting)
            }
        }
    }
}
