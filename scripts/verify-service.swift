import AppKit
import Foundation
let application = NSApplication.shared
let board = NSPasteboard.withUniqueName()
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
board.writeObjects([folder as NSURL])
print("Service invocation accepted:", NSPerformService("New File with CloakTools", board))
board.releaseGlobally()
