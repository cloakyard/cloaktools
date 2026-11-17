import Foundation
import Darwin

/// A private capture with a process-held lease. Recovery never touches a live
/// capture, follows a link, or scans output folders selected by the user.
final class MediaWorkspace: Sendable {
    let folder: URL
    private let descriptor: Int32
    static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("CloakTools-Owned-Media", isDirectory: true) }
    private static let marker = Data("CloakTools media capture v1\n".utf8)
    init(root: URL = MediaWorkspace.root) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try Self.isOwnedDirectory(root) else { throw CocoaError(.fileWriteNoPermission) }
        Self.recover(in: root)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let lock = folder.appendingPathComponent("lease")
        let fd = lock.withUnsafeFileSystemRepresentation { open($0!, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600) }
        guard fd >= 0 else { try? fm.removeItem(at: folder); throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); try? fm.removeItem(at: folder); throw CocoaError(.fileWriteUnknown)
        }
        do { try Self.marker.write(to: folder.appendingPathComponent("owner"), options: .withoutOverwriting) }
        catch { close(fd); try? fm.removeItem(at: folder); throw error }
        self.folder = folder; descriptor = fd
    }
    deinit {
        // Keep the lease until removal, so recovery cannot race this cleanup.
        try? FileManager.default.removeItem(at: folder)
        close(descriptor)
    }
    static func recover(in root: URL = MediaWorkspace.root) {
        guard (try? isOwnedDirectory(root)) == true,
              let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for folder in items.prefix(1024) {
            guard UUID(uuidString: folder.lastPathComponent) != nil, (try? isOwnedDirectory(folder)) == true else { continue }
            let owner = folder.appendingPathComponent("owner")
            guard let values = try? owner.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey]), values.isSymbolicLink != true,
                  values.fileSize == marker.count, (try? Data(contentsOf: owner)) == marker else { continue }
            let lock = folder.appendingPathComponent("lease")
            let fd = lock.withUnsafeFileSystemRepresentation { open($0!, O_RDWR | O_NOFOLLOW | O_NONBLOCK) }
            guard fd >= 0 else { continue }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG,
                  flock(fd, LOCK_EX | LOCK_NB) == 0 else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }
    private static func isOwnedDirectory(_ url: URL) throws -> Bool {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { lstat($0!, &info) }
        return result == 0 && info.st_uid == getuid() && (info.st_mode & S_IFMT) == S_IFDIR && (info.st_mode & 0o077) == 0
    }
}

public enum TemporaryMediaRecovery {
    /// Only known, unlocked captures beneath the app-owned temporary root.
    public static func recoverAbandonedCaptures() { MediaWorkspace.recover() }
}
