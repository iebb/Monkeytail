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
    @State private var chosenFile: ImportFile?
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
                        Text("cURL, collection, or .http file").font(.subheadline.weight(.medium))
                        CodeEditor(text: $source, label: "Import content", minimumHeight: 240)
                        HStack {
                            PasteButton(payloadType: String.self) { strings in source = strings.first ?? "" }.labelStyle(.titleAndIcon)
                            Spacer()
                            Button { importing = true } label: { Label("Choose files or folder", systemImage: "folder") }.buttonStyle(.bordered)
                        }
                        DisclosureGroup("Supported formats") {
                            Text("cURL; Postman v1, v2 and v2.1 collections, environments, globals and data dumps; Insomnia v4 JSON/YAML and v5 YAML; Bruno folders, .bru files and JSON; Hoppscotch; Thunder Client; HAR; .http files (REST Client and JetBrains); OpenAPI and Swagger; and Monkeytail. Choose a Bruno collection folder to import it with its folders and environments. Imports append to your workspace, and imported scripts run when you send.")
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.subheadline)
                    } else {
                        Picker("File format", selection: $format) { ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(store.workspace.collections.count) \(store.workspace.collections.count == 1 ? "collection" : "collections") · \(store.requestCount) \(store.requestCount == 1 ? "request" : "requests")")
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
            }.background(Palette.canvas).sheetTitle("Import & export")
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
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .yaml, .plainText, .data, .folder], allowsMultipleSelection: true) { result in
                    do {
                        let urls = try result.get()
                        let files = try urls.flatMap(ImportFileReader.read)
                        if urls.count == 1, let url = urls.first, !url.hasDirectoryPath, let file = files.first {
                            chosenFile = file; source = file.text; error = nil
                        } else {
                            try store.importFiles(files, name: urls.count == 1 ? urls[0].lastPathComponent : "Imported files"); dismiss()
                        }
                    } catch { self.error = error.localizedDescription }
                }
                .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "monkeytail-\(format == .postman ? "postman_collection" : format == .insomnia ? "insomnia" : "workspace")") { result in
                    if case .failure(let failure) = result { error = failure.localizedDescription }
                }
        }.macSheetFrame(minHeight: 420)
    }
    private func performImport() {
        do {
            if let chosenFile, chosenFile.text == source { try store.importFiles([chosenFile], name: (chosenFile.path as NSString).deletingPathExtension) } else { try store.importContent(source) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

/// Reads chosen files, or every importable file inside a chosen folder, with paths relative to it.
enum ImportFileReader {
    static let extensions: Set = ["bru", "json", "yaml", "yml", "http", "rest", "har", "txt", "curl", "sh"]
    static func read(_ url: URL) throws -> [ImportFile] {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        guard url.hasDirectoryPath else {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 40 * 1024 * 1024 else { throw ClientError("Import files must be smaller than 40 MB.") }
            return [ImportFile(path: url.lastPathComponent, text: try String(contentsOf: url, encoding: .utf8))]
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [ImportFile] = [], total = 0
        let root = url.standardizedFileURL.path.hasSuffix("/") ? url.standardizedFileURL.path : url.standardizedFileURL.path + "/"
        for case let item as URL in enumerator {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values.isDirectory == true { if ["node_modules", ".git"].contains(item.lastPathComponent) { enumerator.skipDescendants() }; continue }
            guard extensions.contains(item.pathExtension.lowercased()), let text = try? String(contentsOf: item, encoding: .utf8) else { continue }
            total += values.fileSize ?? 0
            guard files.count < 5000, total <= 40 * 1024 * 1024 else { throw ClientError("Folders can contain at most 5,000 files and 40 MB to import.") }
            let path = item.standardizedFileURL.path
            files.append(ImportFile(path: path.hasPrefix(root) ? String(path.dropFirst(root.count)) : item.lastPathComponent, text: text))
        }
        guard !files.isEmpty else { throw ClientError("The folder contains no importable files.") }
        return files
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
                            .disabled(store.workspace.selectedEnvironmentID == editingID)
                        Button("Delete environment", role: .destructive) {
                            if store.workspace.selectedEnvironmentID == editingID { store.workspace.selectedEnvironmentID = nil }
                            store.workspace.environments.removeAll { $0.id == editingID }; editingID = store.workspace.environments.first?.id
                        }.font(.footnote).padding(.top, 16)
                    }
                    Divider().padding(.vertical, 8)
                    Text("Globals").font(.headline)
                    Text("Available in every environment. Collection, environment, and request variables with the same name take precedence. Scripts can change them with pm.globals.set.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    FieldEditor(fields: Binding(get: { store.workspace.globals ?? [] }, set: { store.workspace.globals = $0 }), name: "Global")
                    Text("Exports include values.").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
            }.background(Palette.canvas).sheetTitle("Environments")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .onAppear { editingID = store.workspace.selectedEnvironmentID ?? store.workspace.environments.first?.id }
        }.macSheetFrame()
    }
}

struct SettingsView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @State private var showingLicenses = false
    #endif
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
                    #if os(macOS)
                    Button("Licenses") { showingLicenses = true }
                    #else
                    NavigationLink("Licenses") {
                        ScrollView { Text(BrowserImpersonation.thirdPartyNotices).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
                            .navigationTitle("Licenses")
                    }
                    #endif
                } header: { Text("About") } footer: { Text("Kitta Co · No data collected") }
            }.formStyle(.grouped).toggleStyle(.switch).noCapitalization().autocorrectionDisabled()
                .navigationTitle("Settings").inlineTitle()
                #if !os(macOS)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) } }
                #endif
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        .sheet(isPresented: $showingLicenses) { LicenseSheet() }
        #endif
        .tint(Palette.mint)
    }
}

#if os(macOS)
private struct LicenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Text(BrowserImpersonation.thirdPartyNotices)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.sheetTitle("Licenses")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.macSheetFrame(minHeight: 450)
    }
}
#endif

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
            }.background(Palette.canvas).sheetTitle("Request history")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.macSheetFrame()
    }
}
