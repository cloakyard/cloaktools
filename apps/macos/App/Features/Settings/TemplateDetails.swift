import SwiftUI
import CloakToolsCore

struct TemplateDetails: View {
    let template: CustomTemplate
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var filename: String
    @State private var error: String?
    init(template: CustomTemplate, model: AppModel) {
        self.template = template; self.model = model
        _title = State(initialValue: template.title); _filename = State(initialValue: template.suggestedName)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DialogHeading(title: "Template details", subtitle: ".\(template.fileExtension) · \(template.content.count.formatted()) bytes", symbol: "doc.on.doc")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow { Text("Title"); TextField("Template title", text: $title).textFieldStyle(.roundedBorder).accessibilityLabel("Template title") }
                GridRow { Text("Default name"); TextField("Name without extension", text: $filename).textFieldStyle(.roundedBorder).accessibilityLabel("Default filename without extension") }
            }
            Text("Content preview").font(.caption).foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(String(String(decoding: template.content, as: UTF8.self).prefix(4096)))
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 140).modifier(DialogCard())
            if String(decoding: template.content, as: UTF8.self).count > 4096 { Text("Preview is limited to 4,096 characters. The full saved content is used.").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                Button("Save") {
                    do {
                        var updated = template; updated.title = title; updated.suggestedName = filename
                        try model.saveTemplate(updated); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 460)
    }
}
