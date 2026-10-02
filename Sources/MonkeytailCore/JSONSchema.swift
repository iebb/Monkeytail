import Foundation
import CoreFoundation

/// Bounded validator for the portable JSON Schema subset used by imported API contracts.
public enum JSONSchema {
    public static func validate(_ data: Data, schema: String) throws -> [String] {
        guard data.count <= 2 * 1024 * 1024, schema.utf8.count <= 1024 * 1024 else { throw ClientError("Schema validation is limited to 2 MB bodies and 1 MB schemas.") }
        let root = try JSONSerialization.jsonObject(with: Data(schema.utf8), options: [.fragmentsAllowed])
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var errors: [String] = [], nodes = 0
        func equal(_ a: Any, _ b: Any) -> Bool {
            guard let x = try? JSONSerialization.data(withJSONObject: a, options: [.fragmentsAllowed, .sortedKeys]), let y = try? JSONSerialization.data(withJSONObject: b, options: [.fragmentsAllowed, .sortedKeys]) else { return false }; return x == y
        }
        func number(_ v: Any) -> Double? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }; return n.doubleValue }
        func typeMatches(_ type: String, _ v: Any) -> Bool {
            switch type {
            case "null": return v is NSNull
            case "boolean": return (v as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            case "number": return number(v) != nil
            case "integer": return number(v).map { $0.rounded() == $0 } ?? false
            case "string": return v is String
            case "array": return v is [Any]
            case "object": return v is [String: Any]
            default: return false
            }
        }
        func resolve(_ ref: String) throws -> Any {
            guard ref.hasPrefix("#/") else { throw ClientError("Only local JSON Schema references are supported.") }
            var value = root
            for part in ref.dropFirst(2).components(separatedBy: "/") {
                let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
                guard let next = (value as? [String: Any])?[key] else { throw ClientError("Missing schema reference: \(ref)") }; value = next
            }
            return value
        }
        func walk(_ v: Any, _ raw: Any, _ path: String, _ depth: Int) throws {
            nodes += 1
            guard depth < 48, nodes < 20000 else { throw ClientError("Schema exceeds the depth or node limit.") }
            guard errors.count < 100 else { return }
            if let bool = raw as? NSNumber, CFGetTypeID(bool) == CFBooleanGetTypeID() { if !bool.boolValue { errors.append("\(path): disallowed by schema") }; return }
            guard let s = raw as? [String: Any] else { throw ClientError("A schema must be an object or boolean.") }
            let unsupported = ["$dynamicRef", "patternProperties", "unevaluatedProperties", "unevaluatedItems", "contains", "dependentSchemas", "if", "then", "else", "prefixItems"]
            if let key = unsupported.first(where: { s[$0] != nil }) { throw ClientError("Unsupported JSON Schema keyword: \(key)") }
            if let ref = s["$ref"] as? String { try walk(v, resolve(ref), path, depth + 1) }
            if s["nullable"] as? Bool == true && v is NSNull { return }
            if let types = (s["type"] as? String).map({ [$0] }) ?? s["type"] as? [String], !types.contains(where: { typeMatches($0, v) }) {
                errors.append("\(path): expected \(types.joined(separator: " or "))"); return
            }
            if s["nullable"] as? Bool == true && v is NSNull { return }
            if let values = s["enum"] as? [Any], !values.contains(where: { equal($0, v) }) { errors.append("\(path): value is outside enum") }
            if let constant = s["const"], !equal(v, constant) { errors.append("\(path): expected constant") }
            if let all = s["allOf"] as? [Any] { for item in all { try walk(v, item, path, depth + 1) } }
            for key in ["anyOf", "oneOf", "not"] {
                let choices: [Any] = key == "not" ? s[key].map { [$0] } ?? [] : s[key] as? [Any] ?? []
                if choices.isEmpty { continue }
                var passed = 0
                for choice in choices { let previous = errors; try walk(v, choice, path, depth + 1); if errors == previous { passed += 1 }; errors = previous }
                if (key == "anyOf" && passed == 0) || (key == "oneOf" && passed != 1) || (key == "not" && passed != 0) { errors.append("\(path): failed \(key)") }
            }
            if let object = v as? [String: Any] {
                let properties = s["properties"] as? [String: Any] ?? [:]
                for key in s["required"] as? [String] ?? [] where object[key] == nil { errors.append("\(path).\(key): required") }
                for (key, value) in object {
                    if let schema = properties[key] { try walk(value, schema, path + "." + key, depth + 1) }
                    else if let extra = s["additionalProperties"] { try walk(value, extra, path + "." + key, depth + 1) }
                }
                if let min = s["minProperties"] as? Int, object.count < min { errors.append("\(path): too few properties") }
                if let max = s["maxProperties"] as? Int, object.count > max { errors.append("\(path): too many properties") }
            }
            if let array = v as? [Any] {
                if let schema = s["items"] { for (index, value) in array.enumerated() { try walk(value, schema, "\(path)[\(index)]", depth + 1) } }
                if let min = s["minItems"] as? Int, array.count < min { errors.append("\(path): too few items") }
                if let max = s["maxItems"] as? Int, array.count > max { errors.append("\(path): too many items") }
                if s["uniqueItems"] as? Bool == true {
                    let encoded = try array.map { try JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed, .sortedKeys]) }
                    if Set(encoded).count != array.count { errors.append("\(path): duplicate items") }
                }
            }
            if let text = v as? String {
                if let min = s["minLength"] as? Int, text.unicodeScalars.count < min { errors.append("\(path): string too short") }
                if let max = s["maxLength"] as? Int, text.unicodeScalars.count > max { errors.append("\(path): string too long") }
                if let pattern = s["pattern"] as? String {
                    guard pattern.utf8.count <= 512, text.utf8.count <= 4096 else { throw ClientError("Schema pattern input is too large.") }
                    // Limit patterns to a simple linear subset; Foundation has no regex deadline.
                    let repetitions = pattern.filter { "*+{".contains($0) }.count
                    guard !pattern.contains("("), !pattern.contains("|"), !pattern.contains("\\1"), repetitions <= 1 else { throw ClientError("Schema pattern uses unsupported groups, alternation, or repeated quantifiers.") }
                    let regex = try NSRegularExpression(pattern: pattern)
                    if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil { errors.append("\(path): pattern mismatch") }
                }
            }
            if let value = number(v) {
                if let min = s["minimum"] as? Double, value < min { errors.append("\(path): below minimum") }
                if let max = s["maximum"] as? Double, value > max { errors.append("\(path): above maximum") }
                if let min = s["exclusiveMinimum"] as? Double, value <= min { errors.append("\(path): below exclusive minimum") }
                if let max = s["exclusiveMaximum"] as? Double, value >= max { errors.append("\(path): above exclusive maximum") }
                if let multiple = s["multipleOf"] as? Double, multiple > 0, abs(value / multiple - (value / multiple).rounded()) > 1e-9 { errors.append("\(path): not a multiple") }
            }
        }
        try walk(value, root, "$", 0); return errors
    }
}
public enum ResponseTests {
    public static func evaluate(_ tests: [ResponseAssertion], response: APIResponse, schema: String? = nil) -> [AssertionResult] {
        tests.filter(\.enabled).map { test in
            var passed = false, message = ""
            do {
                switch test.kind {
                case .status: passed = Int(test.expected) == response.status; message = "Received \(response.status)"
                case .duration: guard let max = Double(test.expected), max.isFinite, max >= 0 else { throw ClientError("Enter milliseconds.") }; passed = response.duration * 1000 <= max; message = String(format: "%.1f ms", response.duration * 1000)
                case .header: let value = response.headers.filter { $0.name.caseInsensitiveCompare(test.path) == .orderedSame }.map(\.value).joined(separator: ", "); passed = response.headers.contains { $0.name.caseInsensitiveCompare(test.path) == .orderedSame } && value == test.expected; message = value.isEmpty ? "Header missing or empty" : value
                case .json:
                    let extracted = try JSONPath.extract(test.path, from: response.body)
                    let expected = try JSONSerialization.jsonObject(with: Data(test.expected.utf8), options: [.fragmentsAllowed])
                    let actual = try JSONSerialization.jsonObject(with: Data(extracted.utf8), options: [.fragmentsAllowed])
                    passed = try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys, .fragmentsAllowed]) == JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys, .fragmentsAllowed]); message = extracted
                case .schema: let errors = try JSONSchema.validate(response.body, schema: test.expected.isEmpty ? schema ?? "{}" : test.expected); passed = errors.isEmpty; message = errors.isEmpty ? "Schema valid" : errors.prefix(5).joined(separator: "; ")
                }
            } catch { message = error.localizedDescription }
            return AssertionResult(id: test.id, name: test.name, passed: passed, message: String(message.prefix(2000)))
        }
    }
    public static func javascript(_ test: ResponseAssertion) -> String {
        func quote(_ value: String) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), as: UTF8.self) }
        let check: String
        switch test.kind {
        case .status: check = "response.status === Number(\(quote(test.expected)))"
        case .duration: check = "response.duration * 1000 <= Number(\(quote(test.expected)))"
        case .header: check = "Object.entries(response.headers).filter(([k]) => k.toLowerCase() === \(quote(test.path.lowercased()))).map(([,v]) => v).join(', ') === \(quote(test.expected))"
        case .json:
            guard let path = try? JSONPath.javascript(test.path) else { return "// Invalid JSONPath. Fix the path before generating a script." }
            check = "((canonical) => canonical(\(path)) === canonical(JSON.parse(\(quote(test.expected)))))((value) => JSON.stringify(value, (_key, v) => v && typeof v === 'object' && !Array.isArray(v) ? Object.keys(v).sort().reduce((o, k) => (o[k] = v[k], o), {}) : v))"
        case .schema: return "// JSON Schema assertions run in Monkeytail's native validator."
        }
        return "test(\(quote(test.name)), () => assert(\(check), 'Assertion failed'));"
    }
}
