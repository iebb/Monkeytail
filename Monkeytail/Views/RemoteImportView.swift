import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

/// Evil Monk pulls collections straight from a service with the user's own token. Tokens stay in memory for this import only.
struct RemoteImportView: View {
    enum Service: String, CaseIterable, Identifiable { case postman = "Postman", github = "GitHub", hoppscotch = "Hoppscotch"; var id: String { rawValue } }
    @Bindable var store: WorkspaceStore
    var finished: () -> Void
    @State private var service = Service.postman
    @State private var token = ""
    @State private var region = RemoteImporter.PostmanRegion.us
    @State private var workspaces: [RemoteWorkspace] = []
    @State private var selected: Set<String> = []
    @State private var repository = ""
    @State private var server = "https://api.hoppscotch.io"
    @State private var collectionIDs = ""
    @State private var environmentIDs = ""
    @State private var status: String?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    private let importer = RemoteImporter.live

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                EvilMonkTitle(subtitle: "Bring everything over from the app you used before")
                Picker("Service", selection: $service) { ForEach(Service.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    .onChange(of: service) { token = ""; workspaces = []; error = nil }
                Group {
                    switch service {
                    case .postman: postman
                    case .github: github
                    case .hoppscotch: hoppscotch
                    }
                }.textFieldStyle(.roundedBorder).noCapitalization().autocorrectionDisabled()
                if let status { HStack(spacing: 8) { ProgressView(); Text(status).font(.footnote).foregroundStyle(.secondary); Spacer(); Button("Cancel") { task?.cancel() } } }
                if let error { Label(error, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red) }
                Text("Your token is sent only to \(host), used for this import, and never saved. Monkeytail itself has no accounts.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }.background(Palette.canvas).navigationTitle("Connect a service")
            .onDisappear { task?.cancel() }
    }

    @ViewBuilder private var postman: some View {
        SecureField("Postman API key", text: $token).onChange(of: token) { workspaces = [] }
        HStack {
            Link("Create an API key", destination: URL(string: "https://go.postman.co/settings/me/api-keys")!).font(.footnote)
            Spacer()
            Picker("Data region", selection: $region) { ForEach(RemoteImporter.PostmanRegion.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).fixedSize()
        }
        if workspaces.isEmpty {
            primary("Load workspaces", systemImage: "person.2", disabled: token.isEmpty) {
                let found = try await importer.postmanWorkspaces(apiKey: token, region: region)
                workspaces = found; selected = Set(found.map(\.id))
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(workspaces) { workspace in
                    Toggle(isOn: Binding(get: { selected.contains(workspace.id) }, set: { if $0 { selected.insert(workspace.id) } else { selected.remove(workspace.id) } })) {
                        VStack(alignment: .leading) { Text(workspace.name); if !workspace.kind.isEmpty { Text(workspace.kind.capitalized).font(.caption).foregroundStyle(.secondary) } }
                    }.padding(.vertical, 6)
                }
            }.padding(.horizontal, 12).padding(.vertical, 4).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            Text("Imports every collection, environment and the globals of the selected workspaces, with folders, auth, scripts and examples.").font(.caption).foregroundStyle(.secondary)
            primary("Import \(selected.count) \(selected.count == 1 ? "workspace" : "workspaces")", systemImage: "square.and.arrow.down", disabled: selected.isEmpty) {
                let chosen = workspaces.filter { selected.contains($0.id) }
                try finish(await importer.postman(apiKey: token, region: region, workspaces: chosen, progress: report))
            }
        }
    }

    @ViewBuilder private var github: some View {
        TextField("owner/repo or GitHub URL", text: $repository)
        SecureField("Token (private repositories only)", text: $token)
        Link("Create a read-only token", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!).font(.footnote)
        Text("Imports Postman, Insomnia Git Sync, Bruno, Thunder Client, Hoppscotch, .http, HAR and OpenAPI files. Paste a folder URL (…/tree/main/folder) to import part of a repository.")
            .font(.caption).foregroundStyle(.secondary)
        primary("Import repository", systemImage: "square.and.arrow.down", disabled: repository.trimmingCharacters(in: .whitespaces).isEmpty) {
            guard let source = GitHubSource(repository) else { throw ClientError("Enter a repository as owner/repo or paste its GitHub URL.") }
            try finish(await importer.github(source, token: token, progress: report))
        }
    }

    @ViewBuilder private var hoppscotch: some View {
        TextField("Server", text: $server)
        SecureField("Personal access token", text: $token)
        TextField("Collection IDs", text: $collectionIDs, axis: .vertical)
        TextField("Environment IDs (optional)", text: $environmentIDs, axis: .vertical)
        Text("Create a token under Profile → Tokens. Copy IDs from a team collection's or environment's Properties; separate several with commas. Hoppscotch exposes team workspaces only, so export personal collections as JSON instead.")
            .font(.caption).foregroundStyle(.secondary)
        primary("Import from Hoppscotch", systemImage: "square.and.arrow.down", disabled: token.isEmpty || (ids(collectionIDs).isEmpty && ids(environmentIDs).isEmpty)) {
            try finish(await importer.hoppscotch(server: server, token: token, collectionIDs: ids(collectionIDs), environmentIDs: ids(environmentIDs), progress: report))
        }
    }

    private var host: String {
        switch service {
        case .postman: return URL(string: region.host)?.host ?? "Postman"
        case .github: return "GitHub"
        case .hoppscotch: return URL(string: server)?.host ?? "your Hoppscotch server"
        }
    }
    private func report(_ text: String) { Task { @MainActor in if status != nil { status = text } } }
    private func ids(_ text: String) -> [String] { text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init) }
    private func finish(_ result: CollectionImport) throws { try store.importRemote(result); token = ""; finished() }
    private func primary(_ title: String, systemImage: String, disabled: Bool, action: @escaping @MainActor () async throws -> Void) -> some View {
        Button {
            error = nil; status = "Connecting…"
            task = Task {
                do { try await action() } catch is CancellationError {} catch let failure as URLError where failure.code == .cancelled {} catch { self.error = error.localizedDescription }
                status = nil; task = nil
            }
        } label: { Label(title, systemImage: systemImage).frame(maxWidth: .infinity).padding(.vertical, 5) }
            .buttonStyle(.borderedProminent).tint(.purple).disabled(disabled || task != nil)
    }
}

struct EvilMonkTitle: View {
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Evil Monk").font(.title2.weight(.heavy)).foregroundStyle(.purple).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
