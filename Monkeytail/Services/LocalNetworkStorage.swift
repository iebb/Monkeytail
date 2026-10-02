import Foundation
import Observation
import MonkeytailCore

@MainActor @Observable final class LocalNetworkStorage {
    private let vault: SecretVault
    private var values: [String: String]
    private(set) var issue: String?
    private(set) var jars: [String: CookieJar] = [:]
    struct IdentityRecord: Codable, Identifiable {
        var host: String, port: Int, filename: String, data: Data, password: String
        var id: String { host.lowercased() + ":" + String(port) }
    }
    private(set) var identities: [IdentityRecord] = []
    init(directory: URL) {
        vault = SecretVault(directory: directory.appendingPathComponent("network-secrets")); values = [:]
        do {
            values = try vault.load()
            if let raw = values["jars"] { jars = try JSONDecoder().decode([String: CookieJar].self, from: Data(raw.utf8)) }
            if let raw = values["identities"] { identities = try JSONDecoder().decode([IdentityRecord].self, from: Data(raw.utf8)) }
        } catch { issue = error.localizedDescription }
    }
    func jar(_ id: UUID?) -> CookieJar { jars[id?.uuidString ?? "default"] ?? CookieJar() }
    func setJar(_ jar: CookieJar, environment: UUID?) throws { try requireAvailable(); jars[environment?.uuidString ?? "default"] = jar; try save() }
    func addIdentity(_ record: IdentityRecord) throws {
        try requireAvailable()
        guard (1...65535).contains(record.port), !record.host.contains("/"), !record.host.contains("*"), !record.host.isEmpty else { throw ClientError("Enter an exact hostname and a port from 1 to 65535.") }
        _ = try TLSConfiguration.importPKCS12(record.data, password: record.password, host: record.host, port: record.port)
        identities.removeAll { $0.id == record.id }; identities.append(record); try save()
    }
    func removeIdentity(_ id: String) throws { try requireAvailable(); identities.removeAll { $0.id == id }; try save() }
    func identity(for url: URL?) throws -> TLSConfiguration? {
        guard let url, url.scheme == "https", let host = url.host?.lowercased(), let record = identities.first(where: { $0.host.lowercased() == host && $0.port == (url.port ?? 443) }) else { return nil }
        return try TLSConfiguration.importPKCS12(record.data, password: record.password, host: record.host, port: record.port)
    }
    private func requireAvailable() throws { if let issue { throw ClientError(issue) } }
    private func save() throws {
        try requireAvailable()
        values["jars"] = String(decoding: try JSONEncoder().encode(jars), as: UTF8.self)
        values["identities"] = String(decoding: try JSONEncoder().encode(identities), as: UTF8.self)
        try vault.save(values)
    }
}
