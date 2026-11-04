import SwiftUI
#if os(macOS)
import AppKit
#endif
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
    #if os(macOS)
    @State private var searchFocused = false
    @AppStorage("macWorkspaceLayout") private var macWorkspaceLayout = "stacked"
    #else
    @FocusState private var searchFocused: Bool
    #endif
    @State private var newCollection = false
    @State private var collectionName = ""
    @State private var renameID: UUID?
    @State private var folderCollectionID: UUID?
    @State private var folderParentID: UUID?
    @State private var addingFolder = false
    @State private var folderName = ""
    @State private var editingCollectionID: UUID?
    @State private var editingFolderID: UUID?
    @State private var runnerCollectionID: UUID?
    @State private var runnerFolderID: UUID?

    enum WorkspaceSheet: String, Identifiable { case transfer, environment, settings, history, snapshots, curl, code, network, defaults, watch, runner; var id: String { rawValue } }

    var body: some View {
        GeometryReader { geometry in
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            sidebar.navigationSplitViewColumnWidth(min: 240, ideal: 272, max: 340)
        } detail: {
            if let request = store.selectedRequest {
                VStack(spacing: 0) {
                    #if os(macOS)
                    RequestTabStrip(store: store); Divider()
                    #else
                    if geometry.size.width >= 700 { RequestTabStrip(store: store); Divider() }
                    #endif
                    RequestWorkspace(store: store, requestID: request.id)
                        .id(request.id)
                }
                    .requestWindowTitle(request.name)
                    .toolbar { workspaceToolbar }
            } else {
                emptyWorkspace.toolbar { workspaceToolbar }
            }
        }
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .focusedSceneValue(\.workspaceActions, WorkspaceActions(
            findRequest: { visibility = .all; searchFocused = true },
            importExport: { sheet = .transfer },
            exportCurl: { if store.selectedRequest != nil { sheet = .curl } }
        ))
        #else
        .onAppear { visibility = geometry.size.width >= 1100 ? .all : .detailOnly }
        .onChange(of: geometry.size.width) { _, width in visibility = width >= 1100 ? .all : .detailOnly }
        #endif
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
            case .runner: if let id = runnerCollectionID { CollectionRunnerView(store: store, collectionID: id, folderID: runnerFolderID) }
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

    private var emptyWorkspace: some View {
        VStack(spacing: 16) {
            #if os(macOS)
            EmptyPanel(title: "No request selected", message: "Select a request or create one.", symbol: "terminal")
                .frame(maxHeight: 180)
            #else
            EmptyPanel(title: "Your next request starts here", message: "Select a request from Collections, or create something new.", symbol: "terminal")
                .frame(maxHeight: 240)
            #endif
            HStack(spacing: 12) {
                Button("New request", systemImage: "plus") { store.addRequest() }.buttonStyle(.borderedProminent)
                Button("Import", systemImage: "arrow.down.doc") { sheet = .transfer }.buttonStyle(.bordered)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            #if !os(macOS)
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill").font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Palette.mint).frame(width: 38, height: 38)
                    .background(Palette.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monkeytail").font(.headline)
                    Text("API workspace").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(SidebarMetrics.horizontalInset).padding(.top, 4)
            #endif
            HStack(alignment: .center, spacing: 8) {
                Text("Collections")
                    #if os(macOS)
                    .font(.system(size: 13, weight: .semibold))
                    #else
                    .font(.headline)
                    #endif
                Spacer()
                Menu {
                    Button("New request", systemImage: "plus") { store.addRequest(); compactColumn = .detail }
                    Button("New collection", systemImage: "folder.badge.plus") { collectionName = ""; renameID = nil; newCollection = true }
                } label: { Image(systemName: "plus").frame(width: SidebarMetrics.rowHeight, height: SidebarMetrics.rowHeight) }
                .borderlessMenu()
                .accessibilityLabel("Add request or collection")
            }.padding(.horizontal, SidebarMetrics.horizontalInset)
                #if os(macOS)
                .padding(.top, 8).padding(.bottom, 6)
                #endif
            #if os(macOS)
            MacRequestSearchField(text: $search, focused: $searchFocused)
                .frame(height: 28)
                .padding(.horizontal, SidebarMetrics.horizontalInset)
                .padding(.bottom, 12)
            #else
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a request", text: $search).textFieldStyle(.plain).font(.subheadline).noCapitalization().autocorrectionDisabled()
                    .focused($searchFocused).accessibilityIdentifier("Find a request")
            }.padding(.horizontal, 12).frame(minHeight: SidebarMetrics.rowHeight)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.border))
                .padding(.horizontal, SidebarMetrics.horizontalInset).padding(.bottom, 8)
            #endif
            List(selection: $store.selectedRequestID) {
                ForEach(store.workspace.collections) { collection in
                    Section {
                        if search.isEmpty {
                            FolderRows(store: store, collectionID: collection.id, edit: { id in editingCollectionID = collection.id; editingFolderID = id; sheet = .defaults }, add: { parent in folderCollectionID = collection.id; folderParentID = parent; folderName = ""; addingFolder = true }, run: { id in runCollection(collection.id, folder: id) })
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
                                Button("Run collection", systemImage: "play.circle") { runCollection(collection.id, folder: nil) }
                                Button("Collection settings", systemImage: "slider.horizontal.3") { editingCollectionID = collection.id; editingFolderID = nil; sheet = .defaults }
                                Button("Rename", systemImage: "pencil") { renameID = collection.id; collectionName = collection.name; newCollection = true }
                                if collection.requests.isEmpty {
                                    Button("Delete empty collection", systemImage: "trash", role: .destructive) { store.workspace.collections.removeAll { $0.id == collection.id } }
                                }
                            } label: { Image(systemName: "ellipsis").frame(width: SidebarMetrics.rowHeight, height: SidebarMetrics.rowHeight) }.borderlessMenu().buttonStyle(.plain).accessibilityLabel("Collection options")
                        }
                        .frame(minHeight: SidebarMetrics.rowHeight)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: SidebarMetrics.horizontalInset, bottom: 0, trailing: SidebarMetrics.horizontalInset))
                }
            }
                #if os(macOS)
                .listStyle(.sidebar)
                #else
                .listStyle(.plain)
                #endif
                .scrollContentBackground(.hidden)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .environment(\.defaultMinListRowHeight, SidebarMetrics.rowHeight)
                .environment(\.defaultMinListHeaderHeight, SidebarMetrics.rowHeight)
            Divider()
            VStack(spacing: 0) {
                Text("WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, SidebarMetrics.horizontalInset).padding(.top, 8).padding(.bottom, 6)
                sidebarButton("Import & export", symbol: "arrow.down.doc", sheet: .transfer)
                sidebarButton("Environments", symbol: "square.stack.3d.up", sheet: .environment)
                sidebarButton("Request history", symbol: "clock.arrow.circlepath", sheet: .history)
                sidebarButton("Snapshots", symbol: "camera", sheet: .snapshots)
                sidebarButton("Cookies & certificates", symbol: "lock.shield", sheet: .network)
                sidebarButton("Settings", symbol: "slider.horizontal.3", sheet: .settings)
            }.padding(.vertical, 8)
        }
            #if os(macOS)
            .background(MacSidebarBackground())
            #else
            .background(Palette.canvas)
            #endif
            .hideNavigationBar()
            .onChange(of: store.selectedRequestID) { _, id in
                if id != nil { compactColumn = .detail }
            }
    }

    @ViewBuilder private func sidebarButton(_ title: String, symbol: String, sheet value: WorkspaceSheet) -> some View {
        #if os(macOS)
        if value == .settings {
            SettingsLink { sidebarActionLabel(title, symbol: symbol) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(title)
        } else {
            Button { sheet = value } label: { sidebarActionLabel(title, symbol: symbol) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(title)
        }
        #else
        Button { sheet = value } label: { sidebarActionLabel(title, symbol: symbol) }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(title)
        #endif
    }

    private func runCollection(_ id: UUID, folder: UUID?) {
        runnerCollectionID = id; runnerFolderID = folder; sheet = .runner
    }

    private func sidebarActionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22, alignment: .center).accessibilityHidden(true)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.subheadline).padding(.horizontal, SidebarMetrics.horizontalInset)
            .frame(minHeight: SidebarMetrics.rowHeight).contentShape(Rectangle())
    }

    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            if let id = store.selectedRequestID {
                TextField("Request name", text: store.binding(for: id).name)
                    .textFieldStyle(.plain).font(.headline).submitLabel(.done)
                    .frame(minWidth: 140, idealWidth: 240, maxWidth: 360, alignment: .leading)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("Request name")
            }
        }.flatToolbarBackground()
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        } else {
            ToolbarItem(placement: .principal) { Spacer() }
        }
        #else
        ToolbarItem(placement: .principal) {
            if let id = store.selectedRequestID {
                TextField("Request name", text: store.binding(for: id).name)
                    .textFieldStyle(.plain).font(.headline).multilineTextAlignment(.center).submitLabel(.done)
                    .accessibilityIdentifier("Request name")
            }
        }
        #endif
        ToolbarItem(placement: .workspaceTrailing) {
            Menu {
                Button("No environment") { store.workspace.selectedEnvironmentID = nil }
                ForEach(store.workspace.environments) { env in Button(env.name) { store.workspace.selectedEnvironmentID = env.id } }
                Divider()
                Button("Manage environments…", systemImage: "slider.horizontal.3") { sheet = .environment }
            } label: {
                HStack(spacing: 6) {
                    Text(store.environment?.name ?? "No environment")
                    #if os(macOS)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                    #endif
                }
                    #if os(macOS)
                    .font(.system(size: NSFont.preferredFont(forTextStyle: .caption1).pointSize + 1, weight: .medium))
                    .foregroundStyle(.primary).lineLimit(1).padding(.horizontal, 6).frame(maxWidth: 180, minHeight: 28)
                    #else
                    .font(.caption.weight(.medium)).lineLimit(1).frame(maxWidth: 80)
                    #endif
            }.borderlessMenu().accessibilityLabel("Select environment")
        }.flatToolbarBackground()
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
                if let collection = store.workspace.collections.first(where: { $0.requests.contains { $0.id == store.selectedRequestID } }) {
                    Button("Run collection", systemImage: "play.circle") { runCollection(collection.id, folder: nil) }
                }
                Button("Cookies & certificates", systemImage: "lock.shield") { sheet = .network }
                Button("Export cURL", systemImage: "terminal") { sheet = .curl }.disabled(store.selectedRequest == nil)
                Button("Import & export", systemImage: "arrow.down.doc") { sheet = .transfer }.accessibilityIdentifier("Import workspace")
                Button("History", systemImage: "clock.arrow.circlepath") { sheet = .history }
                Button("Snapshots", systemImage: "camera") { sheet = .snapshots }
                #if os(macOS)
                Divider()
                Menu("Workspace layout") {
                    Button { macWorkspaceLayout = "stacked" } label: {
                        if macWorkspaceLayout == "stacked" { Label("Request above response", systemImage: "checkmark") } else { Text("Request above response") }
                    }
                    Button { macWorkspaceLayout = "sideBySide" } label: {
                        if macWorkspaceLayout == "sideBySide" { Label("Side by side", systemImage: "checkmark") } else { Text("Side by side") }
                    }
                }
                Divider()
                SettingsLink { Label("Settings", systemImage: "slider.horizontal.3") }
                #else
                Button("Settings", systemImage: "slider.horizontal.3") { sheet = .settings }.accessibilityIdentifier("Connection settings")
                #endif
            } label: {
                #if os(macOS)
                Image(systemName: "ellipsis").frame(width: 28, height: 28).foregroundStyle(.primary)
                #else
                Image(systemName: "ellipsis.circle")
                #endif
            }.borderlessMenu().accessibilityLabel("Workspace actions")
        }.flatToolbarBackground()
    }
}

struct RequestWorkspace: View {
    @Bindable var store: WorkspaceStore
    let requestID: UUID
    @State private var pane = "Request"
    @State private var inputDismissal = 0
    #if os(macOS)
    @AppStorage("macRequestPaneFraction") private var requestPaneFraction = 0.42
    @AppStorage("macStackedRequestFraction") private var stackedRequestFraction = 0.45
    @AppStorage("macWorkspaceLayout") private var macWorkspaceLayout = "stacked"
    @State private var dividerStart: Double?
    @State private var dividerHovered = false
    #endif
    @FocusState private var urlFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicType
    private var request: Binding<APIRequest> { store.binding(for: requestID) }
    var body: some View {
        GeometryReader { geometry in
            #if os(macOS)
            let sideBySide = geometry.size.height >= 440 && !dynamicType.isAccessibilitySize && (macWorkspaceLayout == "stacked" || geometry.size.width >= 640)
            #else
            let sideBySide = geometry.size.width >= 640 && geometry.size.height >= 440 && !dynamicType.isAccessibilitySize
            #endif
            let stream = request.wrappedValue.transport == .websocket || request.wrappedValue.transport == .sse
            let paneLayout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(ZStackLayout(alignment: .topLeading))
            VStack(spacing: 0) {
                addressBar(showSend: sideBySide && !stream)
                VariableAssist(text: request.url, insets: EdgeInsets(top: -4, leading: WorkspaceMetrics.inset, bottom: WorkspaceMetrics.inset - 2, trailing: WorkspaceMetrics.inset))
                Divider()
                // Keep both panes alive and fully sized on iPhone. A zero-width
                // hidden pane gives its scroll views an invalid initial viewport.
                #if os(macOS)
                if sideBySide {
                    macPanes(stream: stream)
                } else {
                    compactPanes(sideBySide: false, stream: stream, layout: paneLayout)
                }
                #else
                compactPanes(sideBySide: sideBySide, stream: stream, layout: paneLayout)
                #endif
                Divider()
                if !sideBySide {
                    HStack(spacing: 12) {
                        HStack(spacing: 0) {
                            ForEach(["Request", "Response"], id: \.self) { value in
                                Button {
                                    dismissKeyboard()
                                    pane = value
                                } label: {
                                    Text(stream && value == "Response" ? "Messages" : value)
                                        .font(.subheadline.weight(pane == value ? .semibold : .regular))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(pane == value ? Palette.mint : Color.secondary)
                                        .background(pane == value ? Palette.surface : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain).accessibilityAddTraits(pane == value ? .isSelected : [])
                            }
                        }.padding(3).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 11))
                            .frame(maxWidth: 300).accessibilityIdentifier("Workspace pane")
                        Spacer(minLength: 0)
                        if !stream { sendButton }
                    }.padding(.horizontal, 16).padding(.vertical, 8).background(Palette.surface)
                }
                #if !os(macOS)
                if sideBySide {
                    HStack {
                        Label(store.runningID == requestID ? "Sending request…" : "Changes save automatically", systemImage: store.runningID == requestID ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                        Spacer()
                        if !stream { Text("⌘ ↵  Send request") }
                    }.font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).frame(height: 30).background(Palette.surface)
                }
                #endif
            }.background(Palette.canvas).environment(\.inputDismissal, inputDismissal).environment(\.variableHints, store.variableHints(for: request.wrappedValue))
                .onChange(of: pane) { _, _ in dismissKeyboard() }
                .onChange(of: store.responses[requestID]?.response.id) { _, _ in if !sideBySide { pane = "Response" } }
                .onChange(of: store.errors[requestID]) { _, error in if error != nil && !sideBySide { pane = "Response" } }
        }
    }

    #if os(macOS)
    private func macPanes(stream: Bool) -> some View {
        GeometryReader { geometry in
            let stacked = macWorkspaceLayout == "stacked"
            let extent = stacked ? geometry.size.height : geometry.size.width
            let requestMinimum: CGFloat = stacked ? 150 : 280
            let responseMinimum: CGFloat = stacked ? 150 : 327
            let fraction = stacked ? stackedRequestFraction : requestPaneFraction
            let requestExtent = max(requestMinimum, min(extent - responseMinimum, extent * fraction))
            let layout = stacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                RequestEditor(request: request, store: store)
                    .frame(width: stacked ? nil : requestExtent, height: stacked ? requestExtent : nil)
                    .frame(maxWidth: stacked ? .infinity : nil, maxHeight: stacked ? nil : .infinity)
                    .clipped()
                Rectangle().fill(Palette.border)
                    .frame(width: stacked ? nil : 1, height: stacked ? 1 : nil)
                    .padding(stacked ? .vertical : .horizontal, 3).contentShape(Rectangle())
                    .onHover { hovered in
                        guard hovered != dividerHovered else { return }
                        dividerHovered = hovered
                        if hovered { (stacked ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() } else { NSCursor.pop() }
                    }
                    .onChange(of: stacked) { _, newValue in
                        if dividerHovered { NSCursor.pop(); (newValue ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() }
                    }
                    .onDisappear { if dividerHovered { NSCursor.pop(); dividerHovered = false } }
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            guard extent > requestMinimum + responseMinimum else { return }
                            if dividerStart == nil { dividerStart = requestExtent / extent }
                            let translation = stacked ? value.translation.height : value.translation.width
                            let next = max(requestMinimum / extent, min(1 - responseMinimum / extent, (dividerStart ?? fraction) + translation / extent))
                            if stacked { stackedRequestFraction = next } else { requestPaneFraction = next }
                        }.onEnded { _ in dividerStart = nil })
                    .accessibilityLabel("Request and response divider")
                    .accessibilityAdjustableAction { direction in
                        guard extent > requestMinimum + responseMinimum else { return }
                        let change = direction == .increment ? 0.05 : -0.05
                        let next = max(requestMinimum / extent, min(1 - responseMinimum / extent, fraction + change))
                        if stacked { stackedRequestFraction = next } else { requestPaneFraction = next }
                    }
                responsePane(stream: stream)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
    }
    #endif

    @ViewBuilder private func responsePane(stream: Bool) -> some View {
        if stream { LiveView(store: store, requestID: requestID) }
        else { ResponseView(store: store, requestID: requestID) }
    }

    private func compactPanes(sideBySide: Bool, stream: Bool, layout: AnyLayout) -> some View {
        layout {
            RequestEditor(request: request, store: store)
                .disabled(!sideBySide && pane != "Request")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped().opacity(sideBySide || pane == "Request" ? 1 : 0)
                .allowsHitTesting(sideBySide || pane == "Request")
                .accessibilityHidden(!sideBySide && pane != "Request")
            if sideBySide { Divider() }
            responsePane(stream: stream)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped().opacity(sideBySide || pane == "Response" ? 1 : 0)
                .allowsHitTesting(sideBySide || pane == "Response")
                .accessibilityHidden(!sideBySide && pane != "Response")
        }
    }

    private func addressBar(showSend: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Menu {
                    ForEach(RequestTransport.allCases, id: \.self) { transport in Button(transport.rawValue) {
                        request.transport.wrappedValue = transport
                        if transport == .graphql { request.method.wrappedValue = "POST" }
                        if transport == .sse { request.method.wrappedValue = "GET" }
                        if transport == .websocket { request.url.wrappedValue = request.url.wrappedValue.replacingOccurrences(of: "https://", with: "wss://").replacingOccurrences(of: "http://", with: "ws://") }
                        else { request.url.wrappedValue = request.url.wrappedValue.replacingOccurrences(of: "wss://", with: "https://").replacingOccurrences(of: "ws://", with: "http://") }
                    } }
                } label: { Image(systemName: request.wrappedValue.transport == .websocket ? "arrow.left.arrow.right" : request.wrappedValue.transport == .graphql ? "point.3.connected.trianglepath.dotted" : "network").frame(width: 36, height: max(36, WorkspaceMetrics.controlHeight)) }.borderlessMenu().buttonStyle(.plain).accessibilityLabel("Request protocol")
                Menu {
                    ForEach(["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"], id: \.self) { method in Button(method) { request.method.wrappedValue = method } }
                } label: {
                    HStack(spacing: 4) {
                        Text(request.method.wrappedValue).font(.system(.footnote, design: .monospaced, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }.foregroundStyle(Palette.method(request.method.wrappedValue)).padding(.horizontal, 12).frame(minHeight: max(36, WorkspaceMetrics.controlHeight))
                }.borderlessMenu().buttonStyle(.plain).accessibilityLabel("HTTP method")
                Divider().frame(height: 20)
                TextField("https://api.example.com", text: request.url)
                    .textFieldStyle(.plain).font(.system(.footnote, design: .monospaced)).urlInput()
                    .noCapitalization().autocorrectionDisabled().focused($urlFocused)
                    .submitLabel(.go).onSubmit(send).padding(.horizontal, 10).frame(minHeight: max(36, WorkspaceMetrics.controlHeight))
                    .accessibilityIdentifier("Request URL")
            }.background(Palette.surface, in: RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius).strokeBorder(urlFocused ? Palette.mint : Palette.border, lineWidth: urlFocused ? 1.5 : 1))
            if showSend { sendButton }
        }.padding(WorkspaceMetrics.inset)
    }

    private var sendButton: some View {
        Button(action: send) {
            Label(store.runningID == requestID ? "Cancel" : "Send", systemImage: store.runningID == requestID ? "stop.fill" : "arrow.up")
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 20).frame(minHeight: max(36, WorkspaceMetrics.controlHeight))
                .foregroundStyle(Palette.surface).background(Palette.mint, in: RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius))
        }.buttonStyle(.plain).disabled((store.runningID != nil && store.runningID != requestID) || store.collectionRun?.running == true)
            .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("Send request")
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

/// Postman-style tabs for requests opened this session.
struct RequestTabStrip: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        let tabs = store.openRequestIDs.compactMap { store.request($0) }
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs) { request in
                        let selected = request.id == store.selectedRequestID
                        HStack(spacing: 6) {
                            Button { store.selectedRequestID = request.id } label: {
                                HStack(spacing: 6) {
                                    Text(request.transport == .websocket ? "WS" : request.transport == .sse ? "SSE" : request.method)
                                        .font(.system(.caption2, design: .monospaced, weight: .bold)).foregroundStyle(Palette.method(request.method))
                                    Text(request.name).font(.caption.weight(selected ? .semibold : .regular)).lineLimit(1)
                                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                                }.frame(maxWidth: 200, minHeight: 34).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel("\(request.method) \(request.name) tab").accessibilityAddTraits(selected ? .isSelected : [])
                            Button { store.closeTabs([request.id]) } label: { Image(systemName: "xmark").font(.caption2.weight(.semibold)).frame(width: 20, height: 20) }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close \(request.name) tab")
                        }.padding(.leading, 12).padding(.trailing, 6)
                            .background(selected ? Palette.surface : Color.clear)
                            .overlay(alignment: .bottom) { if selected { Rectangle().fill(Palette.mint).frame(height: 2) } }
                            .overlay(alignment: .trailing) { Divider().frame(height: 18) }
                            .contextMenu {
                                Button("Close tab") { store.closeTabs([request.id]) }
                                Button("Close other tabs") { store.closeTabs(Set(store.openRequestIDs).subtracting([request.id])) }
                                Button("Duplicate request") { store.duplicate(request) }
                            }
                            .id(request.id)
                    }
                    Button { store.addRequest(to: store.workspace.collections.first { $0.requests.contains { $0.id == store.selectedRequestID } }?.id) } label: {
                        Image(systemName: "plus").frame(width: 34, height: 34)
                    }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("New request tab")
                }
            }.onChange(of: store.selectedRequestID) { _, id in if let id { withAnimation { proxy.scrollTo(id) } } }
        }.background(Palette.canvas).accessibilityIdentifier("Request tabs")
            .onAppear { if let id = store.selectedRequestID { store.openTab(id) } }
    }
}
