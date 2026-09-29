import Foundation

public enum JSONPath {
    private enum Segment { case key(String), index(Int), wildcard }
    /// Supports $, .key, ['key'], ["key"], [index], and .* / [*]. Filters and recursive descent are intentionally rejected.
    public static func extract(_ expression: String, from data: Data) throws -> String {
        guard data.count <= 2 * 1024 * 1024 else { throw ClientError("JSONPath is limited to 2 MB JSON bodies.") }
        let chars = Array(expression.trimmingCharacters(in: .whitespacesAndNewlines))
        guard chars.first == "$" else { throw ClientError("Start JSONPath with $.") }
        var i = 1, segments: [Segment] = [], many = false
        while i < chars.count {
            guard segments.count < 64 else { throw ClientError("JSONPath is too deep.") }
            if chars[i] == "." {
                i += 1
                if i < chars.count, chars[i] == "*" { segments.append(.wildcard); many = true; i += 1; continue }
                let start = i
                while i < chars.count, chars[i] != ".", chars[i] != "[" { i += 1 }
                let key = String(chars[start..<i])
                guard !key.isEmpty, !key.contains(where: { $0.isWhitespace }) else { throw ClientError("Use .key or ['key']; recursive descent is unsupported.") }
                segments.append(.key(key))
            } else if chars[i] == "[" {
                i += 1
                guard i < chars.count else { throw ClientError("Unclosed JSONPath bracket.") }
                if chars[i] == "'" || chars[i] == "\"" {
                    let quote = chars[i]; i += 1; var key = "", closed = false
                    while i < chars.count {
                        if chars[i] == quote { closed = true; i += 1; break }
                        if chars[i] == "\\" { i += 1; guard i < chars.count else { break } }
                        key.append(chars[i]); i += 1
                    }
                    guard closed, i < chars.count, chars[i] == "]" else { throw ClientError("Unclosed JSONPath key.") }
                    segments.append(.key(key)); i += 1
                } else {
                    let start = i
                    while i < chars.count, chars[i] != "]" { i += 1 }
                    guard i < chars.count else { throw ClientError("Unclosed JSONPath bracket.") }
                    let token = String(chars[start..<i]); i += 1
                    if token == "*" { segments.append(.wildcard); many = true }
                    else if let index = Int(token), index >= 0 { segments.append(.index(index)) }
                    else { throw ClientError("Use [index], ['key'], or [*]. Filters and slices are unsupported.") }
                }
            } else { throw ClientError("Invalid JSONPath. Use $, .key, [index], or [*].") }
        }
        var values: [Any] = [try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])]
        for segment in segments {
            var next: [Any] = []
            for value in values {
                switch segment {
                case .key(let key): if let value = (value as? [String: Any])?[key] { next.append(value) }
                case .index(let index): if let array = value as? [Any], array.indices.contains(index) { next.append(array[index]) }
                case .wildcard:
                    if let array = value as? [Any] { next += array }
                    else if let object = value as? [String: Any] { next += object.keys.sorted().compactMap { object[$0] } }
                }
                guard next.count <= 5000 else { throw ClientError("JSONPath matches more than 5,000 values.") }
            }
            values = next
        }
        guard !values.isEmpty else { throw ClientError("No values match this path.") }
        let object: Any = many ? values : values[0]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }
}

public struct ResponseChange: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public var path: String
    public var before: String?
    public var after: String?
}

public enum ResponseDiff {
    public static func compare(_ before: APIResponse, _ after: APIResponse) throws -> [ResponseChange] {
        var changes: [ResponseChange] = []
        if before.status != after.status { changes.append(ResponseChange(path: "Status", before: String(before.status), after: String(after.status))) }
        func headers(_ values: [Field]) -> [String: String] {
            values.reduce(into: [:]) { result, field in
                let key = field.name.lowercased(); result[key] = result[key].map { $0 + "\n" + field.value } ?? field.value
            }
        }
        let old = headers(before.headers), new = headers(after.headers)
        for key in Set(old.keys).union(new.keys).sorted() where old[key] != new[key] { changes.append(ResponseChange(path: "Header: " + key, before: old[key], after: new[key])) }
        guard before.body != after.body else { return changes }
        guard max(before.body.count, after.body.count) <= 2 * 1024 * 1024 else {
            changes.append(ResponseChange(path: "Body (JSON diff limited to 2 MB)", before: "\(before.body.count) bytes", after: "\(after.body.count) bytes")); return changes
        }
        func render(_ value: Any) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
        if let lhs = try? JSONSerialization.jsonObject(with: before.body, options: [.fragmentsAllowed]), let rhs = try? JSONSerialization.jsonObject(with: after.body, options: [.fragmentsAllowed]) {
            var visited = 0
            func walk(_ lhs: Any?, _ rhs: Any?, path: String, depth: Int) throws {
                visited += 1
                guard visited <= 10000, depth <= 64, changes.count < 2000 else { throw ClientError("Diff exceeds the 2,000-change or 10,000-node limit.") }
                if let a = lhs as? [String: Any], let b = rhs as? [String: Any] {
                    for key in Set(a.keys).union(b.keys).sorted() { try walk(a[key], b[key], path: path + "[" + render(key) + "]", depth: depth + 1) }
                } else if let a = lhs as? [Any], let b = rhs as? [Any] {
                    for index in 0..<max(a.count, b.count) { try walk(a.indices.contains(index) ? a[index] : nil, b.indices.contains(index) ? b[index] : nil, path: path + "[\(index)]", depth: depth + 1) }
                } else {
                    let a = lhs.map(render), b = rhs.map(render)
                    if a != b { changes.append(ResponseChange(path: path, before: a.map { String($0.prefix(4096)) }, after: b.map { String($0.prefix(4096)) })) }
                }
            }
            try walk(lhs, rhs, path: "$", depth: 0)
        } else {
            let common = min(before.body.count, after.body.count)
            let offset = (0..<common).first { before.body[$0] != after.body[$0] } ?? common
            changes.append(ResponseChange(path: "Body: first difference at byte \(offset)", before: "\(before.body.count) bytes", after: "\(after.body.count) bytes"))
        }
        return changes
    }
}

public struct ResponseSnapshot: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var requestID: UUID
    public var method: String
    public var url: String
    public var response: APIResponse
    public init(request: APIRequest, response: APIResponse) {
        name = request.name; requestID = request.id; method = request.method; url = response.url; self.response = response
    }
}
public struct SnapshotSummary: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var requestID: UUID
    public var method: String
    public var url: String
    public var status: Int
    public var date: Date
    public var bytes: Int
    public init(_ snapshot: ResponseSnapshot, bytes: Int) {
        id = snapshot.id; name = snapshot.name; requestID = snapshot.requestID; method = snapshot.method; url = snapshot.url; status = snapshot.response.status; date = snapshot.response.receivedAt; self.bytes = bytes
    }
}
