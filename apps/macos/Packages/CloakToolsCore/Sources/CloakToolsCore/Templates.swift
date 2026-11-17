import Foundation

public enum FileTemplate: String, CaseIterable, Codable, Identifiable, Sendable {
    case text, markdown, json, pdf, python, javascript, typescript, swift, rust, c, cpp, csharp, java, go, ruby, php, kotlin
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .text: "Plain Text"
        case .markdown: "Markdown"
        case .json: "JSON"
        case .pdf: "PDF"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .rust: "Rust"
        case .c: "C"
        case .cpp: "C++"
        case .csharp: "C#"
        case .java: "Java"
        case .go: "Go"
        case .ruby: "Ruby"
        case .php: "PHP"
        case .kotlin: "Kotlin"
        case .swift: "Swift"
        }
    }
    public var fileExtension: String {
        switch self { case .text: "txt"; case .markdown: "md"; case .json: "json"; case .pdf: "pdf"; case .python: "py"; case .javascript: "js"; case .typescript: "ts"; case .swift: "swift"; case .rust: "rs"; case .c: "c"; case .cpp: "cpp"; case .csharp: "cs"; case .java: "java"; case .go: "go"; case .ruby: "rb"; case .php: "php"; case .kotlin: "kt" }
    }
    public var isProgramming: Bool { ![.text, .markdown, .json, .pdf].contains(self) }
    public var starter: String {
        switch self {
        case .python: "print(\"Hello, World!\")\n"
        case .javascript, .typescript: "console.log(\"Hello, World!\");\n"
        case .swift: "print(\"Hello, World!\")\n"
        case .rust: "fn main() {\n    println!(\"Hello, World!\");\n}\n"
        case .c: "#include <stdio.h>\n\nint main(void) {\n    puts(\"Hello, World!\");\n    return 0;\n}\n"
        case .cpp: "#include <iostream>\n\nint main() {\n    std::cout << \"Hello, World!\" << std::endl;\n    return 0;\n}\n"
        case .csharp: "using System;\n\nConsole.WriteLine(\"Hello, World!\");\n"
        case .java: "class HelloWorld {\n    public static void main(String[] args) {\n        System.out.println(\"Hello, World!\");\n    }\n}\n"
        case .go: "package main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello, World!\")\n}\n"
        case .ruby: "puts \"Hello, World!\"\n"
        case .php: "<?php\n\necho \"Hello, World!\\n\";\n"
        case .kotlin: "fun main() {\n    println(\"Hello, World!\")\n}\n"
        default: ""
        }
    }
    public func contents(using preferences: Preferences, customContent: Data? = nil, folderWantsStarter: Bool? = nil) throws -> Data {
        if let customContent { return customContent }
        if self == .pdf { return try BlankDocuments.pdf() }
        if self == .json { return Data("{}\n".utf8) }
        return Data((preferences.usesStarter(for: self, folderWantsStarter: folderWantsStarter) ? starter : "").utf8)
    }
}

public struct CreationRequest: Sendable {
    public let folder: URL
    public let source: TemplateSource
    public let preferences: Preferences
    public let name: String
    public init(folder: URL, template: FileTemplate, preferences: Preferences, name: String = "Untitled") {
        self.init(folder: folder, source: .builtIn(template), preferences: preferences, name: name)
    }
    public init(folder: URL, source: TemplateSource, preferences: Preferences, name: String = "Untitled") {
        self.folder = folder; self.source = source; self.preferences = preferences; self.name = name
    }
    public func perform() throws -> URL {
        try Task.checkCancellation()
        return try SafeOutput.publish(source.contents(using: preferences), in: folder, stem: name, extension: source.fileExtension)
    }
}
