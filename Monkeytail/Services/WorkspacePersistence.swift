import Foundation
import MonkeytailCore

/// Serializes large native workspaces away from the UI. A newer save supersedes queued work.
final class WorkspacePersistence: @unchecked Sendable {
    struct Snapshot: Sendable {
        var workspace: Workspace
        var history: [HistoryEntry]
        var sync: WorkspaceSyncState
        var settings: Data
        var secrets: [String: String]
        var directory: URL
    }
    private let queue = DispatchQueue(label: "co.kitta.monkeytail.persistence", qos: .utility)
    private let lock = NSLock()
    private var revision = 0
    private func reserve() -> Int { lock.lock(); defer { lock.unlock() }; revision += 1; return revision }
    private func current(_ value: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return revision == value }
    func enqueue(_ snapshot: Snapshot, completion: @escaping @Sendable (String?) -> Void) {
        let value = reserve()
        queue.async { [self] in
            guard current(value) else { return }
            do { try persist(snapshot, revision: value) }
            catch { if current(value) { completion(error.localizedDescription) } }
        }
    }
    func save(_ snapshot: Snapshot) throws { try persist(snapshot, revision: reserve()) }
    private func persist(_ snapshot: Snapshot, revision: Int) throws {
        let encoder = JSONEncoder()
        let files = [("history.json", try encoder.encode(snapshot.history)), ("workspace.json", try encoder.encode(snapshot.workspace)), ("sync-state.json", try encoder.encode(snapshot.sync)), ("settings.json", snapshot.settings)]
        lock.lock(); defer { lock.unlock() }
        guard revision == self.revision else { return }
        try SecretVault(directory: snapshot.directory).save(snapshot.secrets)
        try FileManager.default.createDirectory(at: snapshot.directory, withIntermediateDirectories: true)
        for (name, data) in files { try data.write(to: snapshot.directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUnlessOpen]) }
    }
}
