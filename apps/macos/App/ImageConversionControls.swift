import SwiftUI
import CloakToolsCore

struct ImageFormatPicker: View {
    var title = "Format"
    @Binding var selection: ImageOutputFormat
    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(ImageOutputFormat.allCases) { format in
                Text(format.title + (format.isAvailable ? "" : " — unavailable")).tag(format).disabled(!format.isAvailable)
            }
        }
    }
}

struct ImageQualitySlider: View {
    @Binding var quality: Double
    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $quality, in: 0.1...1, step: 0.05)
                .accessibilityLabel("Image quality").accessibilityValue("\(Int((quality * 100).rounded())) percent")
            Text("\(Int((quality * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
        }.help("Higher quality usually produces a larger file. This is not a target file size.")
    }
}

struct ConversionOptionsCard: View {
    @Bindable var operation: FileOperation
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case let .convert(url) = operation.intent {
                HStack(spacing: 12) {
                    if let thumbnail = operation.imageThumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit().frame(width: 48, height: 48).padding(4)
                            .background(operation.conversionOptions.format.isLossy ? (operation.conversionOptions.background == .white ? Color.white : .black) : Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 6))
                            .accessibilityLabel("Source image preview")
                    } else {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.secondary).frame(width: 56, height: 56).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(url.lastPathComponent).fontWeight(.medium).lineLimit(2)
                        if let image = operation.preparedImage {
                            Text("\(image.sourceFormat) · \(image.width) × \(image.height)").font(.caption).foregroundStyle(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(image.sourceByteCount), countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(operation.preparing ? "Preparing source preview…" : "Preview unavailable").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            if operation.output == nil {
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Format").foregroundStyle(.secondary)
                        ImageFormatPicker(selection: $operation.conversionOptions.format).labelsHidden()
                    }
                    if operation.conversionOptions.format.isLossy {
                        GridRow { Text("Quality").foregroundStyle(.secondary); ImageQualitySlider(quality: $operation.conversionOptions.quality) }
                        GridRow {
                            Text("Background").foregroundStyle(.secondary)
                            Picker("Transparent areas", selection: $operation.conversionOptions.background) {
                                ForEach(ImageBackground.allCases) { background in Text(background.title).tag(background) }
                            }.pickerStyle(.segmented).labelsHidden()
                        }
                    }
                }.disabled(operation.busy)
            }
        }.modifier(DialogCard())
    }
}
