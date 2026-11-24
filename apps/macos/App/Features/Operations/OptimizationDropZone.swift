import AppKit
import CloakToolsCore
import SwiftUI

@MainActor
final class OptimizationDropZone: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    init(model: AppModel) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 312, height: 160), styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "CloakTools Drop Zone"
        panel.contentMinSize = .init(width: 300, height: 150)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: DropZoneContent(model: model, close: { [weak panel] in panel?.close() }))
        super.init(window: panel)
        panel.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func showAtPointer() {
        guard let panel = window else { return }
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let rect = screen?.visibleFrame {
            let size = panel.frame.size
            let x = min(max(rect.minX, point.x - size.width / 2), rect.maxX - size.width)
            let y = min(max(rect.minY + size.height, point.y + 14), rect.maxY)
            panel.setFrameTopLeftPoint(.init(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

private struct DropZoneContent: View {
    let model: AppModel
    let close: () -> Void
    @State private var recipeID: UUID?
    @State private var targeted = false
    @State private var error: String?
    private var recipes: [ExportRecipe] {
        model.exportRecipes.filter { if case .optimize = $0.options { true } else { false } }
    }
    var body: some View {
        VStack(spacing: 10) {
            Label("Drop media here", systemImage: "tray.and.arrow.down").font(.headline)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(targeted ? Color.accentColor.opacity(0.18) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? Color.accentColor : .secondary.opacity(0.35), style: .init(lineWidth: 1, dash: [5])))
            if let review = model.lastOptimizer ?? model.optimizer {
                if let result = review.rows.last(where: { $0.result != nil })?.result {
                    HStack {
                        Image(systemName: "doc").accessibilityHidden(true)
                        Text(result.filename).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        OptimizationDragHandle(result: result)
                    }.font(.callout)
                } else if review.task.busy {
                    ProgressView(review.current ?? "Preparing…").controlSize(.small)
                }
            }
            if !recipes.isEmpty {
                Picker("Recipe", selection: $recipeID) {
                    Text("Standard").tag(nil as UUID?)
                    ForEach(recipes) { Text($0.title).tag(Optional($0.id)) }
                }
            }
            if let error { OperationFeedback(error: error) }
            DialogFooter {
                Button("Close", action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                Button("Choose Files…") { submit(OptimizationReview.pickFiles()) }
                    .keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
            }
        }.padding(12).frame(minWidth: 280, minHeight: 150)
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return false }
            return submit(urls)
        } isTargeted: { targeted = $0 }
    }
    @discardableResult
    private func submit(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        do {
            try model.presentDropZoneFiles(urls, recipeID: recipeID)
            error = nil
            return true
        } catch {
            self.error = "Recipe unavailable. Choose another recipe or Standard."
            recipeID = nil
            return false
        }
    }
}
