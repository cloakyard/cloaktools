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

    var category = WorkbenchCategory.finder
    var page: WorkbenchTool?
    var query = ""
    var searchRequest = 0
    private(set) var drafts: [WorkbenchTool: Draft] = [:]
    @ObservationIgnored var showWindow: (() -> Void)?
    var hasBusyDraft: Bool { drafts.values.contains { $0.busy() } }

    func browse(_ category: WorkbenchCategory) {
        self.category = category
        page = nil
        query = ""
    }

    func show(_ tool: WorkbenchTool) {
        if !category.tools.contains(tool), let owner = WorkbenchCategory.allCases.first(where: { $0.tools.contains(tool) }) {
            category = owner
        }
        page = tool
        query = ""
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
        if page == tool { page = nil }
    }

    func windowClosed() {
        for tool in Array(drafts.keys) { close(tool) }
        page = nil
        query = ""
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
