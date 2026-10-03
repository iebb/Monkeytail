import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

struct WorkspaceView: View {
    @Bindable var store: WorkspaceStore
    @State private var visibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    @State private var sheet: WorkspaceSheet?
    @State private var search = ""
    @State private var newCollection = false
    @State private var collectionName = ""
    @State private var renameID: UUID?
    @State private var folderCollectionID: UUID?
    @State private var folderParentID: UUID?
    @State private var addingFolder = false
    @State private var folderName = ""
    @State private var editingCollectionID: UUID?
    @State private var editingFolderID: UUID?

    enum WorkspaceSheet: String, Identifiable { case transfer, environment, settings, history, snapshots, curl, code, network, defaults, watch; var id: String { rawValue } }

    var body: some View {
        GeometryReader { geometry in
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if let request = store.selectedRequest {
                RequestWorkspace(store: store, requestID: request.id)
                    .id(request.id)
                    .navigationTitle(request.name)
                    .inlineTitle()
                    .toolbar { workspaceToolbar }
            } else {
                EmptyPanel(title: "No request selected", message: "Create or import a request.")
                    .background(Palette.canvas).toolbar { workspaceToolbar }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear { visibility = geometry.size.width >= 1100 ? .all : .detailOnly }
        .onChange(of: geometry.size.width) { _, width in visibility = width >= 1100 ? .all : .detailOnly }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .transfer: TransferView(store: store)
            case .environment: EnvironmentView(store: store)
            case .settings: SettingsView(store: store)
            case .history: HistoryView(store: store)
            case .snapshots: SnapshotsView(store: store)
            case .curl: if let request = store.selectedRequest, let resolved = try? store.effective(request) { CurlExportView(request: resolved.request, variables: resolved.variables) }
            case .code: if let request = store.selectedRequest { CodeExportView(store: store, request: request) }
            case .network: NetworkToolsView(store: store)
            case .watch:
                #if os(iOS)
                WatchTransferView(store: store)
                #else
                EmptyView()
                #endif
            case .defaults: if let id = editingCollectionID { FolderSettingsView(store: store, collectionID: id, folderID: editingFolderID) }
            }
        }
        .alert("Workspace", isPresented: Binding(get: { sheet == nil && (store.issue != nil || store.notice != nil) }, set: { if !$0 { store.issue = nil; store.notice = nil } })) {
            Button("OK") { store.issue = nil; store.notice = nil }
        } message: { Text(store.issue ?? store.notice ?? "") }
        .alert(renameID == nil ? "New collection" : "Rename collection", isPresented: $newCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Cancel", role: .cancel) { renameID = nil }
            Button("Save") {
                let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                if let id = renameID, let index = store.workspace.collections.firstIndex(where: { $0.id == id }) { store.workspace.collections[index].name = name }
                else { store.workspace.collections.append(RequestCollection(name: name)) }
                renameID = nil
            }
        }
        .alert("New folder", isPresented: $addingFolder) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                guard let c = store.workspace.collections.firstIndex(where: { $0.id == folderCollectionID }), !folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                store.workspace.collections[c].folders = (store.workspace.collections[c].folders ?? []) + [RequestFolder(name: folderName, parentID: folderParentID)]
            }
        }
        .onOpenURL { url in
            if url.scheme == "monkeytail" { return }
            let granted = url.startAccessingSecurityScopedResource()
            defer { if granted { url.stopAccessingSecurityScopedResource() } }
            do { try store.importContent(String(contentsOf: url, encoding: .utf8)) }
            catch { store.issue = error.localizedDescription }
        }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Collections").font(.headline)
                Spacer()
                Menu {
                    Button("New request", systemImage: "plus") { store.addRequest(); compactColumn = .detail }
                    Button("New collection", systemImage: "folder.badge.plus") { collectionName = ""; renameID = nil; newCollection = true }
                } label: { Image(systemName: "plus").frame(width: 44, height: 44) }.accessibilityLabel("Add request or collection")
            }.padding(.leading, 16).padding(.trailing, 4)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a request", text: $search).font(.subheadline).noCapitalization().autocorrectionDisabled()
            }.padding(10).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 12).padding(.bottom, 4)
            List(selection: $store.selectedRequestID) {
                ForEach(store.workspace.collections) { collection in
                    Section {
                        if search.isEmpty {
                            FolderRows(store: store, collectionID: collection.id, edit: { id in editingCollectionID = collection.id; editingFolderID = id; sheet = .defaults }, add: { parent in folderCollectionID = collection.id; folderParentID = parent; folderName = ""; addingFolder = true })
                        }
                        ForEach(collection.requests.filter { search.isEmpty ? $0.folderID == nil : $0.name.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search) }) { request in
                            RequestSidebarRow(store: store, request: request, collectionID: collection.id)
                        }
                    } header: {
                        HStack {
                            Label(collection.name, systemImage: "folder").textCase(nil).font(.subheadline.weight(.medium))
                            Spacer()
                            Menu {
                                Button("Add request", systemImage: "plus") { store.addRequest(to: collection.id) }
                                Button("New folder", systemImage: "folder.badge.plus") { folderCollectionID = collection.id; folderParentID = nil; folderName = ""; addingFolder = true }
                                Button("Collection settings", systemImage: "slider.horizontal.3") { editingCollectionID = collection.id; editingFolderID = nil; sheet = .defaults }
                                Button("Rename", systemImage: "pencil") { renameID = collection.id; collectionName = collection.name; newCollection = true }
                                if collection.requests.isEmpty {
                                    Button("Delete empty collection", systemImage: "trash", role: .destructive) { store.workspace.collections.removeAll { $0.id == collection.id } }
                                }
                            } label: { Image(systemName: "ellipsis").frame(width: 32, height: 32) }.accessibilityLabel("Collection options")
                        }
                    }
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
            Divider()
            VStack(spacing: 2) {
                sidebarButton("Import & export", symbol: "arrow.down.doc", sheet: .transfer)
                sidebarButton("Environments", symbol: "square.stack.3d.up", sheet: .environment)
                sidebarButton("Request history", symbol: "clock.arrow.circlepath", sheet: .history)
                sidebarButton("Snapshots", symbol: "camera", sheet: .snapshots)
                sidebarButton("Cookies & certificates", symbol: "lock.shield", sheet: .network)
                sidebarButton("Settings", symbol: "slider.horizontal.3", sheet: .settings)
            }.padding(8)
        }.background(Palette.canvas)
            .hideNavigationBar()
            .onChange(of: store.selectedRequestID) { _, _ in compactColumn = .detail }
    }

    private func sidebarButton(_ title: String, symbol: String, sheet value: WorkspaceSheet) -> some View {
        Button { sheet = value } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 22, alignment: .center).accessibilityHidden(true)
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
            }.font(.subheadline).padding(.horizontal, 10).frame(height: 42).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(title)
    }

    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if let id = store.selectedRequestID {
                TextField("Request name", text: store.binding(for: id).name)
                    .font(.headline).multilineTextAlignment(.center).submitLabel(.done)
                    .accessibilityIdentifier("Request name")
            }
        }
        ToolbarItem(placement: .workspaceTrailing) {
            Menu {
                Button("No environment") { store.workspace.selectedEnvironmentID = nil }
                ForEach(store.workspace.environments) { env in Button(env.name) { store.workspace.selectedEnvironmentID = env.id } }
                Divider()
                Button("Manage environments…", systemImage: "slider.horizontal.3") { sheet = .environment }
            } label: {
                Text(store.environment?.name ?? "Env").font(.caption.weight(.medium)).lineLimit(1).frame(maxWidth: 80)
            }.accessibilityLabel("Select environment")
        }
        ToolbarItem(placement: .workspaceTrailing) {
            Menu {
                Button("New request", systemImage: "plus") { store.addRequest() }
                if let request = store.selectedRequest {
                    Button(request.favorite == true ? "Unfavourite" : "Favourite", systemImage: request.favorite == true ? "star.slash" : "star") { var value = request; value.favorite = request.favorite != true; store.update(value) }.accessibilityIdentifier("Toggle request favourite")
                }
                #if os(iOS)
                Button("Apple Watch", systemImage: "applewatch") { sheet = .watch }
                #endif
                Button("Client code", systemImage: "curlybraces") { sheet = .code }.disabled(store.selectedRequest == nil)
                Button("Cookies & certificates", systemImage: "lock.shield") { sheet = .network }
                Button("Export cURL", systemImage: "terminal") { sheet = .curl }.disabled(store.selectedRequest == nil)
                Button("Import & export", systemImage: "arrow.down.doc") { sheet = .transfer }.accessibilityIdentifier("Import workspace")
                Button("History", systemImage: "clock.arrow.circlepath") { sheet = .history }
                Button("Snapshots", systemImage: "camera") { sheet = .snapshots }
                Button("Connection settings", systemImage: "slider.horizontal.3") { sheet = .settings }
            } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Workspace actions")
        }
    }
}

struct RequestWorkspace: View {
    @Bindable var store: WorkspaceStore
    let requestID: UUID
    @State private var pane = "Request"
    @State private var inputDismissal = 0
    @FocusState private var urlFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var request: Binding<APIRequest> { store.binding(for: requestID) }
    var body: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 640 && geometry.size.height >= 440 && !dynamicType.isAccessibilitySize
            let stream = request.wrappedValue.transport == .websocket || request.wrappedValue.transport == .sse
            let paneLayout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(ZStackLayout(alignment: .topLeading))
            VStack(spacing: 0) {
                addressBar
                Divider()
                // Keep both panes alive and fully sized on iPhone. A zero-width
                // hidden pane gives its scroll views an invalid initial viewport.
                paneLayout {
                    RequestEditor(request: request, store: store)
                        .disabled(!sideBySide && pane != "Request")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped().opacity(sideBySide || pane == "Request" ? 1 : 0)
                        .allowsHitTesting(sideBySide || pane == "Request")
                        .accessibilityHidden(!sideBySide && pane != "Request")
                    if sideBySide { Divider() }
                    Group {
                        if stream { LiveView(store: store, requestID: requestID) }
                        else { ResponseView(store: store, requestID: requestID) }
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped().opacity(sideBySide || pane == "Response" ? 1 : 0)
                        .allowsHitTesting(sideBySide || pane == "Response")
                        .accessibilityHidden(!sideBySide && pane != "Response")
                }
                Divider()
                HStack(spacing: 12) {
                    if !sideBySide {
                        HStack(spacing: 0) {
                            ForEach(["Request", "Response"], id: \.self) { value in
                                Button {
                                    dismissKeyboard()
                                    pane = value
                                } label: {
                                    Text(stream && value == "Response" ? "Messages" : value).font(.subheadline.weight(pane == value ? .semibold : .regular))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(pane == value ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain).accessibilityAddTraits(pane == value ? .isSelected : [])
                            }
                        }.padding(3).background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: 300).accessibilityIdentifier("Workspace pane")
                    }
                    Spacer(minLength: 0)
                    if !stream {
                    Button(action: send) {
                        Label(store.runningID == requestID ? "Cancel" : "Send", systemImage: store.runningID == requestID ? "stop.fill" : "arrow.up")
                            .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44)
                            .foregroundStyle(Palette.canvas).background(Palette.mint, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(store.runningID != nil && store.runningID != requestID)
                        .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("Send request")
                    }
                }.padding(.horizontal, 12).padding(.vertical, 4).background(Palette.surface)
            }.background(Palette.canvas).environment(\.inputDismissal, inputDismissal)
                .onChange(of: pane) { _, _ in dismissKeyboard() }
                .onChange(of: store.responses[requestID]?.response.id) { _, _ in if !sideBySide { pane = "Response" } }
                .onChange(of: store.errors[requestID]) { _, error in if error != nil && !sideBySide { pane = "Response" } }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 0) {
            Menu {
                ForEach(RequestTransport.allCases, id: \.self) { transport in Button(transport.rawValue) {
                    request.transport.wrappedValue = transport
                    if transport == .graphql { request.method.wrappedValue = "POST" }
                    if transport == .sse { request.method.wrappedValue = "GET" }
                    if transport == .websocket { request.url.wrappedValue = request.url.wrappedValue.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://") }
                    else { request.url.wrappedValue = request.url.wrappedValue.replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(of: "ws://", with: "http://") }
                } }
            } label: { Image(systemName: request.wrappedValue.transport == .websocket ? "arrow.left.arrow.right" : request.wrappedValue.transport == .graphql ? "point.3.connected.trianglepath.dotted" : "network").frame(width: 36, height: 44) }.buttonStyle(.plain).accessibilityLabel("Request protocol")
            Menu {
                ForEach(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"], id: \.self) { method in Button(method) { request.method.wrappedValue = method } }
            } label: {
                HStack(spacing: 4) {
                    Text(request.method.wrappedValue).font(.system(.footnote, design: .monospaced, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }.foregroundStyle(Palette.method(request.method.wrappedValue)).padding(.horizontal, 12).frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel("HTTP method")
            Divider().frame(height: 20)
            TextField("https://api.example.com", text: request.url)
                .font(.system(.footnote, design: .monospaced)).urlInput()
                .noCapitalization().autocorrectionDisabled().focused($urlFocused)
                .submitLabel(.go).onSubmit(send).padding(.horizontal, 10).frame(minHeight: 44)
                .accessibilityIdentifier("Request URL")
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func dismissKeyboard() {
        urlFocused = false
        inputDismissal += 1
        #if os(iOS) || os(visionOS)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) where scene.activationState == .foregroundActive {
            for window in scene.windows where window.isKeyWindow { window.endEditing(true) }
        }
        #endif
    }
    private func send() {
        dismissKeyboard()
        if store.runningID == requestID { store.cancel() } else { store.send() }
    }
}
