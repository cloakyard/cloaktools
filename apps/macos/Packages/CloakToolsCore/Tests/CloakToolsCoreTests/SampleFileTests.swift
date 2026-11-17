import Foundation
import Testing
@testable import CloakToolsCore

@Test func sampleJSONContainsDeterministicSyntheticRecordsAndEdgeCases() throws {
    let prepared = try SampleFiles.generate(.json(records: 5))
    let records = try #require(try JSONSerialization.jsonObject(with: prepared.data) as? [[String: Any]])
    #expect(records.count == 5 && records[0]["id"] as? Int == 1 && records[4]["id"] as? Int == 5)
    #expect(records[0]["email"] as? String == "sample1@example.com")
    #expect(records[1]["active"] as? Bool == false)
    #expect(records[2]["note"] as? String == "A \"quoted\" value")
    #expect(records[3]["note"] as? String == "First line\nSecond line")
    #expect(records[4]["note"] as? String == "Unicode · नमस्ते 🚀")
    #expect(prepared.data == (try SampleFiles.generate(.json(records: 5))).data)
    #expect(prepared.fileExtension == "json" && prepared.canCopyText && prepared.previewDetail == "Complete preview")
    #expect(prepared.preview.data(using: .utf8) == prepared.data)
}

@Test func sampleCSVEscapesCommasQuotesAndMultilineFields() throws {
    let prepared = try SampleFiles.generate(.csv(records: 5))
    let csv = String(decoding: prepared.data, as: UTF8.self)
    #expect(csv.hasPrefix("id,name,email,active,note\r\n1,Sample item 1,sample1@example.com,true,Ready to test\r\n"))
    #expect(csv.contains("2,Sample item 2,sample2@example.com,false,\"Contains, a comma\"\r\n"))
    #expect(csv.contains("\"A \"\"quoted\"\" value\"\r\n"))
    #expect(csv.contains("\"First line\nSecond line\"\r\n"))
    #expect(csv.hasSuffix("Unicode · नमस्ते 🚀\r\n"))
    #expect(prepared.fileExtension == "csv" && prepared.canCopyText)
}

@Test func sampleSizedFilesAreExactAndRemainValidUTF8OrZeroBytes() throws {
    for count in [1, 27, 28, 29, 1024, 8193, 1_048_576, SampleFiles.maximumBytes] {
        let text = try SampleFiles.generate(.text(bytes: count))
        let binary = try SampleFiles.generate(.binary(bytes: count))
        #expect(text.data.count == count && binary.data.count == count)
        #expect(String(data: text.data, encoding: .utf8) != nil)
        #expect(text.data.starts(with: Data("Sample text from CloakTools.\n".utf8).prefix(count)))
        #expect(binary.data.allSatisfy { $0 == 0 })
        #expect(binary.preview.hasPrefix("00000000  00") && !binary.canCopyText)
        #expect(binary.preview.utf8.count <= 256 && text.preview.utf8.count <= SampleFiles.previewBytes)
    }
}

@Test func sampleRequestParsingIsStrictAndUnitsDoNotOverflow() throws {
    #expect(try SampleFileRequest(format: .text, recordsText: "unused", sizeText: " 2 ", unit: .kibibytes) == .text(bytes: 2048))
    #expect(try SampleFileRequest(format: .binary, recordsText: "unused", sizeText: "32", unit: .mebibytes) == .binary(bytes: SampleFiles.maximumBytes))
    #expect(try SampleFileRequest(format: .json, recordsText: "0010", sizeText: "unused", unit: .bytes) == .json(records: 10))
    for invalid in ["", "0", "-1", "+1", "1.5", "1e3", "1,000", "١", "999999999999999999999999"] {
        #expect(throws: SampleFileError.invalidSize) { try SampleFileRequest(format: .binary, recordsText: "10", sizeText: invalid, unit: .bytes) }
        #expect(throws: SampleFileError.invalidRecordCount) { try SampleFileRequest(format: .csv, recordsText: invalid, sizeText: "1", unit: .bytes) }
    }
    #expect(throws: SampleFileError.invalidSize) { try SampleFileRequest(format: .binary, recordsText: "10", sizeText: "33", unit: .mebibytes) }
    #expect(throws: SampleFileError.invalidRecordCount) { try SampleFileRequest(format: .json, recordsText: "10001", sizeText: "1", unit: .bytes) }
}

@Test func sampleGenerationEnforcesBoundsBeforeAllocation() {
    for request in [SampleFileRequest.json(records: 0), .csv(records: 10001), .json(records: Int.max)] {
        #expect(throws: SampleFileError.invalidRecordCount) { try SampleFiles.generate(request) }
    }
    for request in [SampleFileRequest.text(bytes: 0), .binary(bytes: -1), .text(bytes: SampleFiles.maximumBytes + 1), .binary(bytes: Int.max)] {
        #expect(throws: SampleFileError.invalidSize) { try SampleFiles.generate(request) }
    }
}

@Test func sampleLargeRecordFilesAndPreviewsStayValid() throws {
    let json = try SampleFiles.generate(.json(records: SampleFiles.maximumRecords))
    let records = try #require(try JSONSerialization.jsonObject(with: json.data) as? [[String: Any]])
    #expect(records.count == 10_000 && records.last?["id"] as? Int == 10_000)
    for file in [json, try SampleFiles.generate(.csv(records: SampleFiles.maximumRecords))] {
        #expect(file.data.count < SampleFiles.maximumBytes)
        #expect(file.preview.utf8.count <= SampleFiles.previewBytes && !file.preview.contains("\u{FFFD}"))
        #expect(file.data.starts(with: file.preview.utf8))
        #expect(file.previewDetail.contains("include everything"))
    }
}

@Test func sampleSavingUsesPreparedBytesAndPreservesCollisions() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let json = try SampleFiles.generate(.json(records: 5))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    let first = try SampleFiles.save(json, in: folder, stem: "Fixture")
    let second = try SampleFiles.save(json, in: folder, stem: "Fixture")
    #expect(first.lastPathComponent == "Fixture.json" && second.lastPathComponent == "Fixture 2.json")
    #expect(try Data(contentsOf: first) == json.data && Data(contentsOf: second) == json.data)
    #expect(throws: ToolError.self) { try SampleFiles.save(json, in: folder, stem: "../outside") }
    let binary = try SampleFiles.generate(.binary(bytes: 8193))
    let output = try SampleFiles.save(binary, in: folder, stem: "Bytes")
    let savedBytes = try Data(contentsOf: output)
    #expect(output.pathExtension == "bin" && savedBytes.count == 8193)
    #expect(!(try FileManager.default.contentsOfDirectory(atPath: folder.path)).contains { $0.hasPrefix(".cloaktools-") })
}

@Test func cancelledSampleGenerationDoesNotProduceAFile() async {
    let task = Task { () throws -> PreparedSampleFile in
        withUnsafeCurrentTask { $0?.cancel() }
        return try SampleFiles.generate(.binary(bytes: SampleFiles.maximumBytes))
    }
    do { _ = try await task.value; Issue.record("Cancelled generation should fail") }
    catch { #expect(error is CancellationError) }
}
