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
            if let diagnostics = response.diagnostics {
                VStack(alignment: .leading, spacing: 12) {
                    Text(diagnostics.transport).font(.subheadline.weight(.medium))
                    if let tls = diagnostics.tlsDetails {
                        DisclosureGroup("TLS certificates") {
                            Text(tlsSummary(tls)).font(.system(.caption, design: .monospaced))
                            ForEach(tls.certificates) { certificate in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(certificate.subject).font(.caption.weight(.medium))
                                    if let start = certificate.notBefore { Text("Valid from \(start.formatted())").font(.caption2) }
                                    if let end = certificate.notAfter { Text("Expires \(end.formatted())").font(.caption2).foregroundStyle(end < Date() ? Palette.error : Color.secondary) }
                                    Text("SHA-256 \(certificate.sha256)").font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                    ForEach(Array(diagnostics.transactions.enumerated()), id: \.element.id) { index, transaction in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("\(index + 1)").font(.headline); StatusBadge(status: transaction.status); Spacer(); Text(transaction.protocolName ?? "—").font(.system(.caption, design: .monospaced)) }
                            Text(transaction.request.method + " " + transaction.request.url).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            if let address = transaction.remoteAddress { Text(address).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                            HStack { if transaction.proxy { Label("Proxy", systemImage: "network") }; if transaction.reusedConnection { Label("Reused", systemImage: "arrow.triangle.2.circlepath") } }.font(.caption)
                            timing("DNS", transaction.dns); timing("Connect", transaction.connect); timing("TLS", transaction.tls)
                            timing("Upload", transaction.upload); timing("Server wait", transaction.wait); timing("Download", transaction.download); timing("Total", transaction.total)
                            DisclosureGroup("Sent headers") {
                                Text(transaction.request.headers.map { $0.name + ": " + $0.value }.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.font(.subheadline)
                            if transaction.request.bodyBytes > 0 {
                                DisclosureGroup("Sent body · \(transaction.request.bodyBytes) bytes") {
                                    if let text = String(data: transaction.request.body, encoding: .utf8) { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                                    else { ResponseBytesView(bytes: Array(transaction.request.body.prefix(4096)), totalCount: transaction.request.bodyBytes, binary: false).frame(height: 200) }
                                    if transaction.request.bodyBytes > transaction.request.body.count { Text("First 1 MB shown").font(.caption).foregroundStyle(.secondary) }
                                }.font(.subheadline)
                            }
                        }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("— means the transport did not report this phase. Headers are reported by the transport. Bodies are limited to 1 MB here.").font(.caption).foregroundStyle(.secondary)
                }.padding(12).macReadableWidth()
            } else { EmptyPanel(title: "No diagnostics") }
        }.accessibilityIdentifier("Response diagnostics")
    }
    private func tlsSummary(_ tls: TLSDetails) -> String {
        let version: String
        switch tls.version { case "0x0304": version = "TLS 1.3"; case "0x0303": version = "TLS 1.2"; default: version = tls.version ?? "—" }
        return String(localized: "Version: \(version) · Cipher: \(tls.cipher ?? "—") · ALPN: \(tls.alpn ?? "—")")
    }
    private func timing(_ name: LocalizedStringKey, _ seconds: Double?) -> some View {
        HStack { Text(name); Spacer(); (seconds.map { Text("\($0 * 1000, specifier: "%.1f") ms") } ?? Text(verbatim: "—")).monospacedDigit() }.font(.caption)
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
                    TextField("$.data.items[*].id" as String, text: $path).noCapitalization().autocorrectionDisabled().font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder).accessibilityIdentifier("JSONPath expression")
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
