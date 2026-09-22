import SwiftUI

@main
struct MonkeytailApp: App {
    @State private var store = WorkspaceStore()
    @Environment(\.scenePhase) private var phase
    init() { ResponsePreview.removeStaleMedia() }
    var body: some Scene {
        WindowGroup {
            WorkspaceView(store: store)
                .tint(Palette.mint)
                .onChange(of: phase) { _, value in if value != .active { store.save() } }
        }
    }
}
