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
                            Text(tlsSummary(tls)).font(.caption.monospaced())
                            ForEach(tls.certificates) { certificate in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(certificate.subject).font(.caption.weight(.medium))
                                    if let start = certificate.notBefore { Text("Valid from " + start.formatted()).font(.caption2) }
                                    if let end = certificate.notAfter { Text("Expires " + end.formatted()).font(.caption2).foregroundStyle(end < Date() ? Color.red : Color.secondary) }
                                    Text("SHA-256 " + certificate.sha256).font(.caption2.monospaced()).textSelection(.enabled)
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                    ForEach(Array(diagnostics.transactions.enumerated()), id: \.element.id) { index, transaction in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("\(index + 1) · \(transaction.status)").font(.headline); Spacer(); Text(transaction.protocolName ?? "—").font(.caption.monospaced()) }
                            Text(transaction.request.method + " " + transaction.request.url).font(.caption.monospaced()).textSelection(.enabled)
                            if let address = transaction.remoteAddress { Text(address).font(.caption.monospaced()).foregroundStyle(.secondary) }
                            HStack { if transaction.proxy { Label("Proxy", systemImage: "network") }; if transaction.reusedConnection { Label("Reused", systemImage: "arrow.triangle.2.circlepath") } }.font(.caption)
                            timing("DNS", transaction.dns); timing("Connect", transaction.connect); timing("TLS", transaction.tls)
                            timing("Upload", transaction.upload); timing("Server wait", transaction.wait); timing("Download", transaction.download); timing("Total", transaction.total)
                            DisclosureGroup("Sent headers") {
                                Text(transaction.request.headers.map { $0.name + ": " + $0.value }.joined(separator: "\n")).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.font(.subheadline)
                            if transaction.request.bodyBytes > 0 {
                                DisclosureGroup("Sent body · \(transaction.request.bodyBytes) bytes") {
                                    if let text = String(data: transaction.request.body, encoding: .utf8) { Text(text).font(.caption.monospaced()).textSelection(.enabled) }
                                    else { ResponseBytesView(bytes: Array(transaction.request.body.prefix(4096)), totalCount: transaction.request.bodyBytes, binary: false).frame(height: 200) }
                                    if transaction.request.bodyBytes > transaction.request.body.count { Text("First 1 MB shown").font(.caption).foregroundStyle(.secondary) }
                                }.font(.subheadline)
                            }
                        }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("— means the transport did not report this phase. Headers are reported by the transport. Bodies are limited to 1 MB here.").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
            } else { EmptyPanel(title: "No diagnostics") }
        }.accessibilityIdentifier("Response diagnostics")
    }
    private func tlsSummary(_ tls: TLSDetails) -> String {
        let version: String
        switch tls.version { case "0x0304": version = "TLS 1.3"; case "0x0303": version = "TLS 1.2"; default: version = tls.version ?? "—" }
        return "Version: \(version) · Cipher: \(tls.cipher ?? "—") · ALPN: \(tls.alpn ?? "—")"
    }
    private func timing(_ name: String, _ seconds: Double?) -> some View {
        HStack { Text(name); Spacer(); Text(seconds.map { String(format: "%.1f ms", $0 * 1000) } ?? "—").monospacedDigit() }.font(.caption)
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
                    TextField("$.data.items[*].id", text: $path).noCapitalization().autocorrectionDisabled().font(.body.monospaced()).textFieldStyle(.roundedBorder).accessibilityIdentifier("JSONPath expression")
                    Button("Extract") { extract() }.disabled(extracting).frame(minHeight: 44)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                ScrollView([.horizontal, .vertical]) { Text(result).font(.footnote.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.surface)
                HStack { Text("Keys, indices, and wildcards").font(.caption).foregroundStyle(.secondary); Spacer(); Button { Clipboard.copy(result )} label: { Image(systemName: "doc.on.doc").frame(width: 44, height: 44) }.accessibilityLabel("Copy extracted JSON").disabled(result.isEmpty) }
            }.padding(12).background(Palette.canvas).navigationTitle("JSONPath").inlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
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
    private var filtered: [SnapshotSummary] { store.snapshots.filter { search.isEmpty || "\($0.name) \($0.url) \($0.status)".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        NavigationStack {
            Group {
                if store.snapshots.isEmpty { EmptyPanel(title: "No snapshots", message: "Save one from a response’s menu.") }
                else {
                    List(filtered) { item in
                        NavigationLink { SnapshotDetailView(store: store, summary: item) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { MethodBadge(method: item.method); Text(item.name).font(.subheadline); Spacer(); Text(String(item.status)).font(.caption.monospaced()).foregroundStyle(Palette.mint) }
                                Text(item.url).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                Text(item.date, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }.swipeActions { Button("Delete", role: .destructive) { store.removeSnapshot(item.id) } }
                    }.searchable(text: $search, prompt: "Find snapshot")
                }
            }.navigationTitle("Snapshots").inlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct SnapshotDetailView: View {
    @Bindable var store: WorkspaceStore
    let summary: SnapshotSummary
    @State private var prepared: PreparedResponse?
    @State private var snapshot: ResponseSnapshot?
    @State private var error: String?
    var body: some View {
        Group {
            if let prepared { ResponseView(store: store, requestID: summary.requestID, savedResponse: prepared) }
            else if let error { EmptyPanel(title: error) }
            else { ProgressView() }
        }.navigationTitle(summary.name).inlineTitle()
            .alert("Could not create mock", isPresented: Binding(get: { error != nil && prepared != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .toolbar { ToolbarItem(placement: .workspaceTrailing) {
                Button("Use as mock") {
                    guard let snapshot else { return }
                    do { try store.useSnapshotAsMock(snapshot); error = nil }
                    catch { self.error = error.localizedDescription }
                }.disabled(snapshot == nil)
            } }
            .task(id: summary.id) {
                do { let snapshot = try await store.loadSnapshot(summary.id); self.snapshot = snapshot; prepared = await Task.detached { PreparedResponse(response: snapshot.response) }.value }
                catch { self.error = error.localizedDescription }
            }
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
                    ForEach(store.snapshots) { item in Text(item.name + " · " + item.date.formatted(date: .abbreviated, time: .shortened)).tag(Optional(item.id)) }
                }.pickerStyle(.menu).padding(12).accessibilityIdentifier("Snapshot baseline")
                Divider()
                if let error { EmptyPanel(title: error) }
                else if let changes {
                    if changes.isEmpty { EmptyPanel(title: "Identical status, headers, and body") }
                    else {
                        List(changes) { change in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(change.path).font(.caption.monospaced()).foregroundStyle(Palette.mint).textSelection(.enabled)
                                Text("− " + (change.before ?? "missing")).foregroundStyle(.red)
                                Text("+ " + (change.after ?? "missing")).foregroundStyle(Palette.mint)
                            }.font(.footnote.monospaced()).textSelection(.enabled)
                        }
                    }
                } else { EmptyPanel(title: store.snapshots.isEmpty ? "Save a snapshot first" : "Choose a baseline") }
            }.navigationTitle("Compare response").inlineTitle()
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
        }
    }
}
