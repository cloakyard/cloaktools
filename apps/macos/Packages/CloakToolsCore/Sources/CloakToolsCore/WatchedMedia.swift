import Foundation

/// Only new, regular files directly inside the selected folder qualify. Two matching observations
/// avoid starting on an ordinary partial download. The caller rechecks again after encoding.
public struct WatchedMedia: Sendable {
    public struct Stamp: Equatable, Sendable {
        let size: Int
        let modified: Date
        let identity: UInt64
    }
    public typealias Snapshot = [URL: Stamp]
    private var previous: Snapshot
    private var handled: Set<URL>
    public init(baseline: Snapshot) {
        previous = baseline
        handled = Set(baseline.keys)
    }
    public var hasPending: Bool { previous.keys.contains { !handled.contains($0) } }
    public mutating func stableAdditions(_ snapshot: Snapshot) -> [URL] {
        handled = handled.filter { snapshot[$0]?.identity == previous[$0]?.identity && snapshot[$0] != nil }
        let stable = snapshot.keys.filter { !handled.contains($0) && previous[$0] == snapshot[$0] }
        handled.formUnion(stable)
        previous = snapshot
        return stable.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
    public mutating func reconsider(_ url: URL) { handled.remove(url) }

    public static func snapshot(in folder: URL) throws -> Snapshot {
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
        guard folder.isFileURL, values.isDirectory == true, values.isSymbolicLink == false, values.isPackage != true else { throw ToolError.unavailableFolder }
        guard let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil,
                                                         options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants, .skipsHiddenFiles]) else { throw ToolError.unavailableFolder }
        var result: Snapshot = [:]
        for (index, item) in entries.enumerated() {
            try Task.checkCancellation()
            guard index < 4096 else { throw WatchError.largeFolder }
            guard let url = item as? URL, MediaOptimization.extensions.contains(url.pathExtension.lowercased()),
                  let stamp = try? stamp(url) else { continue }
            result[folder.appendingPathComponent(url.lastPathComponent)] = stamp
        }
        return result
    }

    public static func stamp(_ url: URL) throws -> Stamp {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular, let size = attrs[.size] as? Int,
              let date = attrs[.modificationDate] as? Date, let identity = attrs[.systemFileNumber] as? UInt64 else { throw OptimizationError.unsupported }
        return Stamp(size: size, modified: date, identity: identity)
    }
    public static func outputFolder(for folder: URL) throws -> URL {
        let output = folder.appendingPathComponent("Optimized Copies", isDirectory: true)
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch CocoaError.fileWriteFileExists { }
        guard (try FileManager.default.attributesOfItem(atPath: output.path))[.type] as? FileAttributeType == .typeDirectory else {
            throw ToolError.unavailableFolder
        }
        return output
    }
    enum WatchError: LocalizedError {
        case largeFolder
        var errorDescription: String? { "Choose a folder with fewer than 4,096 visible entries for automatic optimization." }
    }
}
