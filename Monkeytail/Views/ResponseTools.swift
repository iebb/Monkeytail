import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct DiagnosticsView: View {
    let response: APIResponse
    var body: some View {
        ScrollView {
            if let diagnostics = response.diagnostics, let last = diagnostics.transactions.last {
                VStack(alignment: .leading, spacing: 16) {
                    TimingSummary(transaction: last, started: response.receivedAt.addingTimeInterval(-response.duration))
                    VStack(spacing: 0) {
                        InfoSection("General", summary: Text(verbatim: "\(last.protocolName ?? diagnostics.transport) · ↑ \(bytes(last.request.bodyBytes)) · ↓ \(bytes(response.body.count))"), expanded: true) {
                            InfoRow("Transport", Text(verbatim: diagnostics.transport))
                            InfoRow("Protocol", Text(verbatim: last.protocolName ?? "—"))
                            InfoRow("Status", Text(verbatim: "\(last.status) \(StatusBadge.label(last.status))"))
                            InfoRow("URL", Text(verbatim: last.request.method + " " + last.request.url), mono: true)
                            InfoRow("Sent", Text(verbatim: bytes(last.request.bodyBytes)))
                            InfoRow("Received", Text(verbatim: bytes(response.body.count)))
                        }
                        InfoSection("Connection", summary: last.remoteAddress.map { Text(verbatim: $0) }, expanded: true) {
                            InfoRow("Remote address", Text(verbatim: last.remoteAddress ?? "—"), mono: true)
                            InfoRow("Route", last.proxy ? Text("Through proxy") : Text("Direct"))
                            InfoRow("Connection", last.reusedConnection ? Text("Reused") : Text("New"))
                        }
                        if diagnostics.transactions.count > 1 {
                            InfoSection("Redirects", summary: Text("\(diagnostics.transactions.count - 1) redirects"), expanded: true) {
                                ForEach(Array(diagnostics.transactions.enumerated()), id: \.element.id) { index, hop in
                                    HStack(spacing: 8) {
                                        Text(verbatim: "\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
                                        StatusBadge(status: hop.status, showsLabel: false)
                                        Text(verbatim: hop.request.method + " " + hop.request.url).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                        Spacer(minLength: 8)
                                        if let total = hop.total { Text("\(total * 1000, specifier: "%.1f") ms").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                        if let tls = diagnostics.tlsDetails {
                            InfoSection("TLS", summary: Text(verbatim: [tlsVersion(tls), tls.alpn].compactMap { $0 }.joined(separator: " · "))) {
                                InfoRow("Version", Text(verbatim: tlsVersion(tls) ?? "—"))
                                InfoRow("Cipher", Text(verbatim: tls.cipher ?? "—"), mono: true)
                                InfoRow("ALPN", Text(verbatim: tls.alpn ?? "—"), mono: true)
                            }
                            if !tls.certificates.isEmpty {
                                InfoSection("Server certificate", summary: Text(verbatim: tls.certificates[0].subject)) {
                                    ForEach(tls.certificates) { certificate in
                                        VStack(alignment: .leading, spacing: 6) {
                                            InfoRow("Subject", Text(verbatim: certificate.subject))
                                            if let start = certificate.notBefore { InfoRow("Valid from", Text(start.formatted())) }
                                            if let end = certificate.notAfter { InfoRow("Expires", Text(end.formatted()).foregroundStyle(end < Date() ? Palette.error : Color.primary)) }
                                            InfoRow("SHA-256", Text(verbatim: certificate.sha256), mono: true)
                                        }.padding(.vertical, 4)
                                        if certificate.id != tls.certificates.last?.id { Rectangle().fill(Palette.border).frame(height: 1) }
                                    }
                                }
                            }
                        }
                        InfoSection("Sent headers", summary: Text("\(last.request.headers.count) headers")) {
                            ForEach(Array(last.request.headers.enumerated()), id: \.offset) { _, header in
                                InfoRow(header, mono: true)
                            }
                        }
                        if last.request.bodyBytes > 0 {
                            InfoSection("Sent body", summary: Text(verbatim: bytes(last.request.bodyBytes))) {
                                if let text = String(data: last.request.body, encoding: .utf8) { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                                else { ResponseBytesView(bytes: Array(last.request.body.prefix(4096)), totalCount: last.request.bodyBytes, binary: false).frame(height: 200) }
                                if last.request.bodyBytes > last.request.body.count { Text("First 1 MB shown").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border))
                    Text("Phases the transport didn't report are left out. Headers are reported by the transport. Bodies are limited to 1 MB here.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).macReadableWidth(760)
            } else if let diagnostics = response.diagnostics {
                VStack(spacing: 0) {
                    InfoSection("General", summary: Text(verbatim: diagnostics.transport), expanded: true) {
                        InfoRow("Transport", Text(verbatim: diagnostics.transport))
                        InfoRow("Status", Text(verbatim: "\(response.status) \(StatusBadge.label(response.status))"))
                        InfoRow("URL", Text(verbatim: response.url), mono: true)
                        InfoRow("Duration", Text("\(response.duration * 1000, specifier: "%.0f") ms"))
                        InfoRow("Received", Text(verbatim: bytes(response.body.count)))
                    }
                }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border))
                    .padding(12).macReadableWidth(760)
            } else { EmptyPanel(title: "No diagnostics") }
        }.accessibilityIdentifier("Response diagnostics")
    }
    private func bytes(_ count: Int) -> String {
        let formatter = ByteCountFormatter(); formatter.countStyle = .file; formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(count))
    }
    private func tlsVersion(_ tls: TLSDetails) -> String? {
        switch tls.version { case "0x0304": "TLS 1.3"; case "0x0303": "TLS 1.2"; case "0x0302": "TLS 1.1"; default: tls.version }
    }
}

/// A stacked bar of the request's phases, as in a network inspector.
private struct TimingSummary: View {
    let transaction: HTTPTransaction
    let started: Date
    private struct Phase { let name: LocalizedStringKey; let seconds: Double; let color: Color }
    private var phases: [Phase] {
        let all: [(LocalizedStringKey, Double?, Color)] = [("DNS", transaction.dns, Palette.info.opacity(0.45)), ("Connect", transaction.connect, Palette.info),
                                                          ("TLS", transaction.tls, Palette.warning), ("Sending", transaction.upload, Color.secondary.opacity(0.6)),
                                                          ("Waiting", transaction.wait, Palette.mint.opacity(0.35)), ("Receiving", transaction.download, Palette.mint)]
        return all.compactMap { name, seconds, color in seconds.map { Phase(name: name, seconds: $0, color: color) } }
    }
    var body: some View {
        let phases = phases, total = max(phases.reduce(0) { $0 + $1.seconds }, transaction.total ?? 0)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timing").font(.headline)
                if let total = transaction.total { Text("\(total * 1000, specifier: "%.1f") ms").font(.subheadline).monospacedDigit().foregroundStyle(.secondary) }
                Spacer()
                Text("Started \(started.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
            }
            if total > 0 && !phases.isEmpty {
                GeometryReader { proxy in
                    HStack(spacing: 1) {
                        ForEach(phases.indices, id: \.self) { index in
                            Rectangle().fill(phases[index].color).frame(width: max(2, (proxy.size.width - CGFloat(phases.count)) * phases[index].seconds / total))
                        }
                        Spacer(minLength: 0)
                    }
                }.frame(height: 8).background(Palette.border).clipShape(RoundedRectangle(cornerRadius: 2)).accessibilityHidden(true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(phases.indices, id: \.self) { index in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(phases[index].color).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(phases[index].name)
                            Text("\(phases[index].seconds * 1000, specifier: "%.1f") ms").monospacedDigit().foregroundStyle(.secondary)
                        }.font(.caption).accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// A flat, collapsible group of label/value rows with a one-line summary in its header.
private struct InfoSection<Content: View>: View {
    let title: LocalizedStringKey
    let summary: Text?
    @State private var expanded: Bool
    @ViewBuilder let content: () -> Content
    init(_ title: LocalizedStringKey, summary: Text? = nil, expanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.summary = summary; self.content = content; _expanded = State(initialValue: expanded)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.app(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 12).accessibilityHidden(true)
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).fixedSize()
                    if let summary, !expanded { summary.font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).padding(.leading, 8) }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 14).frame(minHeight: 40).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(.isHeader).accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
            if expanded {
                VStack(alignment: .leading, spacing: 6) { content() }.padding(.leading, 34).padding(.trailing, 14).padding(.bottom, 12)
            }
        }.overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
    }
}

private struct InfoRow: View {
    let label: Text
    let value: Text
    var mono = false
    init(_ label: LocalizedStringKey, _ value: Text, mono: Bool = false) { self.label = Text(label); self.value = value; self.mono = mono }
    /// A header line: the name is the label and the value is shown verbatim.
    init(_ header: Field, mono: Bool) { label = Text(verbatim: header.name); value = Text(verbatim: header.value); self.mono = mono }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            label.foregroundStyle(.secondary).frame(width: 128, alignment: .leading).lineLimit(2)
            value.font(mono ? .system(.subheadline, design: .monospaced) : .subheadline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.subheadline)
    }
}

struct JSONPathView: View {
    let response: APIResponse
    @Environment(\.dismiss) private var dismiss
    @State private var path = "$"
    @State private var result = ""
    @State private var error: String?
    @State private var extracting = false
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    TextField("$.data.items[*].id" as String, text: $path).noCapitalization().autocorrectionDisabled().font(.system(.body, design: .monospaced)).fieldStyle().accessibilityIdentifier("JSONPath expression")
                    Button("Extract") { extract() }.disabled(extracting).frame(minHeight: 44)
                }
                if let error { Text(error).font(.caption).foregroundStyle(Palette.error) }
                ScrollView([.horizontal, .vertical]) {
                    Group {
                        if result.isEmpty { Text("Run an expression to see the result.").foregroundStyle(.secondary) }
                        else { Text(result).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius).strokeBorder(Palette.border))
                HStack {
                    Text("Keys, indices, and wildcards").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { Clipboard.copy(result) } label: {
                        Image(systemName: "doc.on.doc").frame(width: max(32, WorkspaceMetrics.controlHeight), height: max(32, WorkspaceMetrics.controlHeight))
                    }.buttonStyle(.plain).accessibilityLabel("Copy extracted JSON").disabled(result.isEmpty)
                }
            }.padding(12).background(Palette.canvas).sheetTitle("JSONPath")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.macSheetFrame(minHeight: 400)
    }
    private func extract() {
        extracting = true
        let expression = path
        Task {
            defer { extracting = false }
            do { result = try await Task.detached { try JSONPath.extract(expression, from: response.body) }.value; error = nil }
            catch { self.error = error.localizedDescription; result = "" }
        }
    }
}

struct SnapshotsView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    #if os(macOS)
    @State private var selected: SnapshotSummary?
    @State private var selectedID: UUID?
    @FocusState private var searchFocused: Bool
    #endif
    private var filtered: [SnapshotSummary] { store.snapshots.filter { search.isEmpty || "\($0.name) \($0.url) \($0.status)".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        NavigationStack {
            Group {
                #if os(macOS)
                if let selected {
                    SnapshotDetailView(store: store, summary: selected, back: { self.selected = nil; selectedID = nil })
                } else {
                    snapshotList
                }
                #else
                snapshotList
                #endif
            }.sheetTitle("Snapshots")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.macSheetFrame()
    }

    @ViewBuilder private var snapshotList: some View {
        if store.snapshots.isEmpty {
            EmptyPanel(title: "No snapshots", message: "Save one from a response’s menu.")
        } else {
            VStack(spacing: 0) {
                #if os(macOS)
                SearchField(placeholder: "Find snapshot", text: $search, focused: $searchFocused).padding(12)
                #endif
                #if os(macOS)
                List(selection: $selectedID) {
                    ForEach(filtered) { item in snapshotRow(item).tag(item.id) }
                }.onChange(of: selectedID) { _, id in
                    if let id { selected = store.snapshots.first { $0.id == id } }
                }
                #else
                List(filtered) { item in
                    NavigationLink { SnapshotDetailView(store: store, summary: item) } label: { snapshotRow(item) }
                        .swipeActions { Button("Delete", role: .destructive) { store.removeSnapshot(item.id) } }
                }
                .searchable(text: $search, prompt: "Find snapshot")
                #endif
            }
        }
    }

    private func snapshotRow(_ item: SnapshotSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { MethodBadge(method: item.method); Text(item.name).font(.subheadline); Spacer(); StatusBadge(status: item.status, showsLabel: false) }
            Text(item.url).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            Text(item.date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
        #if os(macOS)
        .contextMenu { Button("Delete snapshot", role: .destructive) { store.removeSnapshot(item.id) } }
        #endif
    }
}

struct SnapshotDetailView: View {
    @Bindable var store: WorkspaceStore
    let summary: SnapshotSummary
    #if os(macOS)
    var back: (() -> Void)? = nil
    #endif
    @State private var prepared: PreparedResponse?
    @State private var snapshot: ResponseSnapshot?
    @State private var error: String?
    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                HStack {
                    Button { back?() } label: { Label("Snapshots", systemImage: "chevron.left") }
                        .buttonStyle(.plain)
                    Text(summary.name).font(.subheadline.weight(.semibold)).lineLimit(1).padding(.leading, 8)
                    Spacer()
                    Button("Use as mock", action: useAsMock).disabled(snapshot == nil)
                }.padding(.horizontal, 12).frame(minHeight: 38).background(Palette.canvas)
                Divider()
                responseContent
            }
            #else
            responseContent.sheetTitle(summary.name)
                .toolbar { ToolbarItem(placement: .workspaceTrailing) {
                    Button("Use as mock", action: useAsMock).disabled(snapshot == nil)
                } }
            #endif
        }.alert("Could not create mock", isPresented: Binding(get: { error != nil && prepared != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .task(id: summary.id) {
            do { let snapshot = try await store.loadSnapshot(summary.id); self.snapshot = snapshot; prepared = await Task.detached { PreparedResponse(response: snapshot.response) }.value }
            catch { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder private var responseContent: some View {
        if let prepared { ResponseView(store: store, requestID: summary.requestID, savedResponse: prepared) }
        else if let error { EmptyPanel(title: error) }
        else { ProgressView() }
    }

    private func useAsMock() {
        guard let snapshot else { return }
        do { try store.useSnapshotAsMock(snapshot); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct SnapshotCompareView: View {
    @Bindable var store: WorkspaceStore
    let current: APIResponse
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var changes: [ResponseChange]?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Compare against", selection: $selection) {
                    Text("Choose baseline").tag(UUID?.none)
                    ForEach(store.snapshots) { item in Text("\(item.name) · \(item.date.formatted(date: .abbreviated, time: .shortened))").tag(Optional(item.id)) }
                }.pickerStyle(.menu).padding(12).accessibilityIdentifier("Snapshot baseline")
                Divider()
                if let error { EmptyPanel(title: error) }
                else if let changes {
                    if changes.isEmpty { EmptyPanel(title: "Identical status, headers, and body") }
                    else {
                        List(changes) { change in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(change.path).font(.system(.caption, design: .monospaced)).foregroundStyle(Palette.mint).textSelection(.enabled)
                                Text("− \(change.before ?? String(localized: "missing"))").foregroundStyle(Palette.error)
                                Text("+ \(change.after ?? String(localized: "missing"))").foregroundStyle(Palette.mint)
                            }.font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                } else { EmptyPanel(title: store.snapshots.isEmpty ? "Save a snapshot first" : "Choose a baseline") }
            }.sheetTitle("Compare response")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .task(id: selection) {
                    changes = nil; error = nil
                    guard let selection else { return }
                    do {
                        let baseline = try await store.loadSnapshot(selection)
                        let result = try await Task.detached { try ResponseDiff.compare(baseline.response, current) }.value
                        guard !Task.isCancelled else { return }; changes = result
                    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
        }.macSheetFrame()
    }
}
