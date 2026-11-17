import AppKit
import CloakToolsCore

/// Called only by an explicit action, never by menu construction, polling or app activation.
@MainActor
enum ClipboardCapture {
    static func read() throws -> ClipboardInput {
        let board = NSPasteboard.general
        let generation = board.changeCount
        guard let items = board.pasteboardItems else { throw readFailure(board, generation: generation) }
        guard !items.isEmpty else { throw board.accessBehavior == .alwaysDeny ? ClipboardError.accessDenied : ClipboardError.unsupported }
        guard items.count == 1, let item = items.first else { throw ClipboardError.multipleItems }
        // A copied file can also advertise text or an icon. Never treat it as file contents.
        let fileTypes = Set(NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) } + [.fileURL])
        guard !item.types.contains(where: fileTypes.contains) else { throw ClipboardError.unsupported }
        let input: ClipboardInput
        if let type = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")].first(where: { item.types.contains($0) }) {
            guard let data = item.data(forType: type) else { throw readFailure(board, generation: generation) }
            input = .image(data)
        } else if item.types.contains(.string) {
            guard let text = item.string(forType: .string) else { throw readFailure(board, generation: generation) }
            input = .text(text)
        } else { throw ClipboardError.unsupported }
        guard board.changeCount == generation else { throw ClipboardError.changed }
        try input.validateSize()
        return input
    }
    private static func readFailure(_ board: NSPasteboard, generation: Int) -> ClipboardError {
        if board.changeCount != generation { return .changed }
        return board.accessBehavior == .alwaysDeny ? .accessDenied : .unavailable
    }
}
