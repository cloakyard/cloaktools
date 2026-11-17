import Foundation
import Testing
@testable import CloakToolsCore

@Test func exampleJSONReplacesEveryScalarWithoutChangingKeysOrderOrDuplicates() throws {
    let input = #"{"token":"secret-123","port":9007199254740993,"port":-1.23e+40,"enabled":true,"disabled":false,"empty":null,"nested":["private@example.com",{},[]],"\u006Bey":"नमस्ते"}"#
    let result = try ExampleCopy.prepare(Data(input.utf8), sourceName: "Settings.json")
    #expect(result.valueCount == 8 && result.format == .json && result.sourceText == input)
    #expect(result.suggestedName == "Settings example" && result.text.hasSuffix("\n"))
    #expect(result.text.contains(#""\u006Bey": "REPLACE_ME""#))
    #expect(try DeveloperText.json(result.text, action: .minify) == #"{"token":"REPLACE_ME","port":0,"port":0,"enabled":false,"disabled":false,"empty":null,"nested":["REPLACE_ME",{},[]],"\u006Bey":"REPLACE_ME"}"#)
    #expect(!result.text.contains("secret-123") && !result.text.contains("private@example.com"))
}

@Test func exampleJSONSupportsTopLevelScalarsEmptyContainersAndBOM() throws {
    for (input, output, count) in [("\"private\"", "\"REPLACE_ME\"\n", 1), ("1e99999", "0\n", 1), ("null", "null\n", 1), ("{}", "{}\n", 0), ("[]", "[]\n", 0)] {
        let file = try ExampleCopy.prepare(Data(("\u{FEFF}" + input).utf8), sourceName: "fixture.JSON")
        #expect(file.text == output && file.valueCount == count)
    }
}

@Test func exampleJSONRejectsMalformedInputDepthAndOutputExpansion() throws {
    for input in [#"{"password":"secret",}"#, #"{"x":"\uD800"}"#, "01", "true false", String(repeating: "[", count: 129) + "0" + String(repeating: "]", count: 129)] {
        #expect(throws: DeveloperTextError.self) { try ExampleCopy.prepare(Data(input.utf8), sourceName: "invalid.json") }
    }
    let deep = String(repeating: "[", count: 100) + "[" + Array(repeating: "0", count: 45_000).joined(separator: ",") + "]" + String(repeating: "]", count: 100)
    #expect(throws: ExampleCopyError.outputTooLarge) { try ExampleCopy.prepare(Data(deep.utf8), sourceName: "large.json") }
}

@Test func exampleEnvironmentDropsValuesAndCommentsButKeepsKeysAndExport() throws {
    let input = "# private comment\r\nAPI_TOKEN=private-token # secret note\r\nexport PORT = 8080\r\nURL=\"https://private.example/#part\" # note\r\nQUOTE='it is private'\r\nEMPTY=\r\nESCAPED=\"escaped \\\"value\\\"\"\r\nAPI_TOKEN=duplicate\r\nSCRIPT=$(echo private)\r\n"
    let result = try ExampleCopy.prepare(Data(input.utf8), sourceName: ".env.local")
    #expect(result.format == .environment && result.valueCount == 8 && result.suggestedName == "Environment example")
    #expect(result.text == "API_TOKEN=REPLACE_ME\nexport PORT=REPLACE_ME\nURL=REPLACE_ME\nQUOTE=REPLACE_ME\nEMPTY=REPLACE_ME\nESCAPED=REPLACE_ME\nAPI_TOKEN=REPLACE_ME\nSCRIPT=REPLACE_ME\n")
    #expect(result.sourceText == input && !result.text.contains("private"))
    for filename in [".env", ".env.production", "configuration.env"] {
        #expect(try ExampleCopy.prepare(Data("KEY=value".utf8), sourceName: filename).format == .environment)
    }
}

@Test func exampleEnvironmentRejectsUnsupportedSyntaxWithoutLeakingValuesInErrors() throws {
    for line in ["source private.env", "1KEY=private", "BAD-KEY=private", "KEY=\"private", "KEY='private", "KEY=private\\", "KEY=\"private\"junk", "KEY=unquoted\"private\""] {
        do { _ = try ExampleCopy.prepare(Data(("GOOD=first\n" + line).utf8), sourceName: ".env"); Issue.record("Expected rejection") }
        catch {
            #expect(error as? ExampleCopyError == .invalidEnvironment(line: 2))
            #expect(!error.localizedDescription.contains("private"))
        }
    }
    #expect(throws: ExampleCopyError.noAssignments) { try ExampleCopy.prepare(Data("\n# comment\n".utf8), sourceName: ".env") }
}

@Test func exampleCopyRejectsUnsupportedBinaryAndOversizedInputs() {
    #expect(throws: ExampleCopyError.unsupportedFile) { try ExampleCopy.prepare(Data("{}".utf8), sourceName: "settings.yaml") }
    #expect(throws: ExampleCopyError.notUTF8) { try ExampleCopy.prepare(Data([0xFF]), sourceName: "data.json") }
    #expect(throws: ExampleCopyError.notUTF8) { try ExampleCopy.prepare(Data([0]), sourceName: ".env") }
    #expect(throws: ExampleCopyError.tooLarge) { try ExampleCopy.prepare(Data(repeating: 32, count: ExampleCopy.maximumInputBytes + 1), sourceName: "large.json") }
}

@Test func exampleCopyPreviewIsBoundedButSavingIncludesAllPreparedData() throws {
    let value = String(repeating: "क", count: 70_000)
    let result = try ExampleCopy.prepare(Data(("{\"" + value + "\":\"private\"}").utf8), sourceName: ".settings.json")
    #expect(result.sourcePreview.count == 65_536 && result.examplePreview.count == 65_536)
    #expect(result.previewIsTruncated(source: true) && result.previewIsTruncated(source: false))
    #expect(!result.examplePreview.contains("\u{FFFD}") && result.text.contains("REPLACE_ME"))
    #expect(result.suggestedName == "Configuration example")
    #expect(result.data.count > result.examplePreview.utf8.count)
}

@Test func exampleCopyCaptureAndSafeSavingPreserveSourcesAndExistingOutputs() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("config.json"), original = Data(#"{"token":"original"}"#.utf8)
    try original.write(to: source)
    let result = try ExampleCopy.capture(source)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["config.json"])
    let sameName = try ExampleCopy.save(result, in: folder, stem: "config")
    let unchangedSource = try Data(contentsOf: source)
    #expect(sameName.lastPathComponent == "config 2.json" && unchangedSource == original)
    try Data("changed".utf8).write(to: source)
    let next = try ExampleCopy.save(result, in: folder, stem: "config")
    #expect(next.lastPathComponent == "config 3.json")
    #expect(try Data(contentsOf: sameName) == result.data && Data(contentsOf: next) == result.data)
    #expect(throws: ToolError.self) { try ExampleCopy.save(result, in: folder, stem: "../outside") }
    #expect(!(try FileManager.default.contentsOfDirectory(atPath: folder.path)).contains { $0.hasPrefix(".cloaktools-") })
}

@Test func exampleCopyCancellationRejectsCapturePreparationAndPublication() async throws {
    let result = try ExampleCopy.prepare(Data("KEY=value".utf8), sourceName: ".env")
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        #expect(throws: CancellationError.self) { try ExampleCopy.prepare(Data("{}".utf8), sourceName: "file.json") }
        #expect(throws: CancellationError.self) { try ExampleCopy.capture(URL(fileURLWithPath: "/nonexistent/file.json")) }
        #expect(throws: CancellationError.self) { try ExampleCopy.save(result, in: FileManager.default.temporaryDirectory, stem: "Cancelled example") }
    }
    await task.value
}
