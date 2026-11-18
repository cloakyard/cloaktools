import Foundation
import Darwin

public enum ToolError: LocalizedError, Sendable {
    case invalidName, unavailableFolder, unsupportedImage, imageTooLarge, encodingFailed, invalidLink, invalidRequest, noDestination
    public var errorDescription: String? {
        switch self {
        case .invalidName: "Use a filename without slashes, colons, control characters, or a leading dot (up to 120 bytes)."
        case .unavailableFolder: "The destination is unavailable or is not a folder. Choose an existing writable folder."
        case .unsupportedImage: "Choose a valid single-frame PNG, JPEG, TIFF or HEIC image. Animated and multipage files are not supported."
        case .imageTooLarge: "This preview supports images up to 40 megapixels and 100 MB. Choose a smaller image."
        case .encodingFailed: "macOS could not encode the image. The source was not changed."
        case .invalidLink: "Choose an HTTP, HTTPS, or mailto link with a valid destination."
        case .invalidRequest: "Select the items required by this action in Finder and try again."
        case .noDestination: "No compatible application is available. Install a browser or mail app, then try again."
        }
    }
}

public enum SafeOutput {
    public static func validate(stem: String) throws {
        guard !stem.isEmpty, !stem.hasPrefix("."), stem == stem.trimmingCharacters(in: .whitespacesAndNewlines),
              stem.utf8.count <= 120, !stem.contains("/"), !stem.contains(":"),
              !stem.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw ToolError.invalidName }
    }
    /// Stage in the destination, then atomically publish with RENAME_EXCL. No check-then-overwrite race.
    public static func publish(_ data: Data, in folder: URL, stem: String, extension ext: String) throws -> URL {
        try Task.checkCancellation()
        try validate(stem: stem)
        guard !ext.isEmpty, ext.utf8.count <= 16, ext.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { throw ToolError.invalidName }
        guard folder.isFileURL, (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw ToolError.unavailableFolder }
        let staging = folder.appendingPathComponent(".cloaktools-\(UUID().uuidString).tmp")
        let descriptor = staging.withUnsafeFileSystemRepresentation { open($0!, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        // Own cleanup before the first write, including a partial write or cancellation.
        defer { try? FileManager.default.removeItem(at: staging) }
        for start in stride(from: data.startIndex, to: data.endIndex, by: 1_048_576) {
            try Task.checkCancellation()
            try handle.write(contentsOf: data[start..<min(start + 1_048_576, data.endIndex)])
        }
        try handle.close()
        return try publishStagedFile(staging, in: folder, stem: stem, extension: ext)
    }
    /// Internal, already-written staging files must be on the destination filesystem.
    /// The caller owns cleanup if validation, cancellation or publication fails.
    static func publishStagedFile(_ staging: URL, in folder: URL, stem: String, extension ext: String) throws -> URL {
        try validate(stem: stem)
        guard !ext.isEmpty, ext.utf8.count <= 16, ext.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { throw ToolError.invalidName }
        guard folder.isFileURL, (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw ToolError.unavailableFolder }
        for index in 1...10_000 {
            try Task.checkCancellation()
            let suffix = index == 1 ? "" : " \(index)"
            let destination = folder.appendingPathComponent("\(stem)\(suffix).\(ext)")
            let result = staging.withUnsafeFileSystemRepresentation { from in
                destination.withUnsafeFileSystemRepresentation { to in renamex_np(from!, to!, UInt32(RENAME_EXCL)) }
            }
            if result == 0 { return destination }
            let code = errno
            if code != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    static func publishFolder(named name: String, in destination: URL, populate: (URL) throws -> Void) throws -> URL {
        try SafeOutput.validate(stem: name)
        try Task.checkCancellation()
        guard destination.isFileURL, [nil, "", "localhost"].contains(destination.host),
              destination.user == nil, destination.password == nil, destination.port == nil,
              destination.query == nil, destination.fragment == nil,
              (try? destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw ToolError.unavailableFolder }
        let fm = FileManager.default
        let stage = destination.appendingPathComponent(".cloaktools-set-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }
        try populate(stage)
        for index in 1...10_000 {
            try Task.checkCancellation()
            let targetName = name + (index == 1 ? "" : " \(index)")
            let target = destination.appendingPathComponent(targetName, isDirectory: true)
            let status = stage.withUnsafeFileSystemRepresentation { from in
                target.withUnsafeFileSystemRepresentation { to in renamex_np(from!, to!, UInt32(RENAME_EXCL)) }
            }
            if status == 0 { return target }
            let code = errno
            if code != EEXIST { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
