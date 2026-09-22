import SwiftUI
import MonkeytailCore

struct RequestEditor: View {
    @Binding var request: APIRequest
    @State private var tab = "Headers"
    @State private var scriptTab = "Before"
    @State private var editorError: String?

    var body: some View {
        VStack(spacing: 0) {
            PillTabs(tabs: ["Params", "Headers", "Body", "Auth", "Scripts"], selection: $tab)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case "Params": FieldEditor(fields: $request.query, name: "Parameter")
                    case "Headers": FieldEditor(fields: $request.headers)
                    case "Body": bodyEditor
                    case "Auth": authEditor
                    default: scriptsEditor
                    }
                    if let editorError { Label(editorError, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red) }
                }.padding(12)
            }.scrollDismissesKeyboard(.interactively)
        }
    }

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Body type", selection: $request.bodyKind) { ForEach(BodyKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            switch request.bodyKind {
            case .none: Text("No body").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 12)
            case .form: FieldEditor(fields: $request.form, name: "Field")
            case .json, .text:
                if request.bodyKind == .json {
                    HStack {
                        Text("JSON").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Format") { formatJSON(pretty: true) }.frame(minHeight: 44)
                        Button("Minify") { formatJSON(pretty: false) }.frame(minHeight: 44)
                    }.font(.caption.weight(.medium))
                }
                CodeEditor(text: $request.body, label: "Request body", minimumHeight: 300)
            }
        }
    }

    private func formatJSON(pretty: Bool) {
        do { request.body = try JSONTools.format(request.body, pretty: pretty); editorError = nil }
        catch { editorError = error.localizedDescription }
    }

    private var authEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Authentication type", selection: $request.auth.kind) { ForEach(AuthKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            switch request.auth.kind {
            case .none: EmptyView()
            case .bearer: SecureField("Token or {{token}}", text: $request.auth.token).dismissibleInput().textFieldStyle(.roundedBorder)
            case .basic:
                TextField("Username", text: $request.auth.username).dismissibleInput().textFieldStyle(.roundedBorder)
                SecureField("Password", text: $request.auth.password).dismissibleInput().textFieldStyle(.roundedBorder)
            }
            Divider()
            HStack {
                Text("TLS profile")
                Spacer(minLength: 8)
                Picker("TLS profile", selection: Binding<BrowserProfile?>(
                    get: { request.impersonation?.profile },
                    set: { profile in request.impersonation = profile.map { BrowserImpersonation(profile: $0, browserHeaders: request.impersonation?.browserHeaders ?? true) } }
                )) {
                    Text("System").tag(BrowserProfile?.none)
                    ForEach(BrowserProfile.allCases) { Text($0.title).tag(Optional($0)) }
                }.pickerStyle(.menu).labelsHidden().frame(minHeight: 44).accessibilityIdentifier("TLS profile")
            }.font(.subheadline)
            if request.impersonation != nil {
                Toggle("Browser headers", isOn: Binding(get: { request.impersonation?.browserHeaders ?? true }, set: { request.impersonation?.browserHeaders = $0 }))
                Text("TLS + HTTP/2. Your headers override browser defaults.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Follow redirects", isOn: $request.followRedirects).font(.subheadline)
            Stepper("Timeout: \(Int(request.timeout))s", value: $request.timeout, in: 1...300, step: 5).font(.subheadline)
        }.textInputAutocapitalization(.never).autocorrectionDisabled()
    }

    private var scriptsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Run scripts", isOn: $request.scriptsEnabled).font(.subheadline)
            Picker("Script phase", selection: $scriptTab) { Text("Before request").tag("Before"); Text("After response").tag("After") }.pickerStyle(.segmented)
            CodeEditor(text: scriptTab == "Before" ? $request.preScript : $request.postScript, label: "JavaScript editor", minimumHeight: 250)
            Menu {
                Button("Set header") { request.preScript = "request.headers['X-Request-ID'] = crypto.randomUUID();\nconsole.log('Sending', request.method, request.url);"; scriptTab = "Before" }
                Button("Assert status") { request.postScript = "test('Status is OK', () => {\n  assert(response.status === 200, 'Expected HTTP 200');\n});\nconsole.log(response.json());"; scriptTab = "After" }
                Button("Save token") { request.postScript = "const data = response.json();\nenvironment.set('token', data.token);"; scriptTab = "After" }
            } label: { Label("Examples", systemImage: "text.badge.plus").font(.subheadline).frame(minHeight: 44) }
            DisclosureGroup("Scripting reference") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("request · response · environment\nconsole.log() · test() · assert()")
                        .font(.system(.caption, design: .monospaced))
                    Text("3-second limit. No network or file access. Before-request hooks can change the URL, method, headers, and raw body. Results appear in Console.")
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
                if request.impersonation != nil { Text("Requires curl-impersonate 2.2.3 or later.").font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                ScrollView { Text(curl).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    ShareLink(item: curl) { Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    Button { UIPasteboard.general.string = curl; dismiss() } label: { Label("Copy", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                }.disabled(curl.isEmpty)
            }.padding(12).background(Palette.canvas).navigationTitle("cURL").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }.task {
            do { curl = try CurlCodec.encode(request, variables: variables) } catch { self.error = error.localizedDescription }
        }
    }
}
