import AppKit
import SwiftUI
import AVKit
import UniformTypeIdentifiers
import CloakToolsCore

@MainActor
func chooseMediaSource(title: String) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.prompt = "Choose Media"
    panel.allowedContentTypes = MediaExport.inputExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message = "Choose a local movie or audio file, up to 1 GB and 30 minutes."
    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor @Observable
final class MediaOperation: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let revealOutput: Bool
    var source: PreparedMedia?
    var player: AVPlayer?
    var preset: MediaExportPreset = .video720
    var recipe: ExportRecipe?
    var compatibilityError: String? {
        guard let source else { return nil }
        do { try ExportRecipeOptions.media(preset).validateMediaCompatibility(source.presets); return nil }
        catch { return error.localizedDescription }
    }
    var name: String
    var destination: URL
    var output: URL?
    var outputBytes: Int?
    var cancellation: String?
    var error: String?
    var activity: String?
    var progress: Double?
    var stopping = false
    var onPrepared: ((Bool) -> Void)?
    var busy: Bool { activity != nil }
    private var preparation: Task<PreparedMedia, Error>?
    private var publication: Task<URL, Error>?
    private var exportID: UUID?

    init(sourceURL: URL, revealOutput: Bool, recipe: ExportRecipe? = nil) {
        self.sourceURL = sourceURL; self.revealOutput = revealOutput
        self.recipe = recipe
        let requestedPreset: MediaExportPreset?
        if case let .media(value) = recipe?.options { requestedPreset = value; preset = value } else { requestedPreset = nil }
        let stem = sourceURL.deletingPathExtension().lastPathComponent + " export"
        name = (try? SafeOutput.validate(stem: stem)) != nil ? stem : "Media export"
        destination = sourceURL.deletingLastPathComponent()
        activity = "Preparing a private copy…"
        let worker = Task.detached(priority: .userInitiated) { try await MediaExport.prepare(sourceURL) }
        preparation = worker
        Task { [self] in
            do {
                let prepared = try await worker.value
                if worker.isCancelled { throw CancellationError() }
                source = prepared; preset = requestedPreset ?? prepared.presets.first ?? .audio
                player = AVPlayer(playerItem: AVPlayerItem(asset: MediaExport.localAsset(prepared.playbackURL)))
                player?.allowsExternalPlayback = false
                onPrepared?(prepared.hasVideo)
            } catch is CancellationError { cancellation = "Cancelled. No copy was exported." }
            catch { self.error = error.localizedDescription }
            preparation = nil; activity = nil; stopping = false
        }
    }
    func chooseDestination() {
        let panel = NSOpenPanel(); panel.title = "Export media to…"; panel.prompt = "Choose Folder"
        panel.directoryURL = destination; panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let folder = panel.url { destination = folder }
    }
    func export() {
        guard !busy, output == nil, let source, compatibilityError == nil else { return }
        do { try SafeOutput.validate(stem: name) } catch { self.error = error.localizedDescription; return }
        player?.pause(); error = nil; cancellation = nil; activity = "Exporting copy…"; progress = 0
        let token = UUID(); exportID = token
        let preset = preset, destination = destination, name = name
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            try await MediaExport.export(source, preset: preset, in: destination, name: name) { [weak self] value in
                await self?.reportProgress(value, token: token)
            }
        }
        publication = worker
        Task { [self] in
            do {
                let url = try await worker.value; output = url
                outputBytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if revealOutput { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch is CancellationError { cancellation = "Cancelled. No copy was exported." }
            catch { self.error = error.localizedDescription }
            publication = nil; exportID = nil; activity = nil; stopping = false; progress = nil
        }
    }
    private func reportProgress(_ value: Double, token: UUID) { if exportID == token { progress = max(progress ?? 0, value) } }
    func cancel() { player?.pause(); stopping = true; preparation?.cancel(); publication?.cancel() }
    func finish() { player?.pause(); player?.replaceCurrentItem(with: nil); player = nil; source = nil }
    func open() {
        guard let output else { return }
        guard let viewer = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.QuickTimePlayerX") else {
            error = "Copy saved. QuickTime Player is unavailable; reveal the file in Finder to open it."; return
        }
        NSWorkspace.shared.open([output], withApplicationAt: viewer, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            let message = error.map { "Copy saved, but it couldn’t be opened: \($0.localizedDescription)" }
            Task { @MainActor in self?.error = message }
        }
    }
}

@MainActor
final class MediaWindow: NSWindowController, NSWindowDelegate {
    let operation: MediaOperation
    var onClose: (() -> Void)?
    init(operation: MediaOperation) {
        self.operation = operation
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 550), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Export Media"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.contentViewController = NSHostingController(rootView: MediaOperationView(operation: operation, close: { [weak window] in window?.close() }))
        window.contentMinSize = NSSize(width: 440, height: 440)
        window.setContentSize(NSSize(width: 480, height: 550)); window.center(); window.isReleasedWhenClosed = false
        operation.onPrepared = { [weak window] hasVideo in
            if !hasVideo, let window, abs((window.contentView?.bounds.height ?? 0) - 550) < 1 {
                window.setContentSize(NSSize(width: 480, height: 440))
            }
        }
        super.init(window: window); window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if operation.busy { operation.cancel(); return false }; operation.finish(); return true }
    func windowWillClose(_ notification: Notification) { operation.finish(); onClose?() }
}

struct MediaOperationView: View {
    @Bindable var operation: MediaOperation
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Export media", subtitle: operation.recipe.map { "From “\($0.title)” · \(operation.sourceURL.lastPathComponent)" } ?? operation.sourceURL.lastPathComponent, symbol: "play.rectangle")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let source = operation.source {
                        VStack(alignment: .leading, spacing: 10) {
                            if let player = operation.player {
                                MediaPlayer(player: player).frame(height: source.hasVideo ? 186 : 64)
                                    .clipShape(.rect(cornerRadius: 8)).disabled(operation.busy)
                                    .accessibilityLabel("Original media preview")
                            }
                            HStack {
                                Label(duration(source.duration), systemImage: "clock")
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: Int64(source.sourceByteCount), countStyle: .file))
                            }.font(.caption).foregroundStyle(.secondary)
                            Text(source.hasVideo ? "\(source.width) × \(source.height) · \(source.frameRate.formatted(.number.precision(.fractionLength(0...2)))) fps · \(source.hasAudio ? "With audio" : "No audio")" : "Audio only · Local preview")
                                .font(.caption).foregroundStyle(.secondary)
                        }.modifier(DialogCard())
                        if operation.output == nil {
                            VStack(alignment: .leading, spacing: 10) {
                                Picker("Export as", selection: $operation.preset) {
                                    ForEach(source.presets) { Text($0.title).tag($0) }
                                    if !source.presets.contains(operation.preset) { Text(operation.preset.title + " · Unavailable for this source").tag(operation.preset).disabled(true) }
                                }
                                Text(operation.preset.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 8) {
                                    Text("Name").foregroundStyle(.secondary)
                                    TextField("File name", text: $operation.name).textFieldStyle(.roundedBorder).accessibilityLabel("Export file name, without extension")
                                    Text(".\(operation.preset.fileExtension)").foregroundStyle(.secondary)
                                }
                            }.modifier(DialogCard()).disabled(operation.busy)
                        }
                    }
                    if let output = operation.output {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Saved \(output.lastPathComponent)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            if let count = operation.outputBytes { Text("\(count.formatted()) bytes · \(operation.preset.title)").font(.caption).foregroundStyle(.secondary) }
                            HStack(spacing: 16) {
                                ShowInFinderButton(url: output)
                                Button("Open in QuickTime", action: operation.open).buttonStyle(.link)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
                    } else {
                        Text("Exports the full clip. Size varies with content. Extra tracks and source metadata are omitted.").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize)
            if operation.output == nil { DestinationRow(folder: operation.destination, change: operation.chooseDestination).disabled(operation.busy) }
            OperationFeedback(cancellation: operation.cancellation, error: operation.error ?? operation.compatibilityError)
            if let activity = operation.activity {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(operation.stopping ? "Stopping…" : activity)
                        Spacer()
                        if let progress = operation.progress { Text("\(Int(progress * 100))%").monospacedDigit() }
                    }.font(.callout)
                    if let progress = operation.progress { ProgressView(value: progress).accessibilityLabel("Export progress") }
                    else { ProgressView().controlSize(.small) }
                }
            }
            DialogFooter {
                if operation.busy {
                    Button("Cancel", role: .cancel, action: operation.cancel).keyboardShortcut(.cancelAction).modifier(DialogActionStyle()).disabled(operation.stopping)
                } else if operation.output == nil {
                    Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                }
            } actions: {
                if operation.output != nil && !operation.busy {
                    DialogDoneButton(action: close)
                } else if !operation.busy {
                    if operation.source != nil && operation.compatibilityError == nil {
                        SaveExportRecipeButton(recipe: $operation.recipe) { .media(operation.preset) }
                            .modifier(DialogActionStyle())
                    }
                    Button("Export Copy", action: operation.export).keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true)).disabled(operation.source == nil || operation.compatibilityError != nil || operation.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }.padding(20).frame(minWidth: 440, minHeight: 440)
    }
    private func duration(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

struct MediaPlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.controlsStyle = .inline; view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = false; view.showsSharingServiceButton = false
        view.allowsPictureInPicturePlayback = false; view.updatesNowPlayingInfoCenter = false
        view.allowsVideoFrameAnalysis = false; view.player = player
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player?.pause(); view.player = nil }
}
