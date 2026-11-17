import Foundation
import Darwin
import Testing
@testable import CloakToolsCore

private func hardeningFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CloakTools-Hardening-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    return folder
}

@Test func safePublicationUsesPrivatePermissionsAndCleansStages() throws {
    let folder = try hardeningFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let data = Data(repeating: 42, count: 2_100_000)
    let result = try SafeOutput.publish(data, in: folder, stem: "Private", extension: "bin")
    #expect(try Data(contentsOf: result) == data)
    let permissions = try FileManager.default.attributesOfItem(atPath: result.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o600)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Private.bin"])
}

@Test func cancelledPublicationLeavesNoOutputOrStaging() async throws {
    let folder = try hardeningFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try SafeOutput.publish(Data(repeating: 42, count: 2_100_000), in: folder, stem: "Cancelled", extension: "bin")
    }
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
}

@Test func safePublicationAcceptsNonzeroBasedDataSlices() throws {
    let folder = try hardeningFolder(); defer { try? FileManager.default.removeItem(at: folder) }
    let original = Data((0..<2_100_000).map { UInt8($0 % 251) })
    let slice = original.dropFirst(137)
    #expect(slice.startIndex == 137)
    let result = try SafeOutput.publish(slice, in: folder, stem: "Slice", extension: "bin")
    #expect(try Data(contentsOf: result) == slice)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Slice.bin"])
}

@Test func mediaRecoveryKeepsLeasedCapturesAndRemovesAbandonedOnes() throws {
    let root = try hardeningFolder(); defer { try? FileManager.default.removeItem(at: root) }
    let live = try MediaWorkspace(root: root)
    let abandoned = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: abandoned, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    try Data("CloakTools media capture v1\n".utf8).write(to: abandoned.appendingPathComponent("owner"))
    try Data().write(to: abandoned.appendingPathComponent("lease"))
    try Data("Private test capture".utf8).write(to: abandoned.appendingPathComponent("source.mov"))
    MediaWorkspace.recover(in: root)
    #expect(FileManager.default.fileExists(atPath: live.folder.path))
    #expect(!FileManager.default.fileExists(atPath: abandoned.path))
    withExtendedLifetime(live) {}
}

@Test func mediaRecoveryIgnoresUnknownFoldersAndSymbolicLinks() throws {
    let root = try hardeningFolder(), outside = try hardeningFolder()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
    let unknown = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    try Data("Keep".utf8).write(to: unknown.appendingPathComponent("source.mov"))
    let link = root.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    MediaWorkspace.recover(in: root)
    #expect(FileManager.default.fileExists(atPath: unknown.path))
    #expect(FileManager.default.fileExists(atPath: outside.path))
    #expect(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
}

@Test func finderScopeStoreRoundTripsAndRejectsDuplicateOrOversizedRecords() throws {
    let root = try hardeningFolder(); defer { try? FileManager.default.removeItem(at: root) }
    let store = FinderScopeStore(url: root.appendingPathComponent("folders.json"))
    let folder = FinderFolder(name: "Project", path: "/tmp/Project", bookmark: Data([1, 2, 3]))
    try store.save([folder]); #expect(try store.load() == [folder])
    #expect(throws: FinderScopeError.self) { try store.save([folder, folder]) }
    #expect(throws: FinderScopeError.self) { try store.save([.init(name: "Bad", path: "/", bookmark: Data([1]))]) }
    #expect(throws: FinderScopeError.self) { try store.save([.init(name: "Big", path: "/tmp/Big", bookmark: Data(repeating: 0, count: 65_537))]) }
    #expect(try store.load() == [folder])
}

@Test func finderScopeStorePreservesUnknownVersionAndCorruptState() throws {
    let root = try hardeningFolder(); defer { try? FileManager.default.removeItem(at: root) }
    let store = FinderScopeStore(url: root.appendingPathComponent("folders.json"))
    for data in [Data("{\"version\":999,\"folders\":[]}".utf8), Data("broken".utf8)] {
        try data.write(to: store.url)
        #expect(throws: (any Error).self) { try store.save([]) }
        #expect(try Data(contentsOf: store.url) == data)
    }
}

@Test func unsignedBuildDoesNotEnableSharedFinderScopes() {
    #expect(FinderScopeStore.authorized(bundle: Bundle(for: ScopeBundleMarker.self)) == nil)
}
private final class ScopeBundleMarker: NSObject {}
