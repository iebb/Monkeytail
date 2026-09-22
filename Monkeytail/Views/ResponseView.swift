import SwiftUI
import MonkeytailCore

struct ResponseView: View {
    @Bindable var store: WorkspaceStore
    let requestID: UUID
    @State private var tab = "Body"
    @State private var format = "Pretty"
    @State private var search = ""
    @State private var preview = ResponsePreview()
    @State private var copied = false
    @State private var shareURL: URL?
    @State private var showShare = false
    @FocusState private var searchFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.inputDismissal) private var inputDismissal
    @ScaledMetric(relativeTo: .footnote) private var characterWidth: CGFloat = 8
    var response: APIResponse? { store.responses[requestID] }
    private var formatted: String { preview.formatted }
    private var tree: JSONNode? { preview.tree }
    private var compactSearch: Bool { searchFocused && sizeClass != .regular }
    private static let tokenPattern = try? NSRegularExpression(pattern: #"\"(?:[^\"\\]|\\.)*\"|\b(?:true|false|null|\d+(?:\.\d+)?)\b"#)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = store.errors[requestID] {
                Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.06))
                if response != nil { Text("Previous response shown below").font(.caption).foregroundStyle(.secondary).padding(12) }
            }
            if let response {
                responseContent(response)
            } else if store.runningID == requestID {
                VStack(spacing: 12) { ProgressView(); Text("Sending…").font(.subheadline).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyPanel(title: "No response")
            }
        }
        .task(id: response?.id) { await prepare() }
        .onChange(of: inputDismissal) { _, _ in searchFocused = false }
        .sheet(isPresented: $showShare) { if let shareURL { ShareSheet(items: [shareURL]) } }
    }

    private func responseContent(_ response: APIResponse) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { status(response); timing(response); size(response) }
                    VStack(alignment: .leading, spacing: 4) { status(response); HStack { timing(response); size(response) } }
                }
                Spacer(minLength: 0)
                if store.runningID == requestID { ProgressView().controlSize(.small) }
                Button { save(response) } label: { Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44) }.accessibilityLabel("Save response")
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
                            Picker("Response format", selection: $format) { Text("Pretty").tag("Pretty"); Text("Tree").tag("Tree"); Text("Raw").tag("Raw") }.pickerStyle(.segmented)
                            Button { UIPasteboard.general.string = format == "Raw" ? response.text : formatted; copied = true } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44) }.accessibilityLabel("Copy response")
                                .disabled(format != "Raw" && preview.responseID != response.id)
                        }
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find in response", text: $search).font(.caption).textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused).submitLabel(.done).onSubmit { searchFocused = false }
                        if !search.isEmpty { Button { search = ""; searchFocused = false } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("Clear search") }
                    }.padding(.leading, 10).frame(minHeight: 44).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                }.padding(.horizontal, 12).padding(.bottom, 8)
                if preview.responseID != response.id {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if format == "Tree", let tree, search.isEmpty {
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading) { JSONTreeRow(node: tree, depth: 0) }
                                .frame(width: max(geometry.size.width - 24, CGFloat(preview.treeColumns) * characterWidth), alignment: .leading).padding(12)
                        }.defaultScrollAnchor(.topLeading)
                            .id(response.id)
                            .accessibilityIdentifier("Response tree")
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Palette.surface.opacity(0.5))
                } else {
                    codeResponse(response)
                }
            }
            Spacer(minLength: 0)
        }
    }
    private func save(_ response: APIResponse) {
        let ext = response.headers.contains { $0.name.lowercased() == "content-type" && $0.value.contains("json") } ? "json" : "txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("response-\(response.id.uuidString.prefix(8)).\(ext)")
        do { try response.body.write(to: url); shareURL = url; showShare = true } catch { store.issue = error.localizedDescription }
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

    private func codeResponse(_ response: APIResponse) -> some View {
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
    private func prepare() async {
        guard let response else { return }
        let result = await Task.detached(priority: .userInitiated) { ResponsePreview(response: response) }.value
        guard !Task.isCancelled, self.response?.id == response.id else { return }
        preview = result
        copied = false
        if tree == nil && format == "Tree" { format = "Raw" }
    }
}

private struct ResponsePreview: Sendable {
    var responseID: UUID?
    var formatted = ""
    var rawLines: [String] = []
    var prettyLines: [String] = []
    var rawColumns = 0
    var prettyColumns = 0
    var tree: JSONNode?
    var treeColumns = 0
    init() {}
    init(response: APIResponse) {
        responseID = response.id
        let text = response.body.count <= 1_000_000 ? response.text : String(decoding: response.body.prefix(1_000_000), as: UTF8.self)
        formatted = (try? JSONTools.format(text)) ?? text
        rawLines = text.components(separatedBy: "\n")
        prettyLines = formatted.components(separatedBy: "\n")
        rawColumns = rawLines.map(Self.textColumns).max() ?? 0
        prettyColumns = prettyLines.map(Self.textColumns).max() ?? 0
        tree = response.body.count <= 1_000_000 ? try? JSONTools.tree(text) : nil
        if let tree { treeColumns = Self.columns(tree, depth: 0) }
    }
    private static func columns(_ node: JSONNode, depth: Int) -> Int {
        let own = depth * 3 + textColumns(String(node.key.prefix(512))) + textColumns(String(node.summary.prefix(512))) + 8
        return max(own, node.children?.map { columns($0, depth: depth + 1) }.max() ?? 0)
    }
    private static func textColumns(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { $0 + ($1.value > 255 ? 2 : 1) }
    }
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
