import Darwin
import Foundation
import UniformTypeIdentifiers

struct ReviewedOptimizationSource: Sendable {
    let url: URL
    let stamp: WatchedMedia.Stamp

    init(_ url: URL) throws {
        guard url.isFileURL, [nil, "", "localhost"].contains(url.host) else { throw OptimizationError.unsupported }
        self.url = url
        stamp = try WatchedMedia.stamp(url)
    }
    func checkUnchanged() throws {
        guard (try? WatchedMedia.stamp(url)) == stamp else { throw OriginalFileError.changed }
    }
}

public enum OriginalFileError: LocalizedError {
    case changed, format, backup
    public var errorDescription: String? {
        switch self {
        case .changed: "The file has changed since review. Preview it again before changing the original."
        case .backup: "Choose the original file inside its CloakTools Backup folder."
        case .format: "Replacement requires the same file format as the original. Save a copy for this conversion."
        }
    }
}

/// Both files remain available across the atomic exchange, including if the app exits immediately.
public struct OptimizationBackup: Sendable {
    public let originalURL: URL
    public let backupURL: URL
    private let originalStamp: WatchedMedia.Stamp
    private let replacementStamp: WatchedMedia.Stamp
    fileprivate init(original: ReviewedOptimizationSource, candidate: ReviewedOptimizationSource) {
        originalURL = original.url
        backupURL = candidate.url
        originalStamp = original.stamp
        replacementStamp = candidate.stamp
    }

    private struct Record: Codable {
        let version: Int
        let name: String
        let original: WatchedMedia.Stamp
        let replacement: WatchedMedia.Stamp
    }
    private static let recordName = ".cloaktools-recovery.json"
    fileprivate func writeRecord() throws {
        let record = Record(version: 1, name: originalURL.lastPathComponent, original: originalStamp, replacement: replacementStamp)
        let file = backupURL.deletingLastPathComponent().appendingPathComponent(Self.recordName)
        try JSONEncoder().encode(record).write(to: file, options: .withoutOverwriting)
    }

    /// Reopen a local backup after relaunch. Relative names keep the pair portable on its volume.
    public init(backupFile: URL) throws {
        guard backupFile.isFileURL, [nil, "", "localhost"].contains(backupFile.host) else { throw OriginalFileError.backup }
        let folder = backupFile.deletingLastPathComponent()
        let prefix = "CloakTools Backup "
        guard folder.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(folder.lastPathComponent.dropFirst(prefix.count))) != nil,
              (try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let data = try? LocalFileCapture.read(folder.appendingPathComponent(Self.recordName), limit: 4096),
              let record = try? JSONDecoder().decode(Record.self, from: data), record.version == 1,
              record.name == backupFile.lastPathComponent, ![".", "..", Self.recordName].contains(record.name) else { throw OriginalFileError.backup }
        backupURL = backupFile
        originalURL = folder.deletingLastPathComponent().appendingPathComponent(record.name)
        originalStamp = record.original
        replacementStamp = record.replacement
        try verify()
    }

    public func restore() throws {
        try withOriginalDirectoryLock(originalURL) {
            try verify()
            try exchange(originalURL, backupURL)
        }
    }
    private func verify() throws {
        guard try WatchedMedia.stamp(originalURL) == replacementStamp, try WatchedMedia.stamp(backupURL) == originalStamp else {
            throw OriginalFileError.changed
        }
    }
}

/// Serialize CloakTools operations that publish or restore a replacement in this directory.
private func withOriginalDirectoryLock<T>(_ file: URL, action: () throws -> T) throws -> T {
    let directory = file.deletingLastPathComponent()
    let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    defer { Darwin.close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    return try action()
}

private func exchange(_ first: URL, _ second: URL) throws {
    try Task.checkCancellation()
    let status = first.withUnsafeFileSystemRepresentation { left in
        second.withUnsafeFileSystemRepresentation { right in renamex_np(left!, right!, UInt32(RENAME_SWAP)) }
    }
    guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}

extension OptimizedMedia {
    public var canReplaceOriginal: Bool {
        guard let source = reviewedSource, let type = UTType(filenameExtension: source.url.pathExtension) else { return false }
        return type == UTType(filenameExtension: previewURL.pathExtension)
    }
    public func replaceOriginal() throws -> OptimizationBackup {
        guard canReplaceOriginal, let source = reviewedSource else { throw OriginalFileError.format }
        try source.checkUnchanged()
        let parent = source.url.deletingLastPathComponent()
        let backupDir = parent.appendingPathComponent("CloakTools Backup \(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let candidate = backupDir.appendingPathComponent(source.url.lastPathComponent)
        do {
            try fm.copyItem(at: previewURL, to: candidate)
            let backup = try OptimizationBackup(original: source, candidate: ReviewedOptimizationSource(candidate))
            try backup.writeRecord()
            try withOriginalDirectoryLock(source.url) {
                try source.checkUnchanged()
                try exchange(source.url, candidate)
            }
            return backup
        } catch {
            try? fm.removeItem(at: candidate)
            try? fm.removeItem(at: backupDir)
            throw error
        }
    }
    public func trashOriginal(afterSaving copy: URL) throws {
        guard let source = reviewedSource, copy.standardizedFileURL != source.url.standardizedFileURL else { throw OriginalFileError.changed }
        // Ensure the separately saved copy still exists and still matches the reviewed encoding.
        try Task.checkCancellation()
        guard try WatchedMedia.stamp(copy).size == outputBytes,
              FileManager.default.contentsEqual(atPath: copy.path, andPath: previewURL.path) else { throw OriginalFileError.changed }
        try source.checkUnchanged()
        try FileManager.default.trashItem(at: source.url, resultingItemURL: nil)
    }
}
