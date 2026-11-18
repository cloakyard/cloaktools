import SwiftUI

struct ToolWelcomeView: View {
    let model: AppModel
    @State private var developerEnabled = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image("AboutAppIcon").resizable().frame(width: 54, height: 54).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to CloakTools").font(.title2.weight(.semibold))
                    Text("Just the tools you need.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "square.grid.2x2").font(.title3).foregroundStyle(.blue).frame(width: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Everyday tools").font(.headline)
                            Spacer()
                            Label("Included", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Create documents, prepare images and PDFs, export media, and open links in the right app.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.title3).foregroundStyle(.teal).frame(width: 24).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Developer Tools").font(.headline)
                            Spacer()
                            Toggle("Developer Tools", isOn: $developerEnabled).labelsHidden().toggleStyle(.switch)
                                .accessibilityLabel("Developer Tools")
                        }
                        Text("Add data, configuration and programming tools.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.modifier(DialogCard())
            Text("You can change this in Settings → General at any time.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            OperationFeedback(error: error)
            GlassEffectContainer(spacing: 8) {
                HStack {
                    Spacer()
                    Button("Start Using CloakTools") {
                        do { try model.completeToolSelection(developerEnabled: developerEnabled); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                }
            }
        }.padding(24).frame(width: 460)
            .onAppear { developerEnabled = model.preferences.developerToolsEnabled }
    }
}
