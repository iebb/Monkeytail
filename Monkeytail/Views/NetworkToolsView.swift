import SwiftUI
import UniformTypeIdentifiers
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct NetworkToolsView: View {
    let store: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = "443"
    @State private var password = ""
    @State private var choosing = false
    @State private var error: String?
    @State private var cookie = StoredCookie(name: "", value: "", domain: "")
    @State private var addingCookie = false
    @State private var originalCookieID: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Cookies · \(store.environment?.name ?? "Default")") {
                    ForEach(store.network.jar(store.workspace.selectedEnvironmentID).cookies) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name + " · " + item.domain + item.path).font(.caption.monospaced())
                            SecureField("Value", text: Binding(get: { store.network.jar(store.workspace.selectedEnvironmentID).cookies.first { $0.id == item.id }?.value ?? "" }, set: { value in mutateJar { if let index = $0.cookies.firstIndex(where: { $0.id == item.id }) { $0.cookies[index].value = value } } }))
                            HStack { if item.secure { Text("Secure") }; if item.httpOnly { Text("HttpOnly") }; if let expires = item.expires { Text(expires, format: .dateTime) }; Spacer(); Button("Edit") { cookie = item; originalCookieID = item.id; addingCookie = true }; Button("Remove", role: .destructive) { mutateJar { $0.cookies.removeAll { $0.id == item.id } } } }.font(.caption)
                        }
                    }
                    Button("Add cookie") { cookie = StoredCookie(name: "", value: "", domain: ""); originalCookieID = nil; addingCookie = true }
                    if addingCookie {
                        TextField("Name", text: $cookie.name); SecureField("Value", text: $cookie.value); TextField("Exact domain", text: $cookie.domain); TextField("Path", text: $cookie.path)
                        Toggle("HTTPS only", isOn: $cookie.secure)
                        Toggle("HttpOnly", isOn: $cookie.httpOnly)
                        Toggle("Exact host only", isOn: $cookie.hostOnly)
                        Toggle("Session cookie", isOn: Binding(get: { cookie.expires == nil }, set: { cookie.expires = $0 ? nil : Date().addingTimeInterval(86400) }))
                        if cookie.expires != nil { DatePicker("Expiry", selection: Binding(get: { cookie.expires ?? Date() }, set: { cookie.expires = $0 })) }
                        Button("Save cookie") {
                            do {
                                let valid = try cookie.validated()
                                var jar = store.network.jar(store.workspace.selectedEnvironmentID)
                                jar.cookies.removeAll { $0.id == originalCookieID || $0.id == valid.id }; jar.cookies.append(valid)
                                try store.network.setJar(jar, environment: store.workspace.selectedEnvironmentID)
                                addingCookie = false; error = nil
                            } catch { self.error = error.localizedDescription }
                        }
                        Button("Cancel") { addingCookie = false }
                    }
                    Button("Clear cookies", role: .destructive) { mutateJar { $0.cookies = [] } }.disabled(store.network.jar(store.workspace.selectedEnvironmentID).cookies.isEmpty)
                }
                Section("Client certificates · System TLS") {
                    ForEach(store.network.identities) { item in
                        HStack { VStack(alignment: .leading) { Text(item.host + ":" + String(item.port)); Text(item.filename).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Remove", role: .destructive) { do { try store.network.removeIdentity(item.id) } catch { self.error = error.localizedDescription } } }
                    }
                    TextField("Exact hostname", text: $host); TextField("Port", text: $port).numberInput(); SecureField("PKCS#12 password", text: $password)
                    Button("Import .p12 / .pfx") { choosing = true }.accessibilityIdentifier("Import client certificate")
                }
                Section("Local mock server") {
                    if let address = store.mockServer.address { Text(address).font(.footnote.monospaced()).textSelection(.enabled); Button("Copy URL") { Clipboard.copy(address) }; Button("Stop") { store.mockServer.stop() } }
                    else { Button("Start") {
                        do {
                            let requests = try store.workspace.collections.flatMap(\.requests).filter { $0.mock?.enabled == true }.map { request in
                                var resolved = try store.effective(request); resolved.request.url = try RequestBuilder.resolve(resolved.request.url, variables: resolved.variables); return resolved.request
                            }
                            store.mockServer.start(requests, variables: [:])
                        } catch { self.error = error.localizedDescription }
                    } }
                    Text("Loopback only. Runs while Monkeytail is active. Routes use enabled mocks and match method + path.").font(.caption).foregroundStyle(.secondary)
                    if let error = store.mockServer.error { Text(error).foregroundStyle(.red) }
                }
                if let error { Section { Text(error).font(.caption).foregroundStyle(.red) } }
                if let issue = store.network.issue { Section { Text(issue).font(.caption).foregroundStyle(.red) } }
            }.noCapitalization().autocorrectionDisabled().navigationTitle("Cookies & certificates").inlineTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .fileImporter(isPresented: $choosing, allowedContentTypes: [.data]) { result in
                    Task {
                        do {
                            let url = try result.get(), hostname = host.trimmingCharacters(in: .whitespaces), portNumber = Int(port) ?? 0, passphrase = password
                            let data = try await Task.detached {
                                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 5 * 1024 * 1024 else { throw ClientError("Identity exceeds 5 MB.") }; return try Data(contentsOf: url)
                            }.value
                            try store.network.addIdentity(.init(host: hostname, port: portNumber, filename: url.lastPathComponent, data: data, password: passphrase)); password = ""; error = nil
                        } catch { self.error = error.localizedDescription }
                    }
                }
        }.frame(idealWidth: 650, idealHeight: 650)
    }
    private func mutateJar(_ body: (inout CookieJar) -> Void) {
        var jar = store.network.jar(store.workspace.selectedEnvironmentID); body(&jar)
        do { try store.network.setJar(jar, environment: store.workspace.selectedEnvironmentID) } catch { self.error = error.localizedDescription }
    }
}
