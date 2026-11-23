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
