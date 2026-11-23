import Foundation
import ImageIO
import UniformTypeIdentifiers

enum JPEGXLConversion {
    private enum Failure: LocalizedError {
        case reconstruction
        var errorDescription: String? { "Choose a JPEG XL file containing an original JPEG, with Original crop and 100% scale." }
    }

    static func encode(_ bytes: Data, prepared: PreparedImage, options: OptimizationOptions, in folder: URL) async throws -> URL {
        let helpers = ExtendedMediaEncoding.helperDirectory
        let direct = options.crop.aspect == nil && options.scale == 1
        let jpeg = folder.appendingPathComponent("original.jpg")
        let jxl = folder.appendingPathComponent("result.jxl")
        let decode = helpers.appendingPathComponent("djxl")
        let encode = helpers.appendingPathComponent("cjxl")
        if options.imageFormat == .originalJPEG {
            guard direct, prepared.sourceFormat == "JXL" else { throw Failure.reconstruction }
            try bytes.write(to: jxl)
            do { try await ExtendedMediaEncoding.run(decode, args: [jxl.path, jpeg.path, "--reconstruct_jpeg", "--num_threads=2"], output: nil) }
            catch is CancellationError { throw CancellationError() }
            catch { throw Failure.reconstruction }
            try validate(jpeg, type: .jpeg)
            return jpeg
        }

        if prepared.sourceFormat == "JPEG", direct {
            try bytes.write(to: jpeg)
            try await ExtendedMediaEncoding.run(encode, args: [jpeg.path, jxl.path, "--lossless_jpeg=1", "--num_threads=2"], output: nil)
            let check = folder.appendingPathComponent("roundtrip.jpg")
            try await ExtendedMediaEncoding.run(decode, args: [jxl.path, check.path, "--reconstruct_jpeg", "--num_threads=2"], output: nil)
            guard try LocalFileCapture.read(check, limit: bytes.count) == bytes else { throw OptimizationError.exportFailed }
        } else {
            let rect = CGRect(x: 0, y: 0, width: prepared.width, height: prepared.height)
            guard let crop = prepared.image.cropping(to: options.crop.centered(in: rect).integral.intersection(rect)) else { throw OptimizationError.exportFailed }
            let input = folder.appendingPathComponent("pixels.png")
            var scale = options.scale
            for _ in 0..<12 {
                let width = max(1, Int(Double(crop.width) * scale)), height = max(1, Int(Double(crop.height) * scale))
                let rendered = try ImageConversion.render(crop, width: width, height: height)
                try ImageConversion.encode(rendered, options: .init()).write(to: input)
                try await ExtendedMediaEncoding.run(encode, args: [input.path, jxl.path, "--distance=" + (options.aggressive ? "3" : "1.2"), "--num_threads=2"], output: nil)
                let size = try jxl.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                if size <= (options.maximumBytes ?? Int.max) || (width == 1 && height == 1) { break }
                try FileManager.default.removeItem(at: jxl)
                scale *= 0.72
            }
            guard FileManager.default.fileExists(atPath: jxl.path) else { throw OptimizationError.overBudget }
        }
        guard let type = UTType("public.jpeg-xl") else { throw OptimizationError.unsupported }
        try validate(jxl, type: type)
        return jxl
    }

    private static func validate(_ file: URL, type: UTType) throws {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              CGImageSourceGetType(source) as String? == type.identifier,
              CGImageSourceGetCount(source) == 1, CGImageSourceGetStatus(source) == .statusComplete else { throw OptimizationError.exportFailed }
    }
}
