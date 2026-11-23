import SwiftUI
import CloakToolsCore

struct ExportRecipeSection: View {
    @Bindable var model: AppModel
    @State private var newPipeline = false
    @State private var editPipeline: ExportRecipe?
    @State private var renaming: ExportRecipe?
    @State private var removing: ExportRecipe?
    var body: some View {
        Section {
            if let error = model.recipeError {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                Button("Reload Recipes", action: model.reloadRecipes)
            }
            if model.exportRecipes.isEmpty {
                Text("Save your usual settings from Optimize Media, Make It Fit, Export Media or Convert Image.").foregroundStyle(.secondary)
            }
            ForEach(model.exportRecipes) { recipe in
                HStack(spacing: 10) {
                    Image(systemName: recipe.options.symbol).foregroundStyle(.blue).frame(width: 22).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.title).fontWeight(.medium).lineLimit(1).help(recipe.title)
                        Text(recipe.options.toolName + " · " + recipe.options.summary).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).help(recipe.options.detail)
                    }
                    Spacer(minLength: 4)
                    Button("Use…") { model.useRecipe(recipe) }.accessibilityLabel("Use recipe \(recipe.title)")
                    RowActionsMenu(title: "Actions for recipe \(recipe.title)") {
                        if case let .optimize(options) = recipe.options, options.steps != nil {
                            Button("Edit Pipeline…") { editPipeline = recipe }
                        }
                        Button("Rename…") { renaming = recipe }
                        Button("Remove Recipe…", role: .destructive) { removing = recipe }
                    }
                }.padding(.vertical, 3)
            }
            Button("New Pipeline…") { newPipeline = true }
        } header: { Text("Export recipes") } footer: {
            Text("Recipes store output settings. Use one in a review or apply it automatically with a folder rule.")
        }
        .sheet(isPresented: $newPipeline) { OptimizationPipelineEditor() }
        .sheet(item: $editPipeline) { OptimizationPipelineEditor(original: $0) }
        .sheet(item: $renaming) { recipe in ExportRecipeSaveSheet(draft: recipe, original: recipe) { _ in } }
        .confirmationDialog("Remove this export recipe?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let recipe = removing { Button("Remove Recipe", role: .destructive) { model.removeRecipe(recipe); removing = nil } }
        } message: { Text("Created files and open operation drafts stay unchanged.") }
    }
}

/// Captures settings when clicked, without adding persistent controls to the operation.
struct SaveExportRecipeButton: View {
    @Binding var recipe: ExportRecipe?
    let options: () throws -> ExportRecipeOptions
    @State private var editing: ExportRecipe?
    @State private var error: String?
    var body: some View {
        Button("Save Recipe…") {
            do {
                let value = try options(); try value.validate()
                editing = ExportRecipe(id: recipe?.id ?? UUID(), title: recipe?.title ?? value.toolName, options: value)
            } catch { self.error = error.localizedDescription }
        }
            .help("Save these output settings as a recipe")
            .sheet(item: $editing) { draft in ExportRecipeSaveSheet(draft: draft, original: recipe) { recipe = $0 } }
            .alert("Check the export settings", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
}

private struct ExportRecipeSaveSheet: View {
    @State var draft: ExportRecipe
    let original: ExportRecipe?
    let saved: (ExportRecipe) -> Void
    @State private var saveCopy = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: original == nil || saveCopy ? "Save export recipe" : "Update export recipe", subtitle: "The same settings. A fresh source each time.", symbol: "bookmark")
            VStack(alignment: .leading, spacing: 10) {
                TextField("Recipe name", text: $draft.title).textFieldStyle(.roundedBorder).focused($nameFocused)
                Label(draft.options.toolName, systemImage: draft.options.symbol).font(.callout.weight(.medium))
                Text(draft.options.summary).font(.callout)
                Text(draft.options.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.modifier(DialogCard())
            if original != nil { Toggle("Save as a new recipe", isOn: $saveCopy).toggleStyle(.checkbox) }
            Text("No source, destination or filename is saved. This does not export a file or change conversion defaults.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            OperationFeedback(error: error)
            DialogFooter {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                Button(original == nil || saveCopy ? "Save Recipe" : "Save Changes") {
                    do {
                        var value = draft; value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if saveCopy { value.id = UUID() }
                        try AppModel.shared.saveRecipe(value, replacing: saveCopy ? nil : original)
                        saved(value); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 440)
            .onAppear { nameFocused = true }
            .onChange(of: draft.title) { error = nil }
            .onChange(of: saveCopy) { error = nil }
    }
}
