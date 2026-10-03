import SwiftUI
import UniformTypeIdentifiers
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct CollectionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct TransferView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "Import"
    @State private var source = ""
    @State private var format: ExportFormat = .postman
    @State private var error: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var document: CollectionDocument?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Transfer mode", selection: $mode) { Text("Import").tag("Import"); Text("Export").tag("Export") }.pickerStyle(.segmented)
                    if mode == "Import" {
                        Text("cURL or collection JSON").font(.subheadline.weight(.medium))
                        CodeEditor(text: $source, label: "Import content", minimumHeight: 240)
                        HStack {
                            PasteButton(payloadType: String.self) { strings in source = strings.first ?? "" }.labelStyle(.titleAndIcon)
                            Spacer()
                            Button { importing = true } label: { Label("Choose file", systemImage: "doc") }.buttonStyle(.bordered)
                        }
                        DisclosureGroup("Supported formats") {
                            Text("cURL, Postman v2/v2.1, Insomnia v4 JSON, and Monkeytail. Imports append to your workspace. Imported scripts start disabled.")
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.subheadline)
                    } else {
                        Picker("File format", selection: $format) { ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(store.workspace.collections.count) collections · \(store.requestCount) requests")
                            Text(format == .postman ? "Active environment as collection variables" : "All environments").foregroundStyle(.secondary)
                        }.font(.subheadline).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                        Text("Exports include credentials. Monkeytail includes file bytes; other formats reference filenames.")
                            .font(.caption).foregroundStyle(.secondary)
                        if format != .native, store.workspace.collections.contains(where: { $0.requests.contains(where: { $0.impersonation != nil }) }) {
                            Text("Browser profiles restore in Monkeytail. Postman and Insomnia don’t apply them.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button {
                            do { document = CollectionDocument(data: try CollectionCodec.encode(store.workspace, format: format)); exporting = true }
                            catch { self.error = error.localizedDescription }
                        } label: { Label("Export workspace", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 5) }.buttonStyle(.borderedProminent)
                    }
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red) }
                }.padding(12)
            }.background(Palette.canvas).navigationTitle("Import & export").inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if mode == "Import" {
                            Button("Import", action: performImport)
                                .disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("Confirm import")
                        }
                    }
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .data]) { result in
                    do {
                        let url = try result.get()
                        let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 40 * 1024 * 1024 else { throw ClientError("Import files must be smaller than 40 MB.") }
                        source = try String(contentsOf: url, encoding: .utf8); error = nil
                    } catch { self.error = error.localizedDescription }
                }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "monkeytail-\(format == .postman ? "postman_collection" : format == .insomnia ? "insomnia" : "workspace")") { result in
                    if case .failure(let failure) = result { error = failure.localizedDescription }
                }
        }
    }
    private func performImport() {
        do { try store.importContent(source); dismiss() } catch { self.error = error.localizedDescription }
    }
}

struct EnvironmentView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingID: UUID?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Picker("Environment", selection: $editingID) {
                            Text("Choose environment").tag(UUID?.none)
                            ForEach(store.workspace.environments) { Text($0.name).tag(Optional($0.id)) }
                        }
                        Spacer()
                        Button {
                            let environment = APIEnvironment(name: "New environment", variables: [Field("base_url", "https://api.example.com")])
                            store.workspace.environments.append(environment); editingID = environment.id
                        } label: { Label("New", systemImage: "plus") }
                    }
                    if let index = store.workspace.environments.firstIndex(where: { $0.id == editingID }) {
                        TextField("Environment name", text: $store.workspace.environments[index].name).font(.headline).textFieldStyle(.roundedBorder)
                        FieldEditor(fields: $store.workspace.environments[index].variables, name: "Variable")
                        Text("Use {{name}} in requests.").font(.caption).foregroundStyle(.secondary)
                        Button {
                            store.workspace.selectedEnvironmentID = editingID
                        } label: { Label(store.workspace.selectedEnvironmentID == editingID ? "Active environment" : "Use this environment", systemImage: store.workspace.selectedEnvironmentID == editingID ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        Button("Delete environment", role: .destructive) {
                            if store.workspace.selectedEnvironmentID == editingID { store.workspace.selectedEnvironmentID = nil }
                            store.workspace.environments.removeAll { $0.id == editingID }; editingID = store.workspace.environments.first?.id
                        }.font(.footnote).padding(.top, 16)
                    }
                    Text("Exports include values.").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
            }.background(Palette.canvas).navigationTitle("Environments").inlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .onAppear { editingID = store.workspace.selectedEnvironmentID ?? store.workspace.environments.first?.id }
        }
    }
}

struct SettingsView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Proxy", selection: $store.workspace.proxy.kind) { ForEach(ProxyKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    if store.workspace.proxy.kind != .system {
                        TextField("Hostname or IP address", text: $store.workspace.proxy.host).urlInput()
                        TextField("Port", text: $store.workspace.proxy.port).numberInput()
                        TextField("Username (optional)", text: $store.workspace.proxy.username)
                        SecureField("Password (optional)", text: $store.workspace.proxy.password)
                    }
                } header: { Text("Connection") }
                Section {
                    Toggle("iCloud sync", isOn: Binding(get: { store.syncEnabled }, set: { store.setSyncEnabled($0) }))
                    if store.syncEnabled {
                        Toggle("Include credentials", isOn: Binding(get: { store.syncCredentials }, set: { store.setSyncCredentials($0) }))
                        HStack {
                            Text(store.syncStatus).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Sync now") { Task { await store.synchronize() } }.disabled(store.syncing)
                        }
                    }
                    Toggle("Use Keychain", isOn: Binding(get: { store.useKeychain }, set: { store.setUseKeychain($0) }))
                        .help("When off, credentials are stored with the local workspace.")
                    Toggle("Hide in client code", isOn: Binding(get: { store.hideCredentials }, set: { store.setHideCredentials($0) }))
                    DisclosureGroup("Storage & limits") {
                        LabeledContent("Storage", value: store.syncEnabled ? "Local + iCloud" : "Local")
                        LabeledContent("History", value: "50 requests")
                        LabeledContent("Response", value: "20 MB")
                        LabeledContent("Scripts", value: "3 seconds")
                        LabeledContent("Snapshots", value: "50 / 60 MB")
                        LabeledContent("TLS certificates", value: "Verified")
                        Button("Clear request history", role: .destructive) { store.clearHistory() }
                            .disabled(store.history.isEmpty)
                    }
                } header: { Text("Workspace") }
                Section {
                    LabeledContent("Monkeytail", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3")
                    HStack(spacing: 20) {
                        Link("Privacy", destination: URL(string: "https://docs.kitta.co/monkeytail/privacy/")!)
                        Link("Support", destination: URL(string: "https://docs.kitta.co/monkeytail/support/")!)
                        Spacer(minLength: 0)
                    }
                    NavigationLink("Licenses") {
                        ScrollView { Text(BrowserImpersonation.thirdPartyNotices).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                            .navigationTitle("Licenses")
                    }
                } header: { Text("About") } footer: { Text("Kitta Co · No data collected") }
            }.formStyle(.grouped).toggleStyle(.switch).noCapitalization().autocorrectionDisabled()
                .navigationTitle("Settings").inlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) } }
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
        .tint(Palette.mint)
    }
}

struct HistoryView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if store.history.isEmpty { EmptyPanel(title: "No history") }
                else {
                    List(store.history) { entry in
                        Button { store.restore(entry); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { MethodBadge(method: entry.request.method); Text(entry.request.name).font(.subheadline.weight(.medium)); Spacer(); Text(entry.status.map(String.init) ?? "Error").font(.system(.caption, design: .monospaced)).foregroundStyle(entry.status != nil ? Palette.mint : .red) }
                                Text(entry.request.url).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                                Text(entry.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                                if let error = entry.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
                            }.padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                }
            }.background(Palette.canvas).navigationTitle("Request history").inlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
