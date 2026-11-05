#if os(iOS)
import SwiftUI
import MonkeytailCore

struct WatchTransferView: View {
    let store: WorkspaceStore
    @Bindable private var link = WatchCompanionLink.shared
    @State private var result: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Include credentials & body", isOn: Binding(get: { store.watchIncludesCredentials }, set: { store.setWatchIncludesCredentials($0) }))
                }
                Section("Favourites") {
                    if let selected = store.selectedRequest, selected.favorite != true {
                        Button("Favourite current request", systemImage: "star") { var value = selected; value.favorite = true; store.update(value) }
                    }
                    ForEach(store.workspace.collections.flatMap(\.requests).filter { $0.favorite == true }) { request in
                        Button { save(request) } label: {
                            HStack { VStack(alignment: .leading) { Text(request.name); Text(request.method + " " + request.url).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Image(systemName: link.requests.contains { $0.id == request.id } ? "checkmark.applewatch" : "applewatch") }
                        }.accessibilityIdentifier("Save favourite " + request.name)
                    }
                }
                Section("On Watch") {
                    ForEach(link.requests) { request in
                        VStack(alignment: .leading) { Text(request.name); Text(request.method + " " + request.url).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }.onDelete { offsets in let ids = offsets.map { link.requests[$0].id }; for id in ids { do { try link.remove(id) } catch { result = error.localizedDescription } } }
                    Button("Sync") { do {
                        let favourites = Set(store.workspace.collections.flatMap(\.requests).filter { $0.favorite == true }.map(\.id))
                        try link.transfer(favoriteIDs: favourites); result = String(localized: "Queued for Watch.")
                    } catch { result = error.localizedDescription } }
                }
                if let result { Text(result).font(.caption) }
                if let issue = link.issue { Text(issue).font(.caption).foregroundStyle(Palette.error) }
            }.navigationTitle("Apple Watch").inlineTitle().toolbar { Button("Done") { dismiss() } }
        }
    }
    private func save(_ request: APIRequest) {
        do {
            let effective = try store.effective(request)
            let url = try RequestBuilder.build(effective.request, variables: effective.variables).url
            guard try store.network.identity(for: url) == nil else { throw ClientError(String(localized: "Use iPhone for client certificate requests.")) }
            let collection = store.workspace.collections.first { $0.requests.contains { $0.id == request.id } }
            let fields = (store.environment?.variables ?? []) + (collection?.defaults?.variables ?? []) + (collection?.folders ?? []).flatMap { $0.defaults.variables }
            let payload = try WatchCompanionLink.prepare(effective.request, variables: effective.variables, proxy: store.workspace.proxy, includePrivateData: store.watchIncludesCredentials, secretVariableNames: Set(fields.filter(\.isCredential).map(\.name)))
            try link.add(payload); result = String(localized: "Queued for Watch.")
        } catch { result = error.localizedDescription }
    }
}
#endif
