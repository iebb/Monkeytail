import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

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
                        TextField("Folder name", text: Binding(get: { store.workspace.collections[c].folders![f].name }, set: { store.workspace.collections[c].folders![f].name = $0 })).fieldStyle()
                        Picker("Parent", selection: Binding<UUID?>(get: { store.workspace.collections[c].folders![f].parentID }, set: { store.workspace.collections[c].folders![f].parentID = $0 })) {
                            Text("Collection root").tag(UUID?.none)
                            ForEach(parents) { folder in Text(folder.name).tag(Optional(folder.id)) }
                        }.pickerStyle(.menu)
                    }
                    Text("Headers").font(.headline); FieldEditor(fields: defaults.headers)
                    Text("Variables").font(.headline); FieldEditor(fields: defaults.variables, name: "Variable")
                    AuthEditor(auth: defaults.auth, proxy: store.workspace.proxy, allowInheritance: folderID != nil)
                    Toggle("Run inherited scripts", isOn: defaults.scriptsEnabled)
                    if let c, folderID == nil, store.workspace.collections[c].requests.contains(where: { !$0.scriptsEnabled && !($0.preScript.isEmpty && $0.postScript.isEmpty) }) || (store.workspace.collections[c].folders ?? []).contains(where: { !$0.defaults.scriptsEnabled && !($0.defaults.preScript.isEmpty && $0.defaults.postScript.isEmpty) }) {
                        Button("Run scripts in every request and folder") {
                            for r in store.workspace.collections[c].requests.indices { store.workspace.collections[c].requests[r].scriptsEnabled = true }
                            for f in (store.workspace.collections[c].folders ?? []).indices { store.workspace.collections[c].folders![f].defaults.scriptsEnabled = true }
                            store.workspace.collections[c].defaults = defaults.wrappedValue; store.workspace.collections[c].defaults?.scriptsEnabled = true
                        }.font(.subheadline)
                    }
                    CodeEditor(text: defaults.preScript, label: "Before child requests", minimumHeight: 150)
                    CodeEditor(text: defaults.postScript, label: "After child responses", minimumHeight: 150)
                    Text("Documentation").font(.headline); DocsEditor(text: defaults.description)
                }.padding(12)
            }.background(Palette.canvas).sheetTitle(folderID == nil ? "Collection settings" : "Folder settings")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.frame(idealWidth: 650, idealHeight: 650).macSheetFrame(minWidth: 560, minHeight: 450)
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
