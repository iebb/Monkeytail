import Foundation
import Observation
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

@MainActor @Observable final class LocalNetworkStorage {
    private var vault: SecretVault
    private var values: [String: String]
    private(set) var issue: String?
    private(set) var jars: [String: CookieJar] = [:]
    struct IdentityRecord: Codable, Identifiable {
        var host: String, port: Int, filename: String, data: Data, password: String
        var id: String { host.lowercased() + ":" + String(port) }
    }
    private(set) var identities: [IdentityRecord] = []
    /// Server certificates trusted for one host and port on this device only.
    private(set) var trustedCertificates: [TrustedCertificate] = []
    init(directory: URL, useKeychain: Bool = false) {
        vault = SecretVault(directory: directory.appendingPathComponent("network-secrets"), useKeychain: useKeychain); values = [:]
        do {
            values = try vault.load()
            if let raw = values["jars"] { jars = try JSONDecoder().decode([String: CookieJar].self, from: Data(raw.utf8)) }
            if let raw = values["identities"] { identities = try JSONDecoder().decode([IdentityRecord].self, from: Data(raw.utf8)) }
            if let raw = values["trusted"] { trustedCertificates = try JSONDecoder().decode([TrustedCertificate].self, from: Data(raw.utf8)) }
        } catch { issue = error.localizedDescription }
    }
    func setUseKeychain(_ enabled: Bool) throws {
        try requireAvailable()
        guard vault.useKeychain != enabled else { return }
        let previous = vault, target = SecretVault(directory: vault.directory, useKeychain: enabled)
        if enabled {
            let stored = try target.load()
            if let raw = stored["jars"], let old = try? JSONDecoder().decode([String: CookieJar].self, from: Data(raw.utf8)) { jars = old.merging(jars) { _, current in current } }
            if let raw = stored["identities"], let old = try? JSONDecoder().decode([IdentityRecord].self, from: Data(raw.utf8)) { identities = old.filter { item in !identities.contains { $0.id == item.id } } + identities }
            if let raw = stored["trusted"], let old = try? JSONDecoder().decode([TrustedCertificate].self, from: Data(raw.utf8)) { trustedCertificates = old.filter { item in !trustedCertificates.contains { $0.id == item.id } } + trustedCertificates }
            values["jars"] = String(decoding: try JSONEncoder().encode(jars), as: UTF8.self)
            values["identities"] = String(decoding: try JSONEncoder().encode(identities), as: UTF8.self)
            values["trusted"] = String(decoding: try JSONEncoder().encode(trustedCertificates), as: UTF8.self)
        }
        try target.save(values); vault = target
        try previous.remove()
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
    func trust(_ certificate: TrustedCertificate) throws { try requireAvailable(); trustedCertificates.removeAll { $0.id == certificate.id }; trustedCertificates.append(certificate); try save() }
    func removeTrust(_ id: String) throws { try requireAvailable(); trustedCertificates.removeAll { $0.id == id }; try save() }
    func identity(for url: URL?) throws -> TLSConfiguration? {
        guard let url, url.scheme == "https", let host = url.host?.lowercased(), let record = identities.first(where: { $0.host.lowercased() == host && $0.port == (url.port ?? 443) }) else { return nil }
        return try TLSConfiguration.importPKCS12(record.data, password: record.password, host: record.host, port: record.port)
    }
    private func requireAvailable() throws { if let issue { throw ClientError(issue) } }
    private func save() throws {
        try requireAvailable()
        values["jars"] = String(decoding: try JSONEncoder().encode(jars), as: UTF8.self)
        values["identities"] = String(decoding: try JSONEncoder().encode(identities), as: UTF8.self)
        values["trusted"] = String(decoding: try JSONEncoder().encode(trustedCertificates), as: UTF8.self)
        try vault.save(values)
    }
}
