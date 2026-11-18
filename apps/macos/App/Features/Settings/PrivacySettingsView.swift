import SwiftUI

/// Native summary of the repository's PRIVACY.md; processing details remain app-specific.
struct PrivacySettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 38))
                        .symbolRenderingMode(.hierarchical).foregroundStyle(.tint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Privacy Policy").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        Text("Updated 18 November 2026").font(.callout).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("At a glance").font(.subheadline.weight(.semibold))
                    Label("Files and text are processed on this Mac", systemImage: "internaldrive")
                    Label("No accounts, advertising, analytics or telemetry", systemImage: "lock.shield")
                    Label("Outputs are saved as new files", systemImage: "doc.on.doc")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                Divider()
                policy
                Divider()
                SettingsExternalLink("Read the Full Privacy Policy", symbol: "doc.text", destination: AppLinks.privacy)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var policy: some View {
        VStack(alignment: .leading, spacing: 22) {
            policySection("On This Mac") {
                Text("""
                Preferences, saved templates, folder presets, file sets, export recipes and routing rules stay in your \
                user Library. Saved paths, template contents and rule patterns can contain personal information.
                """)
                Text("""
                Media export uses private temporary source copies and staging files. Normal completion removes them; \
                an abrupt exit can leave temporary files. Only recognized abandoned captures are cleaned up later.
                """)
            }
            policySection("Files and Clipboard") {
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
            policySection("Finder Tools") {
                Text("Folder comparison reads both selected trees, including hidden files. Sharing collections keep paths in memory while open. Saved copies can retain personal metadata. Saving a folder structure as a file set stores the selected relative folder names in your Library.")
            }
            policySection("Links and Permissions") {
                Text("""
                Links are not prefetched and no browsing history is saved. Routing hands the original link to the chosen \
                app; its privacy policy then applies. Email links prepare a draft and never send mail.
                """)
                Text("""
                The main app runs outside App Sandbox; the Finder extension is sandboxed. macOS privacy permissions \
                still apply. User-selected Finder folder access is retained only in appropriately provisioned builds.
                """)
            }
            policySection("Updates") {
                Text(UpdatePrivacyCopy.details)
            }
            policySection("Diagnostics and Removal") {
                Text("""
                CloakTools does not upload crash reports or diagnostics. macOS diagnostics follow your system settings. \
                Restore your preferred link handlers before uninstalling. Removing the app leaves created files and \
                saved settings in place; the full policy explains how to remove local settings.
                """)
            }
        }
    }

    private func policySection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Group { content() }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
