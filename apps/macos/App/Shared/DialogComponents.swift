import SwiftUI
import AppKit

/// Compact shared chrome. Glass belongs to actions; text stays on readable surfaces.
struct DialogHeading: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.blue.gradient, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 19, weight: .semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct DialogCard: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(contrast == .increased ? 0.35 : 0.08)))
    }
}

/// Every custom operation window and editing sheet uses the same logical button order.
struct DialogFooter<Dismissal: View, Actions: View>: View {
    @ViewBuilder var dismissal: Dismissal
    @ViewBuilder var actions: Actions

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                dismissal
                Spacer(minLength: 8)
                actions
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DialogDoneButton: View {
    let action: () -> Void
    var body: some View {
        Button("Done", action: action)
            .keyboardShortcut(.defaultAction)
            .modifier(DialogActionStyle(prominent: true))
            .background(DialogKeyEquivalent(key: "\u{1b}", modifiers: [], action: action))
            .onExitCommand(perform: action)
    }
}

/// File-based reviews also accept the Command-Return shortcut used by the text editors.
struct ReviewDefaultButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .keyboardShortcut(.defaultAction)
            .modifier(DialogActionStyle(prominent: true))
            .background(DialogKeyEquivalent(key: "\r", modifiers: .command, action: action))
    }
}

/// SwiftUI gives a button one keyboard equivalent. Route its alternate through the
/// same window without adding a second visible or accessible control.
private struct DialogKeyEquivalent: NSViewRepresentable {
    let key: String
    let modifiers: NSEvent.ModifierFlags
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    final class KeyView: NSView {
        var handle: ((NSEvent) -> Bool)?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard !isHiddenOrHasHiddenAncestor, let window, window.isKeyWindow,
                  window.attachedSheet == nil else { return false }
            return handle?(event) ?? false
        }
    }

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.setAccessibilityElement(false)
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) {
        let enabled = enabled
        view.handle = { event in
            guard enabled, event.charactersIgnoringModifiers == key,
                  event.modifierFlags.intersection([.command, .shift, .option, .control]) == modifiers else { return false }
            action()
            return true
        }
    }
}

/// Cancel a preview in place. Once idle, the same control can close the review.
struct ReviewDismissButton: View {
    let busy: Bool
    var saving = false
    let cancel: () -> Void
    let close: () -> Void

    func perform() {
        guard !saving else { return }
        if busy { cancel() } else { close() }
    }

    var body: some View {
        Button(busy ? "Cancel" : "Close", action: perform)
            .keyboardShortcut(.cancelAction)
            .modifier(DialogActionStyle())
            .disabled(saving)
    }
}

struct ShowInFinderButton: View {
    let url: URL

    var body: some View {
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            .buttonStyle(.link)
            .foregroundStyle(.tint)
            .accessibilityLabel("Show \(url.lastPathComponent) in Finder")
    }
}

struct RowActionsMenu<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: "ellipsis").frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text(title))
        .help(title)
    }
}

struct DialogActionStyle: ViewModifier {
    var prominent = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        Group {
            if reduceTransparency || contrast == .increased {
                if prominent { content.buttonStyle(.borderedProminent) }
                else { content.buttonStyle(.bordered) }
            } else {
                if prominent { content.buttonStyle(.glassProminent) }
                else { content.buttonStyle(.glass) }
            }
        }.controlSize(.large).buttonBorderShape(.capsule)
    }
}

/// Keep status adjacent to the action, even when the editable content scrolls.
struct OperationFeedback: View {
    var activity: String? = nil
    var stopping = false
    var cancellation: String? = nil
    var error: String? = nil
    var body: some View {
        if let activity {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(stopping ? "Stopping…" : activity)
            }.font(.callout).accessibilityElement(children: .combine)
        }
        if let cancellation {
            Label(cancellation, systemImage: "stop.circle").font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let error {
            ScrollView {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 76).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DestinationRow: View {
    let folder: URL
    var change: (() -> Void)? = nil
    private var path: String { (folder.path as NSString).abbreviatingWithTildeInPath }
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").accessibilityHidden(true)
            Text(path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                .accessibilityLabel("Destination folder").accessibilityValue(folder.path)
            Spacer(minLength: 0)
            if let change {
                Button("Change…", action: change).buttonStyle(.link)
                    .accessibilityLabel("Change destination folder")
            }
        }.font(.caption).foregroundStyle(.secondary).help(folder.path)
    }
}
