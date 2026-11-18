#if DEBUG
import AppKit
import CloakToolsCore

/// Explicit development-only UI fixture. It cannot invoke NSWorkspace's default-setting API.
@MainActor final class DefaultHandlerPreview: DefaultHandlerSystem {
    private let workspace = WorkspaceDefaultHandlers()
    private var currentApps: [LinkScheme: HandlerApplication]
    private init(own: HandlerApplication) {
        currentApps = Dictionary(uniqueKeysWithValues: LinkScheme.allCases.map { ($0, own) })
    }
    func current(for scheme: LinkScheme) -> HandlerApplication? { currentApps[scheme] }
    func available(for scheme: LinkScheme) -> [HandlerApplication] { workspace.available(for: scheme) }
    func set(_ application: HandlerApplication, for scheme: LinkScheme) async throws {
        await Task.yield()
        currentApps[scheme] = application
    }
    static func coordinator(own: HandlerApplication) -> DefaultHandlerCoordinator {
        let system = DefaultHandlerPreview(own: own)
        let previous = HandlerApplication(bundleID: "com.example.unavailable-browser", name: "Previous Browser", url: URL(fileURLWithPath: "/Applications/CloakTools-Unavailable-Fixture.app"))
        let points = LinkScheme.allCases.map {
            HandlerRestorePoint(scheme: $0, previous: $0 == .http ? previous : system.workspace.current(for: $0), owner: own)
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsDefaultPreview-\(UUID()).json")
        let store = HandlerHistoryStore(url: temporary)
        do { try store.save(points) } catch { preconditionFailure("Could not create the explicit default-handler UI fixture.") }
        return .init(ownApplication: own, system: system, store: store)
    }
}
#endif
