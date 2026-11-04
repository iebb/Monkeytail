import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct ResponseView: View {
    @Bindable var store: WorkspaceStore
    let requestID: UUID
    var savedResponse: PreparedResponse? = nil
    @State private var pathTool = false
    @State private var comparing = false
    @State private var tab = "Body"
    @State private var format = "Pretty"
    @State private var lastKind: ResponseBodyKind?
    @State private var search = ""
    @State private var copied = false
    @State private var shareItem: ResponseShare?
    @FocusState private var searchFocused: Bool
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.inputDismissal) private var inputDismissal
    @ScaledMetric(relativeTo: .footnote) private var characterWidth: CGFloat = 8
    private var result: PreparedResponse? { savedResponse ?? store.responses[requestID] }
    var response: APIResponse? { result?.response }
    private var compactSearch: Bool {
        #if os(macOS)
        false
        #else
        searchFocused && sizeClass != .regular
        #endif
    }
    private static let tokenPattern = try? NSRegularExpression(pattern: #"\"(?:[^\"\\]|\\.)*\"|\b(?:true|false|null|\d+(?:\.\d+)?)\b"#)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
            if result == nil {
                Text("Response").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).padding(.horizontal, 12)
                    .background(Palette.canvas)
                Divider()
            }
            #else
            if verticalSizeClass != .compact && !compactSearch {
                PanelHeading(title: "Response", symbol: "arrow.down.right", detail: response == nil ? "Awaiting request" : "")
            }
            #endif
            if let error = store.errors[requestID] {
                Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.red).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.06))
                if let certificate = store.untrustedCertificates[requestID] {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SHA-256 \(certificate.sha256)").font(.system(.caption2, design: .monospaced)).textSelection(.enabled).foregroundStyle(.secondary)
                        Text("Trust only a certificate you recognise, such as a local development server. Only this exact certificate is accepted, and only for \(certificate.host):\(String(certificate.port)). Every other host is still verified. Remove it in Network settings.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { store.trustCertificate(for: requestID) } label: { Label("Trust for \(certificate.host):\(String(certificate.port)) and resend", systemImage: "checkmark.shield") }
                            .buttonStyle(.bordered).accessibilityIdentifier("Trust certificate")
                    }.padding(.horizontal, 16).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
                }
                if response != nil { Text("Previous response shown below").font(.caption).foregroundStyle(.secondary).padding(12) }
            }
            if let result = result {
                responseContent(result.response, preview: result.preview)
            } else if store.runningID == requestID {
                VStack(spacing: 12) { ProgressView(); Text("Sending…").font(.subheadline).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.errors[requestID] != nil {
                EmptyPanel(title: "Request failed", message: "Review the error above, adjust your request, and try again.", symbol: "exclamationmark.circle")
            } else {
                #if os(macOS)
                EmptyPanel(title: "No response yet", message: "Send a request to see the result.", symbol: "arrow.down.left")
                #else
                EmptyPanel(title: "Ready when you are", message: "Send your request to inspect the response, headers, and timing here.", symbol: "arrow.up.arrow.down")
                #endif
            }
        }
        .background(Palette.surface)
        .onChange(of: response?.id, initial: true) { _, _ in
            copied = false
            if let preview = result?.preview {
                if lastKind != preview.kind || !preview.formats.contains(format) { format = preview.defaultFormat }
                lastKind = preview.kind
            }
        }
        .onChange(of: format) { _, _ in copied = false; searchFocused = false }
        .onChange(of: inputDismissal) { _, _ in searchFocused = false }
        .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
        .sheet(isPresented: $pathTool) { if let response { JSONPathView(response: response) } }
        .sheet(isPresented: $comparing) { if let response { SnapshotCompareView(store: store, current: response) } }
    }

    private func responseContent(_ response: APIResponse, preview: ResponsePreview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                #if os(macOS)
                Text("Response").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader).padding(.trailing, 8)
                #endif
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { status(response); timing(response); size(response) }
                    VStack(alignment: .leading, spacing: 4) { status(response); HStack { timing(response); size(response) } }
                }
                Spacer(minLength: 0)
                if store.runningID == requestID { ProgressView().controlSize(.small) }
                Menu {
                    Button("Export body", systemImage: "square.and.arrow.up") { save(response, preview: preview) }
                    if savedResponse == nil { Button("Save snapshot", systemImage: "camera") { store.saveSnapshot(requestID: requestID, response: response) } }
                    Button("Compare snapshot", systemImage: "arrow.left.arrow.right") { comparing = true }
                    if preview.kind == .json { Button("Extract JSONPath", systemImage: "line.3.horizontal.decrease") { pathTool = true } }
                } label: { Image(systemName: "ellipsis").frame(width: max(32, WorkspaceMetrics.controlHeight), height: max(32, WorkspaceMetrics.controlHeight)) }.borderlessMenu().accessibilityLabel("Response actions")
            }.padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 2)
                #if os(macOS)
                .background(Palette.canvas)
                #endif
            Divider()
            if !compactSearch { PillTabs(tabs: ["Body", "Headers", "Console", "Tests", "Diagnostics"], selection: $tab) }
            if tab == "Tests" { TestResultsView(results: store.testResults[requestID] ?? []) } else if tab == "Diagnostics" { DiagnosticsView(response: response) } else if tab == "Headers" {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(response.headers) { header in
                            #if os(macOS)
                            HStack(alignment: .top, spacing: 16) {
                                Text(header.name).font(.system(.caption, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(Palette.mint).frame(width: 180, alignment: .leading).textSelection(.enabled)
                                Text(header.value).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.horizontal, 12).padding(.vertical, 8).macReadableWidth()
                            #else
                            VStack(alignment: .leading, spacing: 4) {
                                Text(header.name).font(.system(.caption, design: .monospaced, weight: .semibold)).foregroundStyle(Palette.mint)
                                Text(header.value).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            #endif
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
                #if os(macOS)
                HStack(spacing: 10) {
                    Menu {
                        ForEach(preview.formats, id: \.self) { name in
                            Button { format = name } label: { if name == format { Label(name, systemImage: "checkmark") } else { Text(name) } }
                                .accessibilityIdentifier("Response format " + name)
                        }
                    } label: {
                        HStack(spacing: 5) { Text(format); Image(systemName: "chevron.down").font(.caption2) }
                            .font(.caption.weight(.medium)).frame(minHeight: 30)
                    }.borderlessMenu().accessibilityIdentifier("Response format")
                    if ["Pretty", "Raw", "Tree"].contains(format) {
                        SearchField(placeholder: "Find in response", text: $search, focused: $searchFocused, canvas: true)
                            .frame(minWidth: 80, idealWidth: 220, maxWidth: 220)
                    }
                    Spacer()
                    if !["Image", "Audio", "Video"].contains(format) {
                        Button { copy(response, preview: preview) } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 30, height: 30) }
                            .buttonStyle(.plain).accessibilityLabel("Copy response")
                    }
                }.padding(.horizontal, 12).padding(.vertical, 3).background(Palette.surface)
                Divider()
                #else
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
                            }.borderlessMenu().accessibilityIdentifier("Response format")
                            Spacer()
                            if !["Image", "Audio", "Video"].contains(format) {
                                Button { copy(response, preview: preview) } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44) }.accessibilityLabel("Copy response")
                            }
                        }
                    }
                    if ["Pretty", "Raw", "Tree"].contains(format) {
                        SearchField(placeholder: "Find in response", text: $search, focused: $searchFocused, canvas: true)
                    }
                }.padding(.horizontal, 12).padding(.bottom, 8)
                #endif
                if format == "Image", let image = preview.image {
                    ResponseImageView(image: image).id(response.id).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if format == "Audio" || format == "Video" {
                    GeometryReader { geometry in
                        ResponseMediaView(url: preview.mediaURL, error: preview.mediaError, audio: format == "Audio")
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).id(response.id)
                } else if format == "Preview" {
                    HTMLPreviewView(html: String(decoding: response.body.prefix(1_000_000), as: UTF8.self)).id(response.id).frame(maxWidth: .infinity, maxHeight: .infinity)
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
                case "Raw", "Preview": return response.text
                default: return preview.formatted
                }
            }.value
            Clipboard.copy(text)
            if self.response?.id == response.id && format == selectedFormat { copied = true }
        }
    }
    private func save(_ response: APIResponse, preview: ResponsePreview) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("response-\(response.id.uuidString.prefix(8)).\(preview.fileExtension)")
        do { try response.body.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen]); shareItem = ResponseShare(url: url) } catch { store.issue = error.localizedDescription }
    }
    private func status(_ response: APIResponse) -> some View {
        StatusBadge(status: response.status).accessibilityIdentifier("Response status")
    }
    private func timing(_ response: APIResponse) -> some View { Text(String(format: "%.0f ms", response.duration * 1000)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
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
                    result[attributedRange].foregroundColor = line[range].hasPrefix("\"") ? Palette.mint : Palette.warning
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
                Text(shortened(node.summary)).foregroundStyle(node.kind == "string" ? Palette.mint : node.children != nil ? Color.primary : Palette.warning).textSelection(.enabled)
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
