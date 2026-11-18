import Contacts
import Foundation
import Testing
@testable import CloakToolsCore

private let arrival = Date(timeIntervalSince1970: 1_800_000_000)

@Test func allQRContentTypesRoundTripThroughSavedImagesAndTheReader() throws {
    let samples: [(QRContentKind, QRContent)] = [
        (.text, .text("  Café e\u{301}\r\n新しい  ")),
        (.link, .link("https://example.org/project?a=1&b=%2B#info")),
        (.contact, .contact(given: "Asha", family: "Müller", organization: "Studio, A", phone: "+49 30 123456",
                            email: "asha@example.org", website: "https://example.org/")),
        (.wifi, .wifi(ssid: "Studio; Guest", security: .personal, password: #"spaces,quotes":\"#, hidden: true)),
        (.email, .email(recipient: "user+qr@example.org", subject: "Coffee & tea?", body: "Hello\n世界")),
        (.phone, .phone("+1 (202) 555-0148")),
        (.sms, .sms(number: "+91 98765 43210", body: "Ready? + & 😊")),
        (.location, .location(latitude: "-33.8688", longitude: "151.2093")),
        (.event, .event(title: "Meet, greet; review", start: arrival, end: arrival.addingTimeInterval(3600), location: "Room 2"))
    ]
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(Set(samples.map(\.0)) == Set(QRContentKind.allCases))
    for (kind, content) in samples {
        let encoded = try content.encoded()
        let qr = try QRCodeCreation.prepare(encoded)
        let file = try QRCodeCreation.save(qr, in: folder, stem: kind.rawValue)
        let read = try QRCodeReading.read(file)
        let text = try #require(read.codes.first?.text)
        #expect(text.utf8.elementsEqual(encoded.utf8), "Encoded bytes for \(kind)")
        #expect(QRContentKind.recognizing(text) == kind)
        #expect(qr.inputByteCount == encoded.utf8.count)
    }
}

@Test func wifiEscapesDelimitersAndOmitsOldCredentialsFromOpenNetworks() throws {
    let encoded = try QRContent.wifi(ssid: #"a;\,:""#, security: .personal, password: #" a\,;:" "#, hidden: true).encoded()
    #expect(encoded == #"WIFI:T:WPA;S:a\;\\\,\:\";P: a\\\,\;\:\" ;H:true;;"#)
    #expect(try QRContent.wifi(ssid: "Guest", security: .open, password: "prior secret", hidden: false).encoded() == "WIFI:T:nopass;S:Guest;;")
    #expect(try QRContent.wifi(ssid: "Legacy", security: .wep, password: "12345", hidden: false).encoded() == "WIFI:T:WEP;S:Legacy;P:12345;;")
    #expect(throws: (any Error).self) { try QRContent.wifi(ssid: String(repeating: "é", count: 17), security: .open, password: "", hidden: false).encoded() }
    #expect(throws: (any Error).self) { try QRContent.wifi(ssid: "Guest", security: .personal, password: "", hidden: false).encoded() }
}

@Test func qrContactImportsInContactsWithFoldedUnicodeAndEscapedComponents() throws {
    let name = String(repeating: "子", count: 28)
    let family = #"O\,Neil;Jr"#
    let card = try QRContent.contact(given: name, family: family, organization: "Cafés, Inc.; Labs",
                                     phone: "+44 20 7946 0123", email: "user+qr@example.org", website: "https://example.org").encoded()
    #expect(card.contains("\r\n "))
    #expect(card.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
    let contact = try #require(CNContactVCardSerialization.contacts(with: Data(card.utf8)).first)
    #expect(contact.givenName == name && contact.familyName == family)
    #expect(contact.organizationName == "Cafés, Inc.; Labs")
    #expect(contact.emailAddresses.first?.value as String? == "user+qr@example.org")
}

@Test func qrMessagesPreserveReservedCharactersAndNormalizeMailLineEndings() throws {
    let mail = try QRContent.email(recipient: "user+sales@example.org", subject: "A&B? #1", body: "One\rTwo\r\n三\n").encoded()
    #expect(mail == "mailto:user%2Bsales@example.org?subject=A%26B%3F%20%231&body=One%0D%0ATwo%0D%0A%E4%B8%89%0D%0A")
    #expect(try QRContent.sms(number: "+1 (202) 555-0148", body: "A+B?").encoded() == "sms:+12025550148?body=A%2BB%3F")
    #expect(try QRContent.sms(number: "+1 202 555 0148", body: "").encoded() == "sms:+12025550148")
    #expect(try QRContent.phone("+1 (202) 555-0148").encoded() == "tel:+12025550148")
}

@Test func qrCalendarUsesUTCStableIdentityAndEscapedLocation() throws {
    let id = UUID()
    let start = Date(timeIntervalSince1970: 0)
    let text = try QRContent.event(title: "Meet; review", start: start, end: start.addingTimeInterval(3600), location: "Room A, West")
        .encoded(eventID: id, createdAt: start)
    #expect(text.hasPrefix("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"))
    #expect(text.contains("UID:\(id.uuidString)@cloaktools\r\nDTSTAMP:19700101T000000Z\r\n"))
    #expect(text.contains("DTSTART:19700101T000000Z\r\nDTEND:19700101T010000Z\r\nSUMMARY:Meet\\; review\r\nLOCATION:Room A\\, West"))
    #expect(text.hasSuffix("END:VEVENT\r\nEND:VCALENDAR\r\n"))
}

@Test func qrValidatesActiveFieldsAndTheFullSerializedByteBudget() throws {
    let invalid: [QRContent] = [
        .link("file:///Users/example/file"), .link("https://"), .email(recipient: "not an address", subject: "", body: ""),
        .email(recipient: "a@example.org", subject: "hello\r\nbcc:other@example.org", body: ""),
        .phone("++12025550148"), .sms(number: "+44;ext=1", body: ""), .location(latitude: "90.01", longitude: "0"),
        .location(latitude: "-89", longitude: "181"), .location(latitude: "NaN", longitude: "0"), .location(latitude: "-90.00000000000000001", longitude: "0"),
        .event(title: "Invalid", start: arrival, end: arrival, location: ""),
        .contact(given: "", family: "", organization: "", phone: "", email: "", website: ""),
        .contact(given: "Name\r\nEMAIL:extra", family: "", organization: "", phone: "", email: "", website: "")
    ]
    for content in invalid { #expect(throws: (any Error).self) { try content.encoded() } }
    #expect(try QRContent.location(latitude: " -90 ", longitude: "180").encoded() == "geo:-90,180")
    #expect(throws: QRCodeError.inputTooLarge) { try QRContent.sms(number: "+12025550148", body: String(repeating: " ", count: 350)).encoded() }
    #expect(try QRContent.text(String(repeating: "x", count: 1024)).encoded().utf8.count == 1024)
}

@Test func readerExportsContactAndCalendarDocumentsWithoutChangingTheirText() throws {
    let cases: [(QRContent, QRReadFileFormat)] = [
        (.contact(given: "Mina", family: "Patel", organization: "", phone: "", email: "", website: ""), .vCard),
        (.event(title: "Lunch", start: arrival, end: arrival.addingTimeInterval(600), location: "Studio"), .calendar)
    ]
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: parent) }
    for (content, format) in cases {
        let payload = try content.encoded()
        let png = try QRCodeCreation.prepare(payload).png
        let read = try #require(QRCodeReading.prepare(png).codes.first)
        #expect(read.documentFormat == format)
        let output = try QRCodeReading.save(read, in: parent, stem: "From QR", format: format)
        #expect(output.pathExtension == format.rawValue)
        #expect(try Data(contentsOf: output) == Data(payload.utf8))
        let plain = try QRCodeReading.save(read, in: parent, stem: "From QR")
        #expect(plain.pathExtension == "txt")
    }
    let clipped = ReadQRCode(id: 0, text: "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Incomplete", bounds: .zero)
    #expect(clipped.documentFormat == nil)
    #expect(throws: QRReadError.incompatibleFormat) { try QRCodeReading.save(clipped, in: parent, stem: "Bad card", format: .vCard) }
}
