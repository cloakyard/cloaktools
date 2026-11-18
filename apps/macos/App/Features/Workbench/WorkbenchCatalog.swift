import Foundation
import CloakToolsCore

struct WorkbenchGroup: Identifiable {
    let title: String
    let tools: [WorkbenchTool]
    var id: String { title }
}

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

    var groups: [WorkbenchGroup] {
        switch self {
        case .finder: [
            .init(title: "Folders", tools: [.structure, .compare]),
            .init(title: "Collect and list files", tools: [.collect, .copy, .fileList]),
            .init(title: "Images and PDFs", tools: [.fit, .convert, .pdf]),
            .init(title: "Create a file", tools: [.newFile, .clipboard])
        ]
        case .files: [
            .init(title: "Create", tools: [.newFile, .fileSet]),
            .init(title: "Use again", tools: [.templates, .savedSets, .presets])
        ]
        case .media: [
            .init(title: "Images", tools: [.fit, .convert]),
            .init(title: "PDFs", tools: [.pdf, .pages]),
            .init(title: "Media and saved exports", tools: [.exportMedia, .recipes])
        ]
        case .text: [
            .init(title: "Text and files", tools: [.cleanup, .digest, .clipboard, .fileList]),
            .init(title: "QR codes", tools: [.createQR, .readQR])
        ]
        case .links: [
            .init(title: "Open or test", tools: [.openLink, .testLink]),
            .init(title: "Preferences", tools: [.linkSettings])
        ]
        case .developer: [
            .init(title: "Inspect and transform", tools: [.json, .base64]),
            .init(title: "Test data and starters", tools: [.sample, .example, .languageSettings])
        ]
        }
    }
    var tools: [WorkbenchTool] { groups.flatMap(\.tools) }

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
    case structure = "Reuse a folder structure"
    case collect = "Collect copies for sharing"
    case compare = "Compare two folders"
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
    var detail: String {
        switch self {
        case .newFile: "Start a text, Markdown or PDF file, or use a saved template."
        case .clipboard: "Save copied text as a text file or a copied image as a PNG."
        case .copy: "Preview names, full paths or links before copying them."
        case .convert: "Save a copy as PNG, JPEG or HEIC."
        case .pdf: "Arrange documents and images in reading order."
        case .fileList: "Save names, sizes and other details as CSV or Markdown."
        case .structure: "Choose subfolders to recreate empty or save as a file set."
        case .collect: "Gather files from different locations and review the copy names."
        case .compare: "Find missing or changed files in a working folder and its backup."
        case .fileSet: "Review the folder tree and files before creating them together."
        case .templates: "Import and favorite the text you use to start new files."
        case .savedSets: "Reuse a folder structure and the files it contains."
        case .presets: "Reuse a destination, file type and filename."
        case .fit: "Preview the file size and dimensions before saving a copy."
        case .pages: "Select, reorder or rotate pages from one PDF."
        case .exportMedia: "Save an MP4 video or extract audio as M4A."
        case .recipes: "Apply saved export settings to another image or media file."
        case .cleanup: "Trim spaces, tidy blank lines and preview the result."
        case .digest: "Collect the contents of text files in one Markdown document."
        case .createQR: "Turn text or a link into a scannable PNG."
        case .readQR: "Read the text or link stored in a code."
        case .openLink: "Choose an app for this link and bypass routing rules."
        case .testLink: "Preview which app your rules would choose for a web or email link."
        case .linkSettings: "Choose default apps and edit web and email rules in Settings."
        case .json: "Validate, indent or minify JSON and locate syntax errors."
        case .base64: "Convert between Base64 and text or image data."
        case .sample: "Create test files as JSON, CSV, plain text or binary."
        case .example: "Replace values in a JSON or .env file with placeholders."
        case .languageSettings: "Set the languages that start with a Hello World example."
        }
    }
    var symbol: String {
        switch self {
        case .newFile: "doc.badge.plus"
        case .clipboard: "doc.on.clipboard"
        case .copy: "list.clipboard"
        case .convert: "photo"
        case .pdf: "doc.on.doc"
        case .fileList: "list.bullet.rectangle"
        case .structure: "folder.badge.plus"
        case .collect: "tray.and.arrow.down"
        case .compare: "arrow.left.arrow.right"
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
        case .newFile: availability.builtInTemplates.map { "\($0.title) \($0.fileExtension)" }.joined(separator: " ")
        case .fit: "shrink photo compress resize make it fit upload budget"
        case .pdf: "merge PDFs assemble create PDF from images"
        case .copy: "copy as " + availability.copyFormats.map(\.title).joined(separator: " ")
        case .pages: "rotate reorder remove pages from PDFs"
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
        let categories = WorkbenchCategory.visible(developerEnabled: developerEnabled).map { (name: $0.rawValue, tools: Set($0.tools)) }
        let availability = ToolAvailability(developerEnabled: developerEnabled)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        func matches(_ text: String) -> Bool { words.allSatisfy { text.localizedStandardContains($0) } }
        var titles: [Self] = []
        var capabilities: [Self] = []
        var byCategory: [Self] = []
        for tool in allCases {
            let owners = categories.filter { $0.tools.contains(tool) }
            guard !owners.isEmpty else { continue }
            let terms = [tool.rawValue, tool.detail, tool.searchTerms(for: availability)].joined(separator: " ")
            if matches(tool.rawValue) { titles.append(tool) }
            else if matches(terms) { capabilities.append(tool) }
            else if owners.contains(where: { matches(terms + " " + $0.name) }) { byCategory.append(tool) }
        }
        let direct = titles + capabilities
        return direct.isEmpty ? byCategory : direct
    }
}
