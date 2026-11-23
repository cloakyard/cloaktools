import Accelerate
import CoreGraphics
import Foundation
import libwebp

enum WebPEncoding {
    static func encode(_ image: CGImage, quality: Double, lossless: Bool) throws -> Data {
        guard image.width <= 16383, image.height <= 16383,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let bytes = context.data else { throw ToolError.encodingFailed }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var pixels = vImage_Buffer(data: bytes, height: vImagePixelCount(image.height), width: vImagePixelCount(image.width), rowBytes: context.bytesPerRow)
        var destination = pixels
        guard vImageUnpremultiplyData_RGBA8888(&pixels, &destination, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { throw ToolError.encodingFailed }
        try Task.checkCancellation()
        var output: UnsafeMutablePointer<UInt8>?
        let rgba = bytes.assumingMemoryBound(to: UInt8.self)
        let width = Int32(image.width), height = Int32(image.height), stride = Int32(context.bytesPerRow)
        let size = lossless ? WebPEncodeLosslessRGBA(rgba, width, height, stride, &output)
                            : WebPEncodeRGBA(rgba, width, height, stride, Float(quality * 100), &output)
        guard let output, size > 0 else { throw ToolError.encodingFailed }
        defer { WebPFree(output) }
        return Data(bytes: output, count: size)
    }
}

final class AnimatedWebPWriter {
    private let mux: OpaquePointer
    private var compressedBytes = 0

    init(loopCount: Int) throws {
        guard (0...65535).contains(loopCount), let handle = WebPMuxNew() else { throw ToolError.encodingFailed }
        var params = WebPMuxAnimParams(bgcolor: 0, loop_count: Int32(loopCount))
        guard WebPMuxSetAnimationParams(handle, &params) == WEBP_MUX_OK else {
            WebPMuxDelete(handle)
            throw ToolError.encodingFailed
        }
        mux = handle
    }
    deinit { WebPMuxDelete(mux) }

    func append(_ image: CGImage, delay: Double, options: OptimizationOptions) throws {
        guard delay.isFinite, delay >= 0, delay <= 16_777 else { throw AnimatedOptimization.Failure.limits }
        let encoded = try WebPEncoding.encode(image, quality: options.aggressive ? 0.52 : 0.80, lossless: options.losslessWebP)
        compressedBytes += encoded.count
        guard compressedBytes <= 100_000_000 else { throw AnimatedOptimization.Failure.limits }
        try encoded.withUnsafeBytes { raw in
            var frame = WebPMuxFrameInfo()
            frame.bitstream = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: raw.count)
            frame.id = WEBP_CHUNK_ANMF
            frame.duration = Int32(max(1, (delay * 1000).rounded()))
            frame.dispose_method = WEBP_MUX_DISPOSE_NONE
            frame.blend_method = WEBP_MUX_NO_BLEND
            guard WebPMuxPushFrame(mux, &frame, 1) == WEBP_MUX_OK else { throw ToolError.encodingFailed }
        }
    }

    func write(to url: URL) throws {
        var output = WebPData()
        defer { WebPDataClear(&output) }
        guard WebPMuxAssemble(mux, &output) == WEBP_MUX_OK, let bytes = output.bytes else { throw ToolError.encodingFailed }
        try Data(bytes: bytes, count: output.size).write(to: url, options: .withoutOverwriting)
    }
}
