import Foundation

/// Postman's bulk-edit format: one `name:value` per line, `//` disables a row.
public enum FieldBulkText {
    public static func encode(_ fields: [Field]) -> String {
        fields.filter { !$0.name.isEmpty || !$0.value.isEmpty }.map { ($0.enabled ? "" : "//") + $0.name + ":" + $0.value }.joined(separator: "\n")
    }
    /// Keeps identity and sensitivity of rows whose names already exist.
    public static func decode(_ text: String, existing: [Field] = []) -> [Field] {
        var unused = existing
        return text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces), enabled = true
            if line.hasPrefix("//") { enabled = false; line = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            guard !line.isEmpty else { return nil }
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let name = pair[0].trimmingCharacters(in: .whitespaces), value = pair.count > 1 ? pair[1].trimmingCharacters(in: .whitespaces) : ""
            var field = unused.firstIndex(where: { $0.name == name }).map { unused.remove(at: $0) } ?? Field(name, value)
            field.value = value; field.enabled = enabled
            return field
        }
    }
}
