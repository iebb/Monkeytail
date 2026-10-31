import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct TestsEditor: View {
    @Binding var request: APIRequest
    private var tests: Binding<[ResponseAssertion]> { Binding(get: { request.assertions ?? [] }, set: { request.assertions = $0 }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(tests) { $test in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("Enabled", isOn: $test.enabled).labelsHidden()
                        TextField("Test name", text: $test.name)
                        Button(role: .destructive) { request.assertions?.removeAll { $0.id == test.id } } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.accessibilityLabel("Remove test")
                    }
                    Picker("Check", selection: $test.kind) { ForEach(AssertionKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                    if test.kind == .header || test.kind == .json { TextField(test.kind == .json ? "JSONPath, e.g. $.id" : "Header name", text: $test.path) }
                    if test.kind == .schema { CodeEditor(text: $test.expected, label: "Test JSON schema", minimumHeight: 120) }
                    else { TextField(test.kind == .duration ? "Maximum milliseconds" : test.kind == .json ? "Expected JSON value, e.g. 42 or \"ok\"" : "Expected value", text: $test.expected) }
                    if test.kind != .schema {
                        Button("Add as editable script") { request.postScript += "\n" + ResponseTests.javascript(test); request.scriptsEnabled = true }.font(.caption).frame(minHeight: 44)
                    }
                }.padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            }
            Button { request.assertions = (request.assertions ?? []) + [ResponseAssertion()] } label: { Label("Add test", systemImage: "plus") }.frame(minHeight: 44).accessibilityIdentifier("Add response test")
            DisclosureGroup("Request schema") { CodeEditor(text: Binding(get: { request.requestSchema ?? "" }, set: { request.requestSchema = $0 }), label: "Request JSON schema", minimumHeight: 180) }
            DisclosureGroup("Response schema") {
                CodeEditor(text: Binding(get: { request.responseSchema ?? "" }, set: { request.responseSchema = $0 }), label: "Response JSON schema", minimumHeight: 180)
                Button("Add schema assertion") { var test = ResponseAssertion(); test.kind = .schema; test.name = "Response schema"; test.expected = request.responseSchema ?? "{}"; request.assertions = (request.assertions ?? []) + [test] }.frame(minHeight: 44)
            }
        }.textFieldStyle(.roundedBorder).noCapitalization().autocorrectionDisabled()
    }
}
struct TestResultsView: View {
    let results: [AssertionResult]
    var body: some View {
        List {
            if results.isEmpty { Text("Add checks in Request → Tests.").foregroundStyle(.secondary) }
            ForEach(results) { result in
                VStack(alignment: .leading, spacing: 6) {
                    Label(result.name, systemImage: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(result.passed ? Palette.mint : Color.red)
                    Text(result.message).font(.caption.monospaced()).textSelection(.enabled)
                }.padding(.vertical, 4)
            }
        }.scrollContentBackground(.hidden).accessibilityIdentifier("Response test results")
    }
}
struct MockEditor: View {
    @Binding var request: APIRequest
    let response: APIResponse?
    @State private var error: String?
    private var mock: Binding<MockResponse> { Binding(get: { request.mock ?? MockResponse() }, set: { request.mock = $0 }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Offline mock", isOn: mock.enabled).accessibilityIdentifier("Enable offline mock")
            Button("Use current response") {
                guard let response, let text = String(data: response.body, encoding: .utf8), response.body.count <= 2 * 1024 * 1024 else { error = "Choose a UTF-8 response up to 2 MB."; return }
                var value = MockResponse(); value.status = response.status; value.headers = response.headers.filter { !["content-length", "transfer-encoding", "content-encoding", "connection"].contains($0.name.lowercased()) }; value.body = text; value.enabled = true; request.mock = value
            }.disabled(response == nil).frame(minHeight: 44)
            Stepper("Status: \(mock.wrappedValue.status)", value: mock.status, in: 100...599)
            Stepper("Delay: \(mock.wrappedValue.delayMilliseconds) ms", value: mock.delayMilliseconds, in: 0...30000, step: 100)
            TextField("Simulated error (optional)", text: Binding(get: { request.mock?.simulatedError ?? "" }, set: { if request.mock == nil { request.mock = MockResponse() }; request.mock?.simulatedError = $0.isEmpty ? nil : $0 }))
            FieldEditor(fields: mock.headers)
            CodeEditor(text: mock.body, label: "Mock response body", minimumHeight: 200)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}
struct GraphQLEditor: View {
    @Binding var request: APIRequest
    let store: WorkspaceStore
    @State private var fields: [GraphQLField] = []
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?
    private var graph: Binding<GraphQLRequest> { Binding(get: { request.graphql ?? GraphQLRequest() }, set: { request.graphql = $0 }) }
    private var operations: [String] {
        let regex = try! NSRegularExpression(pattern: #"\b(?:query|mutation|subscription)\s+([A-Za-z_]\w*)"#)
        let query = graph.wrappedValue.query
        return regex.matches(in: query, range: NSRange(query.startIndex..., in: query)).compactMap { Range($0.range(at: 1), in: query).map { String(query[$0]) } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Operation", selection: graph.operationName) { Text("Automatic").tag(""); ForEach(operations, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
            CodeEditor(text: graph.query, label: "GraphQL query", minimumHeight: 220)
            Text("Variables").font(.caption).foregroundStyle(.secondary)
            CodeEditor(text: graph.variables, label: "GraphQL variables", minimumHeight: 140)
            HStack { Button("Load schema") { load() }.disabled(loading); if loading { ProgressView() }; Spacer(); Text("\(fields.count) fields").font(.caption).foregroundStyle(.secondary) }.frame(minHeight: 44)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if !fields.isEmpty {
                TextField("Find a field or type", text: $search).textFieldStyle(.roundedBorder)
                ForEach(Array(fields.filter { search.isEmpty || $0.id.localizedCaseInsensitiveContains(search) }.prefix(100))) { field in
                    Button {
                        var query = graph.wrappedValue.query
                        let insertion = "\n  " + field.name + (field.composite ? " { __typename }" : "") + "\n"
                        if let close = query.lastIndex(of: "}") { query.insert(contentsOf: insertion, at: close) } else { query += insertion }
                        graph.wrappedValue.query = query
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field.id + " → " + field.resultType).font(.caption.monospaced())
                            if !field.arguments.isEmpty { Text("Arguments: " + field.arguments.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary) }
                            if !field.description.isEmpty { Text(field.description).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func load() {
        loading = true; error = nil; let original = request
        Task {
            defer { loading = false }
            do {
                var resolved = try store.effective(original); resolved.request.method = "POST"; resolved.request.transport = .graphql; resolved.request.bodyKind = .none; resolved.request.requestSchema = nil
                var graph = GraphQLRequest(); graph.query = GraphQLSchema.introspection; resolved.request.graphql = graph
                var built = try RequestBuilder.build(resolved.request, variables: resolved.variables)
                if resolved.request.cookieJarEnabled == true, let url = built.url { let value = store.network.jar(store.workspace.selectedEnvironmentID).header(for: url); if !value.isEmpty { built.setValue(value, forHTTPHeaderField: "Cookie") } }
                let response = try await HTTPClient(followRedirects: resolved.request.followRedirects).send(built, proxy: store.workspace.proxy, impersonation: resolved.request.impersonation, tls: store.network.identity(for: built.url))
                guard (200...299).contains(response.status) else { throw ClientError("Schema request returned HTTP \(response.status).") }
                fields = try await Task.detached { try GraphQLSchema.fields(response.body) }.value
            } catch { self.error = error.localizedDescription }
        }
    }
}
@MainActor struct LiveView: View {
    let store: WorkspaceStore
    let requestID: UUID
    @State private var live = LiveSession()
    @State private var message = ""
    @State private var binary = false
    @State private var filter = ""
    @State private var selected: UUID?
    private var request: APIRequest? { store.request(requestID) }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(live.connected || live.connecting ? "Disconnect" : "Connect") {
                    if live.connected || live.connecting { live.disconnect() }
                    else if let request {
                        do {
                            var resolved = try store.effective(request)
                            if resolved.request.auth.kind == .oauth2, let oauth = resolved.request.auth.oauth, let expires = oauth.expiresAt, expires < Date().addingTimeInterval(30), !oauth.refreshToken.isEmpty {
                                Task {
                                    do { resolved.request.auth.oauth = try await OAuthAuthorizer().refresh(oauth, proxy: store.workspace.proxy); store.persistAuth(resolved.request.auth, for: request); connect(resolved) }
                                    catch { live.error = error.localizedDescription }
                                }
                            } else { connect(resolved) }
                        }
                        catch { live.error = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("Connect stream")
                Toggle("Reconnect", isOn: $live.reconnect).font(.caption)
                Spacer(); Button("Clear") { live.clear() }
            }.frame(minHeight: 44)
            if let error = live.error { Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
            TextField("Filter messages", text: $filter).textFieldStyle(.roundedBorder)
            List(live.events.filter { filter.isEmpty || $0.text.localizedCaseInsensitiveContains(filter) || $0.type.localizedCaseInsensitiveContains(filter) }) { event in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(event.direction + " · " + event.type).font(.caption.weight(.medium)); Spacer(); Text(event.date, format: .dateTime.hour().minute().second()).font(.caption2).foregroundStyle(.secondary) }
                    if let data = event.binary { Text(ByteFormatter.dump(Array(data.prefix(4096)), width: 8, binary: false)).font(.caption.monospaced()).textSelection(.enabled) }
                    else { Text((try? JSONTools.format(event.text)) ?? event.text).font(.caption.monospaced()).textSelection(.enabled) }
                }.padding(.vertical, 3)
            }.scrollContentBackground(.hidden).accessibilityIdentifier("Stream messages")
            if request?.transport == .websocket {
                HStack {
                    TextField(binary ? "Hex bytes" : "Message", text: $message, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder).accessibilityIdentifier("WebSocket message")
                    Menu { Toggle("Binary (hex)", isOn: $binary); Button("Ping") { live.ping() } } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                    Button("Send") { live.send(message, binary: binary) }.disabled(!live.connected).frame(minHeight: 44)
                }
            }
        }.padding(12).background(Palette.canvas).onDisappear { live.disconnect() }
    }
    private func connect(_ resolved: ResolvedRequest) {
        do {
            let raw = try RequestBuilder.resolve(resolved.request.url, variables: resolved.variables).replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(of: "ws://", with: "http://")
            let url = URL(string: raw), enabled = resolved.request.cookieJarEnabled == true
            if enabled, let issue = store.network.issue { throw ClientError(issue) }
            live.connect(resolved.request, variables: resolved.variables, proxy: store.workspace.proxy, tls: try store.network.identity(for: url), cookies: enabled ? store.network.jar(store.workspace.selectedEnvironmentID) : nil)
        } catch { live.error = error.localizedDescription }
    }
}
struct CodeExportView: View {
    let store: WorkspaceStore
    let request: APIRequest
    @State private var language: CodeLanguage = .swift
    @State private var code = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack { Picker("Language", selection: $language) { ForEach(CodeLanguage.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu); Toggle("Hide credentials", isOn: Binding(get: { store.hideCredentials }, set: { store.setHideCredentials($0) })) }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                ScrollView([.horizontal, .vertical]) { Text(code).font(.footnote.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.background(Palette.surface)
                HStack { Button("Copy") { Clipboard.copy(code) }; ShareLink(item: code) { Label("Share", systemImage: "square.and.arrow.up") } }.disabled(code.isEmpty).frame(minHeight: 44)
            }.padding(12).sheetTitle("Client code").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.macSheetFrame(minHeight: 400).task(id: language.rawValue + String(store.hideCredentials)) {
            do {
                let resolved = try store.effective(request), selectedLanguage = language, hideCredentials = store.hideCredentials
                code = try await Task.detached { try CodeGenerator.generate(resolved.request, variables: resolved.variables, language: selectedLanguage, redact: hideCredentials) }.value; error = nil
            }
            catch { self.error = error.localizedDescription; code = "" }
        }
    }
}
