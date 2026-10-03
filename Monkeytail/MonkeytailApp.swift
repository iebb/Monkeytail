import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct MonkeytailApp: App {
    @State private var store = WorkspaceStore()
    @Environment(\.scenePhase) private var phase
    init() {
        ResponsePreview.removeStaleMedia()
        #if os(iOS)
        _ = WatchCompanionLink.shared
        #endif
    }
    private var root: some View {
        WorkspaceView(store: store).tint(Palette.mint)
            .onChange(of: phase) { _, value in
                if value == .background { store.save(); store.mockServer.stop() }
                else if value == .active { Task { await store.synchronize() } }
                else { store.save() }
            }
    }
    var body: some Scene {
        #if os(macOS)
        WindowGroup { root.frame(minWidth: 800, minHeight: 560) }
            .defaultSize(width: 1280, height: 800)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("New request") { store.addRequest() }.keyboardShortcut("n", modifiers: .command)
                    Button("Send request") { if store.runningID != nil { store.cancel() } else { store.send() } }.keyboardShortcut(.return, modifiers: .command)
                }
                CommandMenu("Workspace") {
                    Button("Reset window size") { if let window = NSApp.keyWindow { var frame = window.frame; frame.origin.y += frame.height - 800; frame.size = NSSize(width: 1280, height: 800); window.setFrame(frame, display: true) } }
                }
                SidebarCommands()
            }
        Settings { SettingsView(store: store) }
        #elseif os(visionOS)
        WindowGroup { root.frame(minWidth: 750, minHeight: 550) }
            .defaultSize(width: 1280, height: 800)
            .windowResizability(.contentMinSize)
        #else
        WindowGroup { root }
        #endif
    }
}
