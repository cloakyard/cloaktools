import AppKit
import CloakToolsCore
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct OptimizationView: View {
    @Bindable var review: OptimizationReview
    let close: () -> Void
    @State private var replacing: OptimizationRow?
    @State private var bulkReplace = false
    @State private var trashing: OptimizationRow?
    @State private var newPipeline = false
    @State private var advanced = false
    @State private var comparing: OptimizationRow?
    @State private var quickLook: URL?
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DialogHeading(title: "Optimize Media", subtitle: "Review the size of each copy before saving.", symbol: "arrow.down.right.and.arrow.up.left")
            HStack {
                if !review.rows.isEmpty { Button("Add Files…", systemImage: "plus", action: review.chooseFiles) }
                Button("Paste", systemImage: "document.on.clipboard", action: review.addClipboard)
                Menu {
                    Button("Standard") { review.recipe = nil; review.options = .init() }
                    ForEach(AppModel.shared.exportRecipes) { recipe in
                        if case let .optimize(options) = recipe.options {
                            Button(recipe.title) { review.recipe = recipe; review.options = options }
                        }
                    }
                    Divider()
                    Button("New Pipeline…") { newPipeline = true }
                } label: {
                    Text(review.recipe?.title ?? "Recipe").lineLimit(1).truncationMode(.tail)
                }.frame(maxWidth: 180, alignment: .leading)
                Spacer()
                if !review.rows.isEmpty { Text("\(review.rows.count) \(review.rows.count == 1 ? "item" : "items")").foregroundStyle(.secondary) }
            }.disabled(review.task.busy)
            Group {
                if review.rows.isEmpty {
                    ContentUnavailableView("Drop files here", systemImage: "square.and.arrow.down",
                                           description: Text("Images, PDFs, video and audio can share a batch."))
                } else {
                    List(review.rows) { row in item(row) }
                        .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background.secondary, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(targeted ? Color.accentColor : .secondary.opacity(0.25)))
            .dropDestination(for: URL.self) { urls, _ in
                guard !review.task.busy, urls.allSatisfy(\.isFileURL) else { return false }
                review.add(urls)
                return true
            } isTargeted: { targeted = $0 }
            DisclosureGroup("Export options", isExpanded: $advanced) {
                ScrollView {
                    if let steps = review.options.steps {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(steps.indices, id: \.self) { i in Text("\(i + 1). " + steps[i].title) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            field("Compression") {
                                Picker("Compression", selection: $review.options.aggressive) {
                                    Text("Standard").tag(false); Text("Stronger").tag(true)
                                }
                            }
                            if review.includes(.image) {
                                field("Image format") {
                                    Picker("Image format", selection: $review.options.imageFormat) {
                                        ForEach(OptimizedImageFormat.allCases.filter { $0.available && ($0 != .originalJPEG || review.hasJPEGXL || review.options.imageFormat == .originalJPEG) }, id: \.self) { Text($0.title).tag($0) }
                                    }
                                }
                                if review.options.imageFormat == .webp {
                                    GridRow { Text("WebP"); Toggle("Lossless encoding", isOn: $review.options.losslessWebP) }
                                }
                            }
                            if review.includes(.image) || review.includes(.pdf) || review.includes(.video) {
                                field("Crop") {
                                    Picker("Crop", selection: $review.options.crop) {
                                        ForEach(OptimizationCrop.allCases.filter { $0 != .fullPage || review.includes(.pdf) || review.options.crop == .fullPage }, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                }
                            }
                            if review.includes(.image) || review.includes(.video) {
                                field("Scale") {
                                    Picker("Scale", selection: $review.options.scale) {
                                        ForEach([1.0, 0.75, 0.5, 0.25, 0.1], id: \.self) { Text($0, format: .percent).tag($0) }
                                    }
                                }
                            }
                            if review.includes(.pdf) {
                                field("PDF images") {
                                    Picker("PDF images", selection: $review.options.scanDPI) {
                                        Text("Standard").tag(nil as Int?)
                                        ForEach([72, 150, 300], id: \.self) { dpi in Text("Scan · \(dpi) DPI").tag(Optional(dpi)) }
                                    }
                                }
                            }
                            field("Size limit") {
                                Picker("Size limit", selection: $review.options.maximumBytes) {
                                    Text("None").tag(nil as Int?)
                                    ForEach([100_000, 500_000, 1_000_000, 5_000_000, 8_000_000, 25_000_000], id: \.self) {
                                        Text(bytes($0)).tag(Optional($0))
                                    }
                                }
                            }
                            if review.includes(.video) {
                                field("Video format") {
                                    Picker("Video format", selection: $review.options.videoFormat) {
                                        ForEach(OptimizedVideoFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                }
                                field("Video speed") {
                                    Picker("Video speed", selection: $review.options.playbackSpeed) {
                                        ForEach([0.5, 1.0, 1.5, 2.0, 4.0], id: \.self) { Text("\($0.formatted())×").tag($0) }
                                    }
                                }
                                if review.options.videoFormat != .gif {
                                    GridRow { Text("Video audio"); Toggle("Mute video", isOn: $review.options.muteVideo) }
                                }
                            }
                            if review.includes(.audio) {
                                field("Audio format") {
                                    Picker("Audio format", selection: $review.options.audioFormat) {
                                        ForEach(OptimizedAudioFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                    }
                                }
                                if [.automatic, .aac, .mp3, .ogg].contains(review.options.audioFormat) {
                                    field("Audio bitrate") {
                                        Picker("Audio bitrate", selection: $review.options.audioBitrate) {
                                            ForEach([48, 64, 96, 128, 160, 192, 256, 320], id: \.self) { Text("\($0) kbps").tag($0) }
                                        }
                                    }
                                }
                                field("Loudness") {
                                    Picker("Loudness", selection: $review.options.loudnessTarget) {
                                        Text("Original").tag(nil as Int?)
                                        ForEach([-14, -16, -23], id: \.self) { Text("\($0) LUFS").tag(Optional($0)) }
                                    }
                                }
                                if review.options.loudnessTarget == nil {
                                    GridRow { Text("Peaks"); Toggle("Normalize to −1 dB", isOn: $review.options.normalizeAudio) }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        SaveExportRecipeButton(recipe: $review.recipe) { .optimize(review.options) }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxHeight: 220)
            }.disabled(review.task.busy)
            OperationFeedback(activity: review.task.busy ? (review.current ?? review.task.activity) : nil, error: review.task.error)
            if let notice = review.task.notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
            DialogFooter {
                if review.task.busy {
                    Button("Cancel", action: review.task.cancel).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                } else if !allSaved {
                    Button("Close", action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                }
            } actions: {
                if !review.task.busy {
                    if review.rows.isEmpty {
                        Button("Choose Files…", action: review.chooseFiles)
                            .keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                    } else if allSaved {
                        DialogDoneButton(action: close)
                    } else {
                        if review.replaceable.count > 1 {
                            Button("Replace Originals…") { bulkReplace = true }.modifier(DialogActionStyle())
                        }
                        if review.readyCount > 0 {
                            Button("Save \(review.readyCount) \(review.readyCount == 1 ? "Copy" : "Copies")…") {
                                if let folder = chooseFinderFolder("Save optimized copies", prompt: "Save Copies") { review.save(in: folder) }
                            }.modifier(DialogActionStyle(prominent: review.pendingCount == 0))
                            .keyboardShortcut(review.pendingCount == 0 ? .defaultAction : nil)
                        }
                        if review.pendingCount > 0 || review.readyCount == 0 {
                            Button(review.pendingCount == 0 && !review.rows.isEmpty ? "Preview Again" : "Preview", action: review.preview)
                                .keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                        }
                    }
                }
            }
        }.padding(20).frame(minWidth: 440, minHeight: 410)
        .sheet(isPresented: $newPipeline) {
            OptimizationPipelineEditor { recipe in
                if case let .optimize(options) = recipe.options { review.recipe = recipe; review.options = options }
            }
        }
        .onAppear { review.syncRestoredRows() }
        .onChange(of: review.history.entries.map(\.backup)) { review.syncRestoredRows() }
        .confirmationDialog("Replace \(review.replaceable.count) originals?", isPresented: $bulkReplace) {
            Button("Keep Backups and Replace", role: .destructive) { review.replaceOriginals(review.replaceable) }
        } message: { Text("Each original is kept beside its replacement. Use Recent Results to undo this batch.") }
        .sheet(item: $comparing) { row in
            if let result = row.result { OptimizationPDFComparison(result) }
        }
        .quickLookPreview($quickLook)
        .confirmationDialog("Replace the original file?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }), presenting: replacing) { row in
            Button("Keep Backup and Replace", role: .destructive) { review.replaceOriginal(row) }
        } message: { row in Text("The optimized copy takes the place of \(row.input.name). The original is kept in a backup folder beside it.") }
        .confirmationDialog("Move the original to Trash?", isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }), presenting: trashing) { row in
            Button("Move Original to Trash", role: .destructive) { review.trashOriginal(row) }
        } message: { row in Text("The saved optimized copy is kept. Finder can restore \(row.input.name) from Trash.") }
    }

    private var allSaved: Bool { !review.rows.isEmpty && review.rows.allSatisfy { $0.output != nil } }

    private func bytes(_ count: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file) }
    private func field<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow { Text(name); content().labelsHidden() }
    }

    private func item(_ row: OptimizationRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.input.name).lineLimit(1).truncationMode(.middle)
                if let result = row.result {
                    Text("\(bytes(result.inputBytes)) → \(bytes(result.outputBytes)) · \(result.previewURL.pathExtension.uppercased())")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let reason = row.message { Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer()
            if let result = row.result { OptimizationDragHandle(result: result) }
            if let output = row.output {
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
            } else if let result = row.result {
                if result.comparisonOriginal != nil { Button("Compare PDF…") { comparing = row } }
                else { Button("Quick Look") { quickLook = result.previewURL } }
                if UTType(filenameExtension: result.previewURL.pathExtension)?.conforms(to: .image) == true {
                    Button("Copy") { review.copyImage(result) }
                }
            }
            Menu {
                if let backup = row.backup {
                    Button("Reveal Backup") { NSWorkspace.shared.activateFileViewerSelecting([backup.backupURL]) }
                    Button("Restore Original") { review.restoreOriginal(row) }
                } else if case .file = row.input, let result = row.result {
                    if row.output == nil && result.canReplaceOriginal { Button("Replace Original…") { replacing = row } }
                    if row.output != nil && !row.originalRemoved { Button("Move Original to Trash…", role: .destructive) { trashing = row } }
                }
                Button("Remove from Batch") { review.remove(row.id) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for \(row.input.name)").disabled(review.task.busy)
        }.buttonStyle(.borderless).padding(.vertical, 3)
    }
}
