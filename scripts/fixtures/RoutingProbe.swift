import AppKit
import Foundation
// Test-only registered destination. Records ONLY explicitly delivered synthetic test events.
@MainActor final class Probe: NSObject, NSApplicationDelegate {
    private var bounced: Set<String> = []
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "CloakTools Routing Verification"
        let button = NSButton(title: "Send Synthetic Link to CloakTools", target: self, action: #selector(sendProof))
        button.frame = NSRect(x: 38, y: 54, width: 324, height: 34); button.bezelStyle = .rounded
        window.contentView?.addSubview(button); window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window; NSApp.activate()
    }
    @objc private func sendProof() {
        let host = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Verify/Build/Products/Debug/CloakTools.app")
        let url = URL(string: "https://example.com/cloaktools-source-proof?value=a%26b%3Dc#kept")!
        NSWorkspace.shared.open([url], withApplicationAt: host, configuration: .init()) { _, _ in }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        // Restrict this test fixture to the reserved example host and recipient.
        let urls = urls.filter {
            $0.host() == "example.com" || ($0.scheme == "mailto" && URLComponents(url: $0, resolvingAgainstBaseURL: false)?.path == "hello@example.com")
        }
        guard !urls.isEmpty else { return }
        let file = URL(fileURLWithPath: "/tmp/cloaktools-routing-proof.json")
        let existing = (try? JSONDecoder().decode([String].self, from: Data(contentsOf: file))) ?? []
        try? JSONEncoder().encode(existing + urls.map(\.absoluteString)).write(to: file, options: .atomic)
        for url in urls where url.path == "/cloaktools-loop-proof" && bounced.insert(url.absoluteString).inserted {
            let host = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Verify/Build/Products/Debug/CloakTools.app")
            NSWorkspace.shared.open([url], withApplicationAt: host, configuration: .init()) { _, _ in }
        }
    }
}
let delegate = Probe()
let application = NSApplication.shared
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
