import SwiftUI
import MonkeytailCore

struct ResponseView: View {
    @Bindable var store: WorkspaceStore
    let requestID: UUID
    @State private var tab = "Body"
    @State private var format = "Pretty"
    @State private var lastKind: ResponseBodyKind?
    @State private var search = ""
    @State private var copied = false
    @State private var shareItem: ResponseShare?
    @FocusState private var searchFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.inputDismissal) private var inputDismissal
    @ScaledMetric(relativeTo: .footnote) private var characterWidth: CGFloat = 8
    var response: APIResponse? { store.responses[requestID]?.response }
    private var compactSearch: Bool { searchFocused && sizeClass != .regular }
    private static let tokenPattern = try? NSRegularExpression(pattern: #"\"(?:[^\"\\]|\\.)*\"|\b(?:true|false|null|\d+(?:\.\d+)?)\b"#)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = store.errors[requestID] {
                Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.06))
                if response != nil { Text("Previous response shown below").font(.caption).foregroundStyle(.secondary).padding(12) }
            }
            if let result = store.responses[requestID] {
                responseContent(result.response, preview: result.preview)
            } else if store.runningID == requestID {
                VStack(spacing: 12) { ProgressView(); Text("Sending…").font(.subheadline).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyPanel(title: "No response")
            }
        }
        .onChange(of: response?.id, initial: true) { _, _ in
            copied = false
            if let preview = store.responses[requestID]?.preview {
                if lastKind != preview.kind || !preview.formats.contains(format) { format = preview.defaultFormat }
                lastKind = preview.kind
            }
        }
        .onChange(of: format) { _, _ in copied = false; searchFocused = false }
        .onChange(of: inputDismissal) { _, _ in searchFocused = false }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
    }

    private func responseContent(_ response: APIResponse, preview: ResponsePreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { status(response); timing(response); size(response) }
                    VStack(alignment: .leading, spacing: 4) { status(response); HStack { timing(response); size(response) } }
                }
                Spacer(minLength: 0)
                if store.runningID == requestID { ProgressView().controlSize(.small) }
                Button { save(response, preview: preview) } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.accessibilityLabel("Save response")
            }.padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 2)
            Divider()
            if !compactSearch { PillTabs(tabs: ["Body", "Headers", "Console"], selection: $tab) }
            if tab == "Headers" {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(response.headers) { header in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(header.name).font(.system(.caption, design: .monospaced, weight: .semibold)).foregroundStyle(Palette.mint)
                                Text(header.value).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }
                }
            } else if tab == "Console" {
                if response.logs.isEmpty { EmptyPanel(title: "No logs") }
                else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(response.logs) { log in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: log.level == "pass" ? "checkmark.circle.fill" : ["fail", "error"].contains(log.level) ? "xmark.circle.fill" : "chevron.right")
                                        .foregroundStyle(["fail", "error"].contains(log.level) ? .red : Palette.mint)
                                    Text(log.message).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }.padding(12)
                    }
                }
            } else {
                VStack(spacing: 4) {
                    if !compactSearch {
                        HStack {
                            Menu {
                                ForEach(preview.formats, id: \.self) { name in
                                    Button { format = name } label: { if name == format { Label(name, systemImage: "checkmark") } else { Text(name) } }
                                        .accessibilityIdentifier("Response format " + name)
                                }
                            } label: {
                                HStack { Text(format).font(.subheadline.weight(.medium)); Image(systemName: "chevron.down").font(.caption) }.frame(minHeight: 44)
                            }.accessibilityIdentifier("Response format")
                            Spacer()
                            if !["Image", "Audio", "Video"].contains(format) {
                                Button { copy(response, preview: preview) } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44) }.accessibilityLabel("Copy response")
                            }
                        }
                    }
                    if ["Pretty", "Raw", "Tree"].contains(format) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find in response", text: $search).font(.caption).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused).submitLabel(.done).onSubmit { searchFocused = false }
                            if !search.isEmpty { Button { search = ""; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("Clear search") }
                        }.padding(.leading, 10).frame(minHeight: 44).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(.horizontal, 12).padding(.bottom, 8)
                if format == "Image", let image = preview.image {
                    ResponseImageView(image: image).id(response.id).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if format == "Audio" || format == "Video" {
                    GeometryReader { geometry in
                        ResponseMediaView(url: preview.mediaURL, error: preview.mediaError, audio: format == "Audio")
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).id(response.id)
                } else if format == "Hex" || format == "Binary" {
                    ResponseBytesView(bytes: preview.bytes, totalCount: response.body.count, binary: format == "Binary")
                        .id(ResponseScrollIdentity(responseID: response.id, format: format, search: ""))
                } else if format == "Tree", let tree = preview.tree, search.isEmpty {
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading) { JSONTreeRow(node: tree, depth: 0) }
                                .frame(width: max(geometry.size.width - 24, CGFloat(preview.treeColumns) * characterWidth), alignment: .leading).padding(12)
                        }.defaultScrollAnchor(.topLeading)
                            .id(response.id)
                            .accessibilityIdentifier("Response tree")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.surface.opacity(0.5))
                } else {
                    codeResponse(response, preview: preview)
                }
            }
            Spacer(minLength: 0)
        }
    }
    private func copy(_ response: APIResponse, preview: ResponsePreview) {
        let selectedFormat = format
        Task {
            let text = await Task.detached(priority: .userInitiated) {
                switch selectedFormat {
                case "Hex", "Binary": return ByteFormatter.dump(preview.bytes, width: selectedFormat == "Binary" ? 4 : 8, binary: selectedFormat == "Binary")
                case "Raw": return response.text
                default: return preview.formatted
                }
            }.value
            UIPasteboard.general.string = text
            if self.response?.id == response.id && format == selectedFormat { copied = true }
        }
    }
    private func save(_ response: APIResponse, preview: ResponsePreview) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("response-\(response.id.uuidString.prefix(8)).\(preview.fileExtension)")
        do { try response.body.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen]); shareItem = ResponseShare(url: url) } catch { store.issue = error.localizedDescription }
    }
    private func status(_ response: APIResponse) -> some View {
        Text("\(response.status) \(statusLabel(response.status))").font(.system(.caption, design: .monospaced, weight: .semibold)).lineLimit(1)
            .foregroundStyle(response.status < 400 ? Palette.mint : .orange).accessibilityIdentifier("Response status")
    }
    private func timing(_ response: APIResponse) -> some View { Text(String(format: "%.0f ms", response.duration * 1000)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
    private func statusLabel(_ code: Int) -> String {
        [200: "OK", 201: "Created", 202: "Accepted", 204: "No Content", 301: "Moved Permanently", 302: "Found", 304: "Not Modified", 307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict", 422: "Unprocessable Content", 429: "Too Many Requests", 500: "Internal Server Error", 502: "Bad Gateway", 503: "Service Unavailable"][code] ?? HTTPURLResponse.localizedString(forStatusCode: code).capitalized
    }
    private func size(_ response: APIResponse) -> some View { Text(ByteCountFormatter.string(fromByteCount: Int64(response.body.count), countStyle: .file)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }

    private func codeResponse(_ response: APIResponse, preview: ResponsePreview) -> some View {
        let source = format == "Raw" ? preview.rawLines : preview.prettyLines
        let columns = format == "Raw" ? preview.rawColumns : preview.prettyColumns
        let lines = source.enumerated().filter { search.isEmpty || $0.element.localizedCaseInsensitiveContains(search) }
        return GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if response.body.isEmpty { Text("Empty response body").foregroundStyle(.secondary).padding() }
                    if !search.isEmpty { Text("\(lines.count) matching lines").font(.caption).foregroundStyle(.secondary).padding(.bottom, 12) }
                    ForEach(lines, id: \.offset) { line in
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(line.offset + 1)).foregroundStyle(.tertiary).frame(minWidth: 25, alignment: .trailing).accessibilityHidden(true)
                            Text(highlight(line.element)).lineLimit(1).fixedSize(horizontal: true, vertical: false).textSelection(.enabled)
                        }.font(.system(.footnote, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if response.body.count > 1_000_000 { Text("Preview limited to 1 MB. Save the response for the full body.").font(.caption).foregroundStyle(.orange) }
                }.frame(width: max(geometry.size.width - 24, CGFloat(columns + 8) * characterWidth), alignment: .leading).padding(12)
            }
            .defaultScrollAnchor(.topLeading)
            // Formats and filters have different row sizes. Never reuse a scroll
            // offset or lazy-row measurements from the previous representation.
            .id(ResponseScrollIdentity(responseID: response.id, format: format, search: search))
            .accessibilityIdentifier("Response body")
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.surface.opacity(0.5))
    }
    private func highlight(_ line: String) -> AttributedString {
        var result = AttributedString(line)
        if line.utf8.count <= 16_384, let regex = Self.tokenPattern {
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                if let range = Range(match.range, in: line), let attributedRange = Range(range, in: result) {
                    result[attributedRange].foregroundColor = line[range].hasPrefix("\"") ? Palette.mint : Color.orange
                }
            }
        }
        return result
    }
}

private struct ResponseShare: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ResponseScrollIdentity: Hashable {
    let responseID: UUID
    let format: String
    let search: String
}

struct JSONTreeRow: View {
    let node: JSONNode
    let depth: Int
    @State private var expanded: Bool
    init(node: JSONNode, depth: Int) {
        self.node = node; self.depth = depth
        _expanded = State(initialValue: depth < 2)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                if node.children != nil {
                    Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2).frame(width: 24, height: 28) }.accessibilityLabel("Toggle \(node.key)")
                } else { Color.clear.frame(width: 24, height: 28) }
                Text(shortened(node.key)).foregroundStyle(.secondary)
                Text(shortened(node.summary)).foregroundStyle(node.kind == "string" ? Palette.mint : node.children != nil ? Color.primary : .orange).textSelection(.enabled)
            }.font(.system(.footnote, design: .monospaced)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            if expanded, let children = node.children {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(children) { child in JSONTreeRow(node: child, depth: depth + 1) }
                }.padding(.leading, 18)
            }
        }
    }
    private func shortened(_ text: String) -> String {
        text.count > 512 ? String(text.prefix(512)) + "…" : text
    }
}
