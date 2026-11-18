import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable final class FinderScopeSettings {
    let store = FinderScopeStore.authorized()
    var folders: [FinderFolder] = []
    var error: String?
    var unavailable = Set<UUID>()
    init() { reload() }
    func reload() {
        guard let store else { return }
        do {
            folders = try store.load(); error = nil; unavailable = []
            for folder in folders {
                do {
                    let url = try folder.resolve(), scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true { unavailable.insert(folder.id) }
                } catch { unavailable.insert(folder.id) }
            }
        } catch { self.error = error.localizedDescription }
    }
    func choose(replacing folder: FinderFolder? = nil) {
        guard let store else { return }
        let panel = NSOpenPanel(); panel.title = folder == nil ? "Add a Finder folder" : "Renew Finder folder access"
        panel.message = "CloakTools Finder menus will appear in this folder and its subfolders. Each file action still opens a review."
        panel.prompt = "Use Folder"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let selected = try FinderFolder.capture(url, id: folder?.id ?? UUID())
            var current = try store.load()
            if let index = current.firstIndex(where: { $0.id == selected.id }) { current[index] = selected } else { current.append(selected) }
            try store.save(current); changed()
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ folder: FinderFolder) {
        guard let store else { return }
        do { try store.save(store.load().filter { $0.id != folder.id }); changed() }
        catch { self.error = error.localizedDescription }
    }
    private func changed() {
        reload()
        DistributedNotificationCenter.default().postNotificationName(FinderScopeStore.changeNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

struct FinderFoldersSection: View {
    @Bindable var model: FinderScopeSettings
    @State private var removing: FinderFolder?
    var body: some View {
        Section {
            if model.store != nil {
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Reload Folders", action: model.reload)
                }
                ForEach(model.folders) { folder in
                    HStack(spacing: 10) {
                        Image(systemName: "folder").foregroundStyle(.blue).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(folder.name).lineLimit(1).help(folder.path)
                            Text(model.unavailable.contains(folder.id) ? "Choose again to renew access" : folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Menu {
                            Button("Choose Again…") { model.choose(replacing: folder) }
                            Button("Remove from Finder Menus…", role: .destructive) { removing = folder }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for Finder folder \(folder.name)")
                    }
                }
                Button("Add Folder…", systemImage: "folder.badge.plus") { model.choose() }.disabled(model.error != nil || model.folders.count >= 16)
                Text("Include up to 16 folders and their subfolders. Removing one changes menu scope; it never removes files.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Additional folders are available in builds signed for CloakTools’ shared app group. This development build uses the default workspace; Services work with selected items elsewhere.").font(.callout).foregroundStyle(.secondary)
            }
        } header: { Text("Additional Finder folders") }
        .confirmationDialog("Remove this folder from Finder menus?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let folder = removing { Button("Remove Folder", role: .destructive) { model.remove(folder); removing = nil } }
        } message: { Text("The folder and its files stay unchanged. Menus may remain if a parent folder is also included.") }
    }
}
