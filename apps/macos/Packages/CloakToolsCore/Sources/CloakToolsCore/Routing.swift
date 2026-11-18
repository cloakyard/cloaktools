import Foundation
import CryptoKit

public enum LinkRole: String, Codable, CaseIterable, Sendable { case web, email }
public struct IncomingLink: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let original: String
    public let url: URL
    public let role: LinkRole
    public let sourceApplication: String? // Unknown is a supported state. Never infer from the frontmost app.
    public init(_ original: String, sourceApplication: String? = nil) throws {
        guard original.utf8.count <= 65_536, !original.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: original), let scheme = parts.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme), let url = URL(string: original) else { throw ToolError.invalidLink }
        if scheme != "mailto" {
            guard let host = parts.host, !host.isEmpty, !host.contains(" ") else { throw ToolError.invalidLink }
        }
        self.original = original; self.url = url; role = scheme == "mailto" ? .email : .web
        self.sourceApplication = sourceApplication
    }
    public static func permitsDestination(bundleID: String?, appURL: URL, ownURL: URL) -> Bool {
        guard let bundleID, bundleID != "com.cloakyard.cloaktools", !bundleID.hasPrefix("com.cloakyard.cloaktools.") else { return false }
        return appURL.resolvingSymlinksInPath() != ownURL.resolvingSymlinksInPath()
    }
}

/// In-memory short-lived suppression for a destination that bounces a just-dispatched URL back.
/// Callers purge on each ingress. No URL history is written to disk.
public struct LoopGuard: Sendable {
    private var recent: [String: Date] = [:]
    public init() {}
    private static func fingerprint(_ link: IncomingLink) -> String { SHA256.hash(data: Data(link.original.utf8)).map { String(format: "%02x", $0) }.joined() }
    public mutating func recordDispatch(_ link: IncomingLink, now: Date = Date()) { recent[Self.fingerprint(link)] = now }
    public mutating func permits(_ link: IncomingLink, now: Date = Date()) -> Bool {
        recent = recent.filter { now.timeIntervalSince($0.value) < 5 }
        return recent[Self.fingerprint(link)] == nil
    }
}

public enum FinderIntent: Equatable, Sendable {
    case create(folder: URL, template: FileTemplate)
    case convert(image: URL)
    case templates(folder: URL)
    case clipboard(folder: URL)
    case assemble(files: [URL])
    case copy(files: [URL])
    case fit(image: URL)
    case structure(folder: URL)
    case collect(files: [URL])
    case compare(first: URL, second: URL?)
    public var url: URL {
        var parts = URLComponents()
        parts.scheme = "cloaktools-action"
        switch self {
        case let .fit(image):
            parts.host = "fit"; parts.queryItems = [.init(name: "path", value: image.path)]
        case let .structure(folder):
            parts.host = "structure"; parts.queryItems = [.init(name: "path", value: folder.path)]
        case let .collect(files):
            parts.host = "collect"; parts.queryItems = files.map { .init(name: "path", value: $0.path) }
        case let .compare(first, second):
            parts.host = "compare"; parts.queryItems = ([first] + [second].compactMap { $0 }).map { .init(name: "path", value: $0.path) }
        case let .assemble(files):
            parts.host = "assemble"; parts.queryItems = files.map { .init(name: "path", value: $0.path) }
        case let .copy(files):
            parts.host = "copy"; parts.queryItems = files.map { .init(name: "path", value: $0.path) }
        case let .create(folder, template):
            parts.host = "create"
            parts.queryItems = [.init(name: "path", value: folder.path), .init(name: "template", value: template.rawValue)]
        case let .templates(folder):
            parts.host = "templates"; parts.queryItems = [.init(name: "path", value: folder.path)]
        case let .clipboard(folder):
            parts.host = "clipboard"; parts.queryItems = [.init(name: "path", value: folder.path)]
        case let .convert(image):
            parts.host = "convert"
            parts.queryItems = [.init(name: "path", value: image.path)]
        }
        return parts.url!
    }
    public init(url: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.scheme == "cloaktools-action",
              parts.user == nil, parts.password == nil, parts.port == nil, parts.path.isEmpty, parts.fragment == nil,
              url.absoluteString.utf8.count <= 131_072, let items = parts.queryItems else { throw ToolError.invalidRequest }
        if parts.host == "assemble" || parts.host == "copy" || parts.host == "collect" || parts.host == "compare" {
            let count: ClosedRange<Int>
            switch parts.host {
            case "compare": count = 1...2
            case "assemble": count = 1...PDFAssembly.maximumFiles
            case "collect": count = 1...SharingCollection.maximumFiles
            default: count = 1...CopySelection.maximumItems
            }
            guard count.contains(items.count), items.allSatisfy({ $0.name == "path" && Self.validPath($0.value) }) else { throw ToolError.invalidRequest }
            let files = items.map { URL(fileURLWithPath: $0.value!) }
            switch parts.host {
            case "compare":
                let second = files.dropFirst().first
                guard files[0].standardizedFileURL != second?.standardizedFileURL else { throw ToolError.invalidRequest }
                self = .compare(first: files[0], second: second)
            case "collect": self = .collect(files: files)
            case "assemble": self = .assemble(files: files)
            default: self = .copy(files: files)
            }
            return
        }
        guard items.count <= 2, Set(items.map(\.name)).count == items.count,
              let path = items.first(where: { $0.name == "path" })?.value, Self.validPath(path) else { throw ToolError.invalidRequest }
        switch parts.host {
        case "fit", "structure":
            guard items.count == 1 else { throw ToolError.invalidRequest }
            self = parts.host == "fit" ? .fit(image: URL(fileURLWithPath: path)) : .structure(folder: URL(fileURLWithPath: path, isDirectory: true))
        case "create":
            guard items.count == 2, let value = items.first(where: { $0.name == "template" })?.value,
                  let template = FileTemplate(rawValue: value) else { throw ToolError.invalidRequest }
            self = .create(folder: URL(fileURLWithPath: path, isDirectory: true), template: template)
        case "templates":
            guard items.count == 1 else { throw ToolError.invalidRequest }
            self = .templates(folder: URL(fileURLWithPath: path, isDirectory: true))
        case "clipboard":
            guard items.count == 1 else { throw ToolError.invalidRequest }
            self = .clipboard(folder: URL(fileURLWithPath: path, isDirectory: true))
        case "convert":
            guard items.count == 1 else { throw ToolError.invalidRequest }
            self = .convert(image: URL(fileURLWithPath: path))
        default: throw ToolError.invalidRequest
        }
    }
    private static func validPath(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.hasPrefix("/") && !value.contains("\0") && value.utf8.count < 4096
    }
}
