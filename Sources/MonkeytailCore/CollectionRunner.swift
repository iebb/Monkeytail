import Foundation

public struct RunnerTest: Codable, Equatable, Sendable {
    public var name: String
    public var passed: Bool
    public init(name: String, passed: Bool) { self.name = name; self.passed = passed }
}

public struct RunnerResult: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var iteration: Int
    public var requestID: UUID
    public var name: String
    public var method: String
    public var url: String
    public var status: Int?
    public var duration: Double = 0
    public var tests: [RunnerTest] = []
    public var error: String?
    public var skipped = false
    public var bodyPreview: String?
    public var passed: Bool { error == nil && tests.allSatisfy(\.passed) }
    public init(iteration: Int, request: APIRequest) {
        self.iteration = iteration; requestID = request.id; name = request.name; method = request.method; url = request.url
    }
}

public struct RunnerReport: Codable, Equatable, Sendable {
    public var name: String
    public var environment: String?
    public var iterations: Int
    public var startedAt = Date()
    public var finishedAt: Date?
    public var results: [RunnerResult] = []
    public init(name: String, environment: String?, iterations: Int) { self.name = name; self.environment = environment; self.iterations = iterations }
    public var sentCount: Int { results.filter { !$0.skipped }.count }
    public var failedCount: Int { results.filter { !$0.passed }.count }
    public var testCount: Int { results.reduce(0) { $0 + $1.tests.count } }
    public var failedTestCount: Int { results.reduce(0) { $0 + $1.tests.filter { !$0.passed }.count } }
    public var totalDuration: Double { results.reduce(0) { $0 + $1.duration } }
}

public enum RunnerDirective: Equatable, Sendable { case stop, jump(String) }

public enum RunnerPlan {
    /// Requests in sidebar order: each folder's subfolders, then its requests, depth first.
    public static func requests(in collection: RequestCollection, folderID: UUID? = nil) -> [APIRequest] {
        let folders = collection.folders ?? []
        var visited = Set<UUID>()
        func walk(_ parent: UUID?) -> [APIRequest] {
            if let parent, !visited.insert(parent).inserted { return [] }
            return folders.filter { $0.parentID == parent }.flatMap { walk($0.id) } + collection.requests.filter { $0.folderID == parent }
        }
        return walk(folderID).filter { $0.transport != .websocket && $0.transport != .sse }
    }

    /// Returns nil when the iteration ends.
    public static func nextIndex(after index: Int, directive: RunnerDirective?, plan: [APIRequest]) -> Int? {
        switch directive {
        case nil: return index + 1 < plan.count ? index + 1 : nil
        case .stop: return nil
        case .jump(let target): return plan.firstIndex { $0.name == target || $0.id.uuidString.caseInsensitiveCompare(target) == .orderedSame }
        }
    }
}

public enum RunnerData {
    public static let maximumRows = 1000
    public static let maximumBytes = 10 * 1024 * 1024

    /// Parses a JSON array of objects or a CSV file with a header row.
    public static func parse(_ data: Data, filename: String = "") throws -> [[String: String]] {
        guard data.count <= maximumBytes else { throw ClientError("Data files must be smaller than 10 MB.") }
        guard var text = String(data: data, encoding: .utf8) else { throw ClientError("Data files must be UTF-8 text.") }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let rows = filename.lowercased().hasSuffix(".json") || trimmed.hasPrefix("[") ? try json(trimmed) : try csv(text)
        guard !rows.isEmpty else { throw ClientError("The data file has no rows.") }
        guard rows.count <= maximumRows else { throw ClientError("Data files are limited to \(maximumRows) rows.") }
        return rows
    }

    private static func json(_ text: String) throws -> [[String: String]] {
        guard let array = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) as? [Any] else { throw ClientError("JSON data files must contain an array of objects.") }
        return try array.enumerated().map { index, element in
            guard let object = element as? [String: Any] else { throw ClientError("JSON data row \(index + 1) is not an object.") }
            return object.mapValues { value in
                switch value {
                case let string as String: return string
                case let number as NSNumber: return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
                case is NSNull: return ""
                default: return (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
                }
            }
        }
    }

    private static func csv(_ text: String) throws -> [[String: String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, quotedField = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" { field.append("\""); index += 1 } else { quoted = false }
                } else { field.append(character) }
            } else if character == "\"" && field.isEmpty && !quotedField {
                quoted = true; quotedField = true
            } else if character == "," {
                row.append(field); field = ""; quotedField = false
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                row.append(field); rows.append(row); row = []; field = ""; quotedField = false
            } else { field.append(character) }
            index += 1
        }
        guard !quoted else { throw ClientError("The CSV file has an unterminated quoted value.") }
        if !field.isEmpty || !row.isEmpty || quotedField { row.append(field); rows.append(row) }
        rows.removeAll { $0 == [""] }
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces) }) else { return [] }
        guard !header.contains(where: \.isEmpty), Set(header).count == header.count else { throw ClientError("CSV header names must be non-empty and unique.") }
        return try rows.dropFirst().enumerated().map { offset, values in
            guard values.count <= header.count else { throw ClientError("CSV row \(offset + 2) has more values than the header.") }
            return Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0 < values.count ? values[$0] : "") })
        }
    }
}

public enum RunnerReportFormat: String, CaseIterable, Identifiable, Sendable {
    case json = "JSON", junit = "JUnit XML"
    public var id: String { rawValue }
    public var fileExtension: String { self == .json ? "json" : "xml" }
}

public enum RunnerReportCodec {
    /// Reports include sent URLs, statuses, timings, and test names. Response bodies are omitted.
    public static func encode(_ report: RunnerReport, format: RunnerReportFormat) throws -> Data {
        switch format {
        case .json:
            var value = report
            for index in value.results.indices { value.results[index].bodyPreview = nil }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(value)
        case .junit:
            return Data(junit(report).utf8)
        }
    }

    private static func junit(_ report: RunnerReport) -> String {
        let errors = report.results.filter { $0.error != nil }.count
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<testsuites name=\"\(escape(report.name))\" tests=\"\(report.testCount + errors)\" failures=\"\(report.failedTestCount)\" errors=\"\(errors)\" time=\"\(seconds(report.totalDuration))\">\n"
        let timestamp = ISO8601DateFormatter().string(from: report.startedAt)
        for result in report.results {
            let failures = result.tests.filter { !$0.passed }.count, error = result.error == nil ? 0 : 1
            xml += "  <testsuite name=\"\(escape("Iteration \(result.iteration) · \(result.name)"))\" tests=\"\(result.tests.count + error)\" failures=\"\(failures)\" errors=\"\(error)\" skipped=\"\(result.skipped ? 1 : 0)\" time=\"\(seconds(result.duration))\" timestamp=\"\(timestamp)\">\n"
            let classname = escape(report.name + "." + result.name)
            if result.skipped { xml += "    <testcase name=\"\(escape(result.name))\" classname=\"\(classname)\" time=\"0.000\"><skipped/></testcase>\n" }
            if let message = result.error { xml += "    <testcase name=\"\(escape(result.name))\" classname=\"\(classname)\" time=\"\(seconds(result.duration))\"><error message=\"\(escape(message))\"/></testcase>\n" }
            for test in result.tests {
                xml += "    <testcase name=\"\(escape(test.name))\" classname=\"\(classname)\" time=\"0.000\">"
                xml += test.passed ? "</testcase>\n" : "<failure message=\"\(escape(test.name))\"/></testcase>\n"
            }
            xml += "  </testsuite>\n"
        }
        return xml + "</testsuites>\n"
    }

    private static func seconds(_ value: Double) -> String { String(format: "%.3f", value) }
    private static func escape(_ value: String) -> String {
        String(value.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || $0.value >= 32 }.map(Character.init))
            .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;")
    }
}
