import AppKit
import Carbon

/// Only the current Get URL event's system-supplied sender is evidence.
/// No frontmost-app guessing, profile inspection or source history.
enum IncomingEventSource {
    @MainActor static func current() -> String? {
        bundleIdentifier(in: NSAppleEventManager.shared().currentAppleEvent) { pid in
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
            return id
        }
    }
    static func bundleIdentifier(in event: NSAppleEventDescriptor?, resolve: (pid_t) -> String?) -> String? {
        guard let event, event.eventClass == AEEventClass(kInternetEventClass), event.eventID == AEEventID(kAEGetURL),
              let sender = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr)),
              sender.descriptorType == DescType(typeSInt32), sender.int32Value > 0 else { return nil }
        return resolve(sender.int32Value)
    }
}
