import CryptoKit
import Foundation
import os

public struct RemoteWorkspace: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var kind: String
    public init(id: String, name: String, kind: String = "") { self.id = id; self.name = name; self.kind = kind }
}

/// A GitHub repository, optionally narrowed to a branch and folder, parsed from `owner/repo` or a github.com URL.
public struct GitHubSource: Equatable, Sendable {
    public var owner: String
    public var repo: String
    public var ref: String?
    public var path: String
    public init?(_ text: String) {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www.", "github.com/"] where value.lowercased().hasPrefix(prefix) { value.removeFirst(prefix.count) }
        let parts = value.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        var repo = parts[1], ref: String?
        if let at = repo.firstIndex(of: "@") { ref = String(repo[repo.index(after: at)...]); repo = String(repo[..<at]) }
        if repo.lowercased().hasSuffix(".git") { repo.removeLast(4) }
        let valid = { (name: String) in !name.isEmpty && name.range(of: #"^[A-Za-z0-9_.\-]+$"#, options: .regularExpression) != nil }
        guard valid(parts[0]), valid(repo) else { return nil }
        owner = parts[0]; self.repo = repo; self.ref = ref; path = ""
        if parts.count >= 4, ["tree", "blob"].contains(parts[2]) { self.ref = parts[3]; path = parts.dropFirst(4).joined(separator: "/") }
        else if parts.count > 2 { return nil }
    }
}

/// A signed-in Insomnia desktop session: the session ID and the account's private key, which opens each project's key.
public struct InsomniaSession: Sendable {
    let id: String
    let privateKey: [String: String]
}

/// A Postman desktop session. Postman's sign-in page hands it to the desktop app by redirecting to `callbackHost`.
public struct PostmanSession: Sendable {
    static let appID = "erisedstraehruoytubecafruoytonwohsi"
    public static let loginURL = URL(string: "https://auth.postman.com/__redirect/client/login?app_id=\(appID)&__showRegionChooserIfNoneDetected=1&__region=us")!
    public static let callbackHost = appID + ".chromiumapp.org"
    /// Postman's web app. Google and GitHub sign-in can finish there instead of at the desktop redirect.
    public static func isWebApp(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), !host.hasPrefix("identity."), !host.hasPrefix("auth.") else { return false }
        return host == "postman.co" || host.hasSuffix(".postman.co") || host == "app.getpostman.com"
    }
    /// Google and GitHub sign-in, which Postman's desktop app always sends to the browser.
    public static func needsBrowser(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), host.hasSuffix("getpostman.com") || host.hasSuffix("postman.com") else { return false }
        return ["/google/oauth2", "/oauth2/github/init"].contains(url.path)
    }
    let accessToken: String
    let teamID: String
    let gateway: String
    init(accessToken: String, teamID: String, region: String) {
        self.accessToken = accessToken; self.teamID = teamID
        gateway = region.lowercased() == "eu" ? "https://bifrost.gw.eu.postman.com" : "https://bifrost-https-v4.gw.postman.com"
    }
    /// The address Postman hands a session to. It never resolves, so it must be read rather than followed.
    static func isCallback(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == callbackHost || host.hasSuffix(".chromiumapp.org")
    }
    static func carriesSession(_ url: URL?) -> Bool {
        guard let url else { return false }
        return ((url.query ?? "") + "&" + (url.fragment ?? "")).contains("access_token=")
    }
    /// Reads the session from the sign-in redirect, or returns nil for any other address. An address Postman itself handed over is read from wherever it points, since it is never meant to be loaded.
    public init?(callback url: URL, fromPostman: Bool = false) throws {
        guard Self.isCallback(url) || (fromPostman && Self.carriesSession(url)) else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = (components?.queryItems ?? []) + (URLComponents(string: "?" + (components?.fragment ?? ""))?.queryItems ?? [])
        let value = { (name: String) in items.first { $0.name == name }?.value ?? "" }
        guard !value("access_token").isEmpty else { throw value("error").isEmpty ? ClientError("Postman did not finish signing in. Try again.") : ClientError("Postman did not finish signing in: \(value("error")). Try again.") }
        self.init(accessToken: value("access_token"), teamID: value("team_id"), region: value("region"))
    }
}

/// Postman's browser sign-in, which its desktop app uses for Google, GitHub and single sign-on. The browser signs in at `url`; the app collects the session with a one-time verifier.
public struct PostmanBrowserLogin: Sendable {
    let verifier: String
    public let url: URL
}

/// A Hoppscotch sign-in waiting for the emailed link. Self-hosted servers also pair the link with a device identifier.
public struct HoppscotchSignIn: Sendable {
    let server: String
    let email: String
    let deviceIdentifier: String?
}

/// A signed-in Hoppscotch session.
public struct HoppscotchSession: Sendable {
    let server: String
    let accessToken: String
}

/// A one-time key pair for Insomnia's desktop sign-in. The website seals the session to this key and shows a code to paste back.
public struct InsomniaLogin: Sendable {
    let publicKey: Data
    let secretKey: Data
    public init() { let key = Curve25519.KeyAgreement.PrivateKey(); secretKey = key.rawRepresentation; publicKey = key.publicKey.rawRepresentation }
    init(secretKey: Data) throws { publicKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secretKey).publicKey.rawRepresentation; self.secretKey = secretKey }
    /// The desktop app's login page. Like the desktop app, the key is URI-encoded and then encoded again as a query value.
    public var url: URL {
        let key = publicKey.base64EncodedString().replacingOccurrences(of: "+", with: "%252B").replacingOccurrences(of: "/", with: "%252F").replacingOccurrences(of: "=", with: "%253D")
        return URL(string: RemoteImporter.insomniaWebsite + "/app/auth-app/?loginKey=" + key + "&source_origin=desktop_app")!
    }
}

/// Downloads collections from a service the user already uses, signing in the way that service's own client does or with a token they supply.
/// Credentials go only to that service, over HTTPS, and are never stored. Monkeytail itself has no accounts.
public struct RemoteImporter: Sendable {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    static let repositoryExtensions: Set = ["bru", "json", "yaml", "yml", "http", "rest", "har"]
    static let ignoredFiles: Set = ["package.json", "package-lock.json", "composer.json", "tsconfig.json", "jsconfig.json", "renovate.json", "lerna.json", "pnpm-lock.yaml", "pubspec.yaml", ".travis.yml", "docker-compose.yml", "docker-compose.yaml"]
    static let insomniaAPI = "https://api.insomnia.rest"
    static let insomniaWebsite = "https://app.insomnia.rest"
    static let insomniaClient = "production::darwin::13.3.1"
    static let postmanClient = "11.68.5"
    static let postmanIdentity = "https://identity.getpostman.com"
    static let postmanUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Postman/\(postmanClient) Electron/37.0.0 Safari/537.36"
    public static let hoppscotchServer = "https://api.hoppscotch.io"
    let fetch: Fetch
    let pause: @Sendable (Double) async throws -> Void
    public init(fetch: @escaping Fetch, pause: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) { self.fetch = fetch; self.pause = pause }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: StopAtPostmanCallback(), delegateQueue: nil)
    }()
    /// Postman hands over a session by redirecting to an address only its desktop app intercepts, so the redirect is returned instead of followed.
    private final class StopAtPostmanCallback: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(PostmanSession.isCallback(request.url) || PostmanSession.carriesSession(request.url) ? nil : request)
        }
    }
    static let log = Logger(subsystem: "Monkeytail", category: "RemoteImport")
    public static let live = RemoteImporter { request in
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError("The server sent an invalid response.") }
        return (data, http)
    }

    // MARK: Postman

    /// Starts a browser sign-in the way the desktop app does: Postman issues a verifier, and the browser confirms its hash.
    public func postmanBrowserLogin() async throws -> PostmanBrowserLogin {
        let page = String(decoding: try await get(Self.postmanIdentity + "/client/browser-auth/init?app_id=\(PostmanSession.appID)&target=login", headers: ["User-Agent": Self.postmanUserAgent, "Accept": "text/html"], service: "Postman"), as: UTF8.self)
        guard let verifier = Self.scriptString("authVerifier", in: page), let challenge = Self.scriptString("authChallenge", in: page),
              let url = URL(string: Self.postmanIdentity + (Self.scriptString("authStartPath", in: page) ?? "/client-auth/confirm") + "?auth_challenge=\(challenge)&auth_device=app_native&auth_device_version=\(Self.postmanClient)")
        else { throw ClientError("Postman's browser sign-in did not start. Sign in in Monkeytail instead.") }
        return PostmanBrowserLogin(verifier: verifier, url: url)
    }

    /// Waits for the browser sign-in to finish, polling as the desktop app's sign-in page does, for up to 30 minutes.
    public func postmanSession(_ login: PostmanBrowserLogin) async throws -> PostmanSession {
        var request = URLRequest(url: URL(string: Self.postmanIdentity + "/handover/preauth/" + Self.segment(login.verifier) + "/consume")!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue(Self.postmanUserAgent, forHTTPHeaderField: "User-Agent"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        for _ in 0..<600 {
            try await pause(3)
            let (data, response) = try await fetch(request)
            if response.statusCode == 404 { throw ClientError("This Postman sign-in expired. Start again.") }
            if [429, 503].contains(response.statusCode) { continue }
            guard (200..<300).contains(response.statusCode) else { throw Self.failure("Postman", status: response.statusCode, data: data) }
            let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            guard reply["status"] as? String == "authenticated" else { continue }
            var url = (reply["redirect"] as? String).flatMap { URL(string: $0, relativeTo: URL(string: Self.postmanIdentity))?.absoluteURL }
            for _ in 0..<8 {
                guard let current = url else { break }
                Self.log.info("Postman handover: \(current.scheme ?? "", privacy: .public)://\(current.host ?? "", privacy: .public)\(current.path, privacy: .public)")
                if let session = try PostmanSession(callback: current, fromPostman: true) { return session }
                var hop = URLRequest(url: current, cachePolicy: .reloadIgnoringLocalCacheData); hop.setValue(Self.postmanUserAgent, forHTTPHeaderField: "User-Agent")
                let response: HTTPURLResponse
                do { response = try await fetch(hop).1 } catch let failure as URLError {
                    if let failed = failure.failingURL, let session = try PostmanSession(callback: failed, fromPostman: true) { return session }
                    throw failure
                }
                Self.log.info("Postman handover: HTTP \(response.statusCode, privacy: .public)")
                url = response.value(forHTTPHeaderField: "Location").flatMap { URL(string: $0, relativeTo: current)?.absoluteURL }
            }
            throw ClientError("Postman finished signing in but did not hand over a session. Try again, or sign in in Monkeytail instead.")
        }
        throw ClientError("Postman sign-in timed out. Start again.")
    }

    static func scriptString(_ name: String, in page: String) -> String? {
        guard let range = page.range(of: name + #"\s*=\s*"[^"]+""#, options: .regularExpression) else { return nil }
        return page[range].split(separator: "\"").dropFirst().first.map(String.init)
    }

    /// Lists the account's workspaces through Postman's gateway, as the desktop app's workspace switcher does.
    public func postmanWorkspaces(_ session: PostmanSession) async throws -> [RemoteWorkspace] {
        var workspaces: [RemoteWorkspace] = [], cursor = ""
        for _ in 0..<50 {
            let page = try await postmanProxy(session, service: "workspaces", path: "/workspaces?archived=false" + (cursor.isEmpty ? "" : "&cursor=" + Self.segment(cursor)))
            for item in page["data"] as? [[String: Any]] ?? [] {
                guard let id = item["id"] as? String, !workspaces.contains(where: { $0.id == id }) else { continue }
                workspaces.append(RemoteWorkspace(id: id, name: item["name"] as? String ?? "Workspace", kind: (item["visibilityStatus"] ?? item["type"]) as? String ?? ""))
            }
            cursor = (page["meta"] as? [String: Any])?["nextCursor"] as? String ?? ""
            if cursor.isEmpty { break }
        }
        guard !workspaces.isEmpty else { throw ClientError("This Postman account has no workspaces.") }
        return workspaces
    }

    /// Imports every collection, environment and the globals of the chosen workspaces from Postman's sync service, in the v1 format the desktop app stores.
    public func postman(_ session: PostmanSession, workspaces: [RemoteWorkspace], progress: (String) -> Void = { _ in }) async throws -> CollectionImport {
        let headers = postmanHeaders(session), host = session.gateway
        var collections: [[String: Any]] = [], environments: [[String: Any]] = [], globals: [[String: Any]] = [], seen = Set<String>(), warnings: [String] = []
        for workspace in workspaces {
            progress(String(localized: "Reading \(workspace.name)…", bundle: .module))
            let id = Self.segment(workspace.id)
            for item in try await postmanList(session, "collection", workspace: id) where seen.insert("collection " + item.uid).inserted {
                progress(item.name.isEmpty ? String(localized: "Downloading collection…", bundle: .module) : String(localized: "Downloading \(item.name)…", bundle: .module))
                let root = try await object(host + "/collection/" + Self.segment(item.uid) + "?populate=true", headers: headers, service: "Postman")
                if let collection = (root["data"] ?? root) as? [String: Any] { collections.append(collection) }
            }
            for item in try await postmanList(session, "environment", workspace: id) where seen.insert("environment " + item.uid).inserted {
                progress(item.name.isEmpty ? String(localized: "Downloading environment…", bundle: .module) : String(localized: "Downloading \(item.name)…", bundle: .module))
                let root = try await object(host + "/environment/" + Self.segment(item.uid), headers: headers, service: "Postman")
                guard var environment = (root["data"] ?? root) as? [String: Any] else { continue }
                if workspaces.count > 1 { environment["name"] = workspace.name + " / " + (environment["name"] as? String ?? "Environment") }
                environments.append(environment)
            }
            let values = ((try? await object(host + "/workspace/" + id + "/globals", headers: headers, service: "Postman"))?["data"] as? [String: Any])?["values"] as? [[String: Any]] ?? []
            if !values.isEmpty && !globals.isEmpty { warnings.append(String(localized: "Several workspaces have globals. Monkeytail has one set of globals, so later workspaces win for duplicate names.", bundle: .module)) }
            globals += values
        }
        guard !collections.isEmpty || !environments.isEmpty || !globals.isEmpty else { throw ClientError("The selected Postman workspaces contain no collections, environments or globals.") }
        var result = try InterchangeImport.postmanDump(["collections": collections, "environments": environments, "globals": globals])
        result.warnings = InterchangeImport.unique(result.warnings + warnings)
        return result
    }

    /// The collections or environments in a workspace, from the sidebar list, falling back to the workspace's elements.
    private func postmanList(_ session: PostmanSession, _ model: String, workspace: String) async throws -> [(uid: String, name: String)] {
        let listed = try? await object(session.gateway + "/list/\(model)?workspace=" + workspace, method: "POST", headers: postmanHeaders(session), service: "Postman")
        let items = Self.postmanItems(listed?["data"])
        if !items.isEmpty { return items }
        let elements = try await postmanProxy(session, service: "workspaces", path: "/workspaces/\(workspace)?include=elements")
        return Self.postmanItems(((elements["data"] as? [String: Any])?["elements"] as? [String: Any])?[model + "s"])
    }

    static func postmanItems(_ value: Any?) -> [(uid: String, name: String)] {
        let items = value as? [Any] ?? (value as? [String: Any]).map { Array($0.values) } ?? []
        return items.compactMap { item in
            if let uid = item as? String { return (uid, "") }
            guard let item = item as? [String: Any] else { return nil }
            let id = CollectionCodec.string(item["id"]), owner = CollectionCodec.string(item["owner"])
            let uid = item["uid"] as? String ?? (owner.isEmpty || id.isEmpty || id.hasPrefix(owner + "-") ? id : owner + "-" + id)
            return uid.isEmpty ? nil : (uid, item["name"] as? String ?? "")
        }
    }

    private func postmanProxy(_ session: PostmanSession, service: String, path: String) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["service": service, "method": "GET", "path": path])
        return try await object(session.gateway + "/ws/proxy", method: "POST", body: body, headers: postmanHeaders(session), service: "Postman")
    }

    private func postmanHeaders(_ session: PostmanSession) -> [String: String] {
        var headers = ["x-access-token": session.accessToken, "x-app-version": Self.postmanClient, "Accept": "application/json"]
        if !session.teamID.isEmpty && session.teamID != "0" { headers["x-entity-team-id"] = session.teamID }
        return headers
    }

    // MARK: GitHub

    /// Imports every supported file in a repository or folder: Postman, Insomnia Git Sync, Bruno, Thunder Client, Hoppscotch, .http, HAR and OpenAPI.
    public func github(_ source: GitHubSource, token: String = "", progress: (String) -> Void = { _ in }) async throws -> CollectionImport {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var headers = ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]
        if !token.isEmpty { headers["Authorization"] = "Bearer " + token }
        let api = "https://api.github.com/repos/\(source.owner)/\(source.repo)"
        progress(String(localized: "Reading \(source.owner)/\(source.repo)…", bundle: .module))
        var ref = source.ref ?? ""
        if ref.isEmpty { ref = try await object(api, headers: headers, service: "GitHub")["default_branch"] as? String ?? "main" }
        let tree = try await object(api + "/git/trees/" + Self.segment(ref) + "?recursive=1", headers: headers, service: "GitHub")
        var warnings: [String] = []
        if tree["truncated"] as? Bool == true { warnings.append(String(localized: "GitHub listed only part of this large repository. Paste a folder URL to import a smaller part.", bundle: .module)) }
        let prefix = source.path.isEmpty ? "" : source.path.hasSuffix("/") ? source.path : source.path + "/"
        let entries = (tree["tree"] as? [[String: Any]] ?? []).compactMap { entry -> (path: String, size: Int)? in
            guard entry["type"] as? String == "blob", let path = entry["path"] as? String, prefix.isEmpty || path.hasPrefix(prefix) || path == source.path else { return nil }
            let components = path.split(separator: "/").map(String.init), name = components.last?.lowercased() ?? ""
            guard Self.repositoryExtensions.contains((name as NSString).pathExtension), !Self.ignoredFiles.contains(name),
                  !components.contains(where: { $0.hasPrefix(".") || $0 == "node_modules" }), (entry["size"] as? Int ?? 0) <= 5 * 1024 * 1024 else { return nil }
            return (path, entry["size"] as? Int ?? 0)
        }
        guard !entries.isEmpty else { throw ClientError("No collection files were found in \(source.owner)/\(source.repo)\(source.path.isEmpty ? "" : "/" + source.path).") }
        guard entries.count <= 1000, entries.reduce(0, { $0 + $1.size }) <= 40 * 1024 * 1024 else { throw ClientError("The repository has too many candidate files. Paste a folder URL (…/tree/branch/folder) to import part of it.") }
        var files: [ImportFile] = []
        for start in stride(from: 0, to: entries.count, by: 8) {
            progress(String(localized: "Downloading files \(start + 1)–\(min(start + 8, entries.count)) of \(entries.count)…", bundle: .module))
            let batch = Array(entries[start..<min(start + 8, entries.count)])
            let downloaded = try await withThrowingTaskGroup(of: (Int, ImportFile?).self) { group in
                for (index, entry) in batch.enumerated() {
                    let url = token.isEmpty ? "https://raw.githubusercontent.com/\(source.owner)/\(source.repo)/\(Self.segment(ref, keepSlash: true))/\(Self.segment(entry.path, keepSlash: true))"
                        : api + "/contents/" + Self.segment(entry.path, keepSlash: true) + "?ref=" + Self.segment(ref)
                    let fileHeaders = token.isEmpty ? [:] : headers.merging(["Accept": "application/vnd.github.raw+json"]) { $1 }
                    group.addTask {
                        let data = try await get(url, headers: fileHeaders, service: "GitHub")
                        let relative = entry.path.hasPrefix(prefix) ? String(entry.path.dropFirst(prefix.count)) : (entry.path as NSString).lastPathComponent
                        return (index, String(data: data, encoding: .utf8).map { ImportFile(path: relative, text: $0) })
                    }
                }
                var results: [(Int, ImportFile?)] = []
                for try await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }.compactMap(\.1)
            }
            files += downloaded
        }
        progress(String(localized: "Converting \(files.count) files…", bundle: .module))
        return try Self.decodeRepository(files, name: source.path.isEmpty ? source.repo : (source.path as NSString).lastPathComponent, warnings: warnings)
    }

    /// Decodes each Bruno collection relative to its own `bruno.json`, and every other file on its own.
    static func decodeRepository(_ files: [ImportFile], name: String, warnings: [String] = []) throws -> CollectionImport {
        let roots = files.compactMap { file -> String? in
            guard (file.path as NSString).lastPathComponent == "bruno.json" else { return nil }
            let directory = (file.path as NSString).deletingLastPathComponent
            return directory.isEmpty ? "" : directory + "/"
        }.sorted { $0.count > $1.count }
        var groups: [String: [ImportFile]] = [:], rest: [ImportFile] = []
        for file in files {
            if let root = roots.first(where: { file.path.hasPrefix($0) }), file.path.lowercased().hasSuffix(".bru") || (file.path as NSString).lastPathComponent == "bruno.json" {
                groups[root, default: []].append(ImportFile(path: String(file.path.dropFirst(root.count)), text: file.text)); continue
            }
            rest.append(file)
        }
        var results: [CollectionImport] = [], skipped = warnings
        for root in groups.keys.sorted() { results.append(try InterchangeImport.decode(files: groups[root]!, name: root.isEmpty ? name : ((root as NSString).lastPathComponent))) }
        if !rest.isEmpty {
            do { results.append(try InterchangeImport.decode(files: rest, name: name)) } catch { if results.isEmpty { throw error }; skipped.append(error.localizedDescription) }
        }
        var merged = InterchangeImport.merge(results); merged.warnings = summarize(InterchangeImport.unique(skipped + merged.warnings))
        return merged
    }

    static func summarize(_ warnings: [String]) -> [String] {
        let pattern = "^" + InterchangeImport.skipped("\u{0}", "\u{0}").components(separatedBy: "\u{0}").map(NSRegularExpression.escapedPattern(for:)).joined(separator: "[\\s\\S]*") + "$"
        let regex = try? NSRegularExpression(pattern: pattern), isSkipped = { (warning: String) in warning.hasPrefix("Skipped ") || regex?.firstMatch(in: warning, range: NSRange(warning.startIndex..., in: warning)) != nil }
        let skipped = warnings.filter(isSkipped)
        return skipped.count <= 3 ? warnings : warnings.filter { !isSkipped($0) } + [String(localized: "Skipped \(skipped.count) files that are not API collections.", bundle: .module)]
    }

    // MARK: Insomnia

    /// Finishes Insomnia's desktop sign-in with the code the website shows, then unlocks the account's end-to-end encryption keys.
    public func insomniaSignIn(_ login: InsomniaLogin, code: String) async throws -> InsomniaSession {
        var text = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if let query = URLComponents(string: text)?.queryItems?.first(where: { $0.name == "box" })?.value { text = query }
        text = (text.removingPercentEncoding ?? text).filter { !$0.isWhitespace }
        guard !text.isEmpty else { throw ClientError("Paste the code Insomnia shows after you sign in.") }
        guard let box = Data(base64Encoded: text) else { throw ClientError("The sign-in code is invalid or expired. Sign in again to get a new one.") }
        let opened = try JSONSerialization.jsonObject(with: try SyncCrypto.openSealedBox(box, publicKey: login.publicKey, secretKey: login.secretKey)) as? [String: Any]
        guard let token = opened?["token"] as? String, let key = opened?["key"] as? String else { throw ClientError("Insomnia sent a sign-in code in an unexpected format.") }
        let keys = try await object(Self.insomniaAPI + "/v3/users/me/encryption-keys", headers: insomniaHeaders(token), service: "Insomnia")
        let symmetricKey = try SyncCrypto.decryptJSON(keys["enc_symmetric_key"], key: key)
        let privateKey = try SyncCrypto.decryptJSON(keys["enc_private_key"], key: symmetricKey)
        return InsomniaSession(id: token, privateKey: privateKey.compactMapValues { $0 as? String })
    }

    /// Lists the Cloud Sync projects in every organization the account belongs to.
    public func insomniaProjects(_ session: InsomniaSession) async throws -> [RemoteWorkspace] {
        var organizations: [[String: Any]] = [], next: String? = "/v3/users/me/spaces?page[size]=200"
        for _ in 0..<50 {
            guard let path = next else { break }
            let page = try await object(Self.insomniaAPI + path.replacingOccurrences(of: "[", with: "%5B").replacingOccurrences(of: "]", with: "%5D"), headers: insomniaHeaders(session.id), service: "Insomnia")
            organizations += page["data"] as? [[String: Any]] ?? []
            next = ((page["meta"] as? [String: Any])?["page"] as? [String: Any])?["next"] as? String
        }
        var projects: [RemoteWorkspace] = [], seen = Set<String>()
        for organization in organizations {
            guard let id = organization["id"] as? String else { continue }
            let name = (organization["display_name"] ?? organization["name"]) as? String ?? "Organization"
            let found = try await insomniaGraphQL("query ($teamId: ID, $allProjects: Boolean) { projects(teamId: $teamId, allProjects: $allProjects) { id name } }", ["teamId": id, "allProjects": true], name: "projects", session)
            for project in found["projects"] as? [[String: Any]] ?? [] {
                guard let projectID = project["id"] as? String, seen.insert(projectID).inserted else { continue }
                projects.append(RemoteWorkspace(id: projectID, name: project["name"] as? String ?? "Project", kind: name))
            }
        }
        guard !projects.isEmpty else { throw ClientError("This Insomnia account has no Cloud Sync projects. Local and Git projects are not stored in Insomnia's cloud.") }
        return projects
    }

    /// Pulls the latest snapshot of each project's default branch, as Insomnia does when it clones a project, and decrypts every document.
    public func insomnia(_ session: InsomniaSession, projects: [RemoteWorkspace], progress: (String) -> Void = { _ in }) async throws -> CollectionImport {
        var resources: [[String: Any]] = [], warnings: [String] = []
        for project in projects {
            progress(String(localized: "Reading \(project.name)…", bundle: .module))
            let projectKey = try await insomniaGraphQL("query ($projectId: ID!) { projectKey(projectId: $projectId) { encSymmetricKey } }", ["projectId": project.id], name: "projectKey", session)
            guard let encrypted = (projectKey["projectKey"] as? [String: Any])?["encSymmetricKey"] as? String else { throw ClientError("Insomnia did not send the key for \(project.name).") }
            let key = try SyncCrypto.decryptRSAJSON(encrypted, privateKey: session.privateKey)
            let branch = try await insomniaGraphQL("query ($projectId: ID!, $branch: String!) { branch(project: $projectId, name: $branch) { snapshots } }", ["projectId": project.id, "branch": "master"], name: "branch", session)
            guard let head = ((branch["branch"] as? [String: Any])?["snapshots"] as? [String])?.last else { warnings.append(String(localized: "\(project.name) has nothing synced yet.", bundle: .module)); continue }
            let snapshots = try await insomniaGraphQL("query ($ids: [ID!]!, $projectId: ID!) { snapshots(ids: $ids, project: $projectId) { id state { blob key name } } }", ["ids": [head], "projectId": project.id], name: "snapshots", session)
            let blobIDs = ((snapshots["snapshots"] as? [[String: Any]])?.first?["state"] as? [[String: Any]] ?? []).compactMap { $0["blob"] as? String }
            for start in stride(from: 0, to: blobIDs.count, by: 50) {
                progress(String(localized: "Decrypting \(project.name): \(min(start + 50, blobIDs.count)) of \(blobIDs.count)…", bundle: .module))
                let found = try await insomniaGraphQL("query ($ids: [ID!]!, $projectId: ID!) { blobs(ids: $ids, project: $projectId) { id content } }", ["ids": Array(blobIDs[start..<min(start + 50, blobIDs.count)]), "projectId": project.id], name: "blobs", session)
                for blob in found["blobs"] as? [[String: Any]] ?? [] {
                    let data = try SyncCrypto.gunzip(try SyncCrypto.decryptAES(blob["content"], key: key))
                    guard var document = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = document["type"] as? String else { continue }
                    document["_type"] = Self.insomniaTypes[type] ?? type
                    resources.append(document)
                }
            }
        }
        guard resources.contains(where: { $0["_type"] as? String == "workspace" }) else { throw warnings.first.map(ClientError.init(verbatim:)) ?? ClientError("The selected Insomnia projects contain no collections.") }
        var result = try InsomniaImport.decode(["__export_source": "insomnia.desktop.app"], resources: resources)
        result.warnings = InterchangeImport.unique(result.warnings + warnings)
        return result
    }

    static let insomniaTypes = ["Workspace": "workspace", "Request": "request", "RequestGroup": "request_group", "Environment": "environment", "WebSocketRequest": "websocket_request", "GrpcRequest": "grpc_request"]

    private func insomniaHeaders(_ session: String) -> [String: String] {
        ["X-Session-Id": session, "X-Insomnia-Client": Self.insomniaClient, "X-Origin": Self.insomniaAPI, "Accept": "application/json",
         "insomnia-request-id": "desk_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()]
    }

    private func insomniaGraphQL(_ query: String, _ variables: [String: Any], name: String, _ session: InsomniaSession) async throws -> [String: Any] {
        try await graphQL(Self.insomniaAPI + "/graphql?" + name, query: query, variables: variables, headers: insomniaHeaders(session.id), service: "Insomnia")
    }

    // MARK: Hoppscotch

    /// Emails a sign-in link the way Hoppscotch's own clients do: Firebase email-link sign-in on hoppscotch.io, the desktop magic link on self-hosted servers.
    public func hoppscotchSendLink(server: String = RemoteImporter.hoppscotchServer, email: String) async throws -> HoppscotchSignIn {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines), base = try Self.hoppscotchBase(server)
        guard email.contains("@") else { throw ClientError("Enter the email address of your Hoppscotch account.") }
        if Self.isHoppscotchCloud(base) {
            let body = try JSONSerialization.data(withJSONObject: ["requestType": "EMAIL_SIGNIN", "email": email, "continueUrl": "https://hoppscotch.io/enter", "canHandleCodeInApp": true])
            _ = try await send(Self.firebase + "sendOobCode?key=" + Self.hoppscotchFirebaseKey, method: "POST", body: body, headers: Self.firebaseHeaders, service: "Hoppscotch")
            return HoppscotchSignIn(server: base, email: email, deviceIdentifier: nil)
        }
        let body = try JSONSerialization.data(withJSONObject: ["email": email])
        let response = try await object(base + "/v1/auth/signin?origin=desktop", method: "POST", body: body, headers: ["Accept": "application/json"], service: "Hoppscotch")
        guard let device = response["deviceIdentifier"] as? String else { throw ClientError("Hoppscotch did not start the sign-in. Check that email sign-in is enabled on this server.") }
        return HoppscotchSignIn(server: base, email: email, deviceIdentifier: device)
    }

    /// Completes sign-in with the emailed link (or its code) and keeps the resulting access token.
    public func hoppscotchSignIn(_ pending: HoppscotchSignIn, link: String) async throws -> HoppscotchSession {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines), expired = ClientError("The sign-in link is invalid or expired. Request a new one and paste it here.")
        guard pending.deviceIdentifier == nil else {
            let token = Self.queryValue("token", in: text) ?? text
            guard !token.isEmpty, !token.contains(" ") else { throw ClientError("Paste the sign-in link from the Hoppscotch email.") }
            let body = try JSONSerialization.data(withJSONObject: ["token": token, "deviceIdentifier": pending.deviceIdentifier!])
            let response: HTTPURLResponse
            do { response = try await send(pending.server + "/v1/auth/verify", method: "POST", body: body, headers: ["Accept": "application/json"], service: "Hoppscotch").1 } catch { throw expired }
            let fields = response.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
            guard let url = response.url, let access = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).first(where: { $0.name == "access_token" })?.value, !access.isEmpty else { throw expired }
            return HoppscotchSession(server: pending.server, accessToken: access)
        }
        let code = Self.queryValue("oobCode", in: text) ?? text
        guard !code.isEmpty, !code.contains(" ") else { throw ClientError("Paste the sign-in link from the Hoppscotch email.") }
        let body = try JSONSerialization.data(withJSONObject: ["email": pending.email, "oobCode": code])
        let response: [String: Any]
        do { response = try await object(Self.firebase + "signInWithEmailLink?key=" + Self.hoppscotchFirebaseKey, method: "POST", body: body, headers: Self.firebaseHeaders, service: "Hoppscotch") } catch { throw expired }
        guard let token = response["idToken"] as? String, !token.isEmpty else { throw expired }
        return HoppscotchSession(server: pending.server, accessToken: token)
    }

    static let firebase = "https://identitytoolkit.googleapis.com/v1/accounts:"
    static let hoppscotchFirebaseKey = "AIzaSyCMsFreESs58-hRxTtiqQrIcimh4i1wbsM"
    static let firebaseHeaders = ["Accept": "application/json", "Referer": "https://hoppscotch.io/", "Origin": "https://hoppscotch.io"]
    static func isHoppscotchCloud(_ base: String) -> Bool { URL(string: base)?.host?.lowercased() == "api.hoppscotch.io" }

    /// Finds a query value in a link, including links nested in `link` or `continueUrl` parameters.
    static func queryValue(_ name: String, in text: String, depth: Int = 0) -> String? {
        guard depth < 3, let items = URLComponents(string: text)?.queryItems else { return nil }
        if let value = items.first(where: { $0.name == name })?.value, !value.isEmpty { return value }
        return items.lazy.compactMap { $0.value.flatMap { queryValue(name, in: $0, depth: depth + 1) } }.first
    }

    /// Imports personal collections and environments, globals, and every team's collections and environments.
    public func hoppscotch(_ session: HoppscotchSession, progress: (String) -> Void = { _ in }) async throws -> CollectionImport {
        progress(String(localized: "Reading your collections…", bundle: .module))
        let mine = try await hoppscotchGraphQL("query { exportUserCollectionsToJSON(collectionType: REST) { exportedCollection } me { environments { name variables } } }", [:], session)
        var list = (Self.parsed((mine["exportUserCollectionsToJSON"] as? [String: Any])?["exportedCollection"]) as? [[String: Any]] ?? []).map { Self.hoppscotchCollection($0, depth: 0) }
        list += ((mine["me"] as? [String: Any])?["environments"] as? [[String: Any]] ?? []).map { ["name": $0["name"] as? String ?? "Environment", "variables": Self.parsed($0["variables"]) ?? []] }
        let globals = try? await hoppscotchGraphQL("query { me { globalEnvironments { variables } } }", [:], session)
        var teams: [[String: Any]] = [], cursor: String?
        for _ in 0..<50 {
            let page = try await hoppscotchGraphQL("query ($cursor: ID) { myTeams(cursor: $cursor) { id name } }", cursor.map { ["cursor": $0] } ?? [:], session)["myTeams"] as? [[String: Any]] ?? []
            guard let last = page.last?["id"] as? String, last != cursor else { break }
            teams += page; cursor = last
        }
        for team in teams {
            guard let id = team["id"] as? String else { continue }
            let name = team["name"] as? String ?? "Team"
            progress(String(localized: "Reading \(name)…", bundle: .module))
            let shared = try await hoppscotchGraphQL("query ($teamID: ID!) { exportCollectionsToJSON(teamID: $teamID) team(teamID: $teamID) { teamEnvironments { name variables } } }", ["teamID": id], session)
            list += (Self.parsed(shared["exportCollectionsToJSON"]) as? [[String: Any]] ?? []).map { Self.hoppscotchCollection($0, depth: 0) }
            list += ((shared["team"] as? [String: Any])?["teamEnvironments"] as? [[String: Any]] ?? []).map { ["name": name + " / " + ($0["name"] as? String ?? "Environment"), "variables": Self.parsed($0["variables"]) ?? []] }
        }
        let globalVariables = Self.parsed(((globals?["me"] as? [String: Any])?["globalEnvironments"] as? [String: Any])?["variables"]) as? [[String: Any]] ?? []
        guard !list.isEmpty || !globalVariables.isEmpty else { throw ClientError("This Hoppscotch account has no collections or environments.") }
        var result = try InterchangeImport.hoppscotch(list)
        if !globalVariables.isEmpty { result.workspace.globals = InterchangeImport.hoppVariables(globalVariables) }
        return result
    }

    static func hoppscotchBase(_ server: String) throws -> String {
        var base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        for suffix in ["/v1", "/graphql"] where base.hasSuffix(suffix) { base.removeLast(suffix.count) }
        guard let url = URL(string: base), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw ClientError("Enter the Hoppscotch server URL, such as https://api.hoppscotch.io.") }
        return base
    }

    private func hoppscotchGraphQL(_ query: String, _ variables: [String: Any], _ session: HoppscotchSession) async throws -> [String: Any] {
        try await graphQL(session.server + "/graphql", query: query, variables: variables, headers: ["Authorization": "Bearer " + session.accessToken, "Accept": "application/json"], service: "Hoppscotch")
    }

    /// Converts an exported collection (JSON-string `data`; requests either inline or as a JSON-string `request`) to Hoppscotch's file format.
    static func hoppscotchCollection(_ source: [String: Any], depth: Int) -> [String: Any] {
        var result: [String: Any] = ["v": 2, "name": source["title"] as? String ?? source["name"] as? String ?? "Hoppscotch collection"]
        if let data = parsed(source["data"]) as? [String: Any] { for key in ["auth", "headers", "variables", "description", "preRequestScript", "testScript"] { if let value = data[key] { result[key] = value } } }
        for key in ["auth", "headers", "variables", "description", "preRequestScript", "testScript"] where result[key] == nil { if let value = source[key] { result[key] = value } }
        result["requests"] = (source["requests"] as? [[String: Any]] ?? []).map { parsed($0["request"]) as? [String: Any] ?? $0 }
        result["folders"] = depth < 32 ? (source["folders"] as? [[String: Any]] ?? []).map { hoppscotchCollection($0, depth: depth + 1) } : []
        return result
    }

    private static func parsed(_ value: Any?) -> Any? {
        guard let text = value as? String else { return value is NSNull ? nil : value }
        return try? JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    // MARK: Transport

    private func object(_ url: String, method: String = "GET", body: Data? = nil, headers: [String: String], service: String) async throws -> [String: Any] {
        let data = try await send(url, method: method, body: body, headers: headers, service: service).0
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClientError("\(service) sent an unexpected response.") }
        return object
    }

    private func graphQL(_ url: String, query: String, variables: [String: Any], headers: [String: String], service: String) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let root = try await object(url, method: "POST", body: body, headers: headers, service: service)
        if let message = (root["errors"] as? [[String: Any]])?.first?["message"] as? String { throw ClientError("\(service): \(message)") }
        guard let data = root["data"] as? [String: Any] else { throw ClientError("\(service) sent an unexpected response.") }
        return data
    }

    func get(_ address: String, headers: [String: String], service: String) async throws -> Data {
        try await send(address, headers: headers, service: service).0
    }

    func send(_ address: String, method: String = "GET", body: Data? = nil, headers: [String: String], service: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: address) else { throw ClientError("The \(service) address is invalid.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method; request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        for attempt in 0..<4 {
            try Task.checkCancellation()
            let (data, response) = try await fetch(request)
            if [429, 503].contains(response.statusCode) || (response.statusCode == 403 && response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
                guard attempt < 3 else { throw service == "GitHub" ? ClientError("GitHub is limiting requests. Try again in a few minutes, or add a token.") : ClientError("\(service) is limiting requests. Try again in a few minutes.") }
                try await pause(min(max(Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(1 << attempt), 1), 30)); continue
            }
            guard (200..<300).contains(response.statusCode) else { throw Self.failure(service, status: response.statusCode, data: data) }
            guard data.count <= 40 * 1024 * 1024 else { throw ClientError("\(service) sent more than 40 MB.") }
            return (data, response)
        }
        throw ClientError("\(service) is limiting requests. Try again in a few minutes.")
    }

    static func failure(_ service: String, status: Int, data: Data) -> ClientError {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let detail = ((object?["error"] as? [String: Any])?["message"] ?? object?["message"] ?? object?["reason"]) as? String
        switch status {
        case 401: return ClientError("\(service) rejected the token. Check that it is correct and has not expired.")
        case 403: return detail.map { ClientError("\(service) denied access: \($0)") } ?? ClientError("\(service) denied access. Check the token's permissions.")
        case 404: return service == "GitHub" ? ClientError("GitHub could not find it. Check the name or ID, and add a token for a private repository.") : ClientError("\(service) could not find it. Check the name or ID.")
        default: return detail.map { ClientError("\(service) returned HTTP \(status): \($0)") } ?? ClientError("\(service) returned HTTP \(status).")
        }
    }

    static func segment(_ value: String, keepSlash: Bool = false) -> String {
        var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "?#;=&+" + (keepSlash ? "" : "/"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
