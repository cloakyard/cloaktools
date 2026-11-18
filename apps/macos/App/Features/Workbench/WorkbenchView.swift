import AppKit
import SwiftUI
import CloakToolsCore

struct WorkbenchView: View {
    let model: AppModel
    @Bindable var navigation: WorkbenchNavigation
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var welcome = false
    @FocusState private var searchFocused: Bool
    private var otherDrafts: [WorkbenchTool] {
        WorkbenchTool.allCases.filter { navigation.drafts[$0] != nil && $0 != navigation.page }
    }
    private var categories: [WorkbenchCategory] {
        WorkbenchCategory.visible(developerEnabled: model.preferences.developerToolsEnabled)
    }
    private var searching: Bool { !navigation.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var tools: [WorkbenchTool] {
        searching ? WorkbenchTool.matching(navigation.query, developerEnabled: model.preferences.developerToolsEnabled) : navigation.category.tools
    }
    private var linkSheet: Binding<WorkbenchTool?> {
        Binding(get: { [.openLink, .testLink].contains(navigation.page) ? navigation.page : nil },
                set: { navigation.page = $0 })
    }
    private var isCatalog: Bool { navigation.page == nil || linkSheet.wrappedValue != nil || searching }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<WorkbenchCategory?>(get: { navigation.category }, set: { if let category = $0 { navigation.browse(category) } })) {
                Section {
                    ForEach(categories) { category in
                        Label(category.rawValue, systemImage: category.symbol).tag(category)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Image("AboutAppIcon").resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                        Text("CloakTools").font(.headline).foregroundStyle(.primary)
                    }.padding(.vertical, 6)
                }
                if !otherDrafts.isEmpty {
                    Section("In Progress") {
                        ForEach(otherDrafts) { tool in
                            Button {
                                if categories.contains(where: { $0.tools.contains(tool) }) { navigation.show(tool) }
                                else { navigation.query = ""; navigation.page = tool }
                            } label: {
                                Label(tool.rawValue, systemImage: tool.symbol)
                                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Resume " + tool.rawValue)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityLabel("Tool categories")
            .searchable(text: $navigation.query, placement: .sidebar, prompt: "Find a tool")
            .searchFocused($searchFocused)
            .safeAreaInset(edge: .bottom, alignment: .leading) {
                SettingsLink { Label("Settings…", systemImage: "gearshape") }
                    .buttonStyle(.borderless).padding(16)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.persistenceError ?? model.templateLibraryError {
                    OperationFeedback(error: error).padding(.horizontal)
                }
                if isCatalog {
                    catalog
                } else if let page = navigation.page {
                    detail(page).id(page)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(searching ? "Search Results" : navigation.category.rawValue)
            .toolbar {
                if !isCatalog {
                    ToolbarItem(placement: .navigation) {
                        Button { navigation.page = nil } label: { Label("Back to \(navigation.category.rawValue)", systemImage: "chevron.backward") }
                            .help("Back to \(navigation.category.rawValue)")
                    }
                } else if !searching && navigation.category == .finder {
                    ToolbarItem {
                        Button("Finder Setup…", systemImage: "gearshape") { settings(.finder) }.labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 800, minHeight: 600)
        .windowDismissBehavior(navigation.hasBusyDraft ? .disabled : .automatic)
        .onAppear {
            navigation.showWindow = { openWindow(id: "workbench"); NSApp.activate() }
            welcome = !model.preferences.hasChosenTools && model.persistenceError == nil
        }
        .onDisappear { navigation.windowClosed() }
        .onChange(of: navigation.searchRequest) { searchFocused = true }
        .onChange(of: model.preferences.developerToolsEnabled) { _, enabled in
            if !enabled && navigation.category == .developer {
                navigation.category = .finder
                if !navigation.drafts.keys.contains(where: { $0 == navigation.page }) { navigation.page = nil }
            }
        }
        .sheet(isPresented: $welcome) { ToolWelcomeView(model: model).interactiveDismissDisabled() }
        .sheet(item: linkSheet) { page in
            if page == .testLink { LinkTester(routing: model.routing) }
            else { OneTimeLink(router: model.router) }
        }
    }

    @ViewBuilder private var catalog: some View {
        if tools.isEmpty {
            ContentUnavailableView.search(text: navigation.query)
        } else {
            Form {
                Section {
                    ForEach(tools) { tool in
                        Button { launch(tool) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tool.symbol).foregroundStyle(.tint).frame(width: 24).accessibilityHidden(true)
                                Text(tool.rawValue)
                                Spacer(minLength: 4)
                                if navigation.drafts[tool] != nil { Text("Resume").font(.caption).foregroundStyle(.secondary) }
                                Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                            }
                            .padding(.vertical, 7).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.formStyle(.grouped).scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder private func detail(_ page: WorkbenchTool) -> some View {
        if let draft = navigation.drafts[page] {
            draft.view
        } else {
            switch page {
            case .templates: SavedTemplatesView(model: model)
            case .savedSets: Form { FileSetSection(model: model) }.formStyle(.grouped)
            case .presets: Form { FolderPresetSection(model: model) }.formStyle(.grouped)
            case .recipes: Form { ExportRecipeSection(model: model) }.formStyle(.grouped)
            default: catalog
            }
        }
    }

    private func settings(_ tab: SettingsCategory) {
        model.settingsTab = tab
        openSettings()
    }

    private func launch(_ tool: WorkbenchTool) {
        if navigation.drafts[tool] != nil { navigation.show(tool); return }
        switch tool {
        case .newFile: model.chooseCreationFolder()
        case .clipboard: model.chooseClipboardFolder()
        case .copy: model.chooseCopyFiles()
        case .convert: model.chooseImage()
        case .pdf: model.beginPDFReview()
        case .fileList: model.presentFileList()
        case .fileSet: model.chooseFileSetFolder()
        case .fit: model.chooseImageToFit()
        case .pages: model.choosePDFToOrganize()
        case .exportMedia: model.chooseMediaToExport()
        case .cleanup: model.presentTextCleanup()
        case .digest: model.presentMarkdownDigest()
        case .createQR: model.presentQRCode()
        case .readQR: model.presentQRReader()
        case .json: model.presentDeveloperText(.json)
        case .base64: model.presentDeveloperText(.base64)
        case .example: model.presentExampleCopy()
        case .sample: model.presentSampleFiles()
        case .linkSettings: settings(.openWith)
        case .languageSettings: settings(.developer)
        case .templates, .savedSets, .presets, .recipes, .openLink, .testLink: navigation.show(tool)
        }
    }
}
