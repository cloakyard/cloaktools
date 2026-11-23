import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public enum OptimizedImageFormat: String, Codable, CaseIterable, Sendable {
    case automatic, png, jpeg, heic, avif, webp, gif, jxl, originalJPEG = "original-jpeg"
    public var title: String { self == .automatic ? "Automatic" : self == .originalJPEG ? "Reconstruct original JPEG" : rawValue.uppercased() }
    public var type: UTType? {
        switch self {
        case .automatic: nil
        case .webp: .webP
        case .gif: .gif
        case .png: .png
        case .jpeg, .originalJPEG: .jpeg
        case .jxl: UTType("public.jpeg-xl")
        case .heic: .heic
        case .avif: UTType("public.avif")
        }
    }
    public var available: Bool {
        if self == .webp { return true }
        if self == .jxl || self == .originalJPEG {
            return FileManager.default.isExecutableFile(atPath: ExtendedMediaEncoding.helperDirectory.appendingPathComponent(self == .jxl ? "cjxl" : "djxl").path)
        }
        return type.map { (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains($0.identifier) } ?? (self == .automatic)
    }
}

public enum OptimizationCrop: String, CaseIterable, Codable, Sendable {
    case original = "Original", square = "Square", landscape = "16∶9", portrait = "9∶16", paper = "A4 portrait", fullPage = "Restore PDF media box"
    var aspect: Double? {
        switch self {
        case .original, .fullPage: nil
        case .square: 1
        case .landscape: 16.0 / 9
        case .portrait: 9.0 / 16
        case .paper: 210.0 / 297
        }
    }
    func centered(in rect: CGRect) -> CGRect {
        guard let aspect else { return rect }
        let width = min(rect.width, rect.height * aspect)
        let height = min(rect.height, rect.width / aspect)
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
}

public struct OptimizationOptions: Codable, Equatable, Sendable {
    public var imageFormat: OptimizedImageFormat = .automatic
    public var losslessWebP = false
    public var aggressive = false
    public var crop: OptimizationCrop = .original
    public var scale = 1.0
    public var maximumBytes: Int?
    public var videoFormat: OptimizedVideoFormat = .mp4
    public var audioFormat: OptimizedAudioFormat = .automatic
    public var audioBitrate = 128
    public var normalizeAudio = false
    public var loudnessTarget: Int?
    public var muteVideo = false
    public var playbackSpeed = 1.0
    public init() {}

    func validate() throws {
        guard loudnessTarget.map({ (-30 ... -10).contains($0) }) ?? true, [48, 64, 96, 128, 160, 192, 256, 320].contains(audioBitrate), scale.isFinite, (0.1...1).contains(scale), playbackSpeed.isFinite, (0.25...4).contains(playbackSpeed),
              maximumBytes.map({ (1_000...1_000_000_000).contains($0) }) ?? true else { throw OptimizationError.invalidOptions }
    }
}

public enum OptimizationError: LocalizedError {
    case unsupported, invalidOptions, overBudget, noReduction, exportFailed, inputLimit
    public var errorDescription: String? {
        switch self {
        case .unsupported: "Choose a supported local image, PDF, movie or audio file."
        case .invalidOptions: "Check the scale, playback speed and byte limit."
        case .overBudget: "The result exceeds the size limit. Increase the limit or use stronger compression."
        case .noReduction: "Already compact. Encoding did not produce a smaller file."
        case .exportFailed: "The encoded result could not be verified."
        case .inputLimit: "Choose an image or PDF up to 100 MB."
        }
    }
}

/// A private, leased preview. Save always publishes these exact measured bytes.
public struct OptimizedMedia: Sendable {
    private let workspace: MediaWorkspace
    public let previewURL: URL
    public let inputBytes: Int
    public let outputBytes: Int
    public let filename: String
    var reviewedSource: ReviewedOptimizationSource?
    init(workspace: MediaWorkspace, previewURL: URL, inputBytes: Int, outputBytes: Int, stem: String) {
        self.workspace = workspace
        self.previewURL = previewURL
        self.inputBytes = inputBytes
        self.outputBytes = outputBytes
        self.filename = stem + "." + previewURL.pathExtension
    }

    public func save(in folder: URL) throws -> URL {
        try Task.checkCancellation()
        guard folder.isFileURL, (try folder.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
            throw ToolError.unavailableFolder
        }
        let stage = folder.appendingPathComponent(".cloaktools-optimized-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        let copy = stage.appendingPathComponent("result")
        try FileManager.default.copyItem(at: previewURL, to: copy)
        return try SafeOutput.publishStagedFile(copy, in: folder, stem: (filename as NSString).deletingPathExtension, extension: previewURL.pathExtension)
    }
}

public enum MediaOptimization {
    public static let maximumItems = 100
    public static let imageExtensions = ImageConversion.inputExtensions.union(["webp", "avif", "gif", "jxl", "bmp"])
    public static let extensions = imageExtensions.union(ExtendedMediaEncoding.movies).union(audioExtensions).union(["pdf"])
    public static let audioExtensions: Set<String> = ExtendedMediaEncoding.audio
    static let imageTypes = ImageConversion.inputTypes + [.webP, .gif, .bmp] + ["public.avif", "public.jpeg-xl"].compactMap(UTType.init)

    public static func prepare(_ url: URL, options: OptimizationOptions = .init()) async throws -> OptimizedMedia {
        let source = try ReviewedOptimizationSource(url)
        var preview = try await prepareFile(url, options: options)
        try source.checkUnchanged()
        preview.reviewedSource = source
        return preview
    }

    private static func prepareFile(_ url: URL, options: OptimizationOptions) async throws -> OptimizedMedia {
        try options.validate()
        try Task.checkCancellation()
        guard url.isFileURL, [nil, "", "localhost"].contains(url.host), extensions.contains(url.pathExtension.lowercased()),
              try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true else { throw OptimizationError.unsupported }
        let ext = url.pathExtension.lowercased()
        if ExtendedMediaEncoding.handles(ext, options: options) {
            let workspace = try MediaWorkspace()
            let (output, count) = try await ExtendedMediaEncoding.encode(url, in: workspace.folder, options: options)
            let requireSavings = audioExtensions.contains(ext)
                ? options.audioFormat == .automatic && options.loudnessTarget == nil && !options.normalizeAudio
                : options.videoFormat == .mp4 && options.playbackSpeed == 1 && !options.muteVideo && options.scale == 1 && options.crop.aspect == nil
            return try result(workspace, output, source: url, count: count, options: options, requireSavings: requireSavings)
        }
        if audioExtensions.contains(ext) {
            let workspace = try MediaWorkspace()
            let (output, count) = try AudioOptimization.encode(url, in: workspace.folder, options: options)
            return try result(workspace, output, source: url, count: count, options: options, requireSavings: options.audioFormat == .automatic && !options.normalizeAudio)
        }
        if MediaExport.inputExtensions.contains(ext) {
            let source = try await MediaExport.prepare(url)
            let workspace = try MediaWorkspace()
            if options.videoFormat == .gif {
                let output = try await AnimatedOptimization.movie(source, options: options, in: workspace.folder)
                return try result(workspace, output, source: url, count: source.sourceByteCount, options: options, requireSavings: false)
            }
            let preset: MediaExportPreset = source.hasVideo ? (options.aggressive ? .video720 : .video1080) : .audio
            let output = try await MediaExport.export(source, preset: preset, in: workspace.folder, name: "result", adjustments: options)
            return try result(workspace, output, source: url, count: source.sourceByteCount, options: options,
                              requireSavings: !source.hasVideo || (options.playbackSpeed == 1 && !options.muteVideo && options.scale == 1 && options.crop.aspect == nil))
        }
        let bytes: Data
        do { bytes = try LocalFileCapture.read(url, limit: 100_000_000) }
        catch LocalFileCapture.CaptureError.tooLarge { throw OptimizationError.inputLimit }
        if ext != "pdf" { return try await image(bytes, named: url, options: options) }
        let doc = try PDFAssembly.validated(bytes, name: url.lastPathComponent)
        for index in 0..<doc.pageCount {
            try Task.checkCancellation()
            guard let page = doc.page(at: index) else { throw PDFAssemblyError.encoding }
            let bounds = page.bounds(for: .mediaBox)
            if options.crop == .fullPage { page.setBounds(bounds, for: .cropBox) }
            else if options.crop.aspect != nil {
                // PDF boxes use unrotated coordinates. Present the chosen aspect in reading orientation.
                var crop = options.crop.centered(in: bounds)
                if !page.rotation.isMultiple(of: 180) {
                    let swapped = CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width)
                    let rotated = options.crop.centered(in: swapped)
                    crop = CGRect(x: bounds.midX - rotated.height / 2, y: bounds.midY - rotated.width / 2,
                                  width: rotated.height, height: rotated.width)
                }
                page.setBounds(crop, for: .cropBox)
            }
        }
        let writeOptions: [PDFDocumentWriteOption: Any] = [.optimizeImagesForScreenOption: true, .saveImagesAsJPEGOption: options.aggressive]
        guard let encoded = doc.dataRepresentation(options: writeOptions), encoded.count <= PDFAssembly.maximumBytes,
              let check = PDFDocument(data: encoded), check.pageCount == doc.pageCount else { throw PDFAssemblyError.encoding }
        return try staged(encoded, ext: "pdf", source: url, count: bytes.count, options: options, requireSavings: options.crop == .original)
    }

    public static func clipboardImage(_ bytes: Data, options: OptimizationOptions = .init()) async throws -> OptimizedMedia {
        try options.validate()
        return try await image(bytes, named: URL(fileURLWithPath: "Clipboard Image"), options: options)
    }

    private static func image(_ bytes: Data, named url: URL, options: OptimizationOptions) async throws -> OptimizedMedia {
        if let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
           CGImageSourceGetCount(source) > 1, let kind = CGImageSourceGetType(source) as String?,
           [UTType.gif.identifier, UTType.webP.identifier].contains(kind) {
            guard [.automatic, .webp, .gif].contains(options.imageFormat) else { throw AnimatedOptimization.Failure.stillFormat }
            let workspace = try MediaWorkspace()
            let output = try AnimatedOptimization.image(source, options: options, in: workspace.folder)
            return try result(workspace, output, source: url, count: bytes.count, options: options,
                              requireSavings: options.imageFormat == .automatic && options.scale == 1 && options.crop.aspect == nil)
        }
        let prepared = try ImageConversion.prepare(bytes: bytes, sourceURL: url, acceptedTypes: imageTypes)
        if options.imageFormat == .originalJPEG || options.imageFormat == .jxl {
            let workspace = try MediaWorkspace()
            let output = try await JPEGXLConversion.encode(bytes, prepared: prepared, options: options, in: workspace.folder)
            return try result(workspace, output, source: url, count: bytes.count, options: options, requireSavings: false)
        }
        let bounds = CGRect(x: 0, y: 0, width: prepared.width, height: prepared.height)
        let rect = options.crop.centered(in: bounds).integral.intersection(bounds)
        guard let cropped = prepared.image.cropping(to: rect) else { throw OptimizationError.exportFailed }
        let png = UTType.png
        let type = options.imageFormat.type ?? (["PNG", "GIF", "WEBP"].contains(prepared.sourceFormat) || prepared.sourceFormat == "TIFF" ? png : .jpeg)
        var scale = options.scale
        let initialQuality = options.aggressive ? 0.52 : 0.8
        let qualitySteps = type == png || options.maximumBytes == nil ? [initialQuality] : [initialQuality, initialQuality * 0.72, initialQuality * 0.5]
        for _ in 0..<12 {
            try Task.checkCancellation()
            let width = max(1, Int(Double(cropped.width) * scale)), height = max(1, Int(Double(cropped.height) * scale))
            let rendered = try ImageConversion.render(cropped, width: width, height: height, background: type == .jpeg ? .white : nil)
            for quality in qualitySteps {
                try Task.checkCancellation()
                let data: Data
                if type == .webP {
                    data = try WebPEncoding.encode(rendered, quality: quality, lossless: options.losslessWebP)
                } else {
                    let buffer = NSMutableData()
                    guard let dest = CGImageDestinationCreateWithData(buffer, type.identifier as CFString, 1, nil) else { throw OptimizationError.exportFailed }
                    CGImageDestinationAddImage(dest, rendered, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                    guard CGImageDestinationFinalize(dest) else { throw OptimizationError.exportFailed }
                    data = buffer as Data
                }
                if let limit = options.maximumBytes, data.count > limit { continue }
                guard let check = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(check) == 1,
                      CGImageSourceGetStatus(check) == .statusComplete else { throw OptimizationError.exportFailed }
                return try staged(data, ext: type.preferredFilenameExtension ?? "jpg", source: url, count: bytes.count,
                                  options: options, requireSavings: options.imageFormat == .automatic && options.crop.aspect == nil && options.scale == 1)
            }
            if width == 1 && height == 1 { break }
            scale *= 0.72
        }
        throw OptimizationError.overBudget
    }

    private static func staged(_ bytes: Data, ext: String, source: URL, count: Int, options: OptimizationOptions, requireSavings: Bool) throws -> OptimizedMedia {
        let workspace = try MediaWorkspace()
        let output = try SafeOutput.publish(bytes, in: workspace.folder, stem: "result", extension: ext)
        return try result(workspace, output, source: source, count: count, options: options, requireSavings: requireSavings)
    }

    private static func result(_ workspace: MediaWorkspace, _ url: URL, source: URL, count: Int,
                               options: OptimizationOptions, requireSavings: Bool) throws -> OptimizedMedia {
        try Task.checkCancellation()
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw OptimizationError.exportFailed }
        if let limit = options.maximumBytes, size > limit { throw OptimizationError.overBudget }
        if requireSavings && size >= count { throw OptimizationError.noReduction }
        let name = source.deletingPathExtension().lastPathComponent + " optimized"
        let stem = (try? SafeOutput.validate(stem: name)) != nil ? name : "Optimized copy"
        return OptimizedMedia(workspace: workspace, previewURL: url, inputBytes: count, outputBytes: size, stem: stem)
    }
}
