import AppKit
import SwiftUI
import CloakToolsCore

struct FolderPresetSection: View {
    @Bindable var model: AppModel
    @State private var editing: FolderPreset?
    @State private var removing: FolderPreset?
    var body: some View {
        Section {
            if let error = model.presetError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("Reload Presets", action: model.reloadPresets)
            }
            ForEach(model.visibleFolderPresets) { preset in
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.gearshape").foregroundStyle(.blue).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.title).fontWeight(.medium).lineLimit(1).help(preset.title)
                        Text(summary(preset)).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Text((preset.folder.path as NSString).abbreviatingWithTildeInPath)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(preset.folder.path)
                    }
                    Spacer(minLength: 4)
                    Button("Use…") { model.presentPreset(preset) }.accessibilityLabel("Use preset \(preset.title)")
                    Menu {
                        Button("Edit Preset…") { editing = preset }
                        Button("Remove Preset…", role: .destructive) { removing = preset }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for preset \(preset.title)")
                }.padding(.vertical, 3)
            }
            Button("Add Folder Preset…", systemImage: "plus") {
                let panel = NSOpenPanel(); panel.title = "Choose a folder for this preset"; panel.prompt = "Choose Folder"
                panel.canChooseFiles = false; panel.canChooseDirectories = true
                guard panel.runModal() == .OK, let folder = panel.url else { return }
                editing = FolderPreset(title: String((folder.lastPathComponent.isEmpty ? "New preset" : folder.lastPathComponent).prefix(80)), folder: folder)
            }.disabled(model.presetError != nil || model.folderPresets.count >= FolderPresetStore.maximumPresets)
        } header: { Text("Folder presets") } footer: {
            Text("Save a destination and file choices. Each use opens a review.")
        }
        .sheet(item: $editing) { FolderPresetEditor(draft: $0, model: model) }
        .confirmationDialog("Remove this folder preset?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let preset = removing { Button("Remove Preset", role: .destructive) { model.removePreset(preset); removing = nil } }
        } message: { Text("Only the saved preset is removed. Its folder, templates and created files stay unchanged.") }
    }
    private func summary(_ preset: FolderPreset) -> String {
        guard let source = model.templateSources.first(where: { $0.id == preset.templateID }) else { return "Saved template unavailable · Edit to choose another" }
        return "\(preset.name).\(source.fileExtension) · \(source.title)"
    }
}

struct FolderPresetEditor: View {
    @State var draft: FolderPreset
    let model: AppModel
    let sources: [TemplateSource]
    let preferences: Preferences
    init(draft: FolderPreset, model: AppModel) {
        self._draft = State(initialValue: draft); self.model = model
        sources = model.templateSources; preferences = model.preferences
    }
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool
    private var source: TemplateSource? { sources.first { $0.id == draft.templateID } }
    private var isProgramming: Bool { if case let .builtIn(template) = source { template.isProgramming } else { false } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Folder preset", subtitle: "A familiar starting point for your next file.", symbol: "folder.badge.gearshape")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            Text("Preset name").foregroundStyle(.secondary)
                            TextField("e.g. Work notes", text: $draft.title).textFieldStyle(.roundedBorder)
                                .focused($titleFocused).accessibilityLabel("Preset name")
                        }
                        GridRow {
                            Text("File type").foregroundStyle(.secondary)
                            Picker("File type or saved template", selection: $draft.templateID) {
                                ForEach(sources) { Text($0.title).tag($0.id) }
                                if source == nil { Text("Saved template unavailable").tag(draft.templateID) }
                            }.labelsHidden()
                        }
                        GridRow {
                            Text("File name").foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                TextField("Name without extension", text: $draft.name).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Preset file name, without extension")
                                if let source { Text(".\(source.fileExtension)").foregroundStyle(.secondary) }
                            }
                        }
                    }.modifier(DialogCard())
                    VStack(alignment: .leading, spacing: 10) {
                        if isProgramming {
                            Picker("Programming content", selection: $draft.starterPolicy) {
                                ForEach(FolderStarterPolicy.allCases) { Text($0.title).tag($0) }
                            }
                        }
                        if let source {
                            Label(source.contentDescription(using: draft.preferences(from: preferences)), systemImage: "doc")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Text(isProgramming ? "Global Hello World Off and disabled language choices always create blank code. This preset cannot turn them on." : "Saved templates keep their exact contents. Structured files retain a valid blank format.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize)
            DestinationRow(folder: draft.folder, change: chooseFolder)
            OperationFeedback(error: error)
            Text("Saves choices, not a file.").font(.caption).foregroundStyle(.secondary)
            DialogFooter {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                Button("Save Preset") {
                    do { try model.savePreset(draft); dismiss() } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    .disabled(source == nil || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 480, height: 400)
            .onAppear { titleFocused = true }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel(); panel.title = "Choose preset folder"; panel.prompt = "Choose Folder"
        panel.directoryURL = draft.folder; panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let folder = panel.url { draft.folder = folder; error = nil }
    }
}
