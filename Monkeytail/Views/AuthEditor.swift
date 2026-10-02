import SwiftUI
import MonkeytailCore

struct AuthEditor: View {
    @Binding var auth: RequestAuth
    var proxy = ProxySettings()
    var allowInheritance = true
    @State private var authorizer = OAuthAuthorizer()
    @State private var busy = false
    @State private var error: String?
    private var apiKey: Binding<APIKeyAuth> { Binding(get: { auth.apiKey ?? APIKeyAuth() }, set: { auth.apiKey = $0 }) }
    private var aws: Binding<AWSAuth> { Binding(get: { auth.aws ?? AWSAuth() }, set: { auth.aws = $0 }) }
    private var oauth: Binding<OAuthConfiguration> { Binding(get: { auth.oauth ?? OAuthConfiguration() }, set: { auth.oauth = $0 }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Authentication", selection: $auth.kind) {
                ForEach(AuthKind.allCases.filter { allowInheritance || $0 != .inherit }, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("Authentication type")
            switch auth.kind {
            case .none: EmptyView()
            case .inherit: Text("Uses the nearest folder or collection settings.").font(.caption).foregroundStyle(.secondary)
            case .bearer: SecureField("Token or {{token}}", text: $auth.token)
            case .basic: TextField("Username", text: $auth.username); SecureField("Password", text: $auth.password)
            case .apiKey:
                TextField("Key name", text: apiKey.name); SecureField("Key value", text: apiKey.value)
                Toggle("Send in query", isOn: apiKey.inQuery)
            case .aws:
                TextField("Access key", text: aws.accessKey); SecureField("Secret key", text: aws.secretKey); SecureField("Session token (optional)", text: aws.sessionToken)
                TextField("Region", text: aws.region); TextField("Service", text: aws.service)
            case .oauth2:
                Picker("Grant", selection: oauth.grant) { ForEach(OAuthGrant.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                if oauth.wrappedValue.grant == .pkce { TextField("Authorization URL", text: oauth.authorizationURL).urlInput(); TextField("Callback URL", text: oauth.callbackURL).urlInput() }
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
    private func token(refresh: Bool) {
        busy = true; error = nil; let configuration = oauth.wrappedValue
        Task {
            defer { busy = false }
            do { auth.oauth = try await (refresh ? authorizer.refresh(configuration, proxy: proxy) : authorizer.authorize(configuration, proxy: proxy)) }
            catch { self.error = error.localizedDescription }
        }
    }
}
