import SwiftUI
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif
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
    static let rowHeight: CGFloat = 28
    static let horizontalInset: CGFloat = 16
    static let requestRowHeight: CGFloat = 28
    static let treeRowHeight: CGFloat = 26
    static let treeInset: CGFloat = 0
    static let indent: CGFloat = 12
    static let methodWidth: CGFloat = 30
    static let methodSize: CGFloat = 10
    static let actionWidth: CGFloat = 22
    /// One size for every tree row, as in Postman.
    static var nameFont: Font { .app(size: 13) }
    #else
    static let rowHeight: CGFloat = 44
    static let horizontalInset: CGFloat = 16
    static let requestRowHeight: CGFloat = 44
    static let treeRowHeight: CGFloat = 40
    static let treeInset: CGFloat = 4
    static let indent: CGFloat = 14
    static let methodWidth: CGFloat = 36
    static let methodSize: CGFloat = 11
    static let actionWidth: CGFloat = 36
    static var nameFont: Font { .subheadline }
    #endif
    /// Postman's short method labels, so names line up.
    static func methodLabel(_ request: APIRequest) -> String {
        switch request.transport {
        case .websocket: return "WS"
        case .sse: return "SSE"
        case .graphql: return "GQL"
        default: return ["DELETE": "DEL", "OPTIONS": "OPT"][request.method] ?? request.method
        }
    }
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
    func sheetTitle(_ title: LocalizedStringKey) -> some View { sheetTitle(Text(title)) }
    func sheetTitle<S: StringProtocol>(_ title: S) -> some View { sheetTitle(Text(title)) }
    @ViewBuilder func sheetTitle(_ title: Text) -> some View {
        #if os(macOS)
        if #available(macOS 15, *) {
            navigationTitle(title).toolbar(removing: .title)
                .safeAreaInset(edge: .top, spacing: 0) {
                    SheetHeading(title: title)
                }
        } else {
            navigationTitle("")
                .safeAreaInset(edge: .top, spacing: 0) { SheetHeading(title: title) }
        }
        #else
        navigationTitle(title).inlineTitle()
        #endif
    }
    @ViewBuilder func macSheetFrame(minWidth: CGFloat = 500, minHeight: CGFloat = 360) -> some View {
        #if os(macOS)
        frame(minWidth: minWidth, idealWidth: 620, minHeight: minHeight, idealHeight: 500)
        #else
        self
        #endif
    }
    @ViewBuilder func macReadableWidth(_ width: CGFloat = 680) -> some View {
        #if os(macOS)
        frame(maxWidth: width, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        #else
        self
        #endif
    }
    @ViewBuilder func macGroupedForm() -> some View {
        #if os(macOS)
        formStyle(.grouped).textFieldStyle(.roundedBorder)
        #else
        self
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
extension ToolbarContent {
    @ToolbarContentBuilder func flatToolbarBackground() -> some ToolbarContent {
        #if os(macOS)
        if #available(macOS 26, *) { sharedBackgroundVisibility(.hidden) }
        else { self }
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct SheetHeading: View {
    let title: Text
    var body: some View {
        HStack { title.font(.headline).accessibilityAddTraits(.isHeader); Spacer() }
            .padding(.horizontal, 16).frame(height: 44)
            .background(Palette.canvas)
            .overlay(alignment: .bottom) { Divider() }
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
        field.placeholderString = String(localized: "Find a request")
        field.controlSize = .regular
        field.font = .systemFont(ofSize: 14)
        field.maximumRecents = 0
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        field.setAccessibilityLabel(String(localized: "Find a request"))
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
