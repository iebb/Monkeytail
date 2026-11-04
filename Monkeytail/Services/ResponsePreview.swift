import Foundation
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif
import ImageIO
import UniformTypeIdentifiers

enum ResponseBodyKind: Sendable {
    case json, text, binary, image, audio, video
}

/// Publish body data and its presentation as one value, independent of view tasks.
struct PreparedResponse: Sendable {
    let response: APIResponse
    let preview: ResponsePreview

    init(response: APIResponse) {
        self.response = response
        self.preview = ResponsePreview(response: response)
    }
}

struct ResponsePreview: Sendable {
    var responseID: UUID?
    var formatted = ""
    var rawLines: [String] = []
    var prettyLines: [String] = []
    var rawColumns = 0
    var prettyColumns = 0
    var tree: JSONNode?
    var treeColumns = 0
    var kind: ResponseBodyKind = .text
    var mimeType = ""
    var fileExtension = "bin"
    var bytes: [UInt8] = []
    var image: CGImage?
    private var mediaFile: ResponseMediaFile?
    var mediaURL: URL? { mediaFile?.url }
    var mediaError: String?
    var formats: [String] {
        switch kind {
        case .json: return ["Pretty", "Tree", "Raw", "Hex", "Binary"]
        case .text: return mimeType.lowercased().contains("html") ? ["Raw", "Preview", "Hex", "Binary"] : ["Raw", "Hex", "Binary"]
        case .binary: return ["Hex", "Binary", "Raw"]
        case .image: return ["Image", "Hex", "Binary"]
        case .audio: return ["Audio", "Hex", "Binary"]
        case .video: return ["Video", "Hex", "Binary"]
        }
    }
    var defaultFormat: String { formats[0] }
    static func removeStaleMedia() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeytailResponseMedia", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               date < Date().addingTimeInterval(-86_400) { try? FileManager.default.removeItem(at: file) }
        }
    }
    init(response: APIResponse) {
        responseID = response.id
        mimeType = response.headers.first { $0.name.caseInsensitiveCompare("content-type") == .orderedSame }?.value
            .split(separator: ";", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? ""
        fileExtension = UTType(mimeType: mimeType)?.preferredFilenameExtension ?? "bin"
        bytes = Array(response.body.prefix(1_000_000))
        // Decode only a bounded thumbnail; a MIME header alone is not proof of an image.
        if (mimeType.hasPrefix("image/") || mimeType.isEmpty || mimeType == "application/octet-stream"),
           let source = CGImageSourceCreateWithData(response.body as CFData, [kCGImageSourceShouldCache: false] as CFDictionary), CGImageSourceGetCount(source) > 0,
           let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: 2048,
               kCGImageSourceShouldCacheImmediately: true
           ] as CFDictionary) {
            image = thumbnail
            kind = .image
            if let type = CGImageSourceGetType(source), let ext = UTType(type as String)?.preferredFilenameExtension { fileExtension = ext }
            return
        }
        if mimeType.hasPrefix("audio/") || mimeType.hasPrefix("video/") {
            kind = mimeType.hasPrefix("audio/") ? .audio : .video
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeytailResponseMedia", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
                try response.body.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
                mediaFile = ResponseMediaFile(url: url)
            } catch { mediaError = "Could not prepare media. Use Hex or save the response." }
            return
        }
        let text = response.body.count <= 1_000_000 ? response.text : String(decoding: response.body.prefix(1_000_000), as: UTF8.self)
        formatted = (try? JSONTools.format(text)) ?? text
        rawLines = text.components(separatedBy: "\n")
        prettyLines = formatted.components(separatedBy: "\n")
        rawColumns = rawLines.map(Self.textColumns).max() ?? 0
        prettyColumns = prettyLines.map(Self.textColumns).max() ?? 0
        tree = response.body.count <= 1_000_000 ? try? JSONTools.tree(text) : nil
        if let tree { treeColumns = Self.columns(tree, depth: 0) }
        let textual = response.body.isEmpty || (String(data: Data(bytes), encoding: .utf8) != nil && !bytes.contains { $0 < 32 && ![9, 10, 13].contains($0) })
        let declaredText = mimeType.hasPrefix("text/") || ["application/json", "application/xml", "application/javascript"].contains(mimeType) || mimeType.hasSuffix("+json") || mimeType.hasSuffix("+xml")
        kind = tree != nil ? .json : declaredText || (textual && !mimeType.hasPrefix("image/") && mimeType != "application/octet-stream") ? .text : .binary
        if fileExtension == "bin", kind == .json { fileExtension = "json" }
        if fileExtension == "bin", kind == .text { fileExtension = "txt" }
    }
    private static func columns(_ node: JSONNode, depth: Int) -> Int {
        let own = depth * 3 + textColumns(String(node.key.prefix(512))) + textColumns(String(node.summary.prefix(512))) + 8
        return max(own, node.children?.map { columns($0, depth: depth + 1) }.max() ?? 0)
    }
    private static func textColumns(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + ($1.value > 255 ? 2 : 1) }
    }
}

/// Cached media lives only as long as the prepared response (including its view).
private final class ResponseMediaFile: @unchecked Sendable {
    let url: URL
    init(url: URL) { self.url = url }
    deinit { try? FileManager.default.removeItem(at: url) }
}
