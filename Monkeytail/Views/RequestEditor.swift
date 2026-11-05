import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct RequestEditor: View {
    @Binding var request: APIRequest
    let store: WorkspaceStore
    @State private var tab = "Headers"
    @State private var scriptTab = "Before"
    @State private var editorError: String?
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            #if !os(macOS)
            if verticalSizeClass != .compact { PanelHeading(title: "Request", symbol: "slider.horizontal.3") }
            #endif
            PillTabs(tabs: ["Params", "Headers", "Body", "Auth", "Tests", "Scripts", "Mock", "Docs"], selection: $tab)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case "Params":
                        editorHeading("Query parameters", message: "Add key–value pairs to your request URL.")
                        FieldEditor(fields: $request.query, name: "Parameter")
                        if !(request.pathVariables ?? []).isEmpty {
                            editorHeading("Path variables", message: "Values for :name segments in the URL path.").padding(.top, 12)
                            FieldEditor(fields: Binding(get: { request.pathVariables ?? [] }, set: { request.pathVariables = $0 }), name: "Path variable")
                        }
                        editorHeading("Request variables", message: "Reference these values with {{variable}}.").padding(.top, 12)
                        FieldEditor(fields: Binding(get: { request.variables ?? [] }, set: { request.variables = $0 }), name: "Variable")
                        if let hints = request.parameterHints, !hints.isEmpty { DisclosureGroup("API parameters") { ForEach(hints) { hint in Text(parameterSummary(hint)).font(.caption) } } }
                    case "Headers":
                        editorHeading("Request headers", message: "Control the metadata sent with this request.")
                        FieldEditor(fields: $request.headers)
                    case "Body":
                        editorHeading("Request body", message: "Choose a format and add your payload.")
                        bodyEditor
                    case "Auth":
                        editorHeading("Authentication", message: "Configure credentials and connection options.")
                        authEditor
                    case "Tests": TestsEditor(request: $request)
                    case "Mock": MockEditor(request: $request, response: store.responses[request.id]?.response)
                    case "Docs":
                        editorHeading("Documentation", message: "Markdown notes; imported from and exported to Postman descriptions.")
                        DocsEditor(text: $request.description)
                    default: scriptsEditor
                    }
                    if let editorError { Label(editorError, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(Palette.error) }
                }.padding(WorkspaceMetrics.inset)
            }.dismissKeyboardOnScroll()
        }.background(Palette.canvas)
            .onChange(of: request.url) { _, url in syncPathVariables(url) }
    }

    /// Keeps one path variable per `:name` segment, preserving existing values.
    private func syncPathVariables(_ url: String) {
        let names = RequestBuilder.pathVariableNames(in: url), existing = request.pathVariables ?? []
        guard names != existing.map(\.name) else { return }
        let synced = names.map { name in existing.first { $0.name == name } ?? Field(name) }
        request.pathVariables = synced.isEmpty && request.pathVariables == nil ? nil : synced
    }

    @ViewBuilder private func editorHeading(_ title: LocalizedStringKey, message: LocalizedStringKey) -> some View {
        #if os(macOS)
        Text(title).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
        #else
        EditorHeading(title: title, message: message)
        #endif
    }

    private func parameterSummary(_ hint: ParameterHint) -> String {
        var result = "\(hint.name) · \(hint.location) · \(hint.type)"
        if hint.required { result += " · " + String(localized: "required") }
        if !hint.description.isEmpty { result += "\n" + hint.description }
        return result
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if request.transport == .graphql { GraphQLEditor(request: $request, store: store) }
            else {
            Picker("Body type", selection: $request.bodyKind) { ForEach(BodyKind.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            switch request.bodyKind {
            case .none:
                #if os(macOS)
                Text("No request body").font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
                #else
                EmptyPanel(title: "No body needed", message: "Choose a body type above to send JSON, text, or files.", symbol: "doc.text")
                    .frame(minHeight: 180)
                #endif
            case .form: FieldEditor(fields: $request.form, name: "Field")
            case .multipart: MultipartEditor(parts: Binding(get: { request.multipart ?? [] }, set: { request.multipart = $0 }))
            case .file: UploadFileEditor(file: $request.fileBody)
            case .json, .text:
                if request.bodyKind == .json {
                    HStack {
                        Text(verbatim: "JSON").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Format") { formatJSON(pretty: true) }.frame(minHeight: 44)
                        Button("Minify") { formatJSON(pretty: false) }.frame(minHeight: 44)
                    }.font(.caption.weight(.medium))
                }
                CodeEditor(text: $request.body, label: "Request body", minimumHeight: 300)
            }
            }
        }
    }

    private func formatJSON(pretty: Bool) {
        do { request.body = try JSONTools.format(request.body, pretty: pretty); editorError = nil }
        catch { editorError = error.localizedDescription }
    }

    private var authEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuthEditor(auth: $request.auth, proxy: store.workspace.proxy)
            Toggle("Use cookie jar", isOn: Binding(get: { request.cookieJarEnabled ?? false }, set: { request.cookieJarEnabled = $0 }))
            Divider()
            HStack {
                Text("TLS profile")
                Spacer(minLength: 8)
                Picker("TLS profile", selection: Binding<BrowserProfile?>(
                    get: { request.impersonation?.profile },
                    set: { profile in request.impersonation = profile.map { BrowserImpersonation(profile: $0, browserHeaders: request.impersonation?.browserHeaders ?? true) } }
                )) {
                    Text("System").tag(BrowserProfile?.none)
                    ForEach(BrowserProfile.isSupported ? BrowserProfile.allCases : []) { Text($0.title).tag(Optional($0)) }
                }.pickerStyle(.menu).labelsHidden().frame(minHeight: 44).accessibilityIdentifier("TLS profile")
            }.font(.subheadline)
            if request.impersonation != nil {
                Toggle("Browser headers", isOn: Binding(get: { request.impersonation?.browserHeaders ?? true }, set: { request.impersonation?.browserHeaders = $0 }))
                Text("TLS + HTTP/2. Your headers override browser defaults.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Follow redirects", isOn: $request.followRedirects).font(.subheadline)
            Stepper("Timeout: \(Int(request.timeout))s", value: $request.timeout, in: 1...300, step: 5).font(.subheadline)
        }.macReadableWidth().noCapitalization().autocorrectionDisabled()
    }

    private var scriptsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Run scripts", isOn: $request.scriptsEnabled).font(.subheadline)
            if !request.scriptsEnabled && !(request.preScript.isEmpty && request.postScript.isEmpty) {
                Label("This request's scripts are saved but skipped on send.", systemImage: "pause.circle").font(.caption).foregroundStyle(Palette.warning)
            }
            SegmentedChoice(title: "Script phase", selection: $scriptTab, options: [("Before", "Before request"), ("After", "After response")])
            CodeEditor(text: scriptTab == "Before" ? $request.preScript : $request.postScript, label: "JavaScript editor", minimumHeight: 250)
            Menu {
                Button("Set header") { request.preScript = "request.headers['X-Request-ID'] = crypto.randomUUID();\nconsole.log('Sending', request.method, request.url);"; scriptTab = "Before" }
                Button("Assert status") { request.postScript = "test('Status is OK', () => {\n  assert(response.status === 200, 'Expected HTTP 200');\n});\nconsole.log(response.json());"; scriptTab = "After" }
                Button("Save token") { request.postScript = "const data = response.json();\nenvironment.set('token', data.token);"; scriptTab = "After" }
                Button("Postman test") { request.postScript = "pm.test('Status code is 200', () => {\n  pm.response.to.have.status(200);\n});\npm.test('Body is JSON', () => {\n  pm.expect(pm.response.json()).to.be.an('object');\n});"; scriptTab = "After" }
                Button("Sign with HMAC") { request.preScript = "const timestamp = Date.now().toString();\nconst signature = CryptoJS.HmacSHA256(timestamp, pm.environment.get('secret') || '').toString();\npm.request.headers.upsert({ key: 'X-Timestamp', value: timestamp });\npm.request.headers.upsert({ key: 'X-Signature', value: signature });"; scriptTab = "Before" }
                Button("Fetch token first") { request.preScript = "const res = await pm.sendRequest({ url: pm.environment.replaceIn('{{base_url}}/token'), method: 'POST' });\npm.environment.set('token', res.json().token);"; scriptTab = "Before" }
            } label: { Label("Examples", systemImage: "text.badge.plus").font(.subheadline).frame(minHeight: 44) }
            DisclosureGroup("Scripting reference") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: "pm.environment · pm.collectionVariables · pm.globals\npm.variables · pm.request · pm.response · pm.cookies\npm.test() · pm.expect() · pm.sendRequest()\nCryptoJS · _ · moment() · require() · console.log()")
                        .font(.system(.caption, design: .monospaced))
                    Text("Scripts run on every send and collection run, after any collection and folder scripts. 3-second limit; network only through pm.sendRequest; no file access. Before-request hooks can change the URL, method, headers, and raw body. Results appear in Console.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.font(.footnote)
        }
    }
}

struct CurlExportView: View {
    let request: APIRequest
    let variables: [String: String]
    @Environment(\.dismiss) private var dismiss
    @State private var curl = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Includes resolved variables and credentials.").font(.caption).foregroundStyle(.secondary)
                if request.bodyKind == .multipart || request.bodyKind == .file { Text("Export files from Body and place them beside the command.").font(.caption).foregroundStyle(.secondary) }
                if request.impersonation != nil { Text("Requires curl-impersonate 2.2.3 or later.").font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(Palette.error) }
                ScrollView { Text(curl).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    ShareLink(item: curl) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.secondaryButton()
                    Button { Clipboard.copy(curl); dismiss() } label: { Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }.prominentButton()
                }.disabled(curl.isEmpty)
            }.padding(12).background(Palette.canvas).sheetTitle("cURL")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.macSheetFrame(minHeight: 400).task {
            do { curl = try CurlCodec.encode(request, variables: variables) } catch { self.error = error.localizedDescription }
        }
    }
}

private extension BodyKind {
    var title: LocalizedStringKey {
        switch self { case .none: "None"; case .json: "JSON"; case .text: "Text"; case .form: "Form"; case .multipart: "Multipart"; case .file: "File" }
    }
}
