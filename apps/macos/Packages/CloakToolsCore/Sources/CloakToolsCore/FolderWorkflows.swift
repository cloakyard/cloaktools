import Foundation
import Darwin
import CryptoKit

public struct FolderWorkflowError: LocalizedError, Sendable {
    let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

private struct FileStamp: Equatable, Sendable {
    let device: dev_t
    let inode: ino_t
    let mode: mode_t
    let bytes: off_t
    let seconds: Int
    let nanos: Int

    init(_ info: stat) {
        device = info.st_dev; inode = info.st_ino; mode = info.st_mode & S_IFMT
        bytes = info.st_size; seconds = info.st_ctimespec.tv_sec; nanos = info.st_ctimespec.tv_nsec
    }

    init(_ url: URL) throws {
        guard url.isFileURL, [nil, "", "localhost"].contains(url.host) else { throw ToolError.invalidRequest }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw fileError(url) }
        self.init(info)
    }

    func verify(_ url: URL) throws {
        guard try FileStamp(url) == self else {
            throw FolderWorkflowError("“\(url.lastPathComponent)” changed. Review the current files and try again.")
        }
    }

    func withFile<T>(_ url: URL, _ body: (Int32) throws -> T) throws -> T {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw fileError(url) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw fileError(url) }
        guard mode == S_IFREG, FileStamp(info) == self else {
            throw FolderWorkflowError("“\(url.lastPathComponent)” changed. Select it again.")
        }
        let result = try body(fd)
        try verify(url)
        return result
    }
}

private func fileError(_ url: URL, code: Int32 = errno) -> FolderWorkflowError {
    FolderWorkflowError("“\(url.path)”: \(String(cString: strerror(code))).")
}

/// The enumerator visits symbolic links as entries and never descends into them.
private func inventory(_ root: URL, directoriesOnly: Bool) throws -> [String: FileStamp] {
    let stamp = try FileStamp(root)
    guard stamp.mode == S_IFDIR else { throw FolderWorkflowError("Choose a folder for “\(root.lastPathComponent)”.") }
    let options: FileManager.DirectoryEnumerationOptions = directoriesOnly ? [.skipsHiddenFiles, .skipsPackageDescendants] : []
    var failure: Error?
    guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: directoriesOnly ? [.isPackageKey] : [],
                                                    options: options, errorHandler: { _, error in failure = error; return false }) else {
        throw FolderWorkflowError("Could not read “\(root.path)”.")
    }
    var items = ["": stamp]
    while let url = walk.nextObject() as? URL {
        try Task.checkCancellation()
        let entry = try FileStamp(url)
        if directoriesOnly {
            guard entry.mode == S_IFDIR else { continue }
            if try url.resourceValues(forKeys: [.isPackageKey]).isPackage == true { walk.skipDescendants(); continue }
        } else if ![S_IFDIR, S_IFREG, S_IFLNK].contains(entry.mode) {
            throw FolderWorkflowError("Comparison incomplete. “\(url.path)” is a special filesystem item.")
        }
        // The enumerator may expand /tmp or /var to /private. Its level is relative
        // to the chosen root even when the emitted URL uses a different spelling.
        let path = url.pathComponents.suffix(walk.level).joined(separator: "/")
        guard items.updateValue(entry, forKey: path) == nil else { throw FolderWorkflowError("Ambiguous path: \(path)") }
    }
    if let failure { throw failure }
    try Task.checkCancellation()
    return items
}

public struct FolderStructure: Sendable {
    public let paths: [String]

    public init(from root: URL) throws {
        let items = try inventory(root, directoriesOnly: true)
        paths = items.keys.filter { !$0.isEmpty }.sorted {
            $0.split(separator: "/").lexicographicallyPrecedes($1.split(separator: "/"))
        }
    }

    /// Selecting a nested folder also creates its ancestors. Only the leaves need file-set entries.
    private func selectedLeaves(_ selected: Set<String>) throws -> [String] {
        guard !selected.isEmpty, selected.isSubset(of: Set(paths)) else {
            throw FolderWorkflowError("Choose at least one folder from the preview.")
        }
        var leaves = selected
        for path in selected {
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                leaves.remove(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return leaves.sorted()
    }

    public func definition(named name: String, selected: Set<String>) throws -> FileSetDefinition {
        let definition = FileSetDefinition(title: name, folderName: name, entries: try selectedLeaves(selected).map { FileSetEntry(path: $0) })
        try definition.validate()
        return definition
    }

    public func create(named name: String, selected: Set<String>, in destination: URL) throws -> URL {
        let leaves = try selectedLeaves(selected)
        var folders = Set<String>()
        for leaf in leaves {
            var path = leaf
            while !path.isEmpty && folders.insert(path).inserted {
                path = (path as NSString).deletingLastPathComponent
            }
        }
        return try SafeOutput.publishFolder(named: name, in: destination) { stage in
            for path in folders.sorted() {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(at: stage.appendingPathComponent(path), withIntermediateDirectories: false)
            }
        }
    }
}

public struct SharingFile: Identifiable, Sendable {
    public let source: URL
    public var name: String
    public var id: URL { source }
    public var byteCount: Int64 { stamp.bytes }
    fileprivate let stamp: FileStamp
}

public enum SharingCollection {
    public static let maximumFiles = 200
    private static func key(_ name: String) -> String { name.precomposedStringWithCanonicalMapping.lowercased() }

    public static func adding(_ urls: [URL], to existing: [SharingFile]) throws -> [SharingFile] {
        var result = existing
        var sources = Set(existing.map(\.source))
        var names = Set(existing.map { key($0.name) })
        for url in urls {
            try Task.checkCancellation()
            let source = url.standardizedFileURL
            guard sources.insert(source).inserted else { continue }
            guard result.count < maximumFiles else { throw FolderWorkflowError("Collect up to 200 files at a time.") }
            let stamp = try FileStamp(source)
            guard stamp.mode == S_IFREG else { throw FolderWorkflowError("Choose regular files. “\(source.lastPathComponent)” is not a regular file.") }
            let original = source.lastPathComponent
            let ext = (original as NSString).pathExtension
            let stem = (original as NSString).deletingPathExtension
            var name = original, index = 2
            while !names.insert(key(name)).inserted {
                name = stem + " \(index)" + (ext.isEmpty ? "" : ".\(ext)")
                index += 1
            }
            result.append(SharingFile(source: source, name: name, stamp: stamp))
        }
        return result
    }

    public static func validate(_ files: [SharingFile]) throws {
        guard (1...maximumFiles).contains(files.count) else { throw FolderWorkflowError("Choose 1–200 files to collect.") }
        var names = Set<String>()
        for file in files {
            let name = file.name
            guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255, !name.contains("/"),
                  !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw FolderWorkflowError("Enter a valid output filename for “\(file.source.lastPathComponent)”.")
            }
            guard names.insert(key(name)).inserted else { throw FolderWorkflowError("Two copies are named “\(name)”. Give each copy a unique name.") }
        }
    }

    public static func save(_ files: [SharingFile], named name: String, in folder: URL) throws -> URL {
        try validate(files)
        return try SafeOutput.publishFolder(named: name, in: folder) { stage in
            for file in files {
                try Task.checkCancellation()
                try file.stamp.withFile(file.source) { source in
                    let target = stage.appendingPathComponent(file.name)
                    let dest = open(target.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0o600)
                    guard dest >= 0 else { throw fileError(target) }
                    defer { close(dest) }
                    guard let state = copyfile_state_alloc() else { throw fileError(target) }
                    defer { copyfile_state_free(state) }
                    let callback: copyfile_callback_t = { _, stage, _, _, _, _ in
                        stage == COPYFILE_ERR || Task.isCancelled ? COPYFILE_QUIT : COPYFILE_CONTINUE
                    }
                    guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self)) == 0,
                          fcopyfile(source, dest, state, copyfile_flags_t(COPYFILE_ALL)) == 0 else {
                        let failure = fileError(file.source)
                        try Task.checkCancellation()
                        throw failure
                    }
                }
            }
        }
    }
}

public struct FolderDifference: Identifiable, Sendable {
    public enum Kind: String, Sendable { case leftOnly = "Only in first", rightOnly = "Only in second", changed = "Different contents", type = "Different types" }
    public let path: String
    public let kind: Kind
    public var id: String { path }
}

public struct FolderComparison: Sendable {
    public let differences: [FolderDifference]
    public let checked: Int

    public init(_ left: URL, _ right: URL) throws {
        let a = try inventory(left, directoriesOnly: false)
        let b = try inventory(right, directoriesOnly: false)
        guard a[""]?.device != b[""]?.device || a[""]?.inode != b[""]?.inode else { throw FolderWorkflowError("Choose two different folders.") }
        let paths = Set(a.keys).union(b.keys).subtracting([""])
        var differences: [FolderDifference] = []
        for path in paths.sorted() {
            try Task.checkCancellation()
            let l = left.appendingPathComponent(path), r = right.appendingPathComponent(path)
            let kind: FolderDifference.Kind
            switch (a[path], b[path]) {
            case (.some, nil): kind = .leftOnly
            case (nil, .some): kind = .rightOnly
            case let (x?, y?):
                if x.mode != y.mode { kind = .type }
                else if x.mode == S_IFREG {
                    if x.bytes == y.bytes, try Self.digest(l, x) == Self.digest(r, y) { continue }
                    kind = .changed
                } else if x.mode == S_IFLNK {
                    if try FileManager.default.destinationOfSymbolicLink(atPath: l.path) == FileManager.default.destinationOfSymbolicLink(atPath: r.path) { continue }
                    kind = .changed
                } else { continue }
            default: continue
            }
            differences.append(.init(path: path, kind: kind))
        }
        for (root, items) in [(left, a), (right, b)] {
            for (path, stamp) in items {
                try Task.checkCancellation()
                try stamp.verify(path.isEmpty ? root : root.appendingPathComponent(path))
            }
        }
        self.differences = differences; checked = paths.count
    }

    private struct ForkDigests: Equatable {
        let data: SHA256.Digest
        let resource: SHA256.Digest?
    }

    private static func digest(_ url: URL, _ stamp: FileStamp) throws -> ForkDigests {
        try stamp.withFile(url) { fd in
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            let data = try hash(handle)
            let size = fgetxattr(fd, "com.apple.ResourceFork", nil, 0, 0, 0)
            if size < 0 && errno != ENOATTR && errno != ENOTSUP { throw fileError(url) }
            guard size > 0 else { return ForkDigests(data: data, resource: nil) }
            let fork = try FileHandle(forReadingFrom: url.appendingPathComponent("..namedfork/rsrc"))
            defer { try? fork.close() }
            return try ForkDigests(data: data, resource: hash(fork))
        }
    }

    private static func hash(_ handle: FileHandle) throws -> SHA256.Digest {
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        return hash.finalize()
    }
}

extension FinderIntent {
    /// Finder Sync calls this only for selected items, never for the container background.
    public static func reviewActions(for files: [URL]) -> [(title: String, intent: FinderIntent)] {
        guard !files.isEmpty, files.count <= SharingCollection.maximumFiles else { return [] }
        var folders = 0
        for url in files {
            // Finder may supply resource values on the URL even when the extension
            // cannot open the item. The host revalidates each selection before use.
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey])
            guard values?.isSymbolicLink != true, values?.isPackage != true else { return [] }
            if values?.isDirectory ?? url.hasDirectoryPath { folders += 1 }
            else if values?.isRegularFile == false { return [] }
        }
        if folders == files.count {
            if folders == 1 { return [("Reuse Folder Structure…", .structure(folder: files[0]))] }
            if folders == 2 { return [("Compare Two Folders…", .compare(first: files[0], second: files[1]))] }
        }
        guard folders == 0 else { return [] }
        var actions: [(String, FinderIntent)] = []
        if files.count == 1, ImageConversion.inputExtensions.contains(files[0].pathExtension.lowercased()) {
            actions.append(("Make It Fit…", .fit(image: files[0])))
        }
        actions.append(("Collect Copies for Sharing…", .collect(files: files)))
        return actions
    }
}
