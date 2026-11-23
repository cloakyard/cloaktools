import CloakToolsCore
import SwiftUI

struct OptimizationPipelineEditor: View {
    let original: ExportRecipe?
    let saved: (ExportRecipe) -> Void
    @State private var name: String
    @State private var steps: [OptimizationStep]
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(original: ExportRecipe? = nil, saved: @escaping (ExportRecipe) -> Void = { _ in }) {
        self.original = original
        self.saved = saved
        _name = State(initialValue: original?.title ?? "")
        if case let .optimize(options) = original?.options, let steps = options.steps {
            _steps = State(initialValue: steps)
        } else {
            _steps = State(initialValue: [.resize(percent: 50), .image(.webp), .fit(bytes: 500_000)])
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: original == nil ? "New pipeline" : "Edit pipeline", subtitle: "Matching steps run from top to bottom for each file.", symbol: "list.number")
            TextField("Pipeline name", text: $name).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(steps.indices, id: \.self) { i in
                        HStack {
                            Text("\(i + 1).").monospacedDigit().foregroundStyle(.secondary)
                            Menu(steps[i].title) { choices { steps[i] = $0 } }
                            Spacer()
                            RowActionsMenu(title: "Actions for step \(i + 1)") {
                                Button("Move Up") { steps.swapAt(i, i - 1) }.disabled(i == 0)
                                Button("Move Down") { steps.swapAt(i, i + 1) }.disabled(i + 1 == steps.count)
                                Button("Remove Step") { steps.remove(at: i) }
                            }
                        }
                    }
                }.padding(4)
            }.frame(height: min(250, max(75, CGFloat(steps.count) * 36)))
            Menu("Add Step") { choices { steps.append($0) } }.fixedSize().disabled(steps.count >= 12)
            OperationFeedback(error: error)
            DialogFooter {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                Button("Save Pipeline") {
                    do {
                        var options = OptimizationOptions()
                        options.steps = steps
                        let recipe = ExportRecipe(id: original?.id ?? UUID(), title: name.trimmingCharacters(in: .whitespacesAndNewlines), options: .optimize(options))
                        try AppModel.shared.saveRecipe(recipe, replacing: original)
                        saved(recipe)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    .disabled(steps.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 460)
    }

    @ViewBuilder private func choices(_ select: @escaping (OptimizationStep) -> Void) -> some View {
        Menu("Crop") {
            ForEach(OptimizationCrop.allCases.filter { $0 != .original }, id: \.self) { crop in Button(crop.rawValue) { select(.crop(crop)) } }
        }
        Menu("Resize") {
            ForEach([75, 50, 25, 10], id: \.self) { n in Button("\(n)%") { select(.resize(percent: n)) } }
        }
        Menu("Convert Image") {
            ForEach(OptimizedImageFormat.allCases.filter { $0.available && $0 != .automatic }, id: \.self) { f in Button(f.title) { select(.image(f)) } }
        }
        Menu("Convert Video") {
            ForEach(OptimizedVideoFormat.allCases, id: \.self) { f in Button(f.rawValue) { select(.video(f)) } }
        }
        Menu("Convert Audio") {
            ForEach(OptimizedAudioFormat.allCases.filter { $0 != .automatic }, id: \.self) { f in Button(f.rawValue) { select(.audio(f)) } }
        }
        Menu("Compress Scanned PDF") {
            ForEach([72, 150, 300], id: \.self) { dpi in Button("\(dpi) DPI") { select(.scanPDF(dpi: dpi)) } }
        }
        Menu("Fit Under Size") {
            ForEach([100_000, 500_000, 1_000_000, 5_000_000, 8_000_000, 25_000_000], id: \.self) { n in
                Button(ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)) { select(.fit(bytes: n)) }
            }
        }
    }
}
