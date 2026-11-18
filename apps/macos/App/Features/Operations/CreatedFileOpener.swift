import AppKit

@MainActor
enum CreatedFileOpener {
    static func open(_ url: URL, inPreview: Bool, completion: @escaping @MainActor @Sendable (String?) -> Void) {
        // Explicit viewers never execute source through a shell/runtime file association.
        let bundleID = inPreview ? "com.apple.Preview" : "com.apple.TextEdit"
        guard let viewer = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            completion("File saved, but \(inPreview ? "Preview" : "TextEdit") is unavailable. Reveal it in Finder to open it."); return
        }
        NSWorkspace.shared.open([url], withApplicationAt: viewer, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            let message = error.map { "File saved, but it couldn’t be opened: \($0.localizedDescription)" }
            Task { @MainActor in completion(message) }
        }
    }
}
