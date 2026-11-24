import AppKit
import CloakToolsCore
import SwiftUI

@MainActor @Observable
final class RecentOptimizations {
    struct Entry: Codable, Identifiable {
        let id: UUID
        let batch: UUID
        var output: URL
        var backup: URL?
    }

    private let file: URL?
    private var unreadable = false
    private(set) var restoring = false
    private(set) var entries: [Entry] = []
    private(set) var error: String?
    init(file: URL? = nil) {
        self.file = file
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let saved = try JSONDecoder().decode([Entry].self, from: LocalFileCapture.read(file, limit: 32_000_000))
            func local(_ url: URL) -> Bool { url.isFileURL && [nil, "", "localhost"].contains(url.host) }
            guard saved.count <= 20 * MediaOptimization.maximumItems, Set(saved.map(\.id)).count == saved.count,
                  saved.allSatisfy({ local($0.output) && ($0.backup.map(local) ?? true) }) else { throw CocoaError(.fileReadCorruptFile) }
            entries = saved
        } catch { unreadable = true; self.error = "Recent results could not be read. Clear the list to start again." }
    }

    func add(_ output: URL, batch: UUID, backup: URL? = nil) {
        entries.insert(.init(id: UUID(), batch: batch, output: output, backup: backup), at: 0)
        var batches = Set<UUID>()
        entries = entries.filter { batches.contains($0.batch) || (batches.count < 20 && batches.insert($0.batch).inserted) }
        persist()
    }
    var lastReplacements: [Entry] {
        guard let batch = entries.first(where: { $0.backup != nil })?.batch else { return [] }
        return entries.filter { $0.batch == batch && $0.backup != nil }
    }
    func restored(_ backup: URL) {
        for i in entries.indices where entries[i].backup == backup {
            entries[i].backup = nil
            entries[i].output = backup
        }
        persist()
    }
    func undo(_ batch: [Entry]) async -> [String] {
        guard !restoring else { return [] }
        restoring = true
        defer { restoring = false }
        var problems: [String] = []
        for entry in batch {
            guard let url = entries.first(where: { $0.id == entry.id })?.backup else { continue }
            do {
                try await Task.detached(priority: .userInitiated) {
                    let backup = try OptimizationBackup(backupFile: url)
                    guard backup.originalURL.standardizedFileURL == entry.output.standardizedFileURL else { throw OriginalFileError.changed }
                    try backup.restore()
                }.value
                restored(url)
            }
            catch { problems.append(entry.output.lastPathComponent + " · " + error.localizedDescription) }
        }
        return problems
    }
    func clear() {
        do {
            if let file, FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            entries = []; unreadable = false; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func persist() {
        guard let file, !unreadable else { return }
        do {
            let directory = file.deletingLastPathComponent()
            let fm = FileManager.default
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let temporary = directory.appendingPathComponent(".recent-" + UUID().uuidString)
            defer { try? fm.removeItem(at: temporary) }
            let bytes = try JSONEncoder().encode(entries)
            guard fm.createFile(atPath: temporary.path, contents: bytes, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            guard rename(temporary.path, file.path) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct RecentResultsMenu: View {
    let history: RecentOptimizations
    var body: some View {
        Menu("Recent Results") {
            if history.entries.isEmpty { Text("No saved results") }
            ForEach(history.entries.prefix(10)) { entry in
                Button(entry.output.lastPathComponent) { NSWorkspace.shared.activateFileViewerSelecting([entry.output]) }
                    .help(entry.output.path)
                    .disabled(!FileManager.default.fileExists(atPath: entry.output.path))
            }
            if !history.lastReplacements.isEmpty {
                Divider()
                Button(history.restoring ? "Restoring Originals…" : "Undo Last Replacement Batch…") {
                    let batch = history.lastReplacements
                    let confirm = NSAlert()
                    confirm.messageText = batch.count == 1 ? "Restore the original file?" : "Restore \(batch.count) originals?"
                    confirm.informativeText = batch.prefix(4).map { $0.output.lastPathComponent }.joined(separator: "\n") + "\nEdited files will be skipped. Optimized copies stay in their backup folders."
                    confirm.addButton(withTitle: "Restore Originals")
                    confirm.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
                    guard confirm.runModal() == .alertFirstButtonReturn else { return }
                    Task {
                        let issues = await history.undo(batch)
                        if !issues.isEmpty {
                            let alert = NSAlert()
                            alert.messageText = "Some originals could not be restored"
                            alert.informativeText = issues.joined(separator: "\n")
                            alert.runModal()
                        }
                    }
                }.disabled(history.restoring)
            }
            if let error = history.error { Text(error) }
            if !history.entries.isEmpty || history.error != nil {
                Divider()
                Button("Clear Recent Results", action: history.clear).disabled(history.restoring)
            }
        }
    }
}
