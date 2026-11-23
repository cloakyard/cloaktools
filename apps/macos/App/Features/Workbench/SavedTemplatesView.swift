import SwiftUI
import CloakToolsCore

struct SavedTemplatesView: View {
    let model: AppModel
    @State private var editingTemplate: CustomTemplate?
    @State private var removingTemplate: CustomTemplate?
    var body: some View {
        Form {
            Section {
                DisclosureGroup("Built-in file types") {
                    ForEach(model.preferences.tools.builtInTemplates) { type in
                        LabeledContent(type.title, value: ".\(type.fileExtension)")
                            .accessibilityHint(TemplateSource.builtIn(type).contentDescription(using: model.preferences))
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
                        RowActionsMenu(title: "Actions for template \(template.title)") {
                            Button("Edit Details…") { editingTemplate = template }
                            Button("Remove…", role: .destructive) { removingTemplate = template }
                        }
                    }
                }
                Button("Import Template…", systemImage: "square.and.arrow.down", action: model.importTemplate)
                Text("Import up to 1 MiB of UTF-8 text. Saved content stays exact; favorites appear first in New File.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editingTemplate) { TemplateDetails(template: $0, model: model) }
        .confirmationDialog("Remove saved template?", isPresented: Binding(get: { removingTemplate != nil }, set: { if !$0 { removingTemplate = nil } })) {
            if let template = removingTemplate {
                Button("Remove \(template.title)", role: .destructive) { model.removeTemplate(template); removingTemplate = nil }
            }
        } message: { Text("The saved copy will be removed from CloakTools. Its original file and files already created stay unchanged.") }
    }
}
