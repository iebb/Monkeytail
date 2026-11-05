import SwiftUI
import WebKit
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

/// Imports straight from another app: Postman, Insomnia and Hoppscotch sign in the way their own apps do; GitHub uses the user's own token.
/// Sessions and tokens stay in memory for this import only.
struct RemoteImportView: View {
    enum Service: String, CaseIterable, Identifiable {
        case postman = "Postman", insomnia = "Insomnia", hoppscotch = "Hoppscotch", github = "GitHub"
        var id: String { rawValue }
        var symbol: String {
            switch self { case .postman: "paperplane"; case .insomnia: "moon.stars"; case .hoppscotch: "hare"; case .github: "chevron.left.forwardslash.chevron.right" }
        }
        var caption: LocalizedStringKey {
            switch self { case .postman: "Workspaces"; case .insomnia: "Cloud Sync"; case .hoppscotch: "Email sign-in"; case .github: "Repositories" }
        }
        var summary: LocalizedStringKey {
            switch self {
            case .postman: "Collections, environments and globals, with folders, auth, scripts and examples."
            case .insomnia: "The latest synced version of each project: requests, folders, environments and scripts."
            case .hoppscotch: "Personal and team collections and environments, plus your globals."
            case .github: "Postman, Insomnia Git Sync, Bruno, Thunder Client, Hoppscotch, .http, HAR and OpenAPI files."
            }
        }
        var steps: [LocalizedStringResource] {
            switch self { case .postman: ["Sign in", "Choose workspaces"]; case .insomnia: ["Sign in", "Paste code", "Choose projects"]; case .hoppscotch: ["Request link", "Paste link"]; case .github: [] }
        }
    }
    @Bindable var store: WorkspaceStore
    var finished: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var service = Service.postman
    @State private var token = ""
    @State private var workspaces: [RemoteWorkspace] = []
    @State private var selected: Set<String> = []
    @State private var repository = ""
    @State private var postmanSigningIn = false
    @State private var postmanBrowserURL: URL?
    @State private var postmanSession: PostmanSession?
    @State private var insomniaLogin = InsomniaLogin()
    @State private var insomniaOpened = false
    @State private var insomniaSession: InsomniaSession?
    @State private var server = RemoteImporter.hoppscotchServer
    @State private var customServer = false
    @State private var email = ""
    @State private var pending: HoppscotchSignIn?
    @State private var status: String?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    private let importer = RemoteImporter.live

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) { ForEach(Service.allCases) { tile($0) } }
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if !service.steps.isEmpty { stepper }
                    Group {
                        switch service {
                        case .postman: postman
                        case .insomnia: insomnia
                        case .hoppscotch: hoppscotch
                        case .github: github
                        }
                    }.fieldStyle().noCapitalization().autocorrectionDisabled()
                    if let status {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(status).font(.footnote).foregroundStyle(.secondary); Spacer(); Button("Cancel") { task?.cancel() }.buttonStyle(.borderless).font(.footnote) }
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Palette.danger)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Palette.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
                Label(privacy, systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }.padding(16).macReadableWidth()
        }.background(Palette.canvas).navigationTitle("Import from an app")
            .onDisappear { task?.cancel() }
            .sheet(isPresented: $postmanSigningIn) {
                NavigationStack {
                    PostmanSignInView(signedIn: { result in
                        postmanSigningIn = false
                        run {
                            let session = try result.get()
                            report(String(localized: "Loading workspaces…"))
                            let found = try await importer.postmanWorkspaces(session)
                            postmanSession = session; workspaces = found; selected = Set(found.map(\.id))
                        }
                    }, useBrowser: { postmanSigningIn = false; signInWithBrowser() })
                    .sheetTitle("Sign in to Postman")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { postmanSigningIn = false } } }
                }.frame(idealWidth: 560, idealHeight: 720).macSheetFrame(minWidth: 520, minHeight: 640)
            }
    }

    private func tile(_ option: Service) -> some View {
        let isOn = option == service
        return Button { select(option) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: option.symbol).font(.app(size: 14, weight: .semibold)).foregroundStyle(isOn ? Palette.canvas : Palette.mint)
                    .frame(width: 30, height: 30).background(isOn ? Palette.mint : Palette.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(option.caption).font(.caption).foregroundStyle(.secondary)
                }.lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOn ? Palette.mint : Palette.border, lineWidth: isOn ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).accessibilityLabel(option.rawValue).accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import from \(service.rawValue)").font(.headline)
                Text(service.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if postmanSession != nil || insomniaSession != nil { Button("Sign out", action: signOut).buttonStyle(.borderless).font(.caption) }
        }
    }

    private var step: Int {
        switch service {
        case .postman: postmanSession == nil ? 0 : 1
        case .insomnia: insomniaSession != nil ? 2 : insomniaOpened ? 1 : 0
        case .hoppscotch: pending == nil ? 0 : 1
        case .github: 0
        }
    }

    private var stepper: some View {
        let steps = service.steps
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, name in
                    if index > 0 { Capsule().fill(index <= step ? Palette.mint : Palette.border).frame(width: 18, height: 2) }
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(index < step ? Palette.mint : index == step ? Palette.mint.opacity(0.15) : Palette.border)
                            if index < step { Image(systemName: "checkmark").font(.app(size: 9, weight: .bold)).foregroundStyle(Palette.canvas) }
                            else { Text("\(index + 1)").font(.caption2.weight(.bold)).foregroundStyle(index == step ? Palette.mint : .secondary) }
                        }.frame(width: 20, height: 20)
                        Text(name).font(.caption.weight(index == step ? .semibold : .regular)).foregroundStyle(index == step ? .primary : .secondary).fixedSize()
                    }
                }
            }
            Text("Step \(step + 1) of \(steps.count) · \(String(localized: steps[step]))").font(.caption.weight(.semibold)).foregroundStyle(Palette.mint)
        }.accessibilityElement(children: .ignore).accessibilityLabel("Step \(step + 1) of \(steps.count), \(String(localized: steps[step]))")
    }

    @ViewBuilder private var postman: some View {
        if let session = postmanSession {
            choices()
            primary(selected.count == 1 ? "Import 1 workspace" : "Import \(selected.count) workspaces", systemImage: "square.and.arrow.down", disabled: selected.isEmpty) {
                let chosen = workspaces.filter { selected.contains($0.id) }
                try finish(await importer.postman(session, workspaces: chosen, progress: report))
            }
        } else {
            Text("Sign in to Postman in your browser, then choose the workspaces to import.").font(.subheadline)
            if task != nil, let url = postmanBrowserURL {
                Label("Finish signing in in your browser. Monkeytail continues as soon as Postman confirms.", systemImage: "safari").font(.subheadline).foregroundStyle(.secondary)
                Button("Open the sign-in page again") { openURL(url) }.buttonStyle(.borderless).font(.caption)
            } else {
                prominent("Sign in with your browser", systemImage: "safari", action: signInWithBrowser)
                Text("Works with Google, GitHub, single sign-on and passkeys, and with the account your browser is already signed in to.").font(.caption).foregroundStyle(.secondary)
                Button("Sign in with email in Monkeytail instead") { error = nil; postmanSigningIn = true }.buttonStyle(.borderless).font(.caption).disabled(task != nil)
            }
        }
    }

    @ViewBuilder private var insomnia: some View {
        if let session = insomniaSession {
            choices(projects: true)
            primary(selected.count == 1 ? "Import 1 project" : "Import \(selected.count) projects", systemImage: "square.and.arrow.down", disabled: selected.isEmpty) {
                let chosen = workspaces.filter { selected.contains($0.id) }
                try finish(await importer.insomnia(session, projects: chosen, progress: report))
            }
        } else if !insomniaOpened {
            Text("Sign in on the Insomnia website. It shows a code for the desktop app, which you paste here next.").font(.subheadline)
            prominent("Open Insomnia sign-in", systemImage: "arrow.up.right.square") { error = nil; openURL(insomniaLogin.url); insomniaOpened = true }
        } else {
            Text("When the website asks to open Insomnia, copy the code it shows instead.").font(.subheadline)
            labeled("Sign-in code") { pasteable(TextField("Sign-in code", text: $token, prompt: Text("Paste the code from the Insomnia website"), axis: .vertical).lineLimit(1...4)) }
            Button("Open sign-in again") { openURL(insomniaLogin.url) }.buttonStyle(.borderless).font(.caption)
            primary("Continue", systemImage: "arrow.right", disabled: token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                report(String(localized: "Signing in…"))
                let session = try await importer.insomniaSignIn(insomniaLogin, code: token)
                report(String(localized: "Loading projects…"))
                let found = try await importer.insomniaProjects(session)
                insomniaSession = session; token = ""; workspaces = found; selected = Set(found.map(\.id))
            }
        }
    }

    @ViewBuilder private var hoppscotch: some View {
        if let pending {
            Label { Text("We sent a sign-in link to \(email). Copy the link from the email without opening it, and paste it here.") } icon: { Image(systemName: "envelope.badge").foregroundStyle(Palette.mint) }
                .font(.subheadline)
            labeled("Sign-in link") { pasteable(TextField("Sign-in link", text: $token, prompt: Text(verbatim: "https://…"), axis: .vertical).lineLimit(1...4)) }
            Button("Use a different email") { self.pending = nil; token = "" }.buttonStyle(.borderless).font(.caption)
            primary("Sign in and import", systemImage: "square.and.arrow.down", disabled: token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                report(String(localized: "Signing in…"))
                let session = try await importer.hoppscotchSignIn(pending, link: token)
                try finish(await importer.hoppscotch(session, progress: report))
            }
        } else {
            labeled("Email") { TextField("Email", text: $email, prompt: Text("The email you use with Hoppscotch")) }
            DisclosureGroup(isExpanded: $customServer) {
                labeled("Server") { TextField("Server", text: $server, prompt: Text(RemoteImporter.hoppscotchServer)) }.padding(.top, 6)
            } label: { Text("Self-hosted server").font(.caption) }
            primary("Email me a sign-in link", systemImage: "envelope", disabled: !email.contains("@")) {
                pending = try await importer.hoppscotchSendLink(server: server, email: email)
            }
        }
    }

    @ViewBuilder private var github: some View {
        labeled("Repository") { TextField("Repository", text: $repository, prompt: Text("owner/repo or a GitHub URL")) }
        labeled("Access token") { SecureField("Access token", text: $token, prompt: Text("Only for private repositories")) }
        Link("Create a read-only token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!).font(.caption)
        Label("Paste a folder URL (…/tree/main/folder) to import part of a repository.", systemImage: "lightbulb").font(.caption).foregroundStyle(.secondary)
        primary("Import repository", systemImage: "square.and.arrow.down", disabled: repository.trimmingCharacters(in: .whitespaces).isEmpty) {
            guard let source = GitHubSource(repository) else { throw ClientError(String(localized: "Enter a repository as owner/repo or paste its GitHub URL.")) }
            try finish(await importer.github(source, token: token, progress: report))
        }
    }

    private func choices(projects: Bool = false) -> some View {
        let all = !workspaces.isEmpty && selected.count == workspaces.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(projects ? "\(selected.count) of \(workspaces.count) projects selected" : "\(selected.count) of \(workspaces.count) workspaces selected").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(all ? "Select none" : "Select all") { selected = all ? [] : Set(workspaces.map(\.id)) }.buttonStyle(.borderless).font(.caption).disabled(workspaces.isEmpty)
            }
            VStack(spacing: 0) {
                if workspaces.isEmpty { Text(projects ? "No projects found in this account." : "No workspaces found in this account.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20) }
                ForEach(workspaces) { workspace in
                    let isOn = selected.contains(workspace.id)
                    Button { if isOn { selected.remove(workspace.id) } else { selected.insert(workspace.id) } } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle").font(.app(size: 16)).foregroundStyle(isOn ? Palette.mint : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(workspace.name).foregroundStyle(.primary)
                                if !workspace.kind.isEmpty { Text(workspace.kind.capitalized).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(isOn ? [.isToggle, .isSelected] : .isToggle)
                    if workspace.id != workspaces.last?.id { Divider().padding(.leading, 38) }
                }
            }.background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
        }
    }

    private func labeled<Content: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary); content() }
    }
    private func pasteable(_ field: some View) -> some View {
        HStack(alignment: .top, spacing: 8) { field; PasteButton(payloadType: String.self) { strings in Task { @MainActor in token = strings.first ?? token } }.labelStyle(.iconOnly) }
    }

    private var privacy: LocalizedStringKey {
        switch service {
        case .postman: return "Monkeytail signs in the way Postman's desktop app does and never sees your password. The session is used for this import only and never saved."
        case .insomnia: return "Monkeytail signs in the way Insomnia's desktop app does and decrypts your projects on this device. The session is used for this import only and never saved."
        case .hoppscotch: return "Monkeytail signs in to \(URL(string: server)?.host ?? "Hoppscotch") the way Hoppscotch's own apps do. The session is used for this import only and never saved."
        case .github: return "Your token is sent only to GitHub, used for this import, and never saved. Monkeytail itself has no accounts."
        }
    }
    private func select(_ option: Service) {
        guard option != service else { return }
        task?.cancel(); service = option; token = ""; workspaces = []; selected = []; postmanSession = nil; insomniaSession = nil; insomniaOpened = false; pending = nil; error = nil
    }
    private func signInWithBrowser() {
        run {
            let login = try await importer.postmanBrowserLogin()
            postmanBrowserURL = login.url; openURL(login.url)
            report(String(localized: "Waiting for you to sign in in your browser…"))
            let session = try await importer.postmanSession(login)
            report(String(localized: "Loading workspaces…"))
            let found = try await importer.postmanWorkspaces(session)
            postmanSession = session; workspaces = found; selected = Set(found.map(\.id))
        }
    }
    private func signOut() {
        task?.cancel(); postmanSession = nil; insomniaSession = nil; insomniaLogin = InsomniaLogin(); insomniaOpened = false; workspaces = []; selected = []; token = ""; error = nil
    }
    private func report(_ text: String) { Task { @MainActor in if status != nil { status = text } } }
    private func finish(_ result: CollectionImport) throws { try store.importRemote(result); token = ""; postmanSession = nil; insomniaSession = nil; finished() }
    private func prominent(_ title: LocalizedStringKey, systemImage: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: systemImage).frame(maxWidth: .infinity).padding(.vertical, 5) }
            .prominentButton().disabled(disabled || task != nil)
    }
    private func primary(_ title: LocalizedStringKey, systemImage: String, disabled: Bool, action: @escaping @MainActor () async throws -> Void) -> some View {
        prominent(title, systemImage: systemImage, disabled: disabled) { run(action) }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        error = nil; status = String(localized: "Connecting…")
        task = Task {
            do { try await action() } catch is CancellationError {} catch let failure as URLError where failure.code == .cancelled {}
            catch let failure as URLError { self.error = failure.localizedDescription + (failure.failingURL?.host.map { " (\($0))" } ?? "") }
            catch { self.error = error.localizedDescription }
            status = nil; task = nil
        }
    }
}

/// Postman's own sign-in page in a private browser session. It ends with the redirect Postman's desktop app reads its session from.
struct PostmanSignInView {
    var signedIn: @MainActor (Result<PostmanSession, Error>) -> Void
    var useBrowser: @MainActor () -> Void
    func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = coordinator; view.uiDelegate = coordinator
        view.load(URLRequest(url: PostmanSession.loginURL))
        return view
    }
    func makeCoordinator() -> Coordinator { Coordinator(signedIn: signedIn, useBrowser: useBrowser) }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let signedIn: @MainActor (Result<PostmanSession, Error>) -> Void
        let useBrowser: @MainActor () -> Void
        var done = false
        var retried = false
        init(signedIn: @escaping @MainActor (Result<PostmanSession, Error>) -> Void, useBrowser: @escaping @MainActor () -> Void) { self.signedIn = signedIn; self.useBrowser = useBrowser }
        @MainActor func finish(_ url: URL?) -> Bool {
            guard let url else { return false }
            do { guard let session = try PostmanSession(callback: url) else { return false }; if !done { done = true; signedIn(.success(session)) } }
            catch { if !done { done = true; signedIn(.failure(error)) } }
            return true
        }
        /// Like the desktop app, Google and GitHub sign-in move to the browser. If a sign-in still ends on Postman's website, the identity session it leaves behind lets the desktop sign-in page hand over a session.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if finish(action.request.url) { return decisionHandler(.cancel) }
            if let url = action.request.url, PostmanSession.needsBrowser(url), !done { done = true; decisionHandler(.cancel); return useBrowser() }
            guard action.targetFrame?.isMainFrame == true, let url = action.request.url, PostmanSession.isWebApp(url), !done else { return decisionHandler(.allow) }
            decisionHandler(.cancel)
            if retried { done = true; signedIn(.failure(ClientError(String(localized: "Postman finished signing in on its website instead of handing the session to Monkeytail. Sign in again with your email and password.")))) }
            else { retried = true; webView.load(URLRequest(url: PostmanSession.loginURL)) }
        }
        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) { _ = finish(webView.url) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { _ = finish((error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL) }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if !finish(action.request.url) { webView.load(action.request) }
            return nil
        }
    }
}
#if os(macOS)
extension PostmanSignInView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
extension PostmanSignInView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
