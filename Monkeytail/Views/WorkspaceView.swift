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
    @FocusState private var searchFocused: Bool
    #if os(macOS)
    @AppStorage("macWorkspaceLayout") private var macWorkspaceLayout = "stacked"
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
    @State private var editingWorkspace = false
    @State private var renamingWorkspace = false
    @State private var workspaceName = ""
    @State private var deletingWorkspace = false
    @State private var deletingCollection: RequestCollection?

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
        .toolbar(removing: .sidebarToggle)
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
                else {
                    var collection = RequestCollection(name: name)
                    collection.workspaceID = store.activeWorkspaceID == Workspace.defaultWorkspaceID ? nil : store.activeWorkspaceID
                    store.workspace.collections.append(collection)
                }
                renameID = nil
            }
        }
        .alert("New folder", isPresented: $addingFolder) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Add") { if let id = folderCollectionID { store.addFolder(named: folderName, to: id, parent: folderParentID) } }
        }
        .alert(renamingWorkspace ? "Rename workspace" : "New workspace", isPresented: $editingWorkspace) {
            TextField("Workspace name", text: $workspaceName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = workspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                if renamingWorkspace { store.renameWorkspace(store.activeWorkspaceID, to: name) } else { store.addWorkspace(named: name) }
            }
        } message: { if !renamingWorkspace { Text("Each workspace has its own collections, environments and globals.") } }
        .confirmationDialog(Text("Delete \(store.name(of: store.activeWorkspace))?"), isPresented: $deletingWorkspace, titleVisibility: .visible) {
            Button("Delete workspace", role: .destructive) { store.deleteWorkspace(store.activeWorkspaceID) }
        } message: { Text("Its \(store.collections.count) collections and \(store.environments.count) environments are deleted on every device that syncs.") }
        .confirmationDialog(Text("Delete \(deletingCollection?.name ?? "")?"), isPresented: Binding(get: { deletingCollection != nil }, set: { if !$0 { deletingCollection = nil } }), titleVisibility: .visible) {
            Button("Delete collection", role: .destructive) {
                if let id = deletingCollection?.id { store.workspace.collections.removeAll { $0.id == id }; store.keepSelectionInWorkspace() }
                deletingCollection = nil
            }
        } message: { Text("^[\(deletingCollection?.requests.count ?? 0) request](inflect: true) will be deleted.") }
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
                Button("New request", systemImage: "plus") { store.addRequest(to: currentCollection?.id) }.prominentButton()
                Button("Import", systemImage: "arrow.down.doc") { sheet = .transfer }.secondaryButton()
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.canvas)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 4) {
                workspaceSwitcher
                Menu {
                    Button("New request", systemImage: "plus") { store.addRequest(to: currentCollection?.id); compactColumn = .detail }
                    Button("New collection…", systemImage: "rectangle.stack.badge.plus") { collectionName = ""; renameID = nil; newCollection = true }
                    if let collection = currentCollection {
                        Button("New folder in \(collection.name)", systemImage: "folder.badge.plus") { folderCollectionID = collection.id; folderParentID = nil; folderName = ""; addingFolder = true }
                    }
                    Divider()
                    Button("Import…", systemImage: "arrow.down.doc") { sheet = .transfer }
                } label: { Image(systemName: "plus").frame(width: SidebarMetrics.rowHeight, height: SidebarMetrics.rowHeight).contentShape(Rectangle()) }
                .borderlessMenu()
                .accessibilityLabel("Add request or collection")
            }.padding(.leading, SidebarMetrics.horizontalInset).padding(.trailing, SidebarMetrics.horizontalInset - 8)
                #if os(macOS)
                .padding(.top, 8).padding(.bottom, 6)
                #else
                .padding(.top, 4).padding(.bottom, 8)
                #endif
            SearchField(placeholder: "Find a request", text: $search, focused: $searchFocused)
                .padding(.horizontal, SidebarMetrics.horizontalInset).padding(.bottom, 8)
            SidebarTree(store: store, search: search, actions: SidebarTreeActions(
                newFolder: { collection, parent in folderCollectionID = collection; folderParentID = parent; folderName = ""; addingFolder = true },
                settings: { collection, folder in editingCollectionID = collection; editingFolderID = folder; sheet = .defaults },
                run: { collection, folder in runCollection(collection, folder: folder) },
                rename: { collection in renameID = collection.id; collectionName = collection.name; newCollection = true },
                delete: { collection in deletingCollection = collection },
                newCollection: { collectionName = ""; renameID = nil; newCollection = true },
                opened: { compactColumn = .detail }
            ))
            Divider()
            HStack(spacing: 0) {
                sidebarButton("Import & export", symbol: "arrow.down.doc", sheet: .transfer)
                sidebarButton("Environments", symbol: "square.stack.3d.up", sheet: .environment)
                sidebarButton("Request history", symbol: "clock.arrow.circlepath", sheet: .history)
                sidebarButton("Snapshots", symbol: "camera", sheet: .snapshots)
                sidebarButton("Cookies & certificates", symbol: "lock.shield", sheet: .network)
                sidebarButton("Settings", symbol: "gearshape", sheet: .settings)
            }.padding(.horizontal, 8).padding(.vertical, 4)
        }
            #if os(macOS)
            .background(MacSidebarBackground())
            #else
            .background(Palette.canvas)
            #endif
            .hideNavigationBar()
            #if os(macOS)
            .toolbar(removing: .sidebarToggle)
            .toolbar { ToolbarItem { sidebarToggle }.flatToolbarBackground() }
            #endif
            .onChange(of: store.selectedRequestID) { _, id in
                if id != nil { compactColumn = .detail }
            }
    }

    #if os(macOS)
    /// A flat stand-in for the system's glass sidebar button.
    private var sidebarToggle: some View {
        Button { withAnimation { visibility = visibility == .detailOnly ? .all : .detailOnly } } label: {
            Image(systemName: "sidebar.left").foregroundStyle(.secondary).frame(width: 28, height: 28).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Toggle sidebar").accessibilityLabel("Toggle sidebar")
    }
    #endif

    @ViewBuilder private func sidebarButton(_ title: LocalizedStringKey, symbol: String, sheet value: WorkspaceSheet) -> some View {
        #if os(macOS)
        if value == .settings {
            SettingsLink { sidebarActionLabel(symbol: symbol) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(title).accessibilityLabel(title)
        } else {
            Button { sheet = value } label: { sidebarActionLabel(symbol: symbol) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help(title).accessibilityLabel(title)
        }
        #else
        Button { sheet = value } label: { sidebarActionLabel(symbol: symbol) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(title).accessibilityLabel(title)
        #endif
    }

    private func sidebarActionLabel(symbol: String) -> some View {
        Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: SidebarMetrics.rowHeight).contentShape(Rectangle())
    }

    /// Where new requests go: the selected request's collection, else the workspace's first.
    private var currentCollection: RequestCollection? {
        store.collections.first { $0.requests.contains { $0.id == store.selectedRequestID } } ?? store.collections.first
    }

    private var workspaceSwitcher: some View {
        let active = store.activeWorkspace
        return Menu {
            Section("Workspaces") {
                ForEach(store.workspace.workspaceList) { space in
                    Button { store.switchWorkspace(to: space.id) } label: {
                        if space.id == active.id { Label { Text(verbatim: store.name(of: space)) } icon: { Image(systemName: "checkmark") } }
                        else { Text(verbatim: store.name(of: space)) }
                    }
                }
            }
            Divider()
            Button("New workspace…", systemImage: "plus.rectangle.on.rectangle") { workspaceName = ""; renamingWorkspace = false; editingWorkspace = true }
            Button("Rename workspace…", systemImage: "pencil") { workspaceName = store.name(of: active); renamingWorkspace = true; editingWorkspace = true }
            if active.id != Workspace.defaultWorkspaceID {
                Button("Delete workspace…", systemImage: "trash", role: .destructive) { deletingWorkspace = true }
            }
        } label: {
            HStack(spacing: 8) {
                #if !os(macOS)
                Image(systemName: "square.stack.3d.up.fill").font(.app(size: 17, weight: .medium))
                    .foregroundStyle(Palette.mint).frame(width: 36, height: 36)
                    .background(Palette.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                #endif
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(verbatim: store.name(of: active)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                        #if os(macOS)
                        .font(.app(size: 13, weight: .semibold))
                        #else
                        .font(.headline)
                        #endif
                        .foregroundStyle(.primary)
                    Text("^[\(store.collections.count) collection](inflect: true)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.frame(minHeight: SidebarMetrics.rowHeight).contentShape(Rectangle())
        }
            #if os(macOS)
            .menuStyle(.button).menuIndicator(.hidden)
            #endif
            .buttonStyle(.plain)
            .accessibilityLabel("Switch workspace").accessibilityValue(Text(verbatim: store.name(of: active)))
            .accessibilityIdentifier("Switch workspace")
    }

    private func runCollection(_ id: UUID, folder: UUID?) {
        runnerCollectionID = id; runnerFolderID = folder; sheet = .runner
    }

    private func sidebarActionLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 22, alignment: .center).accessibilityHidden(true)
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.subheadline).padding(.horizontal, SidebarMetrics.horizontalInset)
            .frame(minHeight: SidebarMetrics.rowHeight).contentShape(Rectangle())
    }

    @ToolbarContentBuilder private var workspaceToolbar: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            if visibility == .detailOnly { sidebarToggle }
        }.flatToolbarBackground()
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
                Button("No environment") { store.selectedEnvironmentID = nil }
                ForEach(store.environments) { env in Button(env.name) { store.selectedEnvironmentID = env.id } }
                Divider()
                Button("Manage environments…", systemImage: "slider.horizontal.3") { sheet = .environment }
            } label: {
                HStack(spacing: 6) {
                    Text(store.environment?.name ?? "No environment")
                    #if os(macOS)
                    Image(systemName: "chevron.down").font(.app(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary).accessibilityHidden(true)
                    #endif
                }
                    #if os(macOS)
                    .font(.app(size: NSFont.preferredFont(forTextStyle: .caption1).pointSize + 1, weight: .medium))
                    .foregroundStyle(.primary).lineLimit(1).padding(.horizontal, 6).frame(maxWidth: 180, minHeight: 28)
                    #else
                    .font(.caption.weight(.medium)).lineLimit(1).frame(maxWidth: 80)
                    #endif
            }.borderlessMenu().accessibilityLabel("Select environment")
        }.flatToolbarBackground()
        ToolbarItem(placement: .workspaceTrailing) {
            Menu {
                Button("New request", systemImage: "plus") { store.addRequest(to: currentCollection?.id) }
                if let request = store.selectedRequest {
                    Button(request.favorite == true ? "Unfavourite" : "Favourite", systemImage: request.favorite == true ? "star.slash" : "star") { var value = request; value.favorite = request.favorite != true; store.update(value) }.accessibilityIdentifier("Toggle request favourite")
                }
                #if os(iOS)
                Button("Apple Watch", systemImage: "applewatch") { sheet = .watch }
                #endif
                Button("Client code", systemImage: "curlybraces") { sheet = .code }.disabled(store.selectedRequest == nil)
                if let collection = currentCollection {
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
    @State private var fold: CGRect?
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
            let tabletop = fold.flatMap { tabletopSplit($0, in: geometry.size) }
            let stream = request.wrappedValue.transport == .websocket || request.wrappedValue.transport == .sse
            let paneLayout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(ZStackLayout(alignment: .topLeading))
            Group {
                if let tabletop { tabletopPanes(top: tabletop.top, bottom: tabletop.bottom, stream: stream) }
                else { standardPanes(sideBySide: sideBySide, stream: stream, layout: paneLayout) }
            }.background(Palette.canvas).environment(\.inputDismissal, inputDismissal).environment(\.variableHints, store.variableHints(for: request.wrappedValue))
                #if os(iOS)
                .background { FoldReader(fold: $fold) }
                #endif
                .onChange(of: pane) { _, _ in dismissKeyboard() }
                .onChange(of: store.responses[requestID]?.response.id) { _, _ in if !sideBySide && tabletop == nil { pane = "Response" } }
                .onChange(of: store.errors[requestID]) { _, error in if error != nil && !sideBySide && tabletop == nil { pane = "Response" } }
        }
    }

    /// Half-folded: read the response above the hinge, edit below it. Nothing crosses the fold.
    private func tabletopSplit(_ fold: CGRect, in size: CGSize) -> (top: CGFloat, bottom: CGFloat)? {
        guard !dynamicType.isAccessibilitySize else { return nil }
        let top = min(fold.minY, fold.midY - 7), bottom = max(fold.maxY, fold.midY + 7)
        return top >= 120 && size.height - bottom >= 200 ? (top, bottom) : nil
    }

    private func tabletopPanes(top: CGFloat, bottom: CGFloat, stream: Bool) -> some View {
        VStack(spacing: 0) {
            responsePane(stream: stream).frame(maxWidth: .infinity).frame(height: top).clipped().background(Palette.surface)
            Color.clear.frame(height: bottom - top).accessibilityHidden(true)
            addressBar(showSend: !stream)
            VariableAssist(text: request.url, insets: EdgeInsets(top: -4, leading: WorkspaceMetrics.inset, bottom: WorkspaceMetrics.inset - 2, trailing: WorkspaceMetrics.inset))
            Divider()
            RequestEditor(request: request, store: store).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
        }
    }

    private func standardPanes(sideBySide: Bool, stream: Bool, layout paneLayout: AnyLayout) -> some View {
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
                    if !stream { sendButton() }
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
                        Image(systemName: "chevron.down").font(.app(size: 8))
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
            if showSend {
                #if os(macOS)
                sendButton()
                #else
                sendButton(minWidth: 120)
                #endif
            }
        }.padding(WorkspaceMetrics.inset)
    }

    private func sendButton(minWidth: CGFloat? = nil) -> some View {
        Button(action: send) {
            Label(store.runningID == requestID ? "Cancel" : "Send", systemImage: store.runningID == requestID ? "stop.fill" : "arrow.up")
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 20).frame(minWidth: minWidth, minHeight: max(36, WorkspaceMetrics.controlHeight))
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
        let requests = store.collections.flatMap(\.requests)
        let tabs = store.openRequestIDs.compactMap { id in requests.first { $0.id == id } }
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
                            Button { store.closeTabs([request.id]); store.keepSelectionInWorkspace() } label: { Image(systemName: "xmark").font(.caption2.weight(.semibold)).frame(width: 20, height: 20) }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close \(request.name) tab")
                        }.padding(.leading, 12).padding(.trailing, 6)
                            .background(selected ? Palette.surface : Color.clear, ignoresSafeAreaEdges: [])
                            .overlay(alignment: .bottom) { if selected { Rectangle().fill(Palette.mint).frame(height: 2) } }
                            .overlay(alignment: .trailing) { Divider().frame(height: 18) }
                            .contextMenu {
                                Button("Close tab") { store.closeTabs([request.id]); store.keepSelectionInWorkspace() }
                                Button("Close other tabs") { store.closeTabs(Set(tabs.map(\.id)).subtracting([request.id])) }
                                Button("Duplicate request") { store.duplicate(request) }
                            }
                            .id(request.id)
                    }
                    Button { store.addRequest(to: store.collections.first { $0.requests.contains { $0.id == store.selectedRequestID } }?.id) } label: {
                        Image(systemName: "plus").frame(width: 34, height: 34)
                    }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("New request tab")
                }
            }.onChange(of: store.selectedRequestID) { _, id in if let id { withAnimation { proxy.scrollTo(id) } } }
        }.background(Palette.canvas).accessibilityIdentifier("Request tabs")
            .onAppear { if let id = store.selectedRequestID { store.openTab(id) } }
    }
}

#if os(iOS)
/// Reports the horizontal fold of a half-open foldable in this view's coordinates, or nil when flat, closed, or unsupported.
struct FoldReader: UIViewRepresentable {
    @Binding var fold: CGRect?
    func makeUIView(context: Context) -> FoldView { let view = FoldView(); view.onChange = { fold = $0 }; return view }
    func updateUIView(_ view: FoldView, context: Context) { view.onChange = { fold = $0 } }
}

final class FoldView: UIView {
    var onChange: ((CGRect?) -> Void)?
    private var partiallyOpen = false
    private var reported: CGRect?
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            addInteraction(UIHingeInteraction { [weak self] _, update in
                self?.partiallyOpen = update.hinge?.status == .partiallyOpen
                self?.refresh()
            })
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() { super.layoutSubviews(); refresh() }
    private func refresh() {
        var fold: CGRect?
        if #available(iOS 27.1, *), partiallyOpen {
            fold = reservedRegions(kind: .division).first { $0.isActive && $0.frame.width > $0.frame.height && $0.frame.width >= bounds.width * 0.9 && bounds.intersects($0.frame) }?.frame
        }
        guard fold != reported else { return }
        reported = fold
        DispatchQueue.main.async { [weak self] in self?.onChange?(fold) }
    }
}
#endif
