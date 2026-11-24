import AppKit
import CloakToolsCore
import SwiftUI
import UniformTypeIdentifiers

struct OptimizationDragHandle: View {
    let result: OptimizedMedia
    var body: some View {
        Image(systemName: "hand.draw")
            .frame(width: 24, height: 24).contentShape(Rectangle())
            .onDrag { Self.copyProvider(for: result) } preview: { Label(result.filename, systemImage: "doc") }
            .help("Drag the optimized copy to Finder or another app")
            .accessibilityLabel("Drag " + result.filename)
    }

    static func copyProvider(for result: OptimizedMedia) -> NSItemProvider {
        let provider = NSItemProvider()
        let type = UTType(filenameExtension: result.previewURL.pathExtension) ?? .data
        provider.suggestedName = result.filename
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            // Retain the preview lease with the provider. The receiver gets a copy of the measured file.
            completion(result.previewURL, false, nil)
            return nil
        }
        return provider
    }
}
