import Foundation
import MonkeytailCore

/// One file per installation avoids concurrent file writes. Records merge independently across files.
actor ICloudWorkspace {
    static let container = "iCloud.co.kitta.monkeytail"
    private var accountIdentity: Data?
    init(accountIdentity: Data? = nil) { self.accountIdentity = accountIdentity }
    func identity() -> Data? { accountIdentity }
    private func verifyAccount() throws {

        guard let token = FileManager.default.ubiquityIdentityToken else { throw ClientError("iCloud Drive is unavailable. Enable it in iOS Settings; your workspace stays local.") }
        let identity = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
        if let previous = accountIdentity, let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(previous), !token.isEqual(decoded) {
            throw ClientError("Your iCloud session changed. Turn sync off and on to use this session.")
        }
        accountIdentity = identity
    }
    func read() throws -> [WorkspaceSyncState] {
        try verifyAccount()
        let directory = try location()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey, .fileSizeKey], options: [.skipsHiddenFiles]).filter { $0.pathExtension == "monkeytail-sync" }
        var result: [WorkspaceSyncState] = []
        for url in files {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            let status = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
            if status == .notDownloaded { continue }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20 * 1024 * 1024 else { throw ClientError("An iCloud workspace exceeds the 20 MB sync limit.") }
            let data = try coordinatedRead(url)
            guard data.count <= 20 * 1024 * 1024 else { throw ClientError("An iCloud workspace exceeds the 20 MB sync limit.") }
            result.append(try JSONDecoder().decode(WorkspaceSyncState.self, from: data))
        }
        return result
    }
    func write(_ state: WorkspaceSyncState) throws {
        try verifyAccount()
        let data = try JSONEncoder().encode(state)
        guard data.count <= 20 * 1024 * 1024 else { throw ClientError("Workspace exceeds the 20 MB sync limit. Upload files are kept local.") }
        let url = try location().appendingPathComponent(state.device.uuidString + ".monkeytail-sync")
        var coordinationError: NSError?, writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do { try data.write(to: target, options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError as NSError? { throw error }
    }
    private func location() throws -> URL {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: Self.container) else { throw ClientError("iCloud Drive is unavailable. Your workspace stays local.") }
        let directory = root.appendingPathComponent("Documents/Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    private func coordinatedRead(_ url: URL) throws -> Data {
        var coordinationError: NSError?, readError: Error?, data = Data()
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            do { data = try Data(contentsOf: target) } catch { readError = error }
        }
        if let error = coordinationError ?? readError as NSError? { throw error }
        return data
    }
}
