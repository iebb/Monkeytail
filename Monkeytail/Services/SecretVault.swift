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
    init(directory: URL) { account = SHA256.hash(data: Data(directory.path.utf8)).map { String(format: "%02x", $0) }.joined() }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "co.kitta.monkeytail.local-secrets", kSecAttrAccount as String: account] }
    func load() throws -> [String: String] {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else { throw ClientError("Local credentials are unavailable while the device is locked.") }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    func save(_ secrets: [String: String]) throws {
        let data = try JSONEncoder().encode(secrets)
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
}
