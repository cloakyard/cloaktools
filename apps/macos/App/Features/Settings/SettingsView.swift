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
            Tab("Privacy", systemImage: "lock.shield", value: SettingsCategory.privacy) { PrivacySettingsView() }
            Tab("About", systemImage: "info.circle", value: SettingsCategory.about) { settingsForm { about } }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = model.persistenceError { OperationFeedback(error: error).padding(.horizontal) }
        }
        .frame(minWidth: 640, idealWidth: 640, maxWidth: .infinity,
               minHeight: 480, idealHeight: 600, maxHeight: .infinity)
        .onDisappear { model.settingsTab = .general }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshFinder() }
    }
    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form(content: content)
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)
    }

    private var general: some View {
        Group {
            Section {
                Toggle("Developer Tools", isOn: preference(\.developerToolsEnabled))
            } header: { Text("Your tools") } footer: {
                Text("Adds JSON, Base64, code starters, sample files and developer copy formats. Turning it off preserves saved items, language choices and open drafts.")
            }
            Section {
                Toggle("Reveal the new file in Finder", isOn: preference(\.revealCreatedFile))
                Toggle("Open after creation", isOn: preference(\.openAfterCreation))
            } header: { Text("After creating a file") } footer: {
                Text(model.preferences.developerToolsEnabled ? "Text and source files open in TextEdit. PDFs and clipboard images open in Preview." : "Text files open in TextEdit. PDFs and clipboard images open in Preview.")
            }
            Section {
                if AutomationAvailability.hasSigningIdentity {
                    Button("Open Shortcuts…", systemImage: "square.stack.3d.up") {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts") {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init())
                        }
                    }
                } else {
                    LabeledContent("Shortcuts actions", value: "Unavailable in this build")
                }
            } header: { Text("Use with Shortcuts") } footer: {
                Text(AutomationAvailability.hasSigningIdentity ? "Choose CloakTools in the Shortcuts action library to fit an image, collect a Markdown digest or review a file set." : "Shortcuts requires a build with a signing identity. You can fit an image, collect a Markdown digest or review a file set in the Workbench.")
            }
        }
    }
    private var finder: some View {
        Group {
            Section {
                LabeledContent("Finder extension", value: model.finderEnabled ? "Enabled" : "Not enabled")
                Button("Open Finder Workspace", systemImage: "folder", action: model.openWorkspace)
                Button("Manage Finder Extension…") { FIFinderSyncController.showExtensionManagementInterface() }
            } header: { Text("Finder workspace") } footer: {
                Text("Right-click a file or an empty area in CloakTools Files in your home folder. The extension also works in its subfolders.")
            }
            FinderFoldersSection(model: model.finderScopes)
            Section {
                LabeledContent("New File with CloakTools", value: "Select a folder")
                LabeledContent("Convert Image with CloakTools", value: "Select one image")
                LabeledContent("Assemble PDF with CloakTools", value: "Select PDFs or images")
                LabeledContent("Copy As with CloakTools", value: "Select files or folders")
            } header: { Text("Finder Services") } footer: {
                Text("In other folders, select items and open Finder’s Services menu. Enable missing actions in System Settings → Keyboard → Keyboard Shortcuts → Services.")
            }
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
                Button("Manage Your Tools…") { model.settingsTab = .general }
            } footer: { Text("Turn Developer Tools on or off in General. Your language choices and saved workflows are kept.") }
        }
    }
    private func imagePreference<Value>(_ key: WritableKeyPath<ImageConversionOptions, Value>) -> Binding<Value> {
        Binding(get: { model.preferences.imageConversion[keyPath: key] }, set: { value in model.update { $0.imageConversion[keyPath: key] = value } })
    }
    private var conversions: some View {
        Group {
            Section {
                ImageFormatPicker(title: "Format", selection: imagePreference(\.format))
                if model.preferences.imageConversion.format.isLossy {
                    LabeledContent("Quality") { ImageQualitySlider(quality: imagePreference(\.quality)).frame(maxWidth: 240) }
                    Picker("Transparent areas", selection: imagePreference(\.background)) {
                        ForEach(ImageBackground.allCases) { background in Text(background.title).tag(background) }
                    }
                }
                LabeledContent("Location", value: "Beside the original")
                Toggle("Reveal the converted copy in Finder", isOn: preference(\.revealConvertedFile))
            } header: { Text("Image conversion defaults") } footer: {
                Text("These defaults apply when you start a conversion. Open conversions keep their current settings.")
            }
        }
    }
    private var about: some View {
        Group {
            Section {
                VStack(spacing: 12) {
                    Image("AboutAppIcon").resizable().scaledToFit()
                        .frame(width: 84, height: 84).accessibilityHidden(true)
                    VStack(spacing: 3) {
                        Text("Cloak\(Text("Tools").foregroundStyle(Color.accentColor))")
                            .font(.title2.weight(.semibold)).accessibilityLabel("CloakTools")
                            .accessibilityAddTraits(.isHeader)
                        Text("Version \(versionLabel)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        Text("Created by Sumit Sahoo · Cloakyard").font(.footnote).foregroundStyle(.secondary)
                            .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowInsets(EdgeInsets())
            }
            UpdateSettingsSection()
            Section {
                SettingsExternalLink("tools.cloakyard.com", symbol: "globe", destination: AppLinks.website)
                SettingsExternalLink("github.com/cloakyard/cloaktools", symbol: "chevron.left.forwardslash.chevron.right", destination: AppLinks.repository)
                SettingsExternalLink("Report a Bug", symbol: "ladybug", destination: AppLinks.issues)
                SettingsExternalLink("Buy me a coffee", symbol: "cup.and.saucer", destination: AppLinks.support)
            } footer: { Text("macOS 27 · Apple silicon · MIT License") }
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

struct SettingsExternalLink: View {
    let title: String
    let symbol: String
    let destination: URL

    init(_ title: String, symbol: String, destination: URL) {
        self.title = title
        self.symbol = symbol
        self.destination = destination
    }

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20).accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
            }.contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
