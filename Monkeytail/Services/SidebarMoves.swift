import Foundation
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

/// A request or folder being moved in the sidebar, by menu or drag and drop.
enum SidebarItem: Hashable {
    case request(UUID), folder(UUID)
    var payload: String {
        switch self {
        case .request(let id): "monkeytail-request:" + id.uuidString
        case .folder(let id): "monkeytail-folder:" + id.uuidString
        }
    }
    init?(payload: String) {
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "monkeytail-request": self = .request(id)
        case "monkeytail-folder": self = .folder(id)
        default: return nil
        }
    }
}

struct FolderEntry: Identifiable {
    let folder: RequestFolder
    let path: String
    var id: UUID { folder.id }
}

extension RequestCollection {
    /// Folders depth-first, each with its path from the collection root.
    var folderTree: [FolderEntry] {
        let folders = self.folders ?? []
        var result: [FolderEntry] = [], seen = Set<UUID>()
        func visit(_ parent: UUID?, prefix: String) {
            for folder in folders where folder.parentID == parent && seen.insert(folder.id).inserted {
                let path = prefix.isEmpty ? folder.name : prefix + " › " + folder.name
                result.append(FolderEntry(folder: folder, path: path))
                visit(folder.id, prefix: path)
            }
        }
        visit(nil, prefix: "")
        return result
    }
    /// A folder and every folder nested inside it.
    func folderSubtree(_ id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id], changed = true
        while changed {
            changed = false
            for folder in folders ?? [] where folder.parentID.map(result.contains) == true && result.insert(folder.id).inserted { changed = true }
        }
        return result
    }
}

extension WorkspaceStore {
    func location(of item: SidebarItem) -> (collection: UUID, folder: UUID?)? {
        switch item {
        case .request(let id):
            for collection in workspace.collections { if let request = collection.requests.first(where: { $0.id == id }) { return (collection.id, request.folderID) } }
        case .folder(let id):
            for collection in workspace.collections { if let folder = collection.folders?.first(where: { $0.id == id }) { return (collection.id, folder.parentID) } }
        }
        return nil
    }

    func canMove(_ item: SidebarItem, to collectionID: UUID, folder: UUID?) -> Bool {
        guard let current = location(of: item), current.collection != collectionID || current.folder != folder,
              let destination = workspace.collections.first(where: { $0.id == collectionID }),
              folder.map({ id in destination.folders?.contains { $0.id == id } == true }) ?? true else { return false }
        if case .folder(let id) = item, let folder, current.collection == collectionID { return !destination.folderSubtree(id).contains(folder) }
        return true
    }

    /// Moves a request or a folder with everything inside it. `before` places a request ahead of another request.
    func move(_ item: SidebarItem, to collectionID: UUID, folder: UUID?, before target: UUID? = nil) {
        var collections = workspace.collections
        guard let to = collections.firstIndex(where: { $0.id == collectionID }),
              folder.map({ id in collections[to].folders?.contains { $0.id == id } == true }) ?? true else { return }
        switch item {
        case .request(let id):
            guard id != target, let from = collections.firstIndex(where: { $0.requests.contains { $0.id == id } }),
                  var request = collections[from].requests.first(where: { $0.id == id }) else { return }
            collections[from].requests.removeAll { $0.id == id }
            request.folderID = folder
            let position = target.flatMap { target in collections[to].requests.firstIndex { $0.id == target } } ?? collections[to].requests.endIndex
            collections[to].requests.insert(request, at: position)
        case .folder(let id):
            guard let from = collections.firstIndex(where: { $0.folders?.contains { $0.id == id } == true }) else { return }
            let subtree = collections[from].folderSubtree(id)
            if from == to {
                guard folder.map({ !subtree.contains($0) }) ?? true, let index = collections[to].folders?.firstIndex(where: { $0.id == id }) else { return }
                collections[to].folders![index].parentID = folder
            } else {
                var folders = (collections[from].folders ?? []).filter { subtree.contains($0.id) }
                if let root = folders.firstIndex(where: { $0.id == id }) { folders[root].parentID = folder }
                let requests = collections[from].requests.filter { $0.folderID.map(subtree.contains) == true }
                collections[from].folders?.removeAll { subtree.contains($0.id) }
                collections[from].requests.removeAll { $0.folderID.map(subtree.contains) == true }
                collections[to].folders = (collections[to].folders ?? []) + folders
                collections[to].requests += requests
            }
        }
        workspace.collections = collections
    }

    /// Handles sidebar drops; returns whether anything moved.
    @discardableResult func drop(_ payloads: [String], to collectionID: UUID, folder: UUID?, before target: UUID? = nil) -> Bool {
        var moved = false
        for item in payloads.compactMap(SidebarItem.init(payload:)) {
            if case .request(let id) = item, id == target { continue }
            let reorders: Bool = if case .request = item { target != nil } else { false }
            guard reorders || canMove(item, to: collectionID, folder: folder) else { continue }
            move(item, to: collectionID, folder: folder, before: target); moved = true
        }
        return moved
    }

    func addFolder(named name: String, to collectionID: UUID, parent: UUID?) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = workspace.collections.firstIndex(where: { $0.id == collectionID }) else { return }
        workspace.collections[index].folders = (workspace.collections[index].folders ?? []) + [RequestFolder(name: name, parentID: parent)]
    }
}
