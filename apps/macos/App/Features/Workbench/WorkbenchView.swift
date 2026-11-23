import AppKit
import SwiftUI
import CloakToolsCore

struct WorkbenchView: View {
    let model: AppModel
    @Bindable var navigation: WorkbenchNavigation
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var welcome = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @FocusState private var searchFocused: Bool
    private var otherDrafts: [WorkbenchTool] {
        WorkbenchTool.allCases.filter { navigation.drafts[$0] != nil && ($0 != navigation.page || navigation.isSearching) }
    }
    private var categories: [WorkbenchCategory] {
        WorkbenchCategory.visible(developerEnabled: model.preferences.developerToolsEnabled)
    }
    private var searchResults: [WorkbenchTool] {
        WorkbenchTool.matching(navigation.query, developerEnabled: model.preferences.developerToolsEnabled)
    }
    private var linkSheet: Binding<WorkbenchTool?> {
        Binding(get: { [.openLink, .testLink].contains(navigation.page) ? navigation.page : nil },
                set: { if $0 == nil && [.openLink, .testLink].contains(navigation.page) { navigation.back() } })
    }
    private var isCatalog: Bool { navigation.page == nil || linkSheet.wrappedValue != nil || navigation.isSearching }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image("SidebarAppIcon").interpolation(.high)
                    .frame(width: 44, height: 44).accessibilityHidden(true)
                Text("CloakTools").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            }
            SidebarSearchField(query: $navigation.query)
                .fixedSize(horizontal: false, vertical: true)
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var categoryList: some View {
        List(selection: Binding<WorkbenchCategory?>(get: { navigation.category }, set: { if let category = $0 { navigation.browse(category) } })) {
            Section("Categories") {
                ForEach(categories) { category in
                    Label(category.rawValue, systemImage: category.symbol)
                        .frame(minHeight: 36)
                        .tag(category)
                }
            }
            if !otherDrafts.isEmpty {
                Section("In Progress") {
                    ForEach(otherDrafts) { tool in
                        Button { navigation.show(tool, in: categories) } label: {
                            Label {
                                Text(tool.rawValue).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: tool.symbol)
                            }
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Resume " + tool.rawValue)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Tool categories")
    }

    private var settingsFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().accessibilityHidden(true)
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading, spacing: 0) {
                sidebarHeader
                categoryList.clipped()
                settingsFooter
            }
            .navigationSplitViewColumnWidth(min: 208, ideal: 244, max: 300)
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
            .navigationTitle(navigation.isSearching ? "Search Results" : navigation.category.rawValue)
            .toolbar {
                if !isCatalog {
                    ToolbarItem(placement: .navigation) {
                        Button(action: navigation.back) { Label(navigation.backTitle, systemImage: "chevron.backward") }
                            .keyboardShortcut("[", modifiers: .command)
                            .help(navigation.backTitle)
                    }
                } else if !navigation.isSearching && navigation.category == .finder {
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
        .onChange(of: navigation.searchRequest) {
            if columnVisibility == .detailOnly {
                columnVisibility = .all
                Task { @MainActor in
                    await Task.yield()
                    searchFocused = true
                }
            } else {
                searchFocused = true
            }
        }
        .onChange(of: isCatalog) { _, showingCatalog in
            if !showingCatalog || navigation.isSearching { searchFocused = showingCatalog }
        }
        .onChange(of: model.preferences.developerToolsEnabled) { _, enabled in
            if !enabled { navigation.hideDeveloperCategory() }
        }
        .sheet(isPresented: $welcome) { ToolWelcomeView(model: model).interactiveDismissDisabled() }
        .sheet(item: linkSheet) { page in
            if page == .testLink { LinkTester(routing: model.routing) }
            else { OneTimeLink(router: model.router) }
        }
    }

    @ViewBuilder private var catalog: some View {
        let matches = navigation.isSearching ? searchResults : []
        if navigation.isSearching && matches.isEmpty {
            ContentUnavailableView {
                Label("No matching tools", systemImage: "magnifyingglass")
            } description: {
                Text("Try a file type like PDF or an action like resize.")
            } actions: {
                Button("Clear Search") { navigation.query = ""; searchFocused = true }
            }
        } else {
            Form {
                if navigation.isSearching {
                    Section(matches.count == 1 ? "1 tool" : "\(matches.count) tools") {
                        ForEach(matches) { tool in toolRow(tool, singleResult: matches.count == 1) }
                    }
                } else {
                    if navigation.category == .finder {
                        Text("Right-click a selection in Finder and choose Services. You can also start a tool here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(navigation.category.groups) { group in
                        Section(group.title) { ForEach(group.tools) { tool in toolRow(tool) } }
                    }
                }
            }.formStyle(.grouped).scrollBounceBehavior(.basedOnSize)
        }
    }

    private func toolRow(_ tool: WorkbenchTool, singleResult: Bool = false) -> some View {
        let resume = navigation.drafts[tool] != nil
        return Button { launch(tool) } label: {
            HStack(spacing: 12) {
                Image(systemName: tool.symbol).font(.title3).foregroundStyle(.tint).frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.rawValue).fontWeight(.medium)
                    Text(tool.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                if resume { Text("Resume").font(.caption).foregroundStyle(.secondary) }
                if singleResult {
                    Text("⌘↩").font(.callout).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(singleResult ? KeyboardShortcut(.return, modifiers: .command) : nil)
        .accessibilityLabel(Text(resume ? "Resume \(tool.rawValue)" : tool.rawValue))
        .accessibilityHint(Text(tool.detail))
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
        case .structure: model.chooseStructure()
        case .collect: model.collectForSharing([])
        case .compare: model.chooseComparison()
        case .newFile: model.chooseCreationFolder()
        case .clipboard: model.chooseClipboardFolder()
        case .copy: model.chooseCopyFiles()
        case .convert: model.chooseImage()
        case .pdf: model.beginPDFReview()
        case .fileList: model.presentFileList()
        case .fileSet: model.chooseFileSetFolder()
        case .optimize: model.presentOptimizer()
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
        case .folderRules: settings(.general)
        case .linkSettings: settings(.openWith)
        case .languageSettings: settings(.developer)
        case .templates, .savedSets, .presets, .recipes, .openLink, .testLink: navigation.show(tool)
        }
    }
}

private struct SidebarSearchField: NSViewRepresentable {
    @Binding var query: String

    func makeCoordinator() -> Coordinator { Coordinator(query: $query) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Find a tool"
        field.setAccessibilityLabel("Find a tool")
        field.controlSize = .large
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != query { field.stringValue = query }
    }

    @MainActor final class Coordinator: NSObject {
        @Binding var query: String
        init(query: Binding<String>) { _query = query }

        @objc func searchChanged(_ field: NSSearchField) { query = field.stringValue }
    }
}
