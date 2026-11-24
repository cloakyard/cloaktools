import Foundation

public enum OptimizationStep: Codable, Equatable, Sendable {
    case crop(OptimizationCrop)
    case resize(percent: Int)
    case image(OptimizedImageFormat)
    case video(OptimizedVideoFormat)
    case audio(OptimizedAudioFormat)
    case scanPDF(dpi: Int)
    case fit(bytes: Int)

    public var title: String {
        switch self {
        case let .crop(value): "Crop to " + value.rawValue
        case let .resize(percent): "Resize to \(percent)%"
        case let .image(format): "Convert image to " + format.title
        case let .video(format): "Convert video to " + format.rawValue
        case let .audio(format): "Convert audio to " + format.rawValue
        case let .scanPDF(dpi): "Compress scans at \(dpi) DPI"
        case let .fit(bytes): "Fit under " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }
    func validate() throws {
        switch self {
        case let .scanPDF(dpi) where ![72, 150, 300].contains(dpi): throw OptimizationError.invalidOptions
        case let .resize(n) where !(10...100).contains(n): throw OptimizationError.invalidOptions
        case let .fit(n) where !(1_000...1_000_000_000).contains(n): throw OptimizationError.invalidOptions
        default: break
        }
    }
    // The encoder crops, scales, converts and measures in this order. Combine adjacent
    // steps only when a single encoding pass produces the requested sequence.
    private var order: Int {
        switch self { case .crop: 0; case .resize: 1; case .image, .video, .audio, .scanPDF: 2; case .fit: 3 }
    }
    private func applies(to kind: OptimizationFileKind) -> Bool {
        switch self {
        case .crop(.fullPage): kind == .pdf
        case .crop: kind == .image || kind == .video || kind == .pdf
        case .resize: kind == .image || kind == .video
        case .image: kind == .image
        case .video: kind == .video
        case .audio: kind == .audio
        case .scanPDF: kind == .pdf
        case .fit: true
        }
    }
    private func apply(to options: inout OptimizationOptions) {
        switch self {
        case let .crop(value): options.crop = value
        case let .resize(percent): options.scale = Double(percent) / 100
        case let .image(value): options.imageFormat = value
        case let .video(value): options.videoFormat = value
        case let .audio(value): options.audioFormat = value
        case let .scanPDF(dpi): options.scanDPI = dpi
        case let .fit(bytes): options.maximumBytes = bytes
        }
    }
    struct Stage {
        let options: OptimizationOptions
        let convertsFormat: Bool
        let onlyFits: Bool
    }

    static func stages(_ steps: [Self], input: URL) throws -> [Stage] {
        guard var kind = OptimizationFileKind.allCases.first(where: { $0 != .all && $0.accepts(input) }) else { throw OptimizationError.unsupported }
        var stages: [Stage] = []
        var format = OptimizationOptions()
        var options = format
        var pending: [Self] = []

        func finishStage() {
            guard !pending.isEmpty else { return }
            let onlyFits = pending.count == 1 && pending[0].order == 3
            stages.append(Stage(options: options, convertsFormat: pending.contains { $0.order == 2 }, onlyFits: onlyFits))
            pending.removeAll(keepingCapacity: true)
            options = format
        }

        for step in steps where step.applies(to: kind) {
            if let last = pending.last, step.order <= last.order { finishStage() }
            pending.append(step)
            step.apply(to: &options)
            switch step {
            case .image(.originalJPEG): format.imageFormat = .jpeg
            case .video(.gif):
                format = OptimizationOptions()
                format.imageFormat = .gif
                finishStage()
                kind = .image
            case .image, .video, .audio: step.apply(to: &format)
            default: break
            }
        }
        finishStage()
        guard !stages.isEmpty else { throw OptimizationError.noMatchingSteps }
        return stages
    }
}
