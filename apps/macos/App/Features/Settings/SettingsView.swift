import SwiftUI
import AppKit
import FinderSync
import CloakToolsCore

struct SettingsView: View {
    @Bindable var model: AppModel
    private func preference(_ key: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(get: { model.preferences[keyPath: key] }, set: { value in model.update { $0[keyPath: key] = value } })
    }
    var body: some View {
        TabView(selection: $model.settingsTab) {
            Tab("General", systemImage: "gearshape", value: SettingsCategory.general) { settingsForm { general } }
            Tab("Finder", systemImage: "folder", value: SettingsCategory.finder) { settingsForm { finder } }
            Tab("Images", systemImage: "photo", value: SettingsCategory.conversions) { settingsForm { conversions } }
            Tab("Links", systemImage: "link", value: SettingsCategory.openWith) {
                settingsForm { RoutingSettingsView(model: model, routing: model.routing) }
            }
            if model.preferences.developerToolsEnabled {
                Tab("Developer", systemImage: "chevron.left.forwardslash.chevron.right", value: SettingsCategory.developer) {
                    settingsForm { developer }
                }
            }
            Tab("Privacy", systemImage: "lock.shield", value: SettingsCategory.privacy) { settingsForm { PrivacySettingsView() } }
            Tab("About", systemImage: "info.circle", value: SettingsCategory.about) { settingsForm { about } }
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 480, idealHeight: 600)
        .onDisappear { model.settingsTab = .general }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshFinder() }
    }
    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form {
            if let error = model.persistenceError {
                OperationFeedback(error: error)
            }
            content()
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var general: some View {
        Group {
            Section {
                Toggle(isOn: preference(\.developerToolsEnabled)) {
                    Label("Developer Tools", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Text("Add JSON, Base64, sample and configuration tools, plus code, language starters and technical copy formats. Everyday tools are always available.").foregroundStyle(.secondary)
            } header: { Text("Your tools") } footer: {
                Text("Turning this off hides developer choices. Saved templates, presets and language settings are kept. Open operations keep their original choices.")
            }
            Section("After creating a file") {
                Toggle("Reveal the new file in Finder", isOn: preference(\.revealCreatedFile))
                Toggle("Open after creation", isOn: preference(\.openAfterCreation))
                Text(model.preferences.developerToolsEnabled ? "Text and source files open in TextEdit; PDFs and clipboard images open in Preview. Generated code is never run." : "Text files open in TextEdit; PDFs and clipboard images open in Preview.").foregroundStyle(.secondary)
            }
            Section("Use with Shortcuts") {
                if AutomationAvailability.hasSigningIdentity {
                    Text("Fit an image, collect a Markdown digest, or review a saved file set. Choose CloakTools in the Shortcuts action library.").font(.callout).foregroundStyle(.secondary)
                    Button("Open Shortcuts…", systemImage: "square.stack.3d.up") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init())
                        }
                    }
                } else {
                    Text("Shortcuts actions need a signed build. In this ad-hoc build, use Make It Fit, Markdown Digest and File Sets directly in CloakTools.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Release", value: releaseChannel)
                Text("No account, analytics or cloud processing. Automatic updates are optional.").foregroundStyle(.secondary)
            }
        }
    }
    private var finder: some View {
        Group {
            Section("Finder workspace") {
                LabeledContent("Finder extension", value: model.finderEnabled ? "Enabled" : "Not enabled")
                Text("Blank-space and selected-item menus are scoped to CloakTools Files in your home folder and its subfolders.").foregroundStyle(.secondary)
                Button("Open Finder Workspace", systemImage: "folder", action: model.openWorkspace)
                Button("Manage Finder Extension…") { FIFinderSyncController.showExtensionManagementInterface() }
            }
            Section("Selected items elsewhere") {
                Text("Select a folder in Finder, then choose Services → New File with CloakTools. For a supported image, choose Services → Convert Image with CloakTools.")
                Text("Select PDFs/images to Assemble PDF, or files/folders to Copy As. Both actions also appear in the scoped Finder workspace.")
                Text("If hidden, enable these services in System Settings → Keyboard → Keyboard Shortcuts → Services.").foregroundStyle(.secondary)
            }
            FinderFoldersSection(model: model.finderScopes)
            Section("Access and scope") {
                Text("Every action shows its destination before writing. macOS may request access to protected folders. Finder search results, cloud-provider views, and virtual locations may not offer extension menus.")
                Text("The host runs outside App Sandbox. The Finder extension is sandboxed and only passes requests to the host; it does not write files or convert images.").foregroundStyle(.secondary)
            }
        }
    }
    private var developer: some View {
        Group {
            Section {
                Toggle("Include Hello World in programming files", isOn: preference(\.includeHelloWorld))
            } footer: {
                Text("Off creates blank programming files. Language choices are kept. Changes apply to new operations.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Programming languages") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 16) {
                    ForEach(FileTemplate.allCases.filter(\.isProgramming)) { template in
                        Toggle(isOn: Binding(get: { model.preferences.languageChoices[template.rawValue, default: true] }, set: { value in model.update { $0.languageChoices[template.rawValue] = value } })) {
                            HStack(spacing: 6) {
                                Text(template.title)
                                Text(".\(template.fileExtension)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkbox).disabled(!model.preferences.includeHelloWorld)
                            .accessibilityLabel("Include Hello World in \(template.title)")
                    }
                }.padding(.vertical, 6)
            }
            Section {
                Text("Developer Tools can be turned off in General. Your language choices and saved workflows are kept.").foregroundStyle(.secondary)
                Button("Manage Your Tools…") { model.settingsTab = .general }
            }
        }
    }
    private func imagePreference<Value>(_ key: WritableKeyPath<ImageConversionOptions, Value>) -> Binding<Value> {
        Binding(get: { model.preferences.imageConversion[keyPath: key] }, set: { value in model.update { $0.imageConversion[keyPath: key] = value } })
    }
    private var conversions: some View {
        Group {
            Section("Image conversion defaults") {
                ImageFormatPicker(title: "Format", selection: imagePreference(\.format))
                if model.preferences.imageConversion.format.isLossy {
                    LabeledContent("Quality") { ImageQualitySlider(quality: imagePreference(\.quality)).frame(maxWidth: 240) }
                    Picker("Transparent areas", selection: imagePreference(\.background)) {
                        ForEach(ImageBackground.allCases) { background in Text(background.title).tag(background) }
                    }
                }
                LabeledContent("Location", value: "Beside the original")
                Toggle("Reveal the converted copy in Finder", isOn: preference(\.revealConvertedFile))
                Text("Used for new image conversions. Each operation keeps its own settings and captured image.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
    private var about: some View {
        Group {
            Section {
                HStack(spacing: 14) { Image("AboutAppIcon").resizable().frame(width: 64, height: 64).accessibilityHidden(true); Text("CloakTools").font(.title) }
                Text("Part of Cloakyard · Built by Sumit Sahoo")
                LabeledContent("Version", value: versionLabel)
                LabeledContent("Platform", value: "macOS 27 · Apple silicon")
                if releaseChannel == "Development preview" {
                    Text("Local development build").foregroundStyle(.secondary)
                }
            }
            UpdateSettingsSection()
            Section("Learn more") {
                Link("tools.cloakyard.com", destination: URL(string: "https://tools.cloakyard.com")!)
                Link(destination: AppLinks.support) {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer")
                }
                Text("MIT License. See the repository for source, privacy, contributions, and the roadmap.")
            }
        }
    }
    private var releaseChannel: String {
        Bundle.main.object(forInfoDictionaryKey: "CloakToolsReleaseChannel") as? String ?? "Development preview"
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build)) · \(releaseChannel)"
    }

}
