import Foundation

/// Postman-style `{{name}}` references and completion for text fields.
public enum VariableHints {
    public struct Reference: Equatable, Sendable {
        public var name: String
        public var value: String?
        public var isDynamic: Bool { name.hasPrefix("$") }
        public var isResolved: Bool { value != nil || (isDynamic && DynamicVariables.names.contains(name)) }
    }
    private static let reference = try! NSRegularExpression(pattern: #"\{\{\s*(\$?[\w.\-]+)\s*\}\}"#)
    private static let pending = try! NSRegularExpression(pattern: #"\{\{\s*(\$?[\w.\-]*)$"#)
    /// Unique references in order of appearance.
    public static func references(in text: String, variables: [String: String]) -> [Reference] {
        var seen = Set<String>()
        return reference.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let name = String(text[range])
            return seen.insert(name).inserted ? Reference(name: name, value: variables[name]) : nil
        }
    }
    /// The partial name after an unclosed `{{` at the end of the text.
    public static func pendingName(in text: String) -> String? {
        guard let match = pending.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    /// Defined names first, then dynamic variables; prefix matches before substring matches.
    public static func suggestions(for partial: String, variables: [String: String], limit: Int = 8) -> [String] {
        let names = variables.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending } + DynamicVariables.names.filter { variables[$0] == nil }
        guard !partial.isEmpty else { return Array(names.prefix(limit)) }
        let prefixed = names.filter { $0.range(of: partial, options: [.caseInsensitive, .anchored]) != nil }
        let contained = names.filter { !prefixed.contains($0) && $0.range(of: partial, options: .caseInsensitive) != nil }
        return Array((prefixed + contained).prefix(limit))
    }
    /// Replaces the trailing unclosed `{{partial` with `{{name}}`.
    public static func complete(_ text: String, with name: String) -> String {
        guard let match = pending.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range, in: text) else { return text }
        return text.replacingCharacters(in: range, with: "{{\(name)}}")
    }
}
