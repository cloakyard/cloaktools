import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Synthetic textured pixels, used only for native Make It Fit verification.
let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/CloakTools-Fit-Verification", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let output = folder.appendingPathComponent("Spectrum.png")
guard !FileManager.default.fileExists(atPath: output.path) else { fatalError("Preserve the existing fixture; choose a new empty folder.") }
let width = 1920, height = 1280
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
var seed: UInt32 = 731
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        let transparent = x < 32 || y < 32 || x >= width - 32 || y >= height - 32
        seed = seed &* 1_664_525 &+ 1_013_904_223
        let noise = Int(seed >> 25)
        let u = Double(x) / Double(width), v = Double(y) / Double(height)
        pixels[i] = transparent ? 0 : UInt8(min(255, 35 + Int(u * 125) + noise / 2))
        pixels[i + 1] = transparent ? 0 : UInt8(min(255, 45 + Int(v * 95) + noise / 3))
        pixels[i + 2] = transparent ? 0 : UInt8(min(255, 125 + Int((1 - u) * 75) + noise / 3))
        pixels[i + 3] = transparent ? 0 : 255
    }
}
context.setFillColor(CGColor(red: 1, green: 0.71, blue: 0.21, alpha: 1))
context.fillEllipse(in: CGRect(x: 240, y: 260, width: 460, height: 460))
context.setFillColor(CGColor(red: 0.9, green: 0.96, blue: 1, alpha: 0.8))
context.fill(CGRect(x: 1120, y: 400, width: 340, height: 580))
let data = NSMutableData()
let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not encode fixture") }
try (data as Data).write(to: output, options: .withoutOverwriting)
print("\(output.path): \(data.length) bytes, \(width) × \(height)")
