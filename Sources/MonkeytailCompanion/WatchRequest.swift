import Foundation
import Security

public struct WatchRequest: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    public var timeout: Double
    public var followRedirects: Bool
    public var sensitiveHeaders: [String]
    public init(id: UUID = UUID(), name: String, request: URLRequest, followRedirects: Bool = true, sensitiveHeaders: [String] = []) {
        self.id = id; self.name = name; url = request.url?.absoluteString ?? ""; method = request.httpMethod ?? "GET"
        headers = request.allHTTPHeaderFields ?? [:]; body = request.httpBody; timeout = min(request.timeoutInterval, 30)
        self.followRedirects = followRedirects; self.sensitiveHeaders = sensitiveHeaders
    }
    public func request() throws -> URLRequest {
        guard self.url.utf8.count <= 8192, sensitiveHeaders.count <= 100, sensitiveHeaders.allSatisfy({ $0.utf8.count <= 256 }) else { throw WatchError("Watch request is too large.") }
        guard let url = URL(string: url), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false, url.user == nil, url.password == nil else { throw WatchError("Enter an HTTP or HTTPS URL without embedded credentials.") }
        let token = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard !method.isEmpty, method.unicodeScalars.allSatisfy(token.contains), timeout.isFinite, (1...30).contains(timeout), (body?.count ?? 0) <= 32 * 1024, headers.count <= 100, name.utf8.count <= 256 else { throw WatchError("Invalid Watch request. Bodies are limited to 32 KB and timeout to 30 seconds.") }
        var result = URLRequest(url: url); result.httpMethod = method; result.httpBody = body; result.timeoutInterval = timeout
        for (key, value) in headers {
            guard !key.isEmpty, key.unicodeScalars.allSatisfy(token.contains), !value.unicodeScalars.contains(where: { $0.value == 13 || $0.value == 10 || $0.value == 0 }), key.utf8.count + value.utf8.count <= 8192 else { throw WatchError("Invalid header.") }
            result.setValue(value, forHTTPHeaderField: key)
        }
        return result
    }
    public static var sample: WatchRequest {
        WatchRequest(name: "Sample JSON", request: URLRequest(url: URL(string: "https://httpbin.org/json")!))
    }
}
public struct WatchError: LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public enum WatchPayload {
    public static let maximumBytes = 60 * 1024
    public static func encode(_ requests: [WatchRequest]) throws -> Data {
        guard requests.count <= 10, Set(requests.map(\.id)).count == requests.count else { throw WatchError("Save at most 10 requests on Watch.") }
        for request in requests { _ = try request.request() }
        let data = try JSONEncoder().encode(requests)
        guard data.count <= maximumBytes else { throw WatchError("Watch requests exceed 60 KB. Remove a request or reduce its body.") }
        return data
    }
    public static func decode(_ data: Data) throws -> [WatchRequest] {
        guard data.count <= maximumBytes else { throw WatchError("Watch transfer exceeds 60 KB.") }
        let value = try JSONDecoder().decode([WatchRequest].self, from: data)
        _ = try encode(value)
        return value
    }
}
/// Local request storage, with Keychain available as an opt-in.
public struct WatchVault {
    private let directory: URL
    private let defaults: UserDefaults
    private let customDirectory: Bool
    private let preference = "monkeytail.watch.useKeychain"
    public var useKeychain: Bool { defaults.bool(forKey: preference) }
    private var file: URL { directory.appendingPathComponent("watch-requests.json") }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "co.kitta.monkeytail.watch-requests", kSecAttrAccount as String: customDirectory ? directory.path : "saved", kSecAttrSynchronizable as String: false] }
    public init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("Monkeytail")
        self.defaults = defaults; self.customDirectory = directory != nil
    }
    public func load() throws -> [WatchRequest]? {
        if !useKeychain {
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return try WatchPayload.decode(Data(contentsOf: file))
        }
        if let data = try loadKeychain() {
            return try WatchPayload.decode(data)
        }
        if FileManager.default.fileExists(atPath: file.path) {
            let value = try WatchPayload.decode(Data(contentsOf: file))
            try save(value); try FileManager.default.removeItem(at: file); return value
        }
        return nil
    }
    private func loadKeychain() throws -> Data? {
        var query = query; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw WatchError("Unlock your device to load Watch requests.") }
        return data
    }
    public func save(_ value: [WatchRequest], useKeychain choice: Bool? = nil) throws {
        let data = try WatchPayload.encode(value), enabled = choice ?? useKeychain, previous = useKeychain
        if enabled {
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var create = query; create[kSecValueData as String] = data; create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(create as CFDictionary, nil)
            }
            guard status == errSecSuccess else { throw WatchError("Could not save Watch requests (\(status)).") }
        } else {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
        defaults.set(enabled, forKey: preference)
        if previous != enabled {
            if enabled, FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            else if !enabled { try removeKeychain() }
        }
    }
    public func setUseKeychain(_ enabled: Bool) throws {
        guard enabled != useKeychain else { return }
        var value = try load() ?? []
        if enabled, let data = try loadKeychain() {
            let ids = Set(value.map(\.id))
            value = try WatchPayload.decode(data).filter { !ids.contains($0.id) } + value
        }
        try save(value, useKeychain: enabled)
    }
    private func removeKeychain() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw WatchError("Could not remove previous Watch storage (\(status)).") }
    }
}
