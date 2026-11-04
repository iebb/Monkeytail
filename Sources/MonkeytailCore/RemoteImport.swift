import Foundation

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

/// Downloads collections from a service the user already uses, with a token they supply.
/// Tokens go only to that service, over HTTPS, and are never stored. Monkeytail itself has no accounts.
public struct RemoteImporter: Sendable {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public enum PostmanRegion: String, CaseIterable, Identifiable, Sendable {
        case us = "US", eu = "EU"
        public var id: String { rawValue }
        public var host: String { self == .us ? "https://api.getpostman.com" : "https://api.eu.postman.com" }
    }
    static let repositoryExtensions: Set = ["bru", "json", "yaml", "yml", "http", "rest", "har"]
    static let ignoredFiles: Set = ["package.json", "package-lock.json", "composer.json", "tsconfig.json", "jsconfig.json", "renovate.json", "lerna.json", "pnpm-lock.yaml", "pubspec.yaml", ".travis.yml", "docker-compose.yml", "docker-compose.yaml"]
    let fetch: Fetch
    let pause: @Sendable (Double) async throws -> Void
    public init(fetch: @escaping Fetch, pause: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) { self.fetch = fetch; self.pause = pause }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCache = nil; configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()
    public static let live = RemoteImporter { request in
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError("The server sent an invalid response.") }
        return (data, http)
    }

    // MARK: Postman

    public func postmanWorkspaces(apiKey: String, region: PostmanRegion = .us) async throws -> [RemoteWorkspace] {
        let root = try await object(region.host + "/workspaces", headers: postmanHeaders(apiKey), service: "Postman")
        let workspaces = (root["workspaces"] as? [[String: Any]] ?? []).compactMap { item in (item["id"] as? String).map { RemoteWorkspace(id: $0, name: item["name"] as? String ?? "Workspace", kind: item["type"] as? String ?? "") } }
        guard !workspaces.isEmpty else { throw ClientError("This Postman API key has no workspaces.") }
        return workspaces
    }

    /// Imports every collection, environment and the globals of the chosen workspaces.
    public func postman(apiKey: String, region: PostmanRegion = .us, workspaces: [RemoteWorkspace], progress: (String) -> Void = { _ in }) async throws -> CollectionImport {
        let headers = try postmanHeaders(apiKey), host = region.host
        var collections: [[String: Any]] = [], environments: [[String: Any]] = [], globals: [[String: Any]] = [], seen = Set<String>(), warnings: [String] = []
        for workspace in workspaces {
            progress("Reading \(workspace.name)…")
            let detail = try await object(host + "/workspaces/" + Self.segment(workspace.id), headers: headers, service: "Postman")["workspace"] as? [String: Any] ?? [:]
            for item in detail["collections"] as? [[String: Any]] ?? [] {
                guard let uid = (item["uid"] ?? item["id"]) as? String, seen.insert("collection " + uid).inserted else { continue }
                progress("Downloading \(item["name"] as? String ?? "collection")…")
                if let collection = try await object(host + "/collections/" + Self.segment(uid), headers: headers, service: "Postman")["collection"] as? [String: Any] { collections.append(collection) }
            }
            for item in detail["environments"] as? [[String: Any]] ?? [] {
                guard let uid = (item["uid"] ?? item["id"]) as? String, seen.insert("environment " + uid).inserted else { continue }
                progress("Downloading \(item["name"] as? String ?? "environment")…")
                guard var environment = try await object(host + "/environments/" + Self.segment(uid), headers: headers, service: "Postman")["environment"] as? [String: Any] else { continue }
                if workspaces.count > 1 { environment["name"] = workspace.name + " / " + (environment["name"] as? String ?? "Environment") }
                environments.append(environment)
            }
            let values = (try? await object(host + "/workspaces/" + Self.segment(workspace.id) + "/global-variables", headers: headers, service: "Postman"))?["values"] as? [[String: Any]] ?? []
            if !values.isEmpty && !globals.isEmpty { warnings.append("Several workspaces have globals. Monkeytail has one set of globals, so later workspaces win for duplicate names.") }
            globals += values
        }
        guard !collections.isEmpty || !environments.isEmpty || !globals.isEmpty else { throw ClientError("The selected Postman workspaces contain no collections, environments or globals.") }
        var result = try InterchangeImport.postmanDump(["collections": collections, "environments": environments, "globals": globals])
        result.warnings = InterchangeImport.unique(result.warnings + warnings)
        return result
    }

    private func postmanHeaders(_ apiKey: String) throws -> [String: String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ClientError("Enter a Postman API key.") }
        return ["X-Api-Key": key, "Accept": "application/json"]
    }

    // MARK: GitHub

    /// Imports every supported file in a repository or folder: Postman, Insomnia Git Sync, Bruno, Thunder Client, Hoppscotch, .http, HAR and OpenAPI.
    public func github(_ source: GitHubSource, token: String = "", progress: (String) -> Void = { _ in }) async throws -> CollectionImport {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        var headers = ["Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]
        if !token.isEmpty { headers["Authorization"] = "Bearer " + token }
        let api = "https://api.github.com/repos/\(source.owner)/\(source.repo)"
        progress("Reading \(source.owner)/\(source.repo)…")
        var ref = source.ref ?? ""
        if ref.isEmpty { ref = try await object(api, headers: headers, service: "GitHub")["default_branch"] as? String ?? "main" }
        let tree = try await object(api + "/git/trees/" + Self.segment(ref) + "?recursive=1", headers: headers, service: "GitHub")
        var warnings: [String] = []
        if tree["truncated"] as? Bool == true { warnings.append("GitHub listed only part of this large repository. Paste a folder URL to import a smaller part.") }
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
            progress("Downloading files \(start + 1)–\(min(start + 8, entries.count)) of \(entries.count)…")
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
        progress("Converting \(files.count) files…")
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
        let skipped = warnings.filter { $0.hasPrefix("Skipped ") }
        return skipped.count <= 3 ? warnings : warnings.filter { !$0.hasPrefix("Skipped ") } + ["Skipped \(skipped.count) files that are not API collections."]
    }

    // MARK: Hoppscotch

    /// Imports team collections and environments by ID with a Hoppscotch personal access token, as the Hoppscotch CLI does.
    public func hoppscotch(server: String = "https://api.hoppscotch.io", token: String, collectionIDs: [String], environmentIDs: [String], progress: (String) -> Void = { _ in }) async throws -> CollectionImport {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines), base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw ClientError("Enter a Hoppscotch personal access token.") }
        guard let url = URL(string: base), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw ClientError("Enter the Hoppscotch server URL, such as https://api.hoppscotch.io.") }
        guard !collectionIDs.isEmpty || !environmentIDs.isEmpty else { throw ClientError("Enter at least one collection or environment ID.") }
        let root = (base.hasSuffix("/") ? base : base + "/") + "v1/access-tokens/", headers = ["Authorization": "Bearer " + token, "Accept": "application/json"]
        var list: [[String: Any]] = []
        for id in collectionIDs {
            progress("Downloading collection \(id)…")
            list.append(Self.hoppscotchCollection(try await object(root + "collection/" + Self.segment(id), headers: headers, service: "Hoppscotch"), depth: 0))
        }
        for id in environmentIDs {
            progress("Downloading environment \(id)…")
            let environment = try await object(root + "environment/" + Self.segment(id), headers: headers, service: "Hoppscotch")
            list.append(["name": environment["name"] ?? "Environment", "variables": Self.parsed(environment["variables"]) ?? []])
        }
        return try InterchangeImport.hoppscotch(list)
    }

    /// Converts the CLI collection shape (JSON-string `data` and `request` fields) to an exported collection.
    static func hoppscotchCollection(_ source: [String: Any], depth: Int) -> [String: Any] {
        var result: [String: Any] = ["v": 2, "name": source["title"] as? String ?? source["name"] as? String ?? "Hoppscotch collection"]
        if let data = parsed(source["data"]) as? [String: Any] { for key in ["auth", "headers", "variables", "description", "preRequestScript", "testScript"] { if let value = data[key] { result[key] = value } } }
        result["requests"] = (source["requests"] as? [[String: Any]] ?? []).compactMap { parsed($0["request"]) as? [String: Any] }
        result["folders"] = depth < 32 ? (source["folders"] as? [[String: Any]] ?? []).map { hoppscotchCollection($0, depth: depth + 1) } : []
        return result
    }

    private static func parsed(_ value: Any?) -> Any? {
        guard let text = value as? String else { return value is NSNull ? nil : value }
        return try? JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    // MARK: Transport

    private func object(_ url: String, headers: [String: String], service: String) async throws -> [String: Any] {
        let data = try await get(url, headers: headers, service: service)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClientError("\(service) sent an unexpected response.") }
        return object
    }

    func get(_ address: String, headers: [String: String], service: String) async throws -> Data {
        guard let url = URL(string: address) else { throw ClientError("The \(service) address is invalid.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        for attempt in 0..<4 {
            try Task.checkCancellation()
            let (data, response) = try await fetch(request)
            if [429, 503].contains(response.statusCode) || (response.statusCode == 403 && response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") {
                guard attempt < 3 else { throw ClientError("\(service) is limiting requests. Try again in a few minutes\(service == "GitHub" ? ", or add a token" : "").") }
                try await pause(min(max(Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? Double(1 << attempt), 1), 30)); continue
            }
            guard (200..<300).contains(response.statusCode) else { throw Self.failure(service, status: response.statusCode, data: data) }
            guard data.count <= 40 * 1024 * 1024 else { throw ClientError("\(service) sent more than 40 MB.") }
            return data
        }
        throw ClientError("\(service) is limiting requests. Try again in a few minutes.")
    }

    static func failure(_ service: String, status: Int, data: Data) -> ClientError {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let detail = ((object?["error"] as? [String: Any])?["message"] ?? object?["message"] ?? object?["reason"]) as? String
        switch status {
        case 401: return ClientError("\(service) rejected the token. Check that it is correct and has not expired.")
        case 403: return ClientError("\(service) denied access\(detail.map { ": " + $0 } ?? ". Check the token's permissions.")")
        case 404: return ClientError("\(service) could not find it. Check the name or ID\(service == "GitHub" ? ", and add a token for a private repository" : "").")
        default: return ClientError("\(service) returned HTTP \(status)\(detail.map { ": " + $0 } ?? ".")")
        }
    }

    static func segment(_ value: String, keepSlash: Bool = false) -> String {
        var allowed = CharacterSet.urlPathAllowed; allowed.remove(charactersIn: "?#;=&+" + (keepSlash ? "" : "/"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
