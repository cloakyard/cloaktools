import Foundation
import Security

public enum FinderScopeError: LocalizedError, Sendable {
    case unavailable, invalid, full, duplicate, needsReview, newerVersion
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Additional Finder folders need a build signed for the shared app group. The default workspace and Services remain available."
        case .invalid: "Choose an existing local folder. The filesystem root cannot be monitored."
        case .full: "You can add up to 16 Finder folders. Remove a folder before adding another."
        case .duplicate: "This folder is already included."
        case .needsReview: "Choose this folder again to renew its access. It is not monitored until access is renewed."
        case .newerVersion: "These Finder folders were saved by a newer app version. They have been kept unchanged."
        }
    }
}

public struct FinderFolder: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let path: String
    public let bookmark: Data
    public init(id: UUID = UUID(), name: String, path: String, bookmark: Data) {
        self.id = id; self.name = name; self.path = path; self.bookmark = bookmark
    }
    public static func capture(_ url: URL, id: UUID = UUID()) throws -> Self {
        guard url.isFileURL, [nil, "", "localhost"].contains(url.host), url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil, url.port == nil else { throw FinderScopeError.invalid }
        let folder = url.standardizedFileURL.resolvingSymlinksInPath()
        guard folder.path != "/", (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw FinderScopeError.invalid }
        let bookmark = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        return Self(id: id, name: folder.lastPathComponent, path: folder.path, bookmark: bookmark)
    }
    public func resolve() throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        // A moved or stale folder needs an explicit new selection; never broaden silently.
        guard !stale, url.isFileURL, url.standardizedFileURL.path == path else { throw FinderScopeError.needsReview }
        return url
    }
}

public struct FinderScopeStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static let changeNotification = Notification.Name("com.cloakyard.cloaktools.finder-folders-changed")
    private struct Document: Codable { var version = 1; var folders: [FinderFolder] }
    public func load() throws -> [FinderFolder] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let document = try JSONDecoder().decode(Document.self, from: LocalFileCapture.read(url, limit: 2_097_152))
        guard document.version == 1 else { throw FinderScopeError.newerVersion }
        try validate(document.folders)
        return document.folders
    }
    public func save(_ folders: [FinderFolder]) throws {
        try validate(folders)
        // Refuse to replace unreadable/future state, even when the caller has an old list.
        _ = try load()
        let data = try JSONEncoder().encode(Document(folders: folders))
        guard data.count <= 2_097_152 else { throw FinderScopeError.full }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func validate(_ folders: [FinderFolder]) throws {
        guard folders.count <= 16 else { throw FinderScopeError.full }
        guard Set(folders.map(\.id)).count == folders.count, Set(folders.map(\.path)).count == folders.count else { throw FinderScopeError.duplicate }
        for folder in folders {
            guard !folder.name.isEmpty, folder.name.utf8.count <= 1024, folder.path.hasPrefix("/"), folder.path != "/",
                  folder.path.utf8.count < 4096, !folder.path.contains("\0"),
                  URL(fileURLWithPath: folder.path).standardizedFileURL.path == folder.path,
                  !folder.bookmark.isEmpty, folder.bookmark.count <= 65_536 else { throw FinderScopeError.invalid }
        }
    }
    /// Both the declared group and the actual signing entitlements must agree.
    /// Ad-hoc builds do not request access to an unentitled shared container.
    public static func authorized(bundle: Bundle = .main) -> Self? {
        guard let group = bundle.object(forInfoDictionaryKey: "CloakToolsAppGroupIdentifier") as? String,
              !group.isEmpty, let task = SecTaskCreateFromSelf(nil),
              let team = SecTaskCopyValueForEntitlement(task, "com.apple.developer.team-identifier" as CFString, nil) as? String,
              group == team + ".com.cloakyard.cloaktools",
              let groups = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil) as? [String], groups.contains(group),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return Self(url: container.appendingPathComponent("finder-folders.json"))
    }
}
