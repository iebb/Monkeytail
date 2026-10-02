import Foundation
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

actor SnapshotStorage {
    private let directory: URL
    private let index: URL
    init(directory: URL) { self.directory = directory.appendingPathComponent("Snapshots", isDirectory: true); self.index = self.directory.appendingPathComponent("index.json") }
    func summaries() throws -> [SnapshotSummary] {
        guard FileManager.default.fileExists(atPath: index.path) else { return [] }
        return try JSONDecoder().decode([SnapshotSummary].self, from: Data(contentsOf: index))
    }
    func load(_ id: UUID) throws -> ResponseSnapshot { try JSONDecoder().decode(ResponseSnapshot.self, from: Data(contentsOf: location(id))) }
    func save(_ snapshot: ResponseSnapshot) throws -> [SnapshotSummary] {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: location(snapshot.id), options: [.atomic, .completeFileProtectionUnlessOpen])
        var items = try summaries()
        items.insert(SnapshotSummary(snapshot, bytes: data.count), at: 0)
        // Evict oldest snapshots until both disk limits are met. Always retain the newly saved item.
        while items.count > 50 || items.reduce(0, { $0 + $1.bytes }) > 60 * 1024 * 1024, items.count > 1 {
            let removed = items.removeLast(); try FileManager.default.removeItem(at: location(removed.id))
        }
        try persist(items)
        return items
    }
    func remove(_ id: UUID) throws -> [SnapshotSummary] {
        var items = try summaries(); items.removeAll { $0.id == id }
        if FileManager.default.fileExists(atPath: location(id).path) { try FileManager.default.removeItem(at: location(id)) }
        try persist(items); return items
    }
    private func location(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func persist(_ items: [SnapshotSummary]) throws { try JSONEncoder().encode(items).write(to: index, options: [.atomic, .completeFileProtectionUnlessOpen]) }
}
