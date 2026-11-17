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

/// A consistent, compact launch row; details wrap while its action remains visible.
struct ToolLauncherRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    var tint: Color = .blue
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open…", action: action).fixedSize().accessibilityLabel("Open \(title)").accessibilityHint(subtitle)
        }.padding(.vertical, 3)
    }
}

/// Explains a collapsed tool group without making users open it to discover its contents.
struct ToolGroupLabel: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 3)
    }
}
