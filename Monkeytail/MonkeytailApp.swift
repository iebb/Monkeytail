import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct MonkeytailApp: App {
    @State private var store = WorkspaceStore()
    @Environment(\.scenePhase) private var phase
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    init() {
        ResponsePreview.removeStaleMedia()
        #if os(iOS)
        _ = WatchCompanionLink.shared
        #endif
    }
    private var root: some View {
        WorkspaceView(store: store).themed()
            .onChange(of: phase) { _, value in
                if value == .background { store.save(); store.mockServer.stop() }
                else if value == .active { Task { await store.synchronize() } }
                else { store.save() }
            }
    }
    var body: some Scene {
        #if os(macOS)
        Window("Monkeytail", id: "workspace") {
            root.font(.body).frame(minWidth: 800, minHeight: 560)
                .onDisappear { store.save(); store.mockServer.stop() }
        }
            .defaultSize(width: 1280, height: 800)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("New request") { store.addRequest(to: UUID(uuidString: UserDefaults.standard.string(forKey: "activeCollectionID") ?? "")) }.keyboardShortcut("n", modifiers: .command)
                    Button("Send request") { if store.runningID != nil { store.cancel() } else { store.send() } }.keyboardShortcut(.return, modifiers: .command)
                }
                CommandMenu("Workspace") {
                    Button("Reset window size") { if let window = NSApp.keyWindow { var frame = window.frame; frame.origin.y += frame.height - 800; frame.size = NSSize(width: 1280, height: 800); window.setFrame(frame, display: true) } }
                }
                CommandGroup(before: .windowArrangement) {
                    Button("Show Monkeytail") { openWindow(id: "workspace") }
                        .keyboardShortcut("0", modifiers: .command)
                }
                SidebarCommands()
                WorkspaceCommands()
            }
        Settings { SettingsView(store: store).font(.body).themed() }
        #elseif os(visionOS)
        WindowGroup { root.frame(minWidth: 750, minHeight: 550) }
            .defaultSize(width: 1280, height: 800)
            .windowResizability(.contentMinSize)
        #else
        WindowGroup { root }
        #endif
    }
}
