import AppKit
import SwiftUI

struct QuickToolsMenu: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Workbench") { openWindow(id: "workbench"); NSApp.activate() }
        Divider()
        Button(model.optimizer?.task.busy == true ? "Show Optimization Progress…" : "Optimize Media…") { model.presentOptimizer() }
        Button("Show Drop Zone", action: model.showDropZone)
        Button("Restore an Original…", action: model.restoreOptimizationBackup)
        Button("Optimize from Clipboard…") { model.presentOptimizer(paste: true) }
            .disabled(model.optimizer?.task.busy == true)
        Toggle("Optimize Copied Images", isOn: Binding(get: { model.preferences.optimizeCopiedImages },
            set: { enabled in model.update { $0.optimizeCopiedImages = enabled } }))
        Button("Make It Fit…") { model.chooseImageToFit() }
        if !model.exportRecipes.isEmpty {
            Menu("Export Recipes") {
                ForEach(model.exportRecipes) { recipe in Button(recipe.title) { model.useRecipe(recipe) } }
            }
        }
        Divider()
        Button("New File…") { model.chooseCreationFolder() }
        Button("Create QR Code…", action: model.presentQRCode)
        if let review = model.sharingReview {
            Button("Review Collected Files (\(review.files.count))…") { model.collectForSharing([]) }
        } else {
            Button("Collect Copies for Sharing…") { model.collectForSharing([]) }
        }
        Divider()
        Button("Settings…") { openSettings(); NSApp.activate() }
        Button("Quit CloakTools") { NSApp.terminate(nil) }
    }
}
