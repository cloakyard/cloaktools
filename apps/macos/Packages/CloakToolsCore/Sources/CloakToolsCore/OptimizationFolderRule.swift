import Foundation

public enum OptimizationFileKind: String, Codable, CaseIterable, Sendable {
    case all = "All media", image = "Images", video = "Videos", audio = "Audio", pdf = "PDFs"

    public func accepts(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch self {
        case .all: return MediaOptimization.extensions.contains(ext)
        case .image: return MediaOptimization.imageExtensions.contains(ext)
        case .audio: return MediaOptimization.audioExtensions.contains(ext)
        case .pdf: return ext == "pdf"
        case .video: return ExtendedMediaEncoding.movies.contains(ext)
        }
    }
}

public struct OptimizationFolderRule: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var folder: URL
    public var kind: OptimizationFileKind
    public var recipeID: UUID?

    public init(id: UUID = UUID(), folder: URL, kind: OptimizationFileKind = .all, recipeID: UUID? = nil) {
        self.id = id
        self.folder = folder.standardizedFileURL
        self.kind = kind
        self.recipeID = recipeID
    }

    public func validate(alongside others: [Self]) throws {
        guard folder.isFileURL, [nil, "", "localhost"].contains(folder.host) else { throw ToolError.unavailableFolder }
        let path = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard !path.pathComponents.contains("Optimized Copies"),
              !path.pathComponents.contains(where: { $0.hasPrefix("CloakTools Backup ") }) else { throw RuleError.outputFolder }
        guard !others.contains(where: {
            $0.id != id && $0.folder.standardizedFileURL.resolvingSymlinksInPath() == path && ($0.kind == kind || $0.kind == .all || kind == .all)
        }) else { throw RuleError.overlap }
    }

    public enum RuleError: LocalizedError {
        case overlap, outputFolder
        public var errorDescription: String? {
            switch self {
            case .overlap: "A rule already handles these files in this folder. Edit that rule or choose a different file type."
            case .outputFolder: "Choose a source folder outside Optimized Copies and original-file backups."
            }
        }
    }
}
