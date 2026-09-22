import Foundation
import CoreFoundation

public enum JSONTools {
    public static func parse(_ text: String) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) }
        catch { throw ClientError("Invalid JSON: \(error.localizedDescription)") }
    }
    public static func format(_ text: String, pretty: Bool = true) throws -> String {
        let object = try parse(text)
        let data = try JSONSerialization.data(withJSONObject: object, options: pretty ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes] : [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    public static func tree(_ text: String) throws -> JSONNode { JSONNode(key: "$", value: try parse(text), path: "$", depth: 0) }
}

public struct JSONNode: Identifiable, Sendable {
    public var id: String
    public var key: String
    public var summary: String
    public var kind: String
    public var children: [JSONNode]?
    init(key: String, value: Any, path: String, depth: Int) {
        self.id = path; self.key = key
        if let object = value as? [String: Any] {
            summary = "{\(object.count) keys}"; kind = "object"
            children = depth < 64 ? object.keys.sorted().map { JSONNode(key: $0, value: object[$0]!, path: path + "/" + $0.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1"), depth: depth + 1) } : nil
        } else if let array = value as? [Any] {
            summary = "[\(array.count) items]"; kind = "array"
            children = depth < 64 ? array.enumerated().map { JSONNode(key: "[\($0.offset)]", value: $0.element, path: path + "/\($0.offset)", depth: depth + 1) } : nil
        } else if let string = value as? String {
            summary = "\"\(string)\""; kind = "string"
        } else if value is NSNull {
            summary = "null"; kind = "null"
        } else if let number = value as? NSNumber {
            let isBool = CFGetTypeID(number) == CFBooleanGetTypeID()
            summary = isBool ? (number.boolValue ? "true" : "false") : number.stringValue
            kind = isBool ? "boolean" : "number"
        } else { summary = String(describing: value); kind = "value" }
    }
}
