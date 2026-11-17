import Foundation
import Testing
@testable import CloakToolsCore

@Test func jsonFormattingPreservesExactTokensAndOrder() throws {
    let source = #" { "z":9007199254740993123456789, "a":1.2300e+999, "z":-0, "s":"\u0061\/🚀" } "#
    let minified = #"{"z":9007199254740993123456789,"a":1.2300e+999,"z":-0,"s":"\u0061\/🚀"}"#
    #expect(try DeveloperText.json(source, action: .minify) == minified)
    let formatted = try #require(try DeveloperText.json(source, action: .format))
    #expect(formatted.hasPrefix("{\n  \"z\": 9007199254740993123456789,\n"))
    #expect(try DeveloperText.json(formatted, action: .minify) == minified)
    #expect(try DeveloperText.json(formatted, action: .format) == formatted)
    #expect(try DeveloperText.json(source, action: .validate) == nil)
}

@Test func jsonContainersAndTopLevelValues() throws {
    #expect(try DeveloperText.json(#"{"a":[true,false,null,{},[]]}"#, action: .format) == "{\n  \"a\": [\n    true,\n    false,\n    null,\n    {},\n    []\n  ]\n}")
    for input in ["null", "true", "false", "-12.30E-7", #""hello""#, "[]", "{}", #""\uD83D\uDE80""#] {
        #expect(try DeveloperText.json(input, action: .minify) == input)
    }
}

@Test func jsonRejectsInvalidGrammarAndUnicode() {
    for input in ["", " ", "[1,]", #"{"a":1,}"#, "[1 2]", "{a:1}", #"{"a" 1}"#, "01", "+1", ".1", "1.", "1e+", "--1", "NaN", "Infinity", "true false", "nullx", "// hi\n{}", "[", "{", "\"a\nb\"", #""\x20""#, #""\u00xz""#, #""\uD800""#, #""\uDC00""#, #""\uD800\u0041""#, "\"unterminated", "\u{FEFF}{}"] {
        #expect(throws: DeveloperTextError.self) { try DeveloperText.json(input, action: .validate) }
    }
}

@Test func jsonErrorLocationsCountUnicodeAndCRLF() {
    do { _ = try DeveloperText.json("{\r\n  \"é\": 1,\r\n  bad: 2\r\n}", action: .format); Issue.record("Expected invalid JSON") }
    catch let error as DeveloperTextError { #expect(error == .invalidJSON("Expected a quoted object key.", line: 3, column: 3)) }
    catch { Issue.record("Unexpected error: \(error)") }
    do { _ = try DeveloperText.json("[\"🚀\",?]", action: .validate); Issue.record("Expected invalid JSON") }
    catch let error as DeveloperTextError { #expect(error == .invalidJSON("Expected an object, array, string, number, true, false or null.", line: 1, column: 6)) }
    catch { Issue.record("Unexpected error: \(error)") }
}

@Test func jsonDepthAndExpansionAreBounded() throws {
    let boundary = String(repeating: "[", count: 128) + "0" + String(repeating: "]", count: 128)
    #expect(try DeveloperText.json(boundary, action: .validate) == nil)
    #expect(throws: DeveloperTextError.self) { try DeveloperText.json("[" + boundary + "]", action: .validate) }
    let wide = String(repeating: "[", count: 127) + "[" + Array(repeating: "0", count: 40_000).joined(separator: ",") + "]" + String(repeating: "]", count: 127)
    #expect(throws: DeveloperTextError.outputTooLarge) { try DeveloperText.json(wide, action: .format) }
    #expect(try DeveloperText.json(wide, action: .minify) == wide)
}

@Test func base64MatchesRFCVectors() throws {
    for (plain, encoded) in [("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"), ("foob", "Zm9vYg=="), ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy")] {
        #expect(try DeveloperText.encodeBase64(plain) == encoded)
        #expect(try DeveloperText.decodeBase64(encoded) == plain)
    }
}

@Test func base64PreservesUnicodeWhitespaceAndNUL() throws {
    let input = "CloakTools · नमस्ते 🚀\r\n\t\u{0}"
    let encoded = try DeveloperText.encodeBase64(input)
    #expect(try DeveloperText.decodeBase64(encoded) == input)
    #expect(try DeveloperText.decodeBase64(" \n\t" + encoded.prefix(4) + "\r\n" + encoded.dropFirst(4) + " ") == input)
    #expect(try DeveloperText.decodeBase64("Zg") == "f")
}

@Test func base64URLSafeAlphabetIsExplicit() throws {
    #expect(try DeveloperText.encodeBase64("\u{FFFF}", alphabet: .urlSafe) == "77-_")
    #expect(try DeveloperText.decodeBase64("77-_", alphabet: .urlSafe) == "\u{FFFF}")
    #expect(try DeveloperText.encodeBase64("f", alphabet: .urlSafe) == "Zg")
    #expect(try DeveloperText.decodeBase64("Zg==", alphabet: .urlSafe) == "f")
    #expect(throws: DeveloperTextError.invalidBase64) { try DeveloperText.decodeBase64("77-_") }
    #expect(throws: DeveloperTextError.invalidBase64) { try DeveloperText.decodeBase64("77+/", alphabet: .urlSafe) }
}

@Test func base64RejectsGarbagePaddingAndNonCanonicalPadBits() {
    for input in ["!Zg==", "Z", "Zg=", "Zg===", "Z=g=", "=", "====", "Zh==", "Zm9=", "Zg==abc", "Zg\u{00A0}==", "🔒"] {
        #expect(throws: DeveloperTextError.invalidBase64) { try DeveloperText.decodeBase64(input) }
    }
}

@Test func base64RejectsBinaryWithoutLossyReplacement() {
    #expect(throws: DeveloperTextError.nonTextBase64) { try DeveloperText.decodeBase64("/w==") }
    #expect(throws: DeveloperTextError.nonTextBase64) { try DeveloperText.decodeBase64("wK8=") }
}

@Test func developerTextInputLimitsUseUTF8Bytes() throws {
    let boundary = String(repeating: "a", count: DeveloperText.maximumInputBytes)
    #expect(try DeveloperText.encodeBase64(boundary).utf8.count == 1_398_104)
    let oversized = boundary + "a"
    #expect(throws: DeveloperTextError.inputTooLarge) { try DeveloperText.encodeBase64(oversized) }
    #expect(throws: DeveloperTextError.inputTooLarge) { try DeveloperText.decodeBase64(oversized) }
    #expect(throws: DeveloperTextError.inputTooLarge) { try DeveloperText.json(oversized, action: .validate) }
    #expect(throws: DeveloperTextError.inputTooLarge) { try DeveloperText.encodeBase64(String(repeating: "é", count: 524_289)) }
}

@Test func generatedJSONStructuresAgreeWithSystemParser() throws {
    for size in [0, 1, 20, 100] {
        let object: [String: Any] = ["items": (0..<size).map { ["index": $0, "label": "Item \($0)\n🚀"] }, "active": true, "nothing": NSNull()]
        let input = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        for action in [JSONTextAction.format, .minify] {
            let output = try #require(try DeveloperText.json(input, action: action))
            let decoded = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? NSDictionary
            #expect(decoded == object as NSDictionary)
        }
    }
}
