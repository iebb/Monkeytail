import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

/// Sheets and prompts the tree asks its host to show.
struct SidebarTreeActions {
    var newFolder: (_ collection: UUID, _ parent: UUID?) -> Void
    var settings: (_ collection: UUID, _ folder: UUID?) -> Void
    var run: (_ collection: UUID, _ folder: UUID?) -> Void
    var rename: (RequestCollection) -> Void
    var delete: (RequestCollection) -> Void
    var newCollection: () -> Void
    var opened: () -> Void
}

/// Postman-style tree: the workspace's collections, nested folders and requests, with indent guides.
struct SidebarTree: View {
    @Bindable var store: WorkspaceStore
    var search: String
    var actions: SidebarTreeActions
    @State private var expanded: Set<UUID> = Self.loadExpanded()
    @State private var target: UUID?

    private enum Row: Identifiable {
        case collection(RequestCollection)
        case folder(RequestFolder, collection: UUID, depth: Int)
        case request(APIRequest, collection: UUID, depth: Int)
        var id: UUID {
            switch self { case .collection(let c): c.id; case .folder(let f, _, _): f.id; case .request(let r, _, _): r.id }
        }
    }

    var body: some View {
        List(selection: $store.selectedRequestID) {
            ForEach(rows) { row in
                rowView(row)
                    .listRowInsets(EdgeInsets(top: 0, leading: SidebarMetrics.treeInset, bottom: 0, trailing: 4))
                    .listRowSeparator(.hidden)
            }
            if store.collections.isEmpty {
                note("No collections yet", action: "New collection", perform: actions.newCollection)
            } else if rows.isEmpty {
                note("No matching requests")
            }
        }
            #if os(macOS)
            .listStyle(.sidebar).focusEffectDisabled()
            #else
            .listStyle(.plain)
            #endif
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, SidebarMetrics.treeRowHeight)
            .onAppear { reveal(store.selectedRequestID) }
            .onChange(of: store.selectedRequestID) { _, id in reveal(id) }
            .onChange(of: expanded) { _, value in UserDefaults.standard.set(value.map(\.uuidString), forKey: "sidebarExpanded") }
    }

    // MARK: Rows

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var rows: [Row] {
        var result: [Row] = []
        for collection in store.collections {
            let folders = collection.folders ?? [], ids = Set(folders.map(\.id))
            func parent(of request: APIRequest) -> UUID? { request.folderID.flatMap { ids.contains($0) ? $0 : nil } }
            var visibleFolders: Set<UUID>?, visibleRequests: Set<UUID>?
            if !query.isEmpty {
                let collectionMatches = collection.name.localizedCaseInsensitiveContains(query)
                var requests = Set(collection.requests.filter(matches).map(\.id))
                var shown = Set<UUID>()
                for folder in folders where folder.name.localizedCaseInsensitiveContains(query) {
                    let subtree = collection.folderSubtree(folder.id)
                    shown.formUnion(subtree); requests.formUnion(collection.requests.filter { parent(of: $0).map(subtree.contains) == true }.map(\.id))
                }
                for request in collection.requests where requests.contains(request.id) { shown.formUnion(ancestors(of: parent(of: request), in: folders)) }
                for folder in shown { shown.formUnion(ancestors(of: folders.first { $0.id == folder }?.parentID, in: folders)) }
                if collectionMatches { requests.formUnion(collection.requests.map(\.id)); shown.formUnion(ids) }
                guard !requests.isEmpty || !shown.isEmpty else { continue }
                visibleFolders = shown; visibleRequests = requests
            }
            result.append(.collection(collection))
            guard visibleFolders != nil || expanded.contains(collection.id) else { continue }
            func children(of parentID: UUID?, depth: Int, seen: Set<UUID>) {
                for folder in folders where folder.parentID.flatMap({ ids.contains($0) ? $0 : nil }) == parentID && !seen.contains(folder.id) && visibleFolders.map({ $0.contains(folder.id) }) != false {
                    result.append(.folder(folder, collection: collection.id, depth: depth))
                    if visibleFolders != nil || expanded.contains(folder.id) { children(of: folder.id, depth: depth + 1, seen: seen.union([folder.id])) }
                }
                for request in collection.requests where parent(of: request) == parentID && visibleRequests.map({ $0.contains(request.id) }) != false {
                    result.append(.request(request, collection: collection.id, depth: depth))
                }
            }
            children(of: nil, depth: 1, seen: [])
        }
        return result
    }

    private func matches(_ request: APIRequest) -> Bool {
        request.name.localizedCaseInsensitiveContains(query) || request.url.localizedCaseInsensitiveContains(query)
    }

    private func ancestors(of id: UUID?, in folders: [RequestFolder]) -> Set<UUID> {
        var result = Set<UUID>(), current = id
        while let id = current, result.insert(id).inserted { current = folders.first { $0.id == id }?.parentID }
        return result
    }

    /// Expands the collection and folders around a selected request so it's visible.
    private func reveal(_ id: UUID?) {
        guard let id, let collection = store.collections.first(where: { $0.requests.contains { $0.id == id } }) else { return }
        let folder = collection.requests.first { $0.id == id }?.folderID
        let needed = ancestors(of: folder, in: collection.folders ?? []).union([collection.id])
        if !needed.isSubset(of: expanded) { expanded.formUnion(needed) }
    }

    private static func loadExpanded() -> Set<UUID> {
        Set((UserDefaults.standard.stringArray(forKey: "sidebarExpanded") ?? []).compactMap(UUID.init(uuidString:)))
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    // MARK: Row views

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        switch row {
        case .collection(let collection):
            TreeRow(depth: 0, expanded: query.isEmpty ? expanded.contains(collection.id) : true, targeted: target == collection.id, toggle: { toggle(collection.id) }) {
                Text(collection.name).lineLimit(1)
            } menu: { collectionMenu(collection) }
                .accessibilityLabel(Text(verbatim: collection.name)).accessibilityIdentifier("Collection \(collection.name)")
                .dropDestination(for: String.self) { items, _ in store.drop(items, to: collection.id, folder: nil) } isTargeted: { highlight(collection.id, $0) }
        case .folder(let folder, let collectionID, let depth):
            TreeRow(depth: depth, expanded: query.isEmpty ? expanded.contains(folder.id) : true, targeted: target == folder.id, toggle: { toggle(folder.id) }) {
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(SidebarMetrics.nameFont).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(folder.name).lineLimit(1)
                }
            } menu: { folderMenu(folder, collection: collectionID) }
                .draggable(SidebarItem.folder(folder.id).payload) { Label(folder.name, systemImage: "folder").padding(6) }
                .dropDestination(for: String.self) { items, _ in
                    let moved = store.drop(items, to: collectionID, folder: folder.id)
                    if moved { expanded.insert(folder.id) }
                    return moved
                } isTargeted: { highlight(folder.id, $0) }
        case .request(let request, let collectionID, let depth):
            requestRow(request, collection: collectionID, depth: depth)
        }
    }

    private func highlight(_ id: UUID, _ on: Bool) {
        if on { target = id } else if target == id { target = nil }
    }

    private func requestRow(_ request: APIRequest, collection collectionID: UUID, depth: Int) -> some View {
        let selected = store.selectedRequestID == request.id
        return Button { store.selectedRequestID = request.id; actions.opened() } label: {
            HStack(spacing: 0) {
                IndentGuides(depth: depth)
                Text(SidebarMetrics.methodLabel(request))
                    .font(.app(size: SidebarMetrics.methodSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.method(request.method)).lineLimit(1).fixedSize()
                    .frame(width: SidebarMetrics.methodWidth, alignment: .trailing).padding(.trailing, 6)
                Text(request.name).font(SidebarMetrics.nameFont.weight(selected ? .medium : .regular)).lineLimit(1)
                Spacer(minLength: 4)
                if request.favorite == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.mint).accessibilityLabel("Favourite") }
            }.frame(minHeight: SidebarMetrics.treeRowHeight).contentShape(Rectangle())
                .background(target == request.id ? Palette.mint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain).tag(request.id)
            .accessibilityLabel(Text(verbatim: "\(request.method) \(request.name)"))
            #if !os(macOS)
            .listRowBackground(selected ? Palette.mint.opacity(0.1) : Color.clear)
            #endif
            .contextMenu { requestMenu(request, collection: collectionID) }
            .draggable(SidebarItem.request(request.id).payload) { Text(verbatim: "\(request.method) \(request.name)").padding(6) }
            .dropDestination(for: String.self) { items, _ in store.drop(items, to: collectionID, folder: request.folderID, before: request.id) } isTargeted: { highlight(request.id, $0) }
    }

    // MARK: Menus

    @ViewBuilder private func collectionMenu(_ collection: RequestCollection) -> some View {
        Button("Add request", systemImage: "plus") { store.addRequest(to: collection.id); expanded.insert(collection.id); actions.opened() }
        Button("New folder", systemImage: "folder.badge.plus") { expanded.insert(collection.id); actions.newFolder(collection.id, nil) }
        Divider()
        Button("Run collection", systemImage: "play.circle") { actions.run(collection.id, nil) }
        Button("Collection settings", systemImage: "slider.horizontal.3") { actions.settings(collection.id, nil) }
        Button("Rename", systemImage: "pencil") { actions.rename(collection) }
        if store.workspace.workspaceList.count > 1 {
            Menu("Move to workspace", systemImage: "square.stack.3d.up") {
                ForEach(store.workspace.workspaceList.filter { $0.id != store.activeWorkspaceID }) { space in
                    Button(store.name(of: space)) { store.moveCollection(collection.id, to: space.id) }
                }
            }
        }
        Divider()
        Button("Delete collection…", systemImage: "trash", role: .destructive) { actions.delete(collection) }
    }

    @ViewBuilder private func folderMenu(_ folder: RequestFolder, collection collectionID: UUID) -> some View {
        Button("Add request", systemImage: "plus") {
            store.addRequest(to: collectionID)
            if let id = store.selectedRequestID, var request = store.request(id) { request.folderID = folder.id; request.auth.kind = .inherit; store.update(request) }
            expanded.insert(folder.id); actions.opened()
        }
        Button("New subfolder", systemImage: "folder.badge.plus") { expanded.insert(folder.id); actions.newFolder(collectionID, folder.id) }
        MoveMenu(store: store, item: .folder(folder.id))
        Divider()
        Button("Run folder", systemImage: "play.circle") { actions.run(collectionID, folder.id) }
        Button("Folder settings", systemImage: "slider.horizontal.3") { actions.settings(collectionID, folder.id) }
        Divider()
        Button("Delete folder", systemImage: "trash", role: .destructive) { deleteFolder(folder.id, collection: collectionID) }
    }

    @ViewBuilder private func requestMenu(_ request: APIRequest, collection collectionID: UUID) -> some View {
        Button(request.favorite == true ? "Unfavourite" : "Favourite", systemImage: request.favorite == true ? "star.slash" : "star") { var value = request; value.favorite = request.favorite != true; store.update(value) }
        Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(request) }
        Button("New folder here", systemImage: "folder.badge.plus") { actions.newFolder(collectionID, request.folderID) }
        MoveMenu(store: store, item: .request(request.id))
        Divider()
        Button("Delete request", systemImage: "trash", role: .destructive) { store.delete(request.id); store.keepSelectionInWorkspace() }
    }

    /// Deleting a folder never loses requests: its contents move up a level.
    private func deleteFolder(_ id: UUID, collection collectionID: UUID) {
        guard let c = store.workspace.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        var collection = store.workspace.collections[c]
        let parent = collection.folders?.first { $0.id == id }?.parentID
        for r in collection.requests.indices where collection.requests[r].folderID == id { collection.requests[r].folderID = parent }
        for f in (collection.folders ?? []).indices where collection.folders![f].parentID == id { collection.folders![f].parentID = parent }
        collection.folders?.removeAll { $0.id == id }
        store.workspace.collections[c] = collection
    }

    private func note(_ message: LocalizedStringKey, action: LocalizedStringKey? = nil, perform: @escaping () -> Void = {}) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            if let action { Button(action, action: perform).buttonStyle(.plain).font(.subheadline).foregroundStyle(Palette.mint) }
        }.padding(.vertical, 8).padding(.horizontal, SidebarMetrics.treeInset).listRowBackground(Color.clear).listRowSeparator(.hidden).selectionDisabled()
    }
}

/// One collection or folder row: indent guides, a disclosure chevron, and actions on hover (Mac) or always (touch).
private struct TreeRow<Label: View, Actions: View>: View {
    let depth: Int
    let expanded: Bool
    let targeted: Bool
    let toggle: () -> Void
    @ViewBuilder let label: () -> Label
    @ViewBuilder let menu: () -> Actions
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 0) {
                    IndentGuides(depth: depth)
                    Image(systemName: "chevron.right").font(.app(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: SidebarMetrics.indent).accessibilityHidden(true)
                    label().font(SidebarMetrics.nameFont).foregroundStyle(.primary).padding(.leading, 2)
                    Spacer(minLength: 4)
                }.frame(minHeight: SidebarMetrics.treeRowHeight).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader).accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
            Menu { menu() } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary)
                    .frame(width: SidebarMetrics.actionWidth, height: SidebarMetrics.treeRowHeight).contentShape(Rectangle())
            }.borderlessMenu().buttonStyle(.plain).accessibilityLabel("Options")
                #if os(macOS)
                .opacity(hovering ? 1 : 0)
                #endif
        }
            .background(targeted ? Palette.mint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contextMenu { menu() }
            .onHover { hovering = $0 }
            .selectionDisabled()
    }
}

/// Vertical guide lines, one per nesting level, as in Postman.
private struct IndentGuides: View {
    let depth: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<max(0, depth), id: \.self) { _ in
                Rectangle().fill(Palette.border).frame(width: 1).frame(maxHeight: .infinity)
                    .frame(width: SidebarMetrics.indent)
            }
        }.accessibilityHidden(true)
    }
}

/// "Move to" with every collection in the workspace and its folder tree.
struct MoveMenu: View {
    let store: WorkspaceStore
    let item: SidebarItem
    var body: some View {
        Menu("Move to", systemImage: "arrow.turn.down.right") {
            ForEach(store.collections) { collection in
                Section {
                    destination(collection, folder: nil, title: Text("Collection root"))
                    ForEach(collection.folderTree) { entry in destination(collection, folder: entry.id, title: Text(verbatim: entry.path)) }
                } header: { Text(verbatim: collection.name) }
            }
        }
    }
    @ViewBuilder private func destination(_ collection: RequestCollection, folder: UUID?, title: Text) -> some View {
        let current = store.location(of: item).map { $0.collection == collection.id && $0.folder == folder } ?? false
        Button { store.move(item, to: collection.id, folder: folder) } label: {
            if current { SwiftUI.Label { title } icon: { Image(systemName: "checkmark") } } else { title }
        }.disabled(current || !store.canMove(item, to: collection.id, folder: folder))
    }
}
