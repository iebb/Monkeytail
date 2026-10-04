import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct FolderRows: View {
    let store: WorkspaceStore
    let collectionID: UUID
    var parentID: UUID? = nil
    var visited: Set<UUID> = []
    var edit: (UUID?) -> Void
    var add: (UUID?) -> Void
    private var collection: RequestCollection? { store.workspace.collections.first { $0.id == collectionID } }
    var body: some View {
        ForEach((collection?.folders ?? []).filter { $0.parentID == parentID && !visited.contains($0.id) }) { folder in
            DisclosureGroup {
                AnyView(FolderRows(store: store, collectionID: collectionID, parentID: folder.id, visited: visited.union([folder.id]), edit: edit, add: add))
                ForEach((collection?.requests ?? []).filter { $0.folderID == folder.id }) { request in RequestSidebarRow(store: store, request: request, collectionID: collectionID) }
            } label: {
                HStack {
                    Label(folder.name, systemImage: "folder").font(.subheadline)
                    Spacer()
                    Menu {
                        Button("Add request") { store.addRequest(to: collectionID); if let id = store.selectedRequestID, var request = store.request(id) { request.folderID = folder.id; request.auth.kind = .inherit; store.update(request) } }
                        Button("New subfolder") { add(folder.id) }
                        Button("Folder settings") { edit(folder.id) }
                        Button("Delete folder", role: .destructive) { delete(folder.id) }
                    } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }.buttonStyle(.plain)
                }
            }
        }
    }
    private func delete(_ id: UUID) {
        guard let c = store.workspace.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        // Move contained requests and subfolders up; deleting a folder never loses requests.
        let parent = store.workspace.collections[c].folders?.first(where: { $0.id == id })?.parentID
        for r in store.workspace.collections[c].requests.indices where store.workspace.collections[c].requests[r].folderID == id { store.workspace.collections[c].requests[r].folderID = parent }
        if store.workspace.collections[c].folders != nil { for f in store.workspace.collections[c].folders!.indices where store.workspace.collections[c].folders![f].parentID == id { store.workspace.collections[c].folders![f].parentID = parent } }
        store.workspace.collections[c].folders?.removeAll { $0.id == id }
    }
}
struct RequestSidebarRow: View {
    let store: WorkspaceStore
    let request: APIRequest
    let collectionID: UUID
    var body: some View {
        Button { store.selectedRequestID = request.id } label: {
            HStack(spacing: 10) {
                Text(request.transport == .websocket ? "WS" : request.transport == .sse ? "SSE" : request.method).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(Palette.method(request.method)).frame(width: 39, alignment: .leading)
                Text(request.name).font(.subheadline).lineLimit(2); Spacer(minLength: 0)
                if request.favorite == true { Image(systemName: "star.fill").font(.caption).foregroundStyle(Palette.mint) }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).tag(request.id).listRowBackground(store.selectedRequestID == request.id ? Palette.mint.opacity(0.1) : Color.clear)
            .contextMenu {
                Button(request.favorite == true ? "Unfavourite" : "Favourite", systemImage: request.favorite == true ? "star.slash" : "star") { var value = request; value.favorite = request.favorite != true; store.update(value) }
                Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(request) }
                Menu("Move to folder") {
                    Button("Collection root") { var value = request; value.folderID = nil; store.update(value) }
                    ForEach(store.workspace.collections.first { $0.id == collectionID }?.folders ?? []) { folder in Button(folder.name) { var value = request; value.folderID = folder.id; store.update(value) } }
                }
                Button("Delete request", systemImage: "trash", role: .destructive) { store.delete(request.id) }
            }
    }
}
struct FolderSettingsView: View {
    @Bindable var store: WorkspaceStore
    let collectionID: UUID
    let folderID: UUID?
    @Environment(\.dismiss) private var dismiss
    private var c: Int? { store.workspace.collections.firstIndex { $0.id == collectionID } }
    private var f: Int? { c.flatMap { store.workspace.collections[$0].folders?.firstIndex { $0.id == folderID } } }
    private var defaults: Binding<RequestDefaults> {
        Binding(get: {
            guard let c else { return RequestDefaults() }
            if let f { return store.workspace.collections[c].folders![f].defaults }
            return store.workspace.collections[c].defaults ?? RequestDefaults()
        }, set: { value in
            guard let c else { return }
            if let f { store.workspace.collections[c].folders![f].defaults = value }
            else { store.workspace.collections[c].defaults = value }
        })
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let c, let f {
                        TextField("Folder name", text: Binding(get: { store.workspace.collections[c].folders![f].name }, set: { store.workspace.collections[c].folders![f].name = $0 })).textFieldStyle(.roundedBorder)
                        Picker("Parent", selection: Binding<UUID?>(get: { store.workspace.collections[c].folders![f].parentID }, set: { store.workspace.collections[c].folders![f].parentID = $0 })) {
                            Text("Collection root").tag(UUID?.none)
                            ForEach(parents) { folder in Text(folder.name).tag(Optional(folder.id)) }
                        }.pickerStyle(.menu)
                    }
                    Text("Headers").font(.headline); FieldEditor(fields: defaults.headers)
                    Text("Variables").font(.headline); FieldEditor(fields: defaults.variables, name: "Variable")
                    AuthEditor(auth: defaults.auth, proxy: store.workspace.proxy, allowInheritance: folderID != nil)
                    Toggle("Run inherited scripts", isOn: defaults.scriptsEnabled)
                    CodeEditor(text: defaults.preScript, label: "Before child requests", minimumHeight: 150)
                    CodeEditor(text: defaults.postScript, label: "After child responses", minimumHeight: 150)
                }.padding(12)
            }.background(Palette.canvas).navigationTitle(folderID == nil ? "Collection settings" : "Folder settings").inlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.frame(idealWidth: 650, idealHeight: 650)
    }
    private var parents: [RequestFolder] {
        guard let c else { return [] }
        let folders = store.workspace.collections[c].folders ?? []
        return folders.filter { candidate in
            var current: UUID? = candidate.id, seen = Set<UUID>()
            while let id = current { guard seen.insert(id).inserted, id != folderID else { return false }; current = folders.first { $0.id == id }?.parentID }
            return true
        }
    }
}
