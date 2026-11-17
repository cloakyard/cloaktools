import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
@testable import CloakToolsCore

private func recipeFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsRecipes-\(UUID())")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
}

@Test func recipesRoundTripEveryOutputSettingWithoutSourceHistory() throws {
    let folder = try recipeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let store = ExportRecipeStore(url: folder.appendingPathComponent("recipes.json"))
    #expect(try store.load().isEmpty)
    let recipes = [
        ExportRecipe(title: "JPEG", options: .image(.init(format: .jpeg, quality: 0.35, background: .black))),
        ExportRecipe(title: "Small image", options: .fit(.init(format: .heic, maximumBytes: 123_000, maximumWidth: 790, maximumHeight: 430, minimumQuality: 0.45, background: .black, allowSmallerDimensions: false))),
        ExportRecipe(title: "Audio", options: .media(.audio)),
        ExportRecipe(title: "720", options: .media(.video720)),
        ExportRecipe(title: "1080", options: .media(.video1080))]
    try store.save(recipes); #expect(try store.load() == recipes)
    let serialized = try String(contentsOf: store.url, encoding: .utf8)
    for forbidden in ["sourceURL", "destination", "filename", "file:///", folder.path] { #expect(!serialized.contains(forbidden)) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["recipes.json"])
}

@Test func recipeValidationRejectsMalformedAndUnrepresentableOptions() throws {
    for title in ["", " leading", "trailing ", "new\nline", String(repeating: "x", count: 81)] {
        #expect(throws: ExportRecipeError.self) { try ExportRecipe(title: title, options: .media(.audio)).validate() }
    }
    for quality in [-1.0, 0.0, 1.01, Double.infinity, Double.nan] {
        #expect(throws: ImageConversionError.self) { try ExportRecipeOptions.image(.init(quality: quality)).validate() }
    }
    for fit in [ImageFitOptions(maximumBytes: 12_345), .init(maximumBytes: 999), .init(maximumWidth: 0), .init(maximumHeight: 20_001), .init(minimumQuality: .nan)] {
        #expect(throws: ImageFitError.self) { try ExportRecipeOptions.fit(fit).validate() }
    }
    try ExportRecipe(title: "日本語 🖼", options: .fit(.init(maximumBytes: 100_000_000, maximumWidth: 20_000))).validate()
}

@Test func recipeLibraryBoundsAndDecodeFailuresPreserveSavedBytes() throws {
    let folder = try recipeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let store = ExportRecipeStore(url: folder.appendingPathComponent("recipes.json"))
    let recipe = ExportRecipe(title: "PNG", options: .image(.init()))
    try store.save([recipe]); let valid = try Data(contentsOf: store.url)
    #expect(throws: ExportRecipeError.self) { try store.save([recipe, recipe]) }
    #expect(throws: ExportRecipeError.self) { try store.save((0..<33).map { ExportRecipe(title: "\($0)", options: .media(.audio)) }) }
    #expect(try Data(contentsOf: store.url) == valid)
    var archive = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
    archive["version"] = 99
    let future = try JSONSerialization.data(withJSONObject: archive); try future.write(to: store.url)
    #expect(throws: ExportRecipeError.self) { try store.load() }
    #expect(throws: ExportRecipeError.self) { try store.upsert(recipe, replacing: nil) }
    #expect(try Data(contentsOf: store.url) == future)
    try Data("{broken".utf8).write(to: store.url)
    #expect(throws: (any Error).self) { try store.upsert(recipe, replacing: nil) }
    #expect(try String(contentsOf: store.url, encoding: .utf8) == "{broken")
    try Data(repeating: 65, count: 262_145).write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
}

@Test func staleRecipeEditsRequireASeparateCopy() throws {
    let folder = try recipeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let store = ExportRecipeStore(url: folder.appendingPathComponent("recipes.json"))
    let original = ExportRecipe(title: "Original", options: .media(.video720))
    _ = try store.upsert(original, replacing: nil)
    var changed = original; changed.title = "Updated"; changed.options = .media(.video1080)
    _ = try store.upsert(changed, replacing: original)
    var stale = original; stale.title = "Old window"
    #expect(throws: ExportRecipeError.self) { try store.upsert(stale, replacing: original) }
    #expect(try store.load() == [changed])
    stale.id = UUID(); _ = try store.upsert(stale, replacing: nil)
    #expect(try store.load().count == 2)
    try store.save([])
    #expect(throws: ExportRecipeError.self) { try store.upsert(changed, replacing: changed) }
    #expect(try store.load().isEmpty)
}

@Test func recipeSnapshotsStayIndependentOfDefaultsAndLaterEdits() throws {
    let global = Preferences()
    var recipe = ExportRecipe(title: "JPEG", options: .image(.init(format: .jpeg, quality: 0.4, background: .black)))
    let captured = recipe
    recipe.title = "Changed"; recipe.options = .image(.init(format: .heic, quality: 1, background: .white))
    guard case let .image(options) = captured.options else { Issue.record("Wrong recipe kind"); return }
    #expect(options.format == .jpeg && options.quality == 0.4 && options.background == .black)
    #expect(captured.title == "JPEG" && global.imageConversion == ImageConversionOptions())
    let fit = ImageFitOptions(format: .png, maximumBytes: 45_000, maximumWidth: 600, maximumHeight: 400, allowSmallerDimensions: false)
    let copy = try JSONDecoder().decode(ExportRecipe.self, from: JSONEncoder().encode(ExportRecipe(title: "Fit", options: .fit(fit))))
    #expect(copy.options == .fit(fit))
}

@Test func savedImageRecipesReuseNativeEncodingAndExactFitPublication() throws {
    let folder = try recipeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.png")
    let context = try #require(CGContext(data: nil, width: 128, height: 64, bitsPerComponent: 8, bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 32, y: 0, width: 96, height: 64))
    let encoder = try #require(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(encoder, try #require(context.makeImage()), nil); #expect(CGImageDestinationFinalize(encoder))
    let original = try Data(contentsOf: source)
    let store = ExportRecipeStore(url: folder.appendingPathComponent("recipes.json"))
    try store.save([.init(title: "JPEG", options: .image(.init(format: .jpeg, quality: 0.35, background: .black))),
                    .init(title: "Fit", options: .fit(.init(format: .png, maximumBytes: 50_000, maximumWidth: 64, maximumHeight: 64)))])
    let loaded = try store.load(), prepared = try ImageConversion.prepare(source)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    guard case let .image(options) = loaded[0].options, case let .fit(limits) = loaded[1].options else { Issue.record("Wrong recipe kind"); return }
    let converted = try ImageConversion.copy(prepared, options: options)
    let image = try #require(CGImageSourceCreateWithURL(converted as CFURL, nil))
    #expect(CGImageSourceGetType(image) as String? == UTType.jpeg.identifier)
    let fitted = try ImageFit.preview(prepared, options: limits)
    #expect(fitted.width == 64 && fitted.height == 32 && fitted.fits)
    let first = try ImageFit.save(fitted), second = try ImageFit.save(fitted)
    let firstBytes = try Data(contentsOf: first), secondBytes = try Data(contentsOf: second)
    #expect(first != second && firstBytes == fitted.bytes && secondBytes == fitted.bytes)
    #expect(try Data(contentsOf: source) == original)
}

@Test func mediaRecipeCompatibilityNeverSubstitutesAPreset() throws {
    let video = ExportRecipeOptions.media(.video720), audio = ExportRecipeOptions.media(.audio)
    #expect(throws: ExportRecipeError.self) { try video.validateMediaCompatibility([.audio]) }
    #expect(throws: ExportRecipeError.self) { try audio.validateMediaCompatibility([.video720, .video1080]) }
    #expect(throws: ExportRecipeError.self) { try video.validateMediaCompatibility([]) }
    try video.validateMediaCompatibility([.video720, .audio]); try audio.validateMediaCompatibility([.audio])
    #expect(video == .media(.video720) && audio == .media(.audio))
}

@Test func savedMediaRecipeExportsFreshSourcesWithoutRetainingThem() async throws {
    let folder = try recipeFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let store = ExportRecipeStore(url: folder.appendingPathComponent("recipes.json"))
    try store.save([.init(title: "Audio", options: .media(.audio))])
    let recipe = try #require(store.load().first)
    guard case let .media(preset) = recipe.options else { Issue.record("Wrong recipe kind"); return }
    for duration in 1...2 {
        let url = folder.appendingPathComponent("Source \(duration).wav"); try MediaFixtures.audio(url, seconds: duration)
        let original = try Data(contentsOf: url), prepared = try await MediaExport.prepare(url)
        try recipe.options.validateMediaCompatibility(prepared.presets)
        let output = try await MediaExport.export(prepared, preset: preset, in: folder, name: "Audio")
        let file = try AVAudioFile(forReading: output)
        #expect(abs(Double(file.length) / file.processingFormat.sampleRate - Double(duration)) < 0.1)
        #expect(try Data(contentsOf: url) == original)
    }
    #expect(try store.load() == [recipe])
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Audio 2.m4a").path))
}
