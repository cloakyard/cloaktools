import SwiftUI

/// Native summary of the repository's PRIVACY.md; processing details remain app-specific.
struct PrivacySettingsView: View {
    var body: some View {
        Group {
            Section {
                Label("Local processing", systemImage: "internaldrive")
                Label("No accounts, advertising, analytics or telemetry", systemImage: "lock.shield")
                Label("Your source files stay unchanged", systemImage: "doc.on.doc")
            } header: {
                Text("Your Privacy")
            } footer: {
                Text("CloakTools processes the files and text you choose on this Mac. It does not upload your content.")
            }
            Section("On This Mac") {
                Text("""
                Preferences, saved templates, folder presets, file sets, export recipes and routing rules stay in your \
                user Library. Saved paths, template contents and rule patterns can contain personal information.
                """)
                Text("""
                Media export uses private temporary source copies and staging files. Normal completion removes them; \
                an abrupt exit can leave temporary files. Only recognized abandoned captures are cleaned up later.
                """)
            }
            Section("Files and Clipboard") {
                Text("""
                Tools read the sources you select. Clipboard input is read only when you invoke it; there is no clipboard \
                monitoring or history. Copy actions replace the clipboard only when requested. Other apps may read it \
                under macOS controls. Outputs are new files; originals are not overwritten.
                """)
                Text("""
                Metadata behavior depends on the tool. Image conversion excludes camera and location metadata; \
                Base64 image copies preserve original bytes. PDFs and file lists can contain personal information. \
                Review output before sharing. A cloud-managed destination may synchronize through its own service.
                """)
            }
            Section("Links and Permissions") {
                Text("""
                Links are not prefetched and no browsing history is saved. Routing hands the original link to the chosen \
                app; its privacy policy then applies. Email links prepare a draft and never send mail.
                """)
                Text("""
                The main app runs outside App Sandbox; the Finder extension is sandboxed. macOS privacy permissions \
                still apply. User-selected Finder folder access is retained only in appropriately provisioned builds.
                """)
            }
            Section("Updates") {
                Text(UpdatePrivacyCopy.details)
            }
            Section("Diagnostics and Removal") {
                Text("""
                CloakTools does not upload crash reports or diagnostics. macOS diagnostics follow your system settings. \
                Restore your preferred link handlers before uninstalling. Removing the app leaves created files and \
                saved settings in place; the full policy explains how to remove local settings.
                """)
            }
            Section {
                Link("Read the Full Privacy Policy", destination: AppLinks.privacy)
            } footer: {
                Text("Policy updated 17 November 2026. External links open in your browser only when you choose them.")
            }
        }
    }
}
