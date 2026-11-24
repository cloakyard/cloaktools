import SwiftUI
import CloakToolsCore

struct FolderRuleSettings: View {
    let model: AppModel
    @State private var edit: OptimizationFolderRule?
    var body: some View {
        ForEach(model.preferences.folderRules) { rule in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(rule.folder.lastPathComponent).help(rule.folder.path)
                    Text(rule.kind.rawValue + " · " + (rule.recipeID == nil ? "Standard" : model.exportRecipes.first { $0.id == rule.recipeID }?.title ?? "Missing recipe"))
                        .font(.caption).foregroundStyle(.secondary)
                    if let status = model.automaticOptimization.ruleStatus[rule.id] { Text(status).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                RowActionsMenu(title: "Actions for " + rule.folder.lastPathComponent) {
                    Button("Edit Rule…") { edit = rule }
                    Button("Stop Watching") { model.update { $0.folderRules.removeAll { $0.id == rule.id } } }
                }
            }
        }
        Button("Add Folder Rule…") {
            if let url = chooseFinderFolder("Choose a folder to watch", prompt: "Choose Folder") { edit = .init(folder: url) }
        }
        if model.preferences.optimizeCopiedImages || !model.preferences.folderRules.isEmpty || model.preferences.automationPaused {
            Button(model.preferences.automationPaused ? "Resume Automation" : "Pause Automation") {
                model.update { $0.automationPaused.toggle() }
            }
        }
        Text("New matching files are saved in Optimized Copies. Existing files stay in place.")
            .font(.caption).foregroundStyle(.secondary)
            .sheet(item: $edit) { FolderRuleEditor(model: model, draft: $0) }
    }
}

private struct FolderRuleEditor: View {
    let model: AppModel
    @State var draft: OptimizationFolderRule
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Folder rule", subtitle: "Choose which new files to process.", symbol: "folder.badge.gearshape")
            LabeledContent("Folder") {
                Button(draft.folder.lastPathComponent) {
                    if let folder = chooseFinderFolder("Choose a folder to watch", startingAt: draft.folder) { draft.folder = folder }
                }.help(draft.folder.path)
            }
            Picker("File type", selection: $draft.kind) {
                ForEach(OptimizationFileKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Recipe", selection: $draft.recipeID) {
                Text("Standard").tag(nil as UUID?)
                ForEach(model.exportRecipes) { recipe in
                    if case .optimize = recipe.options { Text(recipe.title).tag(Optional(recipe.id)) }
                }
                if let id = draft.recipeID, !model.exportRecipes.contains(where: { $0.id == id }) { Text("Missing recipe").tag(Optional(id)) }
            }
            OperationFeedback(error: error)
            DialogFooter {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                Button("Save Rule") {
                    do { try model.saveFolderRule(draft); dismiss() } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
            }
        }.padding(20).frame(width: 440)
    }
}
