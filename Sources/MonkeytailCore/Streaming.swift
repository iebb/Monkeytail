import Foundation

public struct StreamEvent: Identifiable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var direction: String, type: String, text: String
    public var binary: Data?
    public init(direction: String, type: String, text: String, binary: Data? = nil) { self.direction = direction; self.type = type; self.text = text; self.binary = binary }
}
public struct SSEParser: Sendable {
    private var data: [String] = []
    private var event = "message", identifier: String?
    private var bytes = 0
    private var firstLine = true
    public private(set) var lastEventID: String?
    public private(set) var retryMilliseconds: Int?
    public init() {}
    public mutating func consume(_ line: String) throws -> StreamEvent? {
        var line = line
        if firstLine { firstLine = false; if line.hasPrefix("\u{feff}") { line.removeFirst() } }
        guard line.utf8.count <= 64 * 1024 else { throw ClientError("SSE line exceeds 64 KB.") }
        if line.isEmpty {
            defer { data = []; event = "message"; bytes = 0; identifier = nil }
            if let identifier { lastEventID = identifier }
            guard !data.isEmpty else { return nil }
            return StreamEvent(direction: "Received", type: event, text: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var value = pair.count > 1 ? String(pair[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        switch pair[0] {
        case "data": bytes += value.utf8.count; guard bytes <= 1024 * 1024 else { throw ClientError("SSE event exceeds 1 MB.") }; data.append(value)
        case "event": event = value
        case "id": if !value.contains("\0") { identifier = value }
        case "retry": if !value.isEmpty, value.allSatisfy({ $0 >= "0" && $0 <= "9" }), let number = Int(value), number >= 0 { retryMilliseconds = min(number, 60000) }
        default: break
        }
        return nil
    }
}
public struct GraphQLField: Identifiable, Equatable, Sendable {
    public var id: String { type + "." + name }
    public var type: String, name: String, resultType: String, description: String
    public var composite: Bool
    public var arguments: [String]
}
public enum GraphQLSchema {
    public static let introspection = "query MonkeytailSchema { __schema { queryType { name } mutationType { name } subscriptionType { name } types { name kind fields { name description args { name type { kind name ofType { kind name ofType { kind name } } } } type { kind name ofType { kind name ofType { kind name } } } } } } }"
    public static func fields(_ data: Data) throws -> [GraphQLField] {
        guard data.count <= 2 * 1024 * 1024 else { throw ClientError("GraphQL schema exceeds 2 MB.") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let values = root["data"] as? [String: Any], let schema = values["__schema"] as? [String: Any], let types = schema["types"] as? [[String: Any]] else { throw ClientError("The server returned no GraphQL schema. Introspection may be disabled.") }
        func unwrap(_ value: [String: Any]) -> (String, String) {
            var value = value
            for _ in 0..<8 { if let name = value["name"] as? String { return (name, value["kind"] as? String ?? "") }; guard let next = value["ofType"] as? [String: Any] else { break }; value = next }
            return ("Unknown", "")
        }
        var fields: [GraphQLField] = []
        for type in types {
            guard let name = type["name"] as? String, !name.hasPrefix("__") else { continue }
            for field in type["fields"] as? [[String: Any]] ?? [] {
                guard let fieldName = field["name"] as? String else { continue }
                let result = unwrap(field["type"] as? [String: Any] ?? [:])
                let arguments = (field["args"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                fields.append(GraphQLField(type: name, name: fieldName, resultType: result.0, description: field["description"] as? String ?? "", composite: ["OBJECT", "INTERFACE", "UNION"].contains(result.1), arguments: arguments))
                guard fields.count <= 10000 else { throw ClientError("GraphQL schema exceeds 10,000 fields.") }
            }
        }
        return fields.sorted { $0.id < $1.id }
    }
}
