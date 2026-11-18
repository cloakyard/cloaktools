import Foundation
import CloakToolsCore
import Testing
@testable import CloakTools

@MainActor @Test func qrReviewSurvivesFieldCommitAndInvalidatesChangedBytes() async throws {
    let operation = QRCodeOperation()
    operation.draft.kind = .contact
    operation.draft.given = "Mina"
    operation.generate()
    operation.draft.given = "Mina"
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(5))
    while operation.busy, clock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(operation.prepared != nil)
    operation.draft.given = "Mina"
    #expect(operation.prepared != nil)
    operation.draft.given = "Mína"
    #expect(operation.prepared == nil)
    operation.draft.kind = .text
    operation.draft.text = "é"
    operation.generate()
    operation.draft.text = "e\u{301}"
    #expect(operation.prepared == nil && operation.payload?.utf8.elementsEqual("e\u{301}".utf8) == true)
}

@MainActor @Test func qrFormsKeepIndependentFieldsNamesAndActionEligibility() throws {
    let operation = QRCodeOperation()
    operation.draft.kind = .wifi
    operation.draft.ssid = "Studio; Guest"
    #expect(operation.payload == nil)
    operation.draft.password = "example-only"
    operation.name = "Guest network"
    operation.draft.kind = .event
    #expect(operation.name == "Calendar event" && operation.payload == nil)
    operation.draft.eventTitle = "Planning"
    let event = try #require(operation.payload)
    operation.draft.eventTitle = "Planning"
    #expect(operation.payload == event)
    operation.draft.eventTitle = "A different event"
    let second = try #require(operation.payload)
    #expect(event.components(separatedBy: "\r\n").first { $0.hasPrefix("UID:") } != second.components(separatedBy: "\r\n").first { $0.hasPrefix("UID:") })
    operation.draft.kind = .wifi
    #expect(operation.name == "Guest network" && operation.payload?.contains("example-only") == true)
    operation.draft.security = .open
    #expect(operation.payload == "WIFI:T:nopass;S:Studio\\; Guest;;")
    #expect(WorkbenchTool.matching("vcard", developerEnabled: false).contains(.createQR))
}
