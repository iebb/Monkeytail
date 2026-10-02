import SwiftUI
import MonkeytailWatchCore

@main struct MonkeytailWatchApp: App {
    @State private var store = WatchStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    ForEach(store.requests) { request in
                        NavigationLink { WatchRequestView(store: store, request: request) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(request.name).lineLimit(2)
                                Text(request.method + " · " + (URL(string: request.url)?.host ?? request.url)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.accessibilityIdentifier("Watch request " + request.name)
                    }.onDelete { offsets in let ids = offsets.map { store.requests[$0].id }; ids.forEach(store.remove) }
                    if store.requests.isEmpty { Text("Add favourites on iPhone → Apple Watch.").font(.caption) }
                    if let issue = store.issue { Text(issue).font(.caption).foregroundStyle(.red) }
                }.navigationTitle("Favourites")
            }.tint(Color(red: 0.08, green: 0.64, blue: 0.53))
                .onChange(of: phase) { _, value in if value == .background { store.cancel() } else if value == .active { store.reload() } }
        }
    }
}
private struct WatchRequestView: View {
    @Bindable var store: WatchStore
    let request: WatchRequest
    private var current: WatchRequest? { store.requests.first { $0.id == request.id } }
    private var response: WatchResponse? { store.responses[request.id] }
    var body: some View {
        ScrollView {
        VStack(spacing: 6) {
            Text(current.map { $0.method + " " + $0.url } ?? "Removed from Watch").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Button(store.runningID == request.id ? "Cancel" : "Send") {
                if store.runningID == request.id { store.cancel() } else if let current { store.send(current) }
            }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).disabled(current == nil).accessibilityIdentifier("Watch send request")
            if let issue = store.issue { Text(issue).font(.caption).foregroundStyle(.red) }
            if let response {
                Text("\(response.status) · \(Int(response.duration * 1000)) ms · \(response.body.count) B").font(.caption2).monospacedDigit().accessibilityIdentifier("Watch response status")
                NavigationLink("Body") { WatchBodyView(response: response) }.buttonStyle(.bordered).accessibilityIdentifier("Watch view body")
                NavigationLink("Headers") {
                    List(response.headers.keys.sorted(), id: \.self) { key in VStack(alignment: .leading) { Text(key).font(.caption); Text(response.headers[key] ?? "").font(.caption2).foregroundStyle(.secondary) } }.navigationTitle("Headers")
                }.buttonStyle(.plain).font(.caption2)
            }
        }.padding(.horizontal, 6)
        }.navigationTitle(request.name)
            .onDisappear { if store.runningID == request.id { store.cancel() } }
    }
}
private struct WatchBodyView: View {
    let response: WatchResponse
    @State private var format = "Pretty"
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                ForEach(["Pretty", "Raw", "Hex"], id: \.self) { name in
                    Button(name) { format = name }.font(.caption2).frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(format == name ? Color.mint : Color.secondary)
                }
            }.buttonStyle(.plain)
            ScrollView {
                Text(format == "Pretty" ? response.pretty : format == "Hex" ? response.hex : response.text)
                    .font(.system(.caption2, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("Watch response body")
                if response.body.count > 16 * 1024 { Text("Preview limited to 16 KB.").font(.caption2).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Body")
    }
}
