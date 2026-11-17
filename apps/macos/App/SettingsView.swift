import SwiftUI
import AppKit
import FinderSync
import CloakToolsCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var editingTemplate: CustomTemplate?
    @State private var removingTemplate: CustomTemplate?
    @State private var showingWelcome = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selection: Binding<SettingsCategory?> { Binding(get: { model.preferences.lastCategory }, set: { if let category = $0 { model.update { $0.lastCategory = category } } }) }
    private func preference(_ key: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(get: { model.preferences[keyPath: key] }, set: { value in model.update { $0[keyPath: key] = value } })
    }
    var body: some View {
        NavigationSplitView {
            List(model.preferences.tools.categories, selection: selection) { category in
                HStack(spacing: 10) {
                    Image(systemName: symbol(category)).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white).frame(width: 25, height: 25)
                        .background(categoryColor(category).gradient, in: .rect(cornerRadius: 6)).accessibilityHidden(true)
                    Text(category.title)
                }.tag(category).padding(.vertical, 3)
            }
            .navigationTitle("CloakTools")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
            .accessibilityLabel("Settings categories")
        } detail: {
            VStack(spacing: 0) {
                if let error = model.persistenceError ?? model.templateLibraryError {
                    Label(error, systemImage: "exclamationmark.triangle").padding().foregroundStyle(.red)
                }
                Form {
                    switch model.preferences.lastCategory {
                    case .general: general
                    case .finder: finder
                    case .newFiles: newFiles
                    case .conversions: conversions
                    case .developer: developer
                    case .openWith: RoutingSettingsView(model: model, routing: model.routing)
                    case .about: about
                    }
                }
                .formStyle(.grouped)
                .id(model.preferences.lastCategory)
                .id(model.settingsNavigationID)
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle(model.preferences.lastCategory.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .transaction { if reduceMotion { $0.animation = nil } }
        .onAppear { showingWelcome = !model.preferences.hasChosenTools && model.persistenceError == nil }
        .sheet(isPresented: $showingWelcome) { ToolWelcomeView(model: model).interactiveDismissDisabled() }
        .sheet(item: $editingTemplate) { TemplateDetails(template: $0, model: model) }
        .confirmationDialog("Remove saved template?", isPresented: Binding(get: { removingTemplate != nil }, set: { if !$0 { removingTemplate = nil } })) {
            if let template = removingTemplate {
                Button("Remove \(template.title)", role: .destructive) { model.removeTemplate(template); removingTemplate = nil }
            }
        } message: { Text("The saved copy will be removed from CloakTools. Its original file and files already created stay unchanged.") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshFinder() }
    }
    private var general: some View {
        Group {
            Section {
                Label("A few useful things, close at hand.", systemImage: "wrench.and.screwdriver")
                    .font(.title3)
                Text("Create files, prepare images, PDFs and media, or choose where a link opens. Everything starts on your Mac.")
                    .foregroundStyle(.secondary)
            }
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
            Section("Quick actions") {
                ToolLauncherRow(title: "New File", subtitle: "Choose a type or saved template.", symbol: "doc.badge.plus", action: model.chooseCreationFolder)
                ToolLauncherRow(title: "New File Set", subtitle: "Review related files and create them together.", symbol: "folder.badge.plus") { model.chooseFileSetFolder() }
                ToolLauncherRow(title: "Make It Fit", subtitle: "Prepare an image within a size limit.", symbol: "arrow.down.right.and.arrow.up.left", action: model.chooseImageToFit)
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
                    Text("Shortcuts actions need a signed build. In this local preview, use Make It Fit, Markdown Digest and File Sets directly in CloakTools.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                LabeledContent("Release", value: "Development preview")
                Text("No account, analytics, background update checks, or cloud processing.").foregroundStyle(.secondary)
            }
        }
    }
    private var finder: some View {
        Group {
            Section("File lists") {
                ToolLauncherRow(title: "File List", subtitle: "Export selected names and details as CSV or Markdown.", symbol: "list.bullet.rectangle", action: model.presentFileList)
            }
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
                Text("This local preview runs the host outside App Sandbox. The Finder extension is sandboxed and only passes requests to the host; it does not write files or convert images.").foregroundStyle(.secondary)
            }
            Section("Copy names and paths") {
                Button("Copy As…", systemImage: "list.clipboard", action: model.chooseCopyFiles)
                Text(model.preferences.developerToolsEnabled ? "Preview full paths, names, file URLs, shell arguments, Markdown links or a JSON path list before copying. Up to 200 items; file contents are never read." : "Preview full paths, names, file URLs or Markdown links before copying. Up to 200 items; file contents are never read.").foregroundStyle(.secondary)
            }
        }
    }
    private var newFiles: some View {
        Group {
            Section("Create files") {
                ToolLauncherRow(title: "New File", subtitle: "Choose a type or template, then review where it goes.", symbol: "doc.badge.plus", action: model.chooseCreationFolder)
                DisclosureGroup("Built-in file types") {
                    ForEach(model.preferences.tools.builtInTemplates.filter { !$0.isProgramming }) { template in
                        LabeledContent(template.title, value: ".\(template.fileExtension) · \(template == .pdf ? "One A4 page" : template == .json ? "Empty object" : "Blank")")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(template.title).accessibilityValue(TemplateSource.builtIn(template).contentDescription(using: model.preferences))
                    }
                    if model.preferences.developerToolsEnabled {
                        Text("Programming languages are also available in New File.").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Saved templates") {
                ForEach(model.visibleCustomTemplates) { template in
                    HStack(spacing: 10) {
                        Button { model.toggleFavorite(TemplateSource.custom(template).id) } label: {
                            Image(systemName: model.preferences.favoriteTemplateIDs.contains(TemplateSource.custom(template).id) ? "star.fill" : "star")
                        }.buttonStyle(.borderless).accessibilityLabel("Toggle favorite for \(template.title)")
                            .accessibilityValue(model.preferences.favoriteTemplateIDs.contains(TemplateSource.custom(template).id) ? "Favorite" : "Not a favorite")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.title)
                            Text(".\(template.fileExtension) · \(template.content.count.formatted()) bytes").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Edit Details…") { editingTemplate = template }
                            Button("Remove…", role: .destructive) { removingTemplate = template }
                        } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .accessibilityLabel("Options for \(template.title)").help("Template options")
                    }
                }
                Button("Import Template…", systemImage: "square.and.arrow.down", action: model.importTemplate)
                Text("Import up to 1 MiB of UTF-8 text. Saved content stays exact; favorites appear first in New File.").font(.callout).foregroundStyle(.secondary)
            }
            FileSetSection(model: model)
            FolderPresetSection(model: model)
            Section("Text & sharing") {
                ToolLauncherRow(title: "Markdown Digest", subtitle: "Collect selected text files in one reviewed document.", symbol: "doc.text", action: model.presentMarkdownDigest)
                DisclosureGroup {
                    ToolLauncherRow(title: "QR Code", subtitle: "Create a code or read one from an image.", symbol: "qrcode", action: model.presentQRCode)
                    ToolLauncherRow(title: "Text Cleanup", subtitle: "Tidy spaces, tabs and empty lines with a preview.", symbol: "text.alignleft", action: model.presentTextCleanup)
                    ToolLauncherRow(title: "Clipboard to File", subtitle: "Review copied text or an image, then save a new file.", symbol: "doc.on.clipboard", action: model.chooseClipboardFolder)
                } label: {
                    ToolGroupLabel(title: "More text tools", subtitle: "QR codes, cleanup and clipboard files")
                }
            }
        }
    }
    private var developer: some View {
        Group {
            Section("Text & data") {
                ForEach(DeveloperTextTool.allCases) { tool in
                    ToolLauncherRow(title: tool.title, subtitle: tool.subtitle, symbol: tool.symbol, tint: .teal) { model.presentDeveloperText(tool) }
                }
                ToolLauncherRow(title: "Sample Files", subtitle: "Synthetic records and files of an exact size.", symbol: "doc.badge.gearshape", tint: .teal, action: model.presentSampleFiles)
                ToolLauncherRow(title: "Example Copy", subtitle: "Turn JSON or .env values into placeholders.", symbol: "doc.on.doc", tint: .teal, action: model.presentExampleCopy)
            }
            Section {
                Text("Programming and JSON files are available in New File. Shell arguments and JSON path lists are available in Copy As.").foregroundStyle(.secondary)
                Button("Create a File…", action: model.chooseCreationFolder)
            } header: { Text("Files & starters") }
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
                Button("Manage Your Tools…") { model.update { $0.lastCategory = .general } }
            }
        }
    }
    private func imagePreference<Value>(_ key: WritableKeyPath<ImageConversionOptions, Value>) -> Binding<Value> {
        Binding(get: { model.preferences.imageConversion[keyPath: key] }, set: { value in model.update { $0.imageConversion[keyPath: key] = value } })
    }
    private var conversions: some View {
        Group {
            Section("Prepare a copy") {
                ToolLauncherRow(title: "Make It Fit", subtitle: "Preview an image within your size and dimension limits.", symbol: "arrow.down.right.and.arrow.up.left", tint: .orange, action: model.chooseImageToFit)
                ToolLauncherRow(title: "Export Media", subtitle: "Preview a full clip, then save MP4 video or M4A audio.", symbol: "play.rectangle", tint: .orange, action: model.chooseMediaToExport)
            }
            ExportRecipeSection(model: model)
            Section {
                DisclosureGroup {
                    ToolLauncherRow(title: "Convert Image", subtitle: "Create a PNG, JPEG or HEIC copy.", symbol: "photo", tint: .orange, action: model.chooseImage)
                    ToolLauncherRow(title: "Assemble PDF", subtitle: "Combine PDFs and images in the order you choose.", symbol: "doc.on.doc", tint: .orange, action: model.choosePDFFiles)
                    ToolLauncherRow(title: "Organize PDF", subtitle: "Include, reorder and rotate pages in a new copy.", symbol: "square.grid.2x2", tint: .orange, action: model.choosePDFToOrganize)
                } label: {
                    ToolGroupLabel(title: "Image & PDF tools", subtitle: "Convert images, combine PDFs or arrange pages")
                }
                DisclosureGroup("Image conversion defaults") {
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
                DisclosureGroup("Supported files & limits") {
                    Text("Images: PNG, JPEG, TIFF or HEIC, one frame, up to 40 megapixels and 100 MB. Output uses sRGB; original metadata is not kept.")
                    Text("PDF assembly: up to 32 PDFs/images, 200 pages and 200 MB total. Page organization: one PDF up to 200 pages and 100 MB. Encrypted PDFs, forms and signatures are unsupported.")
                    Text("Media: compatible video or audio up to 1 GB and 30 minutes. Presets are checked for each source. Exports use MP4/H.264 or M4A/AAC.")
                }.font(.callout).foregroundStyle(.secondary)
            } header: { Text("More options") } footer: { Text("Review each operation before saving. Originals stay unchanged; existing filenames receive numbered copies.") }
        }
    }
    private var about: some View {
        Group {
            Section {
                HStack(spacing: 14) { Image("AboutAppIcon").resizable().frame(width: 64, height: 64).accessibilityHidden(true); Text("CloakTools").font(.title) }
                Text("Part of Cloakyard · Built by Sumit Sahoo")
                LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0") · Development preview")
                LabeledContent("Platform", value: "macOS 27 · Apple silicon")
                Text("A local development build. No public installer is available yet.").foregroundStyle(.secondary)
            }
            Section("Learn more") {
                Link("tools.cloakyard.com", destination: URL(string: "https://tools.cloakyard.com")!)
                Link(destination: AppLinks.support) {
                    Label("Buy me a coffee", systemImage: "cup.and.saucer")
                }
                Text("MIT License. See the repository for source, privacy, contributions, and the roadmap.")
            }
        }
    }
    private func categoryColor(_ category: SettingsCategory) -> Color {
        switch category {
        case .general, .about: .gray
        case .finder: .blue
        case .newFiles: .indigo
        case .conversions: .orange
        case .developer: .teal
        case .openWith: .purple
        }
    }
    private func symbol(_ category: SettingsCategory) -> String {
        switch category {
        case .general: "gearshape"; case .finder: "folder"; case .newFiles: "doc.badge.plus"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .conversions: "arrow.triangle.2.circlepath"; case .openWith: "arrow.up.forward.app"; case .about: "info.circle"
        }
    }
}
