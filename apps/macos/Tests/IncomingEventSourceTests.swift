import AppKit
import Carbon
import Testing
@testable import CloakTools

@Test func sourceRequiresCurrentGetURLEventAndSystemPIDType() {
    #expect(IncomingEventSource.bundleIdentifier(in: nil) { _ in "wrong" } == nil)
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
                                       targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    #expect(IncomingEventSource.bundleIdentifier(in: event) { _ in "wrong" } == nil)
    event.setAttribute(NSAppleEventDescriptor(string: "123"), forKeyword: AEKeyword(keySenderPIDAttr))
    #expect(IncomingEventSource.bundleIdentifier(in: event) { _ in "wrong" } == nil)
    event.setAttribute(NSAppleEventDescriptor(int32: 123), forKeyword: AEKeyword(keySenderPIDAttr))
    // macOS does not let a constructed event spoof its read-only sender PID.
    #expect(IncomingEventSource.bundleIdentifier(in: event) { _ in "spoofed" } == nil)
    #expect(IncomingEventSource.bundleIdentifier(in: event) { _ in nil } == nil)
    event.setAttribute(NSAppleEventDescriptor(int32: 0), forKeyword: AEKeyword(keySenderPIDAttr))
    #expect(IncomingEventSource.bundleIdentifier(in: event) { _ in "wrong" } == nil)
}

@Test func documentOpenEventDoesNotEstablishLinkSource() {
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenDocuments),
                                       targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    event.setAttribute(NSAppleEventDescriptor(int32: 123), forKeyword: AEKeyword(keySenderPIDAttr))
    #expect(IncomingEventSource.bundleIdentifier(in: event) { _ in "wrong" } == nil)
}
