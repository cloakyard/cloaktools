import AVKit
import CloakToolsCore
import SwiftUI
import Translation

struct SubtitleView: View {
    @Bindable var operation: SubtitleOperation
    let close: () -> Void
    @State private var choosingLanguages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DialogHeading(title: "Generate subtitles", subtitle: operation.url.lastPathComponent, symbol: "captions.bubble")
            if let output = operation.output {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Saved \(operation.exportCount) SRT \(operation.exportCount == 1 ? "file" : "files")", systemImage: "checkmark.circle")
                    Text(output.lastPathComponent).foregroundStyle(.secondary)
                    ShowInFinderButton(url: output)
                }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let player = operation.player {
                            MediaPlayer(player: player)
                                .frame(height: operation.media?.hasVideo == true ? 138 : 48)
                                .clipShape(.rect(cornerRadius: 8)).accessibilityLabel("Original media")
                        }
                        if operation.media != nil {
                            if operation.cues.isEmpty { setup } else { review }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let activity = operation.task.activity ?? operation.job.map({ "Translating to \(SubtitleLanguage.name($0.target))…" }) {
                    HStack { ProgressView().controlSize(.small); Text(activity) }.font(.callout)
                }
                OperationFeedback(cancellation: operation.task.notice, error: operation.task.error)
            }
            DialogFooter {
                if operation.output == nil {
                    Button(operation.busy ? "Cancel" : "Close", role: .cancel) {
                        if operation.busy { operation.cancel() } else { close() }
                    }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                }
            } actions: {
                if operation.output != nil { DialogDoneButton(action: close) }
                else if !operation.busy { primaryActions }
            }
        }
        .padding(20).frame(minWidth: 420, minHeight: 360)
        .sheet(isPresented: $choosingLanguages) {
            SubtitleLanguageSheet(operation: operation)
        }
        .background {
            if let job = operation.job {
                let snapshot = operation.cues
                Color.clear.frame(width: 0, height: 0)
                    .translationTask(source: Locale.Language(identifier: operation.spoken),
                                     target: Locale.Language(identifier: job.target), preferredStrategy: .highFidelity,
                                     action: Self.translate(snapshot, job: job, operation: operation))
                    .id(job.id)
            }
        }
        .onDisappear {
            operation.player?.pause()
            if operation.job != nil { operation.cancel() }
        }
    }

    // The view supplies a session scoped to this action, including any system download prompt.
    private nonisolated static func translate(_ cues: [SubtitleCue], job: SubtitleOperation.TranslationJob,
                                               operation: SubtitleOperation) -> (TranslationSession) async -> Void {
        { session in
            do {
                let result = try await Subtitles.translate(cues, using: session)
                await operation.complete(job, with: .success(result))
            } catch { await operation.complete(job, with: .failure(error)) }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Spoken language", selection: $operation.spoken) {
                ForEach(operation.spokenLanguages) { Text($0.name).tag($0.id) }
            }.fixedSize().disabled(operation.busy)
            Text("Choose the language spoken in the recording. You can add translations after reviewing the captions.")
                .font(.callout).foregroundStyle(.secondary)
            if operation.spokenLanguages.first(where: { $0.id == operation.spoken })?.installed == false {
                Label("macOS needs to download this speech language.", systemImage: "arrow.down.circle")
                    .font(.callout)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
    }

    @ViewBuilder private var review: some View {
        HStack {
            if operation.selected.contains(where: { operation.translations[$0] != nil }) {
                Picker("Review", selection: $operation.reviewLanguage) {
                    Text("Original · \(SubtitleLanguage.name(operation.spoken))").tag(String?.none)
                    ForEach(operation.selected.sorted(), id: \.self) { code in
                        if operation.translations[code] != nil { Text(SubtitleLanguage.name(code)).tag(Optional(code)) }
                    }
                }.disabled(operation.busy)
            } else {
                Text("\(operation.cues.count) captions").font(.headline)
            }
            Spacer()
            Button(operation.selected.isEmpty ? "Add Languages…" : "Languages…") { choosingLanguages = true }
                .disabled(operation.busy || !operation.hasText)
        }
        if operation.reviewLanguage == nil && !operation.translations.isEmpty {
            Text("Editing an original caption clears the translated drafts.").font(.caption).foregroundStyle(.secondary)
        }
        if !operation.pending.isEmpty && !operation.busy {
            Text("Awaiting translation: \(operation.pending.map(SubtitleLanguage.name).joined(separator: ", ")).")
                .font(.caption).foregroundStyle(.secondary)
        }
        if !operation.hasText {
            Text("Enter text for every original caption before translating or exporting.").font(.callout)
        }
        if let folder = operation.partialOutput {
            HStack {
                Text("Completed tracks saved.").font(.callout)
                ShowInFinderButton(url: folder)
            }
        }
        ForEach(operation.failures.keys.sorted(), id: \.self) { code in
            Text("\(SubtitleLanguage.name(code)): \(operation.failures[code] ?? "")")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let language = operation.firstEmptyTranslation {
            Text("Enter text for the empty caption in \(SubtitleLanguage.name(language)) before exporting.").font(.callout)
        }
        ForEach(operation.cues.indices, id: \.self) { index in
            let cue = operation.cues[index]
            let translated = operation.reviewLanguage.flatMap { operation.translations[$0]?[index] }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Button {
                        operation.player?.seek(to: CMTime(value: Int64(cue.start), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
                        operation.player?.play()
                    } label: {
                        Label(Subtitles.timestamp(cue.start), systemImage: "play.circle")
                    }.buttonStyle(.link).monospacedDigit().font(.caption)
                        .accessibilityLabel("Play caption \(index + 1) at \(Subtitles.timestamp(cue.start))")
                    if (translated ?? cue).needsShortening {
                        Label("May read too quickly", systemImage: "text.badge.minus").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let translated, let language = operation.reviewLanguage {
                    Text(cue.text).font(.callout).foregroundStyle(.secondary)
                    TextField("Translation", text: Binding(get: { operation.translations[language]?[index].text ?? translated.text },
                        set: { operation.translations[language]?[index].text = $0 }), axis: .vertical)
                        .textFieldStyle(.roundedBorder).disabled(operation.busy)
                        .accessibilityLabel("Translation for caption \(index + 1)")
                } else {
                    TextField("Caption", text: Binding(get: { operation.cues[index].text },
                        set: { operation.updateSource(at: index, to: $0) }), axis: .vertical)
                        .textFieldStyle(.roundedBorder).disabled(operation.busy)
                        .accessibilityLabel("Original caption \(index + 1)")
                }
            }.padding(.vertical, 3)
            Divider()
        }
    }

    @ViewBuilder private var primaryActions: some View {
        if operation.media == nil {
            ReviewDefaultButton(title: "Choose Media…", action: operation.chooseAnotherFile)
        } else if operation.cues.isEmpty {
            let installed = operation.spokenLanguages.first(where: { $0.id == operation.spoken })?.installed == true
            ReviewDefaultButton(title: installed ? "Generate Captions" : "Download & Generate", action: operation.generate)
        } else if !operation.pending.isEmpty && (operation.exportCount == 0 || (operation.failures.isEmpty && operation.task.notice == nil)) {
            let title = operation.failures.isEmpty && operation.task.notice == nil ? "Translate" : "Retry Translation"
            ReviewDefaultButton(title: title, action: operation.startTranslations).disabled(!operation.hasText)
        } else {
            if !operation.pending.isEmpty {
                Button("Retry Translation", action: operation.startTranslations).modifier(DialogActionStyle()).disabled(!operation.hasText)
            }
            ReviewDefaultButton(title: operation.exportCount > 1 ? "Export \(operation.exportCount) SRTs…" : "Export SRT…",
                                action: operation.export)
                .disabled(!operation.canExport)
        }
    }
}

private struct SubtitleLanguageSheet: View {
    @Bindable var operation: SubtitleOperation
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [SubtitleLanguage]?
    @State private var selection: Set<String>
    @State private var original: Bool
    @State private var search = ""

    init(operation: SubtitleOperation) {
        self.operation = operation
        _selection = State(initialValue: operation.selected)
        _original = State(initialValue: operation.includeOriginal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtitle languages").font(.title2.bold())
            Toggle("Include original · \(SubtitleLanguage.name(operation.spoken))", isOn: $original)
            Divider()
            TextField("Find a translation language", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let choices {
                        let filtered = choices.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
                        if filtered.isEmpty {
                            Text(choices.isEmpty ? "macOS has no translations for this spoken language." : "No matching languages.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(filtered) { choice in
                            HStack {
                                Toggle(choice.name, isOn: Binding(get: { selection.contains(choice.id) }, set: { enabled in
                                    if enabled { selection.insert(choice.id) } else { selection.remove(choice.id) }
                                }))
                                Spacer()
                                if !choice.installed { Text("Download needed").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    } else { ProgressView("Finding languages…") }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            DialogFooter {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                ReviewDefaultButton(title: selection.subtracting(operation.translations.keys).isEmpty ? "Apply" : "Translate") {
                    dismiss()
                    operation.chooseLanguages(selection, includeOriginal: original)
                }.disabled(!original && selection.isEmpty)
            }
        }.padding(20).frame(width: 390, height: 410)
            .task { choices = await SubtitleLanguage.translations(from: operation.spoken) }
    }
}
