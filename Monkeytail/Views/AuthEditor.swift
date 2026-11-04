import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct AuthEditor: View {
    @Binding var auth: RequestAuth
    var proxy = ProxySettings()
    var allowInheritance = true
    @State private var authorizer = OAuthAuthorizer()
    @State private var busy = false
    @State private var error: String?
    private var apiKey: Binding<APIKeyAuth> { Binding(get: { auth.apiKey ?? APIKeyAuth() }, set: { auth.apiKey = $0 }) }
    private var aws: Binding<AWSAuth> { Binding(get: { auth.aws ?? AWSAuth() }, set: { auth.aws = $0 }) }
    private var oauth1: Binding<OAuth1Auth> { Binding(get: { auth.oauth1 ?? OAuth1Auth() }, set: { auth.oauth1 = $0 }) }
    private var jwt: Binding<JWTAuth> { Binding(get: { auth.jwt ?? JWTAuth() }, set: { auth.jwt = $0 }) }
    private var oauth: Binding<OAuthConfiguration> { Binding(get: { auth.oauth ?? OAuthConfiguration() }, set: { auth.oauth = $0 }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Authentication", selection: $auth.kind) {
                ForEach(AuthKind.allCases.filter { allowInheritance || $0 != .inherit }, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("Authentication type")
            switch auth.kind {
            case .none: EmptyView()
            case .inherit: Text("Uses the nearest folder or collection settings.").font(.caption).foregroundStyle(.secondary)
            case .bearer: SecureField("Token or {{token}}", text: $auth.token); VariableAssist(text: $auth.token)
            case .basic, .digest:
                TextField("Username", text: $auth.username); VariableAssist(text: $auth.username); SecureField("Password", text: $auth.password); VariableAssist(text: $auth.password)
                if auth.kind == .digest { Text("Answers the server’s 401 challenge (MD5 or SHA-256, qop auth/auth-int).").font(.caption).foregroundStyle(.secondary) }
            case .apiKey:
                TextField("Key name", text: apiKey.name); SecureField("Key value", text: apiKey.value); VariableAssist(text: apiKey.value)
                Toggle("Send in query", isOn: apiKey.inQuery)
            case .aws:
                TextField("Access key", text: aws.accessKey); SecureField("Secret key", text: aws.secretKey); SecureField("Session token (optional)", text: aws.sessionToken)
                TextField("Region", text: aws.region); TextField("Service", text: aws.service)
            case .oauth1:
                Picker("Signature method", selection: oauth1.signatureMethod) { ForEach(OAuth1Signature.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                TextField("Consumer key", text: oauth1.consumerKey); SecureField("Consumer secret", text: oauth1.consumerSecret)
                SecureField("Access token (optional)", text: oauth1.token); SecureField("Token secret (optional)", text: oauth1.tokenSecret); TextField("Realm (optional)", text: oauth1.realm)
                Text("Signs each send with a fresh nonce and timestamp, including query and form-body parameters.").font(.caption).foregroundStyle(.secondary)
            case .jwt:
                Picker("Algorithm", selection: jwt.algorithm) { ForEach(JWTAlgorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                if jwt.wrappedValue.algorithm.rawValue.hasPrefix("HS") {
                    SecureField("Secret or {{secret}}", text: jwt.secret); VariableAssist(text: jwt.secret)
                    Toggle("Secret is Base64 encoded", isOn: jwt.secretIsBase64)
                } else {
                    CodeEditor(text: jwt.privateKey, label: "Private key (PEM)", minimumHeight: 110)
                    Text(jwt.wrappedValue.algorithm.rawValue.hasPrefix("ES") ? "PKCS#8 or SEC1 EC key on the matching curve." : "PKCS#8 or PKCS#1 RSA key, unencrypted.").font(.caption).foregroundStyle(.secondary)
                }
                CodeEditor(text: jwt.payload, label: "Payload (JSON)", minimumHeight: 110)
                Menu {
                    Button("Issued now (iat)") { jwt.wrappedValue.payload = addClaim(#""iat": {{$timestamp}}"#, to: jwt.wrappedValue.payload) }
                    Button("Unique ID (jti)") { jwt.wrappedValue.payload = addClaim(#""jti": "{{$guid}}""#, to: jwt.wrappedValue.payload) }
                } label: { Label("Add claim", systemImage: "plus.circle").font(.subheadline).frame(minHeight: 44) }
                DisclosureGroup("JWT header") { CodeEditor(text: jwt.header, label: "Extra header fields (JSON)", minimumHeight: 70) }.font(.subheadline)
                Picker("Add token to", selection: jwt.inQuery) { Text("Header").tag(false); Text("Query parameter").tag(true) }.pickerStyle(.segmented)
                if jwt.wrappedValue.inQuery { TextField("Query parameter name", text: jwt.queryKey) } else { TextField("Header prefix", text: jwt.headerPrefix) }
                Text("Signed locally on every send after {{variables}} resolve. The header’s alg always matches the algorithm.").font(.caption).foregroundStyle(.secondary)
            case .oauth2:
                Picker("Grant", selection: oauth.grant) { ForEach(OAuthGrant.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                if oauth.wrappedValue.grant == .pkce { TextField("Authorization URL", text: oauth.authorizationURL).urlInput(); TextField("Callback URL", text: oauth.callbackURL).urlInput() }
                if oauth.wrappedValue.grant == .password {
                    TextField("Username", text: Binding(get: { oauth.wrappedValue.username ?? "" }, set: { oauth.wrappedValue.username = $0 }))
                    SecureField("Password", text: Binding(get: { oauth.wrappedValue.password ?? "" }, set: { oauth.wrappedValue.password = $0 }))
                }
                TextField("Token URL", text: oauth.tokenURL).urlInput()
                TextField("Client ID", text: oauth.clientID); SecureField("Client secret (optional)", text: oauth.clientSecret); TextField("Scopes", text: oauth.scope)
                SecureField("Access token", text: oauth.accessToken); SecureField("Refresh token", text: oauth.refreshToken)
                if let expiry = oauth.wrappedValue.expiresAt { Text("Expires \(expiry.formatted())").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    Button("Get token") { token(refresh: false) }.disabled(busy)
                    Button("Refresh") { token(refresh: true) }.disabled(busy || oauth.wrappedValue.refreshToken.isEmpty)
                    if busy { ProgressView() }
                }.frame(minHeight: 44)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.textFieldStyle(.roundedBorder).noCapitalization().autocorrectionDisabled()
    }
    private func addClaim(_ claim: String, to payload: String) -> String {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("{"), text.hasSuffix("}"), text.count >= 2 else { return "{\n  " + claim + "\n}" }
        let body = text.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
        return "{\n  " + (body.isEmpty ? claim : body + ",\n  " + claim) + "\n}"
    }
    private func token(refresh: Bool) {
        busy = true; error = nil; let configuration = oauth.wrappedValue
        Task {
            defer { busy = false }
            do { auth.oauth = try await (refresh ? authorizer.refresh(configuration, proxy: proxy) : authorizer.authorize(configuration, proxy: proxy)) }
            catch { self.error = error.localizedDescription }
        }
    }
}
