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
