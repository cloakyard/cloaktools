import Foundation
import CloakToolsCore

enum WorkbenchCategory: String, CaseIterable, Identifiable {
    case finder = "Finder Tools"
    case files = "Files & Templates"
    case media = "Images, PDFs & Media"
    case text = "Text & Sharing"
    case links = "Open Links"
    case developer = "Developer Tools"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .finder: "folder"
        case .files: "doc.on.doc"
        case .media: "photo.on.rectangle"
        case .text: "text.alignleft"
        case .links: "link"
        case .developer: "chevron.left.forwardslash.chevron.right"
        }
    }

    var tools: [WorkbenchTool] {
        switch self {
        case .finder: [.newFile, .clipboard, .copy, .convert, .pdf, .fileList]
        case .files: [.newFile, .fileSet, .templates, .savedSets, .presets]
        case .media: [.fit, .convert, .pdf, .pages, .exportMedia, .recipes]
        case .text: [.cleanup, .digest, .clipboard, .createQR, .readQR, .fileList]
        case .links: [.openLink, .testLink, .linkSettings]
        case .developer: [.json, .base64, .sample, .example, .languageSettings]
        }
    }

    static func visible(developerEnabled: Bool) -> [Self] {
        allCases.filter { $0 != .developer || developerEnabled }
    }
}

enum WorkbenchTool: String, CaseIterable, Identifiable {
    case newFile = "Create a new file"
    case clipboard = "Create a file from the clipboard"
    case copy = "Copy file names or paths"
    case convert = "Convert an image"
    case pdf = "Combine files into a PDF"
    case fileList = "Export a file list"
    case fileSet = "Create a folder with a set of files"
    case templates = "Saved file templates"
    case savedSets = "Saved file sets"
    case presets = "Folder presets"
    case fit = "Make an image fit a size limit"
    case pages = "Organize PDF pages"
    case exportMedia = "Export video or audio"
    case recipes = "Saved export recipes"
    case cleanup = "Clean up text"
    case digest = "Combine text files into Markdown"
    case createQR = "Create a QR code"
    case readQR = "Read a QR code from an image"
    case openLink = "Open a link once"
    case testLink = "Test a link rule"
    case linkSettings = "Manage link rules and defaults"
    case json = "Format or check JSON"
    case base64 = "Encode or decode Base64"
    case sample = "Generate sample files"
    case example = "Create a configuration example"
    case languageSettings = "Choose programming language starters"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .newFile: "doc.badge.plus"
        case .clipboard: "doc.on.clipboard"
        case .copy: "list.clipboard"
        case .convert: "photo"
        case .pdf: "doc.on.doc"
        case .fileList: "list.bullet.rectangle"
        case .fileSet, .savedSets: "folder.badge.plus"
        case .templates: "doc.text"
        case .presets: "folder.badge.gearshape"
        case .fit: "arrow.down.right.and.arrow.up.left"
        case .pages: "square.grid.2x2"
        case .exportMedia: "play.rectangle"
        case .recipes: "slider.horizontal.3"
        case .cleanup: "text.alignleft"
        case .digest: "text.document"
        case .createQR: "qrcode"
        case .readQR: "qrcode.viewfinder"
        case .openLink: "arrow.up.forward.app"
        case .testLink: "link.badge.plus"
        case .linkSettings: "arrow.triangle.branch"
        case .json: "curlybraces"
        case .base64: "character.cursor.ibeam"
        case .sample: "doc.badge.gearshape"
        case .example: "doc.on.doc"
        case .languageSettings: "chevron.left.forwardslash.chevron.right"
        }
    }

    private func searchTerms(for availability: ToolAvailability) -> String {
        switch self {
        case .fit: "shrink photo compress resize make it fit upload budget"
        case .pdf: "merge PDFs assemble images"
        case .copy: "copy as " + availability.copyFormats.map(\.title).joined(separator: " ")
        case .pages: "rotate reorder remove pages"
        case .convert: "photo png jpeg heic tiff"
        case .fileList: "csv markdown inventory"
        case .digest: "markdown digest"
        case .cleanup: "trim spaces whitespace blank lines"
        case .exportMedia: "extract audio mp4 m4a movie"
        case .example: "env JSON placeholder example copy"
        case .json: "validate minify pretty print"
        case .languageSettings: "hello world code templates"
        default: ""
        }
    }

    static func matching(_ query: String, developerEnabled: Bool) -> [Self] {
        let categories = WorkbenchCategory.visible(developerEnabled: developerEnabled)
        let availability = ToolAvailability(developerEnabled: developerEnabled)
        let words = query.split(whereSeparator: \.isWhitespace)
        return allCases.filter { tool in
            let owners = categories.filter { $0.tools.contains(tool) }
            let terms = ([tool.rawValue, tool.searchTerms(for: availability)] + owners.map(\.rawValue)).joined(separator: " ")
            return !owners.isEmpty && words.allSatisfy { terms.localizedStandardContains(String($0)) }
        }
    }
}
