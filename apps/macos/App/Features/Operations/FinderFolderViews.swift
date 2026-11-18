import AppKit
import CloakToolsCore
import SwiftUI

private struct FolderReviewPage<Content: View, Actions: View>: View {
    let tool: WorkbenchTool
    let subtitle: String
    let task: FolderTask
    let output: URL?
    let close: () -> Void
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: tool.rawValue, subtitle: subtitle, symbol: tool.symbol)
            content.disabled(task.busy)
            if let output {
                HStack {
                    Label("Created \(output.lastPathComponent)", systemImage: "checkmark.circle")
                        .lineLimit(1).help(output.path)
                    Spacer()
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }.buttonStyle(.link)
                }.modifier(DialogCard())
            }
            OperationFeedback(activity: task.activity, error: task.error)
            if let notice = task.notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if task.busy {
                        Button("Cancel", action: task.cancel).modifier(DialogActionStyle()).keyboardShortcut(.cancelAction)
                    } else {
                        Button(output == nil && tool != .compare ? "Close" : "Done", action: close).modifier(DialogActionStyle()).keyboardShortcut(.cancelAction)
                        actions
                    }
                }
            }
        }.padding(20).frame(minWidth: 440, minHeight: 420)
    }
}

struct StructureReviewView: View {
    @Bindable var review: StructureReview
    let saveSet: (FileSetDefinition) throws -> Void
    let close: () -> Void

    var body: some View {
        FolderReviewPage(tool: .structure, subtitle: "Choose folders from “\(review.source.lastPathComponent)” to recreate empty.",
                         task: review.task, output: review.output, close: close) {
            if let structure = review.structure, !structure.paths.isEmpty {
                LabeledContent("New folder name") {
                    TextField("Folder name", text: $review.name).textFieldStyle(.roundedBorder).accessibilityLabel("New folder name")
                }.disabled(review.output != nil)
                HStack {
                    Text("\(review.selection.count) of \(structure.paths.count) subfolders selected").font(.subheadline)
                    Spacer()
                    Button(review.selection.isEmpty ? "Select All" : "Deselect All") {
                        review.selection = review.selection.isEmpty ? Set(structure.paths) : []
                        review.task.notice = nil
                    }.buttonStyle(.link).disabled(review.output != nil)
                }
                List(structure.paths, id: \.self) { path in
                    Toggle(isOn: Binding(get: { review.selection.contains(path) }, set: { review.toggle(path, included: $0) })) {
                        Label((path as NSString).lastPathComponent, systemImage: "folder")
                    }.toggleStyle(.checkbox).accessibilityLabel(path).help(path)
                        .padding(.leading, CGFloat(min(6, path.filter { $0 == "/" }.count)) * 12)
                }.disabled(review.output != nil)
                if review.output == nil {
                    DestinationRow(folder: review.destination) {
                        if let url = chooseFinderFolder("Choose where to create the new folder", startingAt: review.destination) { review.destination = url }
                    }
                }
            } else {
                ContentUnavailableView(review.structure == nil ? "Folder preview" : "No subfolders to reuse", systemImage: "folder",
                                       description: Text("The preview includes visible folders and skips packages and links."))
            }
        } actions: {
            if review.structure == nil {
                Button("Read Again", action: review.load).modifier(DialogActionStyle())
            } else if !review.selection.isEmpty {
                Button(review.hasSavedSet ? "Update File Set" : "Save File Set") { review.saveSet(using: saveSet) }
                    .modifier(DialogActionStyle()).disabled(review.matchesSavedSet)
                if review.output == nil {
                    Button("Create Folder", action: review.create).modifier(DialogActionStyle(prominent: true)).keyboardShortcut(.defaultAction)
                }
            }
        }
        .onChange(of: review.name) { review.task.notice = nil }
    }
}

struct SharingReviewView: View {
    @Bindable var review: SharingReview
    let close: () -> Void

    private var nameProblem: String? {
        guard !review.files.isEmpty else { return nil }
        do {
            try SafeOutput.validate(stem: review.name)
            try SharingCollection.validate(review.files)
            return nil
        } catch { return error.localizedDescription }
    }

    var body: some View {
        FolderReviewPage(tool: .collect, subtitle: "Keep this collection open to add files from other Finder windows.",
                         task: review.task, output: review.output, close: close) {
            if review.output == nil {
                LabeledContent("New folder name") {
                    TextField("Folder name", text: $review.name).textFieldStyle(.roundedBorder).accessibilityLabel("New folder name")
                }
                HStack {
                    Text("Files (\(review.files.count))").font(.headline)
                    Spacer()
                    Button("Add Files…", action: review.chooseFiles)
                }
            }
            if review.files.isEmpty {
                ContentUnavailableView("Choose files to share", systemImage: "tray",
                                       description: Text("Files from different folders can go into the same collection."))
            } else {
                List($review.files) { $file in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("Copy name", text: $file.name).textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Copy name for \(file.source.lastPathComponent)")
                                .disabled(review.output != nil)
                            Text((file.source.path as NSString).abbreviatingWithTildeInPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(file.source.path)
                        }
                        if review.output == nil {
                            Button { review.files.removeAll { $0.id == file.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless).accessibilityLabel("Remove \(file.name)")
                        }
                    }.padding(.vertical, 3)
                }
                if review.output == nil {
                    Text(nameProblem ?? "Duplicate names are numbered. Edit any copy name before saving.")
                        .font(.callout).foregroundStyle(nameProblem == nil ? Color.secondary : .red)
                }
            }
        } actions: {
            if review.output == nil {
                Button("Save Copies…") {
                    if let folder = chooseFinderFolder("Choose where to save “\(review.name)”", prompt: "Save Copies") { review.save(in: folder) }
                }.modifier(DialogActionStyle(prominent: true)).keyboardShortcut(.defaultAction)
                    .disabled(review.files.isEmpty || nameProblem != nil)
            }
        }
    }
}

struct ComparisonReviewView: View {
    let review: ComparisonReview
    let close: () -> Void

    var body: some View {
        FolderReviewPage(tool: .compare, subtitle: "Compare names, file contents and link targets, including hidden items.",
                         task: review.task, output: nil, close: close) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                folderRow("First", review.first)
                folderRow("Second", review.second)
            }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
            if let result = review.result {
                if result.differences.isEmpty {
                    ContentUnavailableView("Folder contents match", systemImage: "checkmark.circle",
                                           description: Text("\(result.checked) entries compared. Permissions and dates are excluded."))
                } else {
                    Text("\(result.differences.count) differences across \(result.checked) entries").font(.headline)
                    List(result.differences) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.path).lineLimit(2).truncationMode(.middle).help(item.path)
                                Text(description(for: item)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 6)
                            if item.kind != .rightOnly { reveal("First", review.first, item.path) }
                            if item.kind != .leftOnly { reveal("Second", review.second, item.path) }
                        }.padding(.vertical, 3)
                    }
                }
            } else { Spacer() }
        } actions: {
            Button("Compare Again", action: review.compare).modifier(DialogActionStyle(prominent: true))
        }
    }

    private func description(for item: FolderDifference) -> String {
        guard review.first.lastPathComponent != review.second.lastPathComponent else { return item.kind.rawValue }
        switch item.kind {
        case .leftOnly: return "Only in “\(review.first.lastPathComponent)”"
        case .rightOnly: return "Only in “\(review.second.lastPathComponent)”"
        default: return item.kind.rawValue
        }
    }

    private func folderRow(_ label: String, _ url: URL) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text((url.path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled).help(url.path)
        }
    }

    private func reveal(_ side: String, _ folder: URL, _ path: String) -> some View {
        Button("Reveal in \(side)") { NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent(path)]) }
            .buttonStyle(.link).font(.caption).accessibilityLabel("Reveal \(path) in \(side)").help("Show in \(folder.path)")
    }
}
