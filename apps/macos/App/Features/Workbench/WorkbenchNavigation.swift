import SwiftUI

/// Drafts live in memory while the Workbench is open. Browsing another category
/// or opening Settings does not replace the files or text in an existing review.
@MainActor @Observable
final class WorkbenchNavigation {
    struct Draft {
        let view: AnyView
        let busy: () -> Bool
        let finish: () -> Void
    }

    private(set) var category = WorkbenchCategory.finder
    private(set) var page: WorkbenchTool?
    var query = ""
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var lastSearch: (category: WorkbenchCategory, query: String)?
    var backTitle: String { lastSearch == nil ? "Back to \(category.rawValue)" : "Back to Search Results" }
    var searchRequest = 0
    private(set) var drafts: [WorkbenchTool: Draft] = [:]
    @ObservationIgnored var showWindow: (() -> Void)?
    var hasBusyDraft: Bool { drafts.values.contains { $0.busy() } }

    func browse(_ category: WorkbenchCategory) {
        self.category = category
        page = nil
        query = ""
        lastSearch = nil
    }

    func show(_ tool: WorkbenchTool, in categories: [WorkbenchCategory] = WorkbenchCategory.allCases) {
        lastSearch = isSearching ? (category, query) : nil
        if !category.tools.contains(tool), let owner = categories.first(where: { $0.tools.contains(tool) }) {
            category = owner
        }
        page = tool
        query = ""
    }

    func back() {
        if let lastSearch, !isSearching {
            category = lastSearch.category
            query = lastSearch.query
        }
        page = nil
        lastSearch = nil
    }

    func hideDeveloperCategory() {
        if lastSearch?.category == .developer { lastSearch?.category = .finder }
        guard category == .developer else { return }
        category = .finder
        if let page, drafts[page] == nil { self.page = nil; lastSearch = nil }
    }

    /// A second request for the same tool needs its own independent operation window.
    func present<Content: View>(_ tool: WorkbenchTool, busy: @escaping () -> Bool = { false },
                                finish: @escaping () -> Void = {},
                                @ViewBuilder content: (@escaping () -> Void) -> Content) -> Bool {
        guard let showWindow, drafts[tool] == nil else { return false }
        let view = content { [weak self] in self?.close(tool) }
        drafts[tool] = Draft(view: AnyView(view), busy: busy, finish: finish)
        show(tool)
        showWindow()
        return true
    }

    /// A background operation finishing must not steal focus from Settings or another editor.
    func endEditingAfterSave(on tool: WorkbenchTool) -> () -> Void {
        { [weak self] in
            guard self?.page == tool, let window = NSApp.keyWindow,
                  window.identifier?.rawValue == "workbench" else { return }
            window.makeFirstResponder(nil)
        }
    }

    func close(_ tool: WorkbenchTool) {
        guard let draft = drafts[tool], !draft.busy() else { return }
        draft.finish()
        drafts.removeValue(forKey: tool)
        if page == tool { back() }
    }

    func windowClosed() {
        for tool in Array(drafts.keys) { close(tool) }
        browse(category)
    }
}

@MainActor
protocol OperationPanel: AnyObject {
    var onClose: (() -> Void)? { get set }
}

extension ClipboardWindow: OperationPanel {}
extension CopyOperationWindow: OperationPanel {}
extension DeveloperTextWindow: OperationPanel {}
extension ExampleCopyWindow: OperationPanel {}
extension FileListWindow: OperationPanel {}
extension FileSetWindow: OperationPanel {}
extension ImageFitWindow: OperationPanel {}
extension MarkdownDigestWindow: OperationPanel {}
extension MediaWindow: OperationPanel {}
extension OperationWindow: OperationPanel {}
extension PDFOperationWindow: OperationPanel {}
extension PDFPagesWindow: OperationPanel {}
extension QRCodeWindow: OperationPanel {}
extension SampleFileWindow: OperationPanel {}
extension TextCleanupWindow: OperationPanel {}
