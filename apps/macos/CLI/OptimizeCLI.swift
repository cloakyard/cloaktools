import CloakToolsCore
import Foundation

@main
struct OptimizeCLI {
    static let help = """
    cloakopt [--recipe NAME] [--stronger] [--limit-kb N] [--output FOLDER] [--] FILE ...
    cloakopt --list-recipes

    --image-format automatic|png|jpeg|heic|avif|webp|jxl|original-jpeg
    --video-format mp4|hevc|x265|webm|av1|gif
    --audio-format automatic|aac|flac|wav|aiff|mp3|ogg
    --scale PERCENT    --speed MULTIPLIER    --mute
    --normalize-peak    --lufs N    --audio-kbps N
    --crop original|square|landscape|portrait|paper|full-page

    Measures each local file. Supply an output folder to save new copies.
    Reports one JSON record per file. A failed input sets a nonzero exit status.
    """
    struct Record: Encodable {
        let input: String
        var originalBytes: Int?
        var encodedBytes: Int?
        var filename: String?
        var output: String?
        var message: String?
    }

    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard !args.isEmpty else { throw Usage(help) }
            if args == ["--help"] || args == ["-h"] { print(help); return }
            let recipes = try ExportRecipeStore.standard.load().filter { if case .optimize = $0.options { true } else { false } }
            if args == ["--list-recipes"] { for recipe in recipes { print(recipe.title) }; return }
            var options = OptimizationOptions()
            var destination: URL?
            var files = [URL]()
            var flags = true
            var iterator = args.makeIterator()
            while let arg = iterator.next() {
                if !flags || !arg.hasPrefix("-") { files.append(URL(fileURLWithPath: arg)); continue }
                switch arg {
                case "--": flags = false
                case "--stronger": options.aggressive = true
                case "--image-format":
                    guard let raw = iterator.next(), let format = OptimizedImageFormat(rawValue: raw.lowercased()) else { throw Usage("Choose an image format from --help.") }
                    options.imageFormat = format
                case "--video-format":
                    let formats: [String: OptimizedVideoFormat] = ["mp4": .mp4, "hevc": .hevc, "x265": .x265, "webm": .webm, "av1": .av1, "gif": .gif]
                    guard let raw = iterator.next(), let format = formats[raw.lowercased()] else { throw Usage("Choose a video format from --help.") }
                    options.videoFormat = format
                case "--audio-format":
                    guard let raw = iterator.next(), let format = OptimizedAudioFormat.allCases.first(where: { $0 == .ogg ? raw.lowercased() == "ogg" : $0.rawValue.lowercased() == raw.lowercased() }) else { throw Usage("Choose an audio format from --help.") }
                    options.audioFormat = format
                case "--crop":
                    let crops: [String: OptimizationCrop] = ["original": .original, "square": .square, "landscape": .landscape, "portrait": .portrait, "paper": .paper, "full-page": .fullPage]
                    guard let raw = iterator.next(), let crop = crops[raw] else { throw Usage("Choose a crop from --help.") }
                    options.crop = crop
                case "--scale":
                    guard let raw = iterator.next(), let value = Double(raw), (10...100).contains(value) else { throw Usage("Choose a scale of 10–100 percent.") }
                    options.scale = value / 100
                case "--speed":
                    guard let raw = iterator.next(), let value = Double(raw), (0.25...4).contains(value) else { throw Usage("Choose a playback speed of 0.25–4.") }
                    options.playbackSpeed = value
                case "--mute": options.muteVideo = true
                case "--normalize-peak": options.normalizeAudio = true; options.loudnessTarget = nil
                case "--lufs":
                    guard let raw = iterator.next(), let value = Int(raw), (-30 ... -10).contains(value) else { throw Usage("Choose a loudness of −30 to −10 LUFS.") }
                    options.loudnessTarget = value
                case "--audio-kbps":
                    guard let raw = iterator.next(), let value = Int(raw), [48, 64, 96, 128, 160, 192, 256, 320].contains(value) else { throw Usage("Choose 48, 64, 96, 128, 160, 192, 256 or 320 kbps.") }
                    options.audioBitrate = value
                case "--output":
                    guard let path = iterator.next() else { throw Usage("--output needs an existing folder.") }
                    destination = URL(fileURLWithPath: path, isDirectory: true)
                case "--limit-kb":
                    guard let raw = iterator.next(), let kb = Int(raw), (1...1_000_000).contains(kb) else { throw Usage("Choose a limit of 1–1,000,000 KB.") }
                    options.maximumBytes = kb * 1000
                case "--recipe":
                    guard let name = iterator.next() else { throw Usage("--recipe needs a saved optimization recipe name.") }
                    let matches = recipes.filter { $0.title == name }
                    guard matches.count == 1, case let .optimize(value) = matches[0].options else { throw Usage("Choose a unique name from --list-recipes.") }
                    options = value
                default: throw Usage("Unknown option \(arg).\n\(help)")
                }
            }
            guard (1...MediaOptimization.maximumItems).contains(files.count) else { throw Usage("Choose 1–100 local media files.") }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var failed = false
            for file in files {
                var record = Record(input: file.path)
                do {
                    let result = try await MediaOptimization.prepare(file, options: options)
                    record.originalBytes = result.inputBytes
                    record.encodedBytes = result.outputBytes
                    record.filename = result.filename
                    if let destination { record.output = try result.save(in: destination).path }
                } catch OptimizationError.noReduction { record.message = OptimizationError.noReduction.localizedDescription }
                catch { record.message = error.localizedDescription; failed = true }
                print(String(decoding: try encoder.encode(record), as: UTF8.self))
            }
            if failed { exit(1) }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(2)
        }
    }

    struct Usage: LocalizedError {
        let reason: String
        init(_ reason: String) { self.reason = reason }
        var errorDescription: String? { reason }
    }
}
