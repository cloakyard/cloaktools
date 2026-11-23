import CloakToolsCore
import PDFKit
import SwiftUI

struct OptimizationPDFComparison: View {
    let result: OptimizedMedia
    let original: PDFDocument?
    let optimized: PDFDocument?
    @State private var page = 0
    @State private var actualSize = false
    @Environment(\.dismiss) private var dismiss

    init(_ result: OptimizedMedia) {
        self.result = result
        original = result.comparisonOriginal.flatMap { PDFDocument(url: $0) }
        optimized = PDFDocument(url: result.previewURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DialogHeading(title: "Compare PDF", subtitle: result.filename, symbol: "rectangle.split.2x1")
            if let original, let optimized {
                HStack(spacing: 12) {
                    pane("Original", bytes: result.inputBytes, document: original)
                    pane("Optimized", bytes: result.outputBytes, document: optimized)
                }
                HStack {
                    Button { page -= 1 } label: { Image(systemName: "chevron.left") }.disabled(page == 0).accessibilityLabel("Previous page")
                    Text("Page \(page + 1) of \(original.pageCount)").monospacedDigit()
                    Button { page += 1 } label: { Image(systemName: "chevron.right") }.disabled(page + 1 >= original.pageCount).accessibilityLabel("Next page")
                    Spacer()
                    Picker("Zoom", selection: $actualSize) { Text("Fit Page").tag(false); Text("Actual Size").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            } else { OperationFeedback(error: "A comparison preview could not be opened.") }
            DialogFooter {} actions: { DialogDoneButton { dismiss() } }
        }.padding(20).frame(minWidth: 640, idealWidth: 800, minHeight: 430, idealHeight: 560)
    }

    private func pane(_ title: String, bytes: Int, document: PDFDocument) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title + " · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)).font(.headline)
            PDFPane(document: document, page: $page, actualSize: actualSize).accessibilityLabel(title + " page preview")
        }.frame(maxWidth: .infinity)
    }
}

private struct PDFPane: NSViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int
    let actualSize: Bool

    @MainActor final class Coordinator: NSObject, PDFViewDelegate {
        var binding: Binding<Int>
        var updating = false
        init(_ binding: Binding<Int>) { self.binding = binding }
        @objc func changed(_ note: Notification) {
            guard !updating, let view = note.object as? PDFView, let document = view.document, let page = view.currentPage else { return }
            let index = document.index(for: page)
            if index < document.pageCount && binding.wrappedValue != index { binding.wrappedValue = index }
        }
        nonisolated func pdfViewWillClick(onLink sender: PDFView, with url: URL) {}
    }
    func makeCoordinator() -> Coordinator { Coordinator($page) }
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.delegate = context.coordinator
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.changed(_:)), name: .PDFViewPageChanged, object: view)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if view.document !== document { view.document = document }
        if let desired = document.page(at: page), view.currentPage !== desired { view.go(to: desired) }
        view.autoScales = !actualSize
        if actualSize { view.scaleFactor = 1 }
    }
    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}
