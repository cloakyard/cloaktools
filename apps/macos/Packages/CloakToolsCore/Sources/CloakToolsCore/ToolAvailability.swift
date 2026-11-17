import Foundation

/// Presentation choices, not a permission system. Existing operations keep their snapshot.
public struct ToolAvailability: Sendable {
    public let developerEnabled: Bool
    public init(developerEnabled: Bool) { self.developerEnabled = developerEnabled }
    public var categories: [SettingsCategory] { SettingsCategory.allCases.filter { developerEnabled || $0 != .developer } }
    public var builtInTemplates: [FileTemplate] { FileTemplate.allCases.filter { developerEnabled || !$0.isDeveloperTool } }
    public var copyFormats: [CopyFormat] { CopyFormat.allCases.filter { developerEnabled || ![.shellArguments, .json].contains($0) } }
    public func includes(_ source: TemplateSource) -> Bool { developerEnabled || !source.isDeveloperTool }
    public func includes(templateID: String, sources: [TemplateSource]) -> Bool {
        // Keep missing references available for the existing repair flow.
        guard let source = sources.first(where: { $0.id == templateID }) else { return true }
        return includes(source)
    }
    public func includes(_ set: FileSetDefinition, sources: [TemplateSource]) -> Bool {
        set.entries.allSatisfy { $0.templateID.map { includes(templateID: $0, sources: sources) } ?? true }
    }
}

public extension Preferences {
    var tools: ToolAvailability { .init(developerEnabled: developerToolsEnabled) }
}
public extension FileTemplate {
    var isDeveloperTool: Bool { isProgramming || self == .json }
}
public extension TemplateSource {
    var isDeveloperTool: Bool {
        switch self {
        case let .builtIn(template): template.isDeveloperTool
        case let .custom(template):
            // Metadata only: never inspect saved content to infer a user's role.
            Self.developerExtensions.contains(template.fileExtension.lowercased())
        }
    }
    private static var developerExtensions: Set<String> {
        Set(FileTemplate.allCases.filter(\.isDeveloperTool).map(\.fileExtension))
            .union(["h", "hpp", "cc", "cxx", "m", "mm", "jsx", "tsx", "mjs", "cjs", "sh", "bash", "zsh", "sql", "yaml", "yml", "toml", "xml", "html", "css", "scss"])
    }
}

public enum ToolAvailabilityError: LocalizedError {
    case developerToolsOff
    public var errorDescription: String? { "Turn on Developer Tools in General to use this tool, file type or saved workflow. Your saved items are still kept on this Mac." }
}
