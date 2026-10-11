import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Clipboard {
    static func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
}

enum SidebarMetrics {
    #if os(macOS)
    static let rowHeight: CGFloat = 32
    static let horizontalInset: CGFloat = 16
    static let requestRowHeight: CGFloat = 24
    #else
    static let rowHeight: CGFloat = 44
    static let horizontalInset: CGFloat = 16
    static let requestRowHeight: CGFloat = 44
    #endif
}

extension View {
    @ViewBuilder func requestWindowTitle(_ title: String) -> some View {
        #if os(macOS)
        if #available(macOS 15, *) {
            navigationTitle(title).toolbar(removing: .title)
        } else {
            navigationTitle("").background(MacWindowTitle(title: title).frame(width: 0, height: 0))
        }
        #else
        navigationTitle(title).inlineTitle()
        #endif
    }
    @ViewBuilder func borderlessMenu() -> some View {
        #if os(macOS)
        menuStyle(.borderlessButton).menuIndicator(.hidden)
        #else
        self
        #endif
    }
    @ViewBuilder func dismissKeyboardOnScroll() -> some View {
        #if os(visionOS)
        self
        #else
        self.scrollDismissesKeyboard(.interactively)
        #endif
    }
    @ViewBuilder func inlineTitle() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }
    @ViewBuilder func noCapitalization() -> some View {
        #if os(macOS)
        self
        #else
        textInputAutocapitalization(.never)
        #endif
    }
    @ViewBuilder func urlInput() -> some View {
        #if os(macOS)
        self
        #else
        keyboardType(.URL)
        #endif
    }
    @ViewBuilder func numberInput() -> some View {
        #if os(macOS)
        self
        #else
        keyboardType(.numberPad)
        #endif
    }
    @ViewBuilder func hideNavigationBar() -> some View {
        #if os(macOS)
        self
        #else
        toolbar(.hidden, for: .navigationBar)
        #endif
    }
}
extension ToolbarItemPlacement {
    static var workspaceTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }
}
#if os(macOS)
extension ToolbarContent {
    @ToolbarContentBuilder func flatTitleBackground() -> some ToolbarContent {
        if #available(macOS 26, *) { sharedBackgroundVisibility(.hidden) }
        else { self }
    }
}

struct MacWindowTitle: NSViewRepresentable {
    let title: String
    final class TitleView: NSView {
        var title = ""
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateTitle() }
        func updateTitle() { window?.title = title; window?.titleVisibility = .hidden }
    }
    func makeNSView(context: Context) -> TitleView { TitleView() }
    func updateNSView(_ view: TitleView, context: Context) { view.title = title; view.updateTitle() }
}

struct MacSidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct MacRequestSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool

    final class Field: NSSearchField {
        var focusRequested = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if focusRequested { window?.makeFirstResponder(self) }
        }
    }
    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.placeholderString = "Find a request"
        field.controlSize = .regular
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.maximumRecents = 0
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.setAccessibilityLabel("Find a request")
        field.setAccessibilityIdentifier("Find a request")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.focusRequested = focused
        if focused, field.currentEditor() == nil { field.window?.makeFirstResponder(field) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: MacRequestSearchField
        init(_ parent: MacRequestSearchField) { self.parent = parent }
        @objc func searchChanged(_ field: NSSearchField) {
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { searchChanged(field) }
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            if !parent.focused { parent.focused = true }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            if parent.focused { parent.focused = false }
        }
    }
}

struct WorkspaceActions {
    var findRequest: () -> Void
    var importExport: () -> Void
    var exportCurl: () -> Void
}
private struct WorkspaceActionsKey: FocusedValueKey {
    typealias Value = WorkspaceActions
}
extension FocusedValues {
    var workspaceActions: WorkspaceActions? {
        get { self[WorkspaceActionsKey.self] }
        set { self[WorkspaceActionsKey.self] = newValue }
    }
}
struct WorkspaceCommands: Commands {
    @FocusedValue(\.workspaceActions) private var actions
    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import & export…") { actions?.importExport() }
                .keyboardShortcut("i", modifiers: [.command, .shift]).disabled(actions == nil)
            Button("Export cURL…") { actions?.exportCurl() }
                .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(actions == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Find request") { actions?.findRequest() }
                .keyboardShortcut("f", modifiers: .command).disabled(actions == nil)
        }
    }
}

struct ShareSheet: View {
    let items: [Any]
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        VStack(spacing: 12) {
            Text("Export").font(.headline)
            Button("Save…") {
                let panel = NSSavePanel(); panel.canCreateDirectories = true
                if let url = items.first as? URL { panel.nameFieldStringValue = url.lastPathComponent }
                else { panel.nameFieldStringValue = "request.txt" }
                if panel.runModal() == .OK, let target = panel.url {
                    do {
                        if let source = items.first as? URL { try Data(contentsOf: source).write(to: target, options: .atomic) }
                        else if let text = items.first as? String { try text.write(to: target, atomically: true, encoding: .utf8) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }.buttonStyle(.borderedProminent)
            Button("Done") { dismiss() }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(24).frame(minWidth: 300)
    }
}
#endif
