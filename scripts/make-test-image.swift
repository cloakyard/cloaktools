import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let path = CommandLine.arguments.dropFirst().first ?? "/tmp/CloakTools-proof.jpg"
let url = URL(fileURLWithPath: path)
let context = CGContext(data: nil, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0.16, green: 0.35, blue: 0.82, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 640, height: 480))
context.setFillColor(CGColor(red: 0.94, green: 0.96, blue: 1, alpha: 1)); context.fill(CGRect(x: 80, y: 80, width: 220, height: 280))
context.setFillColor(CGColor(red: 0.65, green: 0.8, blue: 1, alpha: 1)); context.fill(CGRect(x: 340, y: 180, width: 220, height: 220))
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not create fixture") }
print(url.path)
