import SwiftUI
import CloakToolsCore

struct FileSetSection: View {
    @Bindable var model: AppModel
    @State private var removing: FileSetDefinition?
    var body: some View {
        Section {
            if let error = model.fileSetError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("Reload File Sets", action: model.reloadFileSets)
            }
            ForEach(model.visibleFileSets) { set in
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus").foregroundStyle(.blue).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(set.title).fontWeight(.medium).lineLimit(1).help(set.title)
                        Text("\(set.entries.filter { $0.templateID != nil }.count) files · \(set.folderName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button("Use…") { model.chooseFileSetFolder(set) }.accessibilityLabel("Use file set \(set.title)")
                    RowActionsMenu(title: "Actions for file set \(set.title)") {
                        Button("Edit & Review…") { model.chooseFileSetFolder(set) }
                        Button("Remove Saved Set…", role: .destructive) { removing = set }
                    }
                }.padding(.vertical, 3)
            }
            HStack(spacing: 16) {
                Button("New File Set…", systemImage: "folder.badge.plus") { model.chooseFileSetFolder() }
                if model.preferences.developerToolsEnabled {
                    Menu("Start with…") {
                        Button("Notes") { model.chooseFileSetFolder(.notes) }
                        Button("Python Files") { model.chooseFileSetFolder(.sourceFiles(.python)) }
                        Button("Rust Files") { model.chooseFileSetFolder(.sourceFiles(.rust)) }
                        Button("C++ Files") { model.chooseFileSetFolder(.sourceFiles(.cpp)) }
                    }.fixedSize()
                }
            }
        } header: { Text("File sets & folder templates") } footer: {
            Text("Review related files and create one new folder. Save the set to reuse it; existing folders are never merged.")
        }
        .confirmationDialog("Remove this saved file set?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let set = removing { Button("Remove Saved Set", role: .destructive) { model.removeFileSet(set); removing = nil } }
        } message: { Text("Created folders, files and source templates stay unchanged.") }
    }
}
