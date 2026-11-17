import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
@testable import CloakToolsCore

private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsTests-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
}
@Test func helloWorldPrecedenceAndRetainedChoices() throws {
    var p = Preferences()
    #expect(!p.includeHelloWorld)
    for t in FileTemplate.allCases where t != .pdf && t != .json { #expect(try t.contents(using: p).isEmpty) }
    p.includeHelloWorld = true
    #expect(String(decoding: try FileTemplate.python.contents(using: p), as: UTF8.self) == "print(\"Hello, World!\")\n")
    #expect(try FileTemplate.javascript.contents(using: p).isEmpty == false)
    #expect(try FileTemplate.swift.contents(using: p).isEmpty == false)
    #expect(try FileTemplate.markdown.contents(using: p).isEmpty)
    p.languageChoices["python"] = false
    #expect(try FileTemplate.python.contents(using: p).isEmpty)
    p.includeHelloWorld = false
    #expect(p.languageChoices["python"] == false)
    #expect(try FileTemplate.swift.contents(using: p, folderWantsStarter: true).isEmpty)
    let custom = Data("my explicit template".utf8)
    #expect(try FileTemplate.swift.contents(using: p, customContent: custom) == custom)
    p.includeHelloWorld = true
    #expect(try FileTemplate.python.contents(using: p).isEmpty)
}
@Test func persistenceReloadAndSnapshot() throws {
    let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
    let store = PreferencesStore(url: f.appendingPathComponent("prefs.json")); var p = try store.load()
    let original = CreationRequest(folder: f, template: .swift, preferences: p)
    p.includeHelloWorld = true; p.lastCategory = .newFiles; try store.save(p)
    let fresh = PreferencesStore(url: store.url)
    #expect(try fresh.load() == p)
    let next = CreationRequest(folder: f, template: .swift, preferences: try fresh.load())
    #expect(try Data(contentsOf: original.perform()).isEmpty)
    #expect(try String(contentsOf: next.perform(), encoding: .utf8) == "print(\"Hello, World!\")\n")
}
@Test func collisionWithFileDirectorySymlink() throws {
    let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
    let first = f.appendingPathComponent("Untitled.txt"); try Data("keep me".utf8).write(to: first)
    try FileManager.default.createDirectory(at: f.appendingPathComponent("Untitled 2.txt"), withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: f.appendingPathComponent("Untitled 3.txt"), withDestinationURL: first)
    let result = try CreationRequest(folder: f, template: .text, preferences: Preferences()).perform()
    #expect(result.lastPathComponent == "Untitled 4.txt")
    #expect(try String(contentsOf: first, encoding: .utf8) == "keep me")
    #expect(try Data(contentsOf: result).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.path).filter { $0.hasPrefix(".cloaktools") }.isEmpty)
}
@Test func concurrentPublication() async throws {
    let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
    let outputs = try await withThrowingTaskGroup(of: URL.self) { group in
        for _ in 0..<24 { group.addTask { try SafeOutput.publish(Data("complete".utf8), in: f, stem: "Same", extension: "txt") } }
        var results: [URL] = []; for try await url in group { results.append(url) }; return results
    }
    #expect(Set(outputs).count == 24)
    for url in outputs { #expect(try String(contentsOf: url, encoding: .utf8) == "complete") }
}
@Test(arguments: ["", "../evil", ".hidden", "bad/name", "bad:name", "bad\nname", " name", String(repeating: "x", count: 121)])
func unsafeNames(_ name: String) { #expect(throws: ToolError.self) { try SafeOutput.validate(stem: name) } }
@Test func unavailableAndUnwritableFolder() throws {
    let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
    #expect(throws: ToolError.self) { try CreationRequest(folder: f.appendingPathComponent("missing"), template: .text, preferences: Preferences()).perform() }
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: f.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.path) }
    #expect(throws: (any Error).self) { try CreationRequest(folder: f, template: .text, preferences: Preferences()).perform() }
}
@Test func nativeImageConversion() throws {
    let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
    let input = f.appendingPathComponent("sample.jpg")
    let context = CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 24, height: 16))
    let encoder = CGImageDestinationCreateWithURL(input as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(encoder, context.makeImage()!, nil); #expect(CGImageDestinationFinalize(encoder))
    let before = try Data(contentsOf: input); let output = try ImageConversion.pngCopy(of: input)
    let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(image.width == 24 && image.height == 16)
    #expect(try Data(contentsOf: input) == before)
    #expect(try ImageConversion.pngCopy(of: input).lastPathComponent == "sample converted 2.png")
    let bad = f.appendingPathComponent("bad.jpg"); try Data("not an image".utf8).write(to: bad)
    #expect(throws: ToolError.self) { try ImageConversion.pngCopy(of: bad) }
}
@Test func cancellationDoesNotPublish() async throws {
    let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
    let task = Task { while !Task.isCancelled { await Task.yield() }; return try CreationRequest(folder: f, template: .text, preferences: Preferences()).perform() }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.path).isEmpty)
}
@Test func URLPreservation() throws {
    let raw = "mailto:person@example.com?cc=other@example.com&subject=Hello%20%26%20Welcome&body=A%0D%0AB%2BC"
    let link = try IncomingLink(raw)
    #expect(link.original == raw && link.url.absoluteString == raw)
    #expect(link.role == .email && link.sourceApplication == nil)
    #expect(try IncomingLink("https://example.com/a?token=a%2Bb#c").original == "https://example.com/a?token=a%2Bb#c")
    #expect(try IncomingLink("http://example.com").role == .web)
    for bad in ["file:///tmp/file", "javascript:alert(1)", "https://", "hello", "https://example.com\n"] { #expect(throws: ToolError.self) { try IncomingLink(bad) } }
}
@Test func selfExclusionAndLoopPrevention() throws {
    let own = URL(fileURLWithPath: "/Applications/CloakTools.app")
    #expect(!IncomingLink.permitsDestination(bundleID: "com.cloakyard.cloaktools", appURL: URL(fileURLWithPath: "/tmp/copy.app"), ownURL: own))
    #expect(!IncomingLink.permitsDestination(bundleID: "different.id", appURL: own, ownURL: own))
    #expect(IncomingLink.permitsDestination(bundleID: "com.apple.Safari", appURL: URL(fileURLWithPath: "/Applications/Safari.app"), ownURL: own))
    var g = LoopGuard(); let link = try IncomingLink("https://example.com"); let now = Date()
    let initial = g.permits(link, now: now); #expect(initial); g.recordDispatch(link, now: now)
    let blocked = g.permits(link, now: now.addingTimeInterval(1)); #expect(!blocked)
    let expired = g.permits(link, now: now.addingTimeInterval(6)); #expect(expired)
}
@Test func finderIntentValidation() throws {
    let create = FinderIntent.create(folder: URL(fileURLWithPath: "/tmp/a # & ?/"), template: .python)
    #expect(try FinderIntent(url: create.url) == create)
    let convert = FinderIntent.convert(image: URL(fileURLWithPath: "/tmp/a # & ?.jpg"))
    #expect(try FinderIntent(url: convert.url) == convert)
    for raw in ["cloaktools-action://delete?path=/tmp/a", "cloaktools-action://create?path=/tmp&template=unknown", "cloaktools-action://convert?path=relative", "cloaktools-action://convert?path=/a&path=/b"] { #expect(throws: ToolError.self) { try FinderIntent(url: URL(string: raw)!) } }
}

@Test(arguments: FileTemplate.allCases.filter(\.isProgramming))
func everyLanguageHonorsMasterAndRetainedChoice(_ template: FileTemplate) throws {
    var p = Preferences()
    #expect(try template.contents(using: p).isEmpty)
    #expect(!template.starter.isEmpty)
    p.includeHelloWorld = true
    #expect(try template.contents(using: p) == Data(template.starter.utf8))
    p.languageChoices[template.rawValue] = false
    #expect(try template.contents(using: p).isEmpty)
    p.includeHelloWorld = false
    #expect(p.languageChoices[template.rawValue] == false)
    #expect(try template.contents(using: p, folderWantsStarter: true).isEmpty)
    p.includeHelloWorld = true
    #expect(try template.contents(using: p).isEmpty)
    p.languageChoices[template.rawValue] = true
    let f = try folder(); defer { try? FileManager.default.removeItem(at: f) }
    let result = try CreationRequest(folder: f, template: template, preferences: p).perform()
    #expect(result.pathExtension == template.fileExtension)
    #expect(try String(contentsOf: result, encoding: .utf8) == template.starter)
}
@Test func catalogCoversRequestedLanguages() {
    #expect(FileTemplate.allCases.filter(\.isProgramming).count >= 10)
    #expect(Set(FileTemplate.allCases.map(\.fileExtension)).count == FileTemplate.allCases.count)
    #expect(FileTemplate.allCases.contains(.rust))
    #expect(FileTemplate.allCases.contains(.c))
    #expect(FileTemplate.allCases.contains(.cpp))
    // A nonpublic Java class permits arbitrary user-selected filenames.
    #expect(FileTemplate.java.starter.hasPrefix("class HelloWorld {"))
}

@Test func finderRequestsRejectAmbiguousURLComponents() throws {
    for raw in [
        "cloaktools-action://user@create?path=/tmp&template=rust",
        "cloaktools-action://create:42?path=/tmp&template=rust",
        "cloaktools-action://create/extra?path=/tmp&template=rust",
        "cloaktools-action://convert?path=/tmp/image.png#extra",
        "cloaktools-action://templates?path=/tmp#extra"
    ] {
        #expect(throws: ToolError.self) { try FinderIntent(url: #require(URL(string: raw))) }
    }
}
