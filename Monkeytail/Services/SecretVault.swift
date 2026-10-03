import Foundation
import Security
import CryptoKit
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct SecretVault {
    let account: String
    let directory: URL
    let useKeychain: Bool
    init(directory: URL, useKeychain: Bool = false) {
        self.directory = directory; self.useKeychain = useKeychain
        account = SHA256.hash(data: Data(directory.path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private var file: URL { directory.appendingPathComponent("credentials.json") }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "co.kitta.monkeytail.local-secrets", kSecAttrAccount as String: account] }
    func load() throws -> [String: String] {
        if !useKeychain {
            guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
            return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        }
        let value = try loadKeychain()
        if value.isEmpty, FileManager.default.fileExists(atPath: file.path) {
            let migrated = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
            if !migrated.isEmpty { try save(migrated) }
            try FileManager.default.removeItem(at: file); return migrated
        }
        return value
    }
    private func loadKeychain() throws -> [String: String] {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else { throw ClientError("Local credentials are unavailable while the device is locked.") }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    func save(_ secrets: [String: String]) throws {
        if useKeychain, secrets.values.allSatisfy(\.isEmpty) { try removeKeychain(); return }
        let data = try JSONEncoder().encode(secrets)
        if !useKeychain {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen]); return
        }
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var create = query; create[kSecValueData as String] = data
            create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            create[kSecAttrSynchronizable as String] = false
            status = SecItemAdd(create as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClientError("Could not save local credentials (\(status)).") }
    }
    func remove() throws {
        if useKeychain { try removeKeychain() }
        else if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    private func removeKeychain() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ClientError("Could not remove the previous credential storage (\(status)).") }
    }
}
