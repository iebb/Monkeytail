#if os(iOS)
import Foundation
import Observation
import WatchConnectivity
import MonkeytailCore
import MonkeytailCompanion

@MainActor @Observable final class WatchCompanionLink: NSObject, WCSessionDelegate {
    static let shared = WatchCompanionLink()
    private(set) var requests: [WatchRequest] = []
    var issue: String?
    private var unavailable = false
    private let vault = WatchVault()
    override init() {
        super.init()
        do { requests = try vault.load() ?? [] } catch { issue = error.localizedDescription; unavailable = true }
        if WCSession.isSupported(), !ProcessInfo.processInfo.arguments.contains("--ui-testing") { WCSession.default.delegate = self; WCSession.default.activate() }
    }
    static func prepare(_ request: APIRequest, variables: [String: String], proxy: ProxySettings, includePrivateData: Bool, secretVariableNames: Set<String> = []) throws -> WatchRequest {
        guard proxy.kind == .system, request.impersonation == nil, request.cookieJarEnabled != true, request.mock?.enabled != true,
              request.transport != .websocket, request.transport != .sse, ![.oauth1, .oauth2, .jwt, .aws, .digest].contains(request.auth.kind),
              !request.scriptsEnabled || (request.preScript.isEmpty && request.postScript.isEmpty) else {
            throw ClientError("Watch supports System HTTP and GraphQL requests. Use iPhone for proxies, browser profiles, cookies, OAuth/AWS/Digest, scripts, or mocks.")
        }
        var built = try RequestBuilder.build(request, variables: variables)
        var privateHeaders = try request.headers.filter { $0.isCredential || SecretPolicy.isSensitive($0.name) }.map { try RequestBuilder.resolve($0.name, variables: variables) }
        if let key = request.auth.apiKey, !key.inQuery { privateHeaders.append(key.name) }
        if !includePrivateData {
            let secretNames = secretVariableNames.union(variables.keys.filter(SecretPolicy.isSensitive)).union((request.variables ?? []).filter(\.isCredential).map(\.name))
            let secrets = try (secretNames.compactMap { variables[$0] } + [request.auth.token, request.auth.password, request.auth.apiKey?.value ?? ""]).map { try RequestBuilder.resolve($0, variables: variables) }.filter { !$0.isEmpty }
            func containsSecret(_ text: String) -> Bool { secrets.contains { text.contains($0) } }
            built.httpBody = nil
            for (name, value) in built.allHTTPHeaderFields ?? [:] where SecretPolicy.isSensitive(name) || containsSecret(name) || containsSecret(value) || privateHeaders.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) || ["content-length", "content-encoding", "transfer-encoding"].contains(name.lowercased()) { built.setValue(nil, forHTTPHeaderField: name) }
            if var url = URLComponents(url: built.url!, resolvingAgainstBaseURL: false) {
                url.user = nil; url.password = nil
                guard !containsSecret(url.host ?? ""), !containsSecret(url.path) else { throw ClientError("The URL contains a private value. Enable credentials to copy it to Watch.") }
                url.fragment = nil
                let marked = try request.query.filter(\.isCredential).map { try RequestBuilder.resolve($0.name, variables: variables) }
                url.queryItems = url.queryItems?.filter { !SecretPolicy.isSensitive($0.name) && !containsSecret($0.name) && !containsSecret($0.value ?? "") && !marked.contains($0.name) && !(request.auth.kind == .apiKey && request.auth.apiKey?.inQuery == true && $0.name == request.auth.apiKey?.name) }
                built.url = url.url
            }
        }
        let model = WatchRequest(id: request.id, name: request.name, request: built, followRedirects: request.followRedirects, sensitiveHeaders: privateHeaders)
        _ = try model.request()
        return model
    }
    func setUseKeychain(_ enabled: Bool) throws { try vault.setUseKeychain(enabled); requests = try vault.load() ?? [] }
    func add(_ request: WatchRequest) throws {
        guard !unavailable else { throw WatchError(issue ?? "Watch storage is unavailable.") }
        var next = requests.filter { $0.id != request.id }; next.append(request)
        _ = try WatchPayload.encode(next); try vault.save(next); requests = next; try transfer()
    }
    func remove(_ id: UUID) throws {
        guard !unavailable else { throw WatchError(issue ?? "Watch storage is unavailable.") }
        let next = requests.filter { $0.id != id }; try vault.save(next); requests = next; try transfer()
    }
    func transfer(favoriteIDs: Set<UUID>? = nil) throws {
        if let favoriteIDs {
            guard !unavailable else { throw WatchError(issue ?? "Watch storage is unavailable.") }
            let next = requests.filter { favoriteIDs.contains($0.id) }
            try vault.save(next); requests = next
        }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { throw WatchError("Saved on iPhone. Install Monkeytail on your paired Watch, then tap Sync.") }
        try WCSession.default.updateApplicationContext(["version": 1, "requests": WatchPayload.encode(requests), "useKeychain": vault.useKeychain])
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in if let error { self.issue = error.localizedDescription } else { try? self.transfer() } }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
#endif
