import AppKit
import SwiftUI
import Testing
@testable import CloakTools

/// Mark actual laid-out controls so the test can measure them without global accessibility permission.
private struct FooterMarker: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor @Test func dialogFooterKeepsDismissalAndPrimaryAtOppositeEdges() throws {
    for width: CGFloat in [400, 660] {
        let cancel = NSView(), copy = NSView(), save = NSView()
        let content = DialogFooter {
            Button("Cancel") {}.modifier(DialogActionStyle()).background(FooterMarker(view: cancel))
        } actions: {
            Button("Copy Result") {}.modifier(DialogActionStyle()).background(FooterMarker(view: copy))
            Button("Save Copy…") {}.modifier(DialogActionStyle(prominent: true)).background(FooterMarker(view: save))
        }.frame(width: width, height: 52)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 52),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: content)
        window.displayIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        let bounds = try #require(window.contentView)
        let frames = [cancel, copy, save].map { $0.convert($0.bounds, to: bounds) }
        #expect(frames.allSatisfy { $0.width > 0 && $0.height > 0 })
        #expect(abs(frames[0].minX) < 5)
        #expect(abs(frames[2].maxX - width) < 5)
        #expect(frames[0].maxX < frames[1].minX && frames[1].maxX < frames[2].minX)
        #expect(frames[0].midY == frames[2].midY)
    }
}

@MainActor @Test func cancellingSamplePreviewKeepsItsDraftAndAllowsRetry() async throws {
    let operation = SampleFileOperation()
    operation.name = "Design sample"
    operation.records = "4"
    var closed = false
    let content = SampleFileView(operation: operation) { closed = true }
    // Stay on the main actor until the press so even a small, fast preview is still pending.
    operation.generate()
    try #require(operation.busy)
    content.dismissal.perform()
    #expect(!closed && !operation.busy && operation.name == "Design sample")
    operation.generate()
    let deadline = ContinuousClock.now.advanced(by: .seconds(4))
    while operation.busy, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(operation.prepared != nil && operation.records == "4")
    ReviewDismissButton(busy: true, saving: true, cancel: { Issue.record("Cancelled a save") }, close: { closed = true }).perform()
    #expect(!closed)
    content.dismissal.perform()
    #expect(closed)
}

@MainActor @Test func shortFolderReviewsKeepActionsAtTheBottomWhenResized() throws {
    for size in [CGSize(width: 440, height: 420), CGSize(width: 700, height: 680)] {
        let marker = NSView()
        let content = FolderReviewPage(tool: .collect, subtitle: "Choose files to share.",
                                     task: FolderTask(), output: nil, close: {}) {
            ContentUnavailableView("Choose files to share", systemImage: "tray")
        } actions: {
            Button("Choose Files…") {}
                .modifier(DialogActionStyle(prominent: true))
                .background(FooterMarker(view: marker))
        }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let host = NSHostingView(rootView: content)
        window.contentView = host
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        let bounds = marker.convert(marker.bounds, to: host)
        let bottomInset = host.isFlipped ? host.bounds.maxY - bounds.maxY : bounds.minY
        #expect(bounds.height > 0 && abs(bottomInset - 20) < 5)
        #expect(abs(host.bounds.maxX - bounds.maxX - 20) < 5)
    }
}

/// Exercise window-scoped equivalents without making the test host the user's key window.
private final class FooterKeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}

@MainActor @Test func reviewKeyboardAlternatesRespectDisabledActions() throws {
    var submissions = 0, completions = 0
    let window = FooterKeyWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 80),
                                 styleMask: .titled, backing: .buffered, defer: false)
    func mount(disabled: Bool) {
        let host = NSHostingView(rootView: HStack {
            ReviewDefaultButton(title: "Generate") { submissions += 1 }.disabled(disabled)
            DialogDoneButton { completions += 1 }
        })
        window.contentView = host
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
    }
    func send(_ key: String, code: UInt16, modifiers: NSEvent.ModifierFlags) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                                 timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                 characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
        _ = window.contentView?.performKeyEquivalent(with: event)
    }
    mount(disabled: false)
    try send("\r", code: 36, modifiers: .command)
    try send("\u{1b}", code: 53, modifiers: [])
    #expect(submissions == 1 && completions == 1)
    mount(disabled: true)
    try send("\r", code: 36, modifiers: .command)
    #expect(submissions == 1)
}
