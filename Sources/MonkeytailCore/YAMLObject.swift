import Foundation
import Yams

/// Converts YAML into JSON-compatible Foundation values, rejecting aliases and oversized documents.
enum YAMLObject {
    static func parse(_ text: String) throws -> Any {
        guard let node = try Yams.compose(yaml: text) else { throw ClientError("The YAML document is empty.") }
        var count = 0
        func convert(_ node: Node, depth: Int) throws -> Any {
            count += 1
            guard count < 200_000, depth < 64 else { throw ClientError("YAML exceeds the depth or node limit.") }
            switch node {
            case .scalar:
                let value = node.any
                return value is Date || value is Data ? node.string ?? "" : value
            case .sequence(let values): return try values.map { try convert($0, depth: depth + 1) }
            case .mapping(let pairs):
                var result: [String: Any] = [:]
                for pair in pairs {
                    guard let key = pair.key.string, result[key] == nil else { throw ClientError("YAML contains duplicate or non-string keys.") }
                    result[key] = try convert(pair.value, depth: depth + 1)
                }
                return result
            case .alias: throw ClientError("YAML aliases must be expanded before importing.")
            }
        }
        return try convert(node, depth: 0)
    }
}
