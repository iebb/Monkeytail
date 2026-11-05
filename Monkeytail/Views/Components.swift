import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

private struct InputDismissalKey: EnvironmentKey {
    static let defaultValue = 0
}
struct VariableHintContext { var values: [String: String] = [:]; var secrets: Set<String> = [] }
private struct VariableHintsKey: EnvironmentKey {
    static let defaultValue = VariableHintContext()
}

extension EnvironmentValues {
    var inputDismissal: Int {
        get { self[InputDismissalKey.self] }
        set { self[InputDismissalKey.self] = newValue }
    }
    var variableHints: VariableHintContext {
        get { self[VariableHintsKey.self] }
        set { self[VariableHintsKey.self] = newValue }
    }
}

/// Postman-style variable help: completes a trailing `{{` and shows what each `{{name}}` resolves to.
struct VariableAssist: View {
    @Binding var text: String
    var showsReferences = true
    var insets = EdgeInsets()
    @Environment(\.variableHints) private var hints
    var body: some View {
        if let partial = VariableHints.pendingName(in: text) {
            let names = VariableHints.suggestions(for: partial, variables: hints.values)
            if !names.isEmpty {
                chips {
                    ForEach(names, id: \.self) { name in
                        Button { text = VariableHints.complete(text, with: name) } label: {
                            Text(name).padding(.horizontal, 7).padding(.vertical, 5).background(Palette.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 5)).foregroundStyle(Palette.mint)
                        }.buttonStyle(.plain).accessibilityLabel("Insert variable \(name)")
                    }
                }
            }
        } else if showsReferences {
            let references = VariableHints.references(in: text, variables: hints.values)
            if !references.isEmpty {
                chips {
                    ForEach(references, id: \.name) { reference in
                        let value = summary(reference), color = reference.isResolved ? Palette.mint : Palette.warning
                        HStack(spacing: 4) { Text(reference.name).foregroundStyle(color); Text(value).foregroundStyle(.secondary).lineLimit(1) }
                            .padding(.horizontal, 7).padding(.vertical, 5).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                            .accessibilityElement(children: .combine).accessibilityLabel("\(reference.name): \(value)")
                    }
                }
            }
        }
    }
    private func summary(_ reference: VariableHints.Reference) -> String {
        if reference.isDynamic { return reference.isResolved ? String(localized: "generated each send") : String(localized: "unknown dynamic variable") }
        guard let value = reference.value else { return String(localized: "unresolved") }
        if hints.secrets.contains(reference.name) { return "••••••" }
        return value.isEmpty ? String(localized: "empty") : value.count > 60 ? String(value.prefix(60)) + "…" : value
    }
    private func chips<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { content() } }.font(.system(.caption, design: .monospaced)).padding(insets)
    }
}

private struct DismissibleInput: ViewModifier {
    @Environment(\.inputDismissal) private var dismissal
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        content.focused($focused).onChange(of: dismissal) { _, _ in focused = false }
    }
}

extension View {
    func dismissibleInput() -> some View { modifier(DismissibleInput()) }
}

enum WorkspaceMetrics {
    #if os(macOS)
    static let inset: CGFloat = 12
    static let cornerRadius: CGFloat = 6
    static let controlHeight: CGFloat = 28
    #else
    static let inset: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let controlHeight: CGFloat = 44
    #endif
}

struct PanelHeading: View {
    let title: LocalizedStringKey
    let symbol: String
    var detail: LocalizedStringKey?
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Palette.mint).accessibilityHidden(true)
            Text(title).fontWeight(.semibold).accessibilityAddTraits(.isHeader)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }.font(.subheadline).padding(.horizontal, WorkspaceMetrics.inset).frame(minHeight: 44)
            .background(Palette.surface)
    }
}

struct EditorHeading: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 4)
    }
}

struct MethodBadge: View {
    let method: String
    var body: some View {
        Text(method).font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(Palette.method(method)).padding(.horizontal, 7).padding(.vertical, 5)
            .background(Palette.method(method).opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel("\(method) method")
    }
}

/// Response status pill: mint for success and redirects, warning amber for 4xx/5xx.
struct StatusBadge: View {
    let status: Int
    var showsLabel = true
    var body: some View {
        let color = status < 400 ? Palette.mint : Palette.warning
        Text(showsLabel ? "\(status) \(Self.label(status))" : String(status)).font(.system(.caption, design: .monospaced, weight: .semibold)).lineLimit(1)
            .foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
    }
    static func label(_ code: Int) -> String {
        [200: "OK", 201: "Created", 202: "Accepted", 204: "No Content", 301: "Moved Permanently", 302: "Found", 304: "Not Modified", 307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 409: "Conflict", 422: "Unprocessable Content", 429: "Too Many Requests", 500: "Internal Server Error", 502: "Bad Gateway", 503: "Service Unavailable"][code] ?? HTTPURLResponse.localizedString(forStatusCode: code).capitalized
    }
}

/// Magnifying-glass search field; a clear button appears once there's text.
struct SearchField: View {
    let placeholder: LocalizedStringResource
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var canvas = false
    #if os(macOS)
    private let radius: CGFloat = 5
    #else
    private let radius: CGFloat = 10
    #endif
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(String(localized: placeholder), text: $text).textFieldStyle(.plain).font(.subheadline).noCapitalization().autocorrectionDisabled()
                .focused(focused).submitLabel(.done).onSubmit { focused.wrappedValue = false }.accessibilityIdentifier(placeholder.key)
            if !text.isEmpty {
                Button { text = ""; focused.wrappedValue = false } label: { Image(systemName: "xmark.circle.fill").frame(width: WorkspaceMetrics.controlHeight, height: WorkspaceMetrics.controlHeight).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, -12).accessibilityLabel("Clear search")
            }
        }.padding(.horizontal, 12).frame(minHeight: WorkspaceMetrics.controlHeight)
            .background(canvas ? Palette.canvas : Palette.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.border))
    }
}

struct EmptyPanel: View {
    let title: Text
    var message: Text?
    var symbol = "tray"
    init(title: LocalizedStringKey, message: LocalizedStringKey? = nil, symbol: String = "tray") { self.title = Text(title); self.message = message.map { Text($0) }; self.symbol = symbol }
    init<S: StringProtocol>(title: S, symbol: String = "tray") { self.title = Text(title); self.symbol = symbol }
    var body: some View {
        #if os(macOS)
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.app(size: 23)).foregroundStyle(.secondary).accessibilityHidden(true)
            title.font(.subheadline.weight(.medium))
            if let message { message.font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(16)
        #else
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.app(size: 26, weight: .light)).foregroundStyle(Palette.mint)
                .frame(width: 64, height: 64).background(Palette.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            title.font(.headline)
            if let message { message.font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
        #endif
    }
}

struct FieldEditor: View {
    @Binding var fields: [Field]
    var name = "Header"
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var bulk = false
    @State private var bulkText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if bulk { Text("One name:value per line. Prefix // to disable.").frame(maxWidth: .infinity, alignment: .leading) }
                else {
                    Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Value").frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(bulk ? "Key-value edit" : "Bulk edit") {
                    if !bulk { bulkText = FieldBulkText.encode(fields) }
                    bulk.toggle()
                }.buttonStyle(.plain).foregroundStyle(Palette.mint).accessibilityIdentifier("\(name) bulk edit")
            }.font(.caption).foregroundStyle(.secondary).padding(.leading, 44).padding(.trailing, 12).padding(.vertical, 7)
                .background(Palette.canvas.opacity(0.7))
            Divider()
            if bulk {
                TextEditor(text: Binding(get: { bulkText }, set: { bulkText = $0; fields = FieldBulkText.decode($0, existing: fields) }))
                    .dismissibleInput().font(.system(.footnote, design: .monospaced)).scrollContentBackground(.hidden)
                    .frame(minHeight: 140).padding(8).accessibilityLabel(copy.bulk)
            } else {
                ForEach($fields) { $field in
                    HStack(alignment: .center, spacing: 0) {
                        Button { field.enabled.toggle() } label: {
                            Image(systemName: field.enabled ? "checkmark.square.fill" : "square").foregroundStyle(field.enabled ? Palette.mint : Color.secondary).frame(width: 44, height: WorkspaceMetrics.controlHeight)
                        }.buttonStyle(.plain).accessibilityLabel(field.enabled ? "Disable \(field.name)" : "Enable \(field.name)")
                        let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 8))
                        layout {
                            TextField(copy.name, text: $field.name).dismissibleInput().frame(maxWidth: .infinity, minHeight: WorkspaceMetrics.controlHeight).accessibilityLabel(copy.name)
                            Group {
                                if field.isSecret { SecureField("Value", text: $field.value) }
                                else { TextField("Value", text: $field.value) }
                            }.dismissibleInput().frame(maxWidth: .infinity, minHeight: WorkspaceMetrics.controlHeight).accessibilityLabel(copy.value)
                        }.opacity(field.enabled ? 1 : 0.5)
                            .font(.system(.footnote, design: .monospaced))
                        Menu {
                            Button(field.isSecret ? "Mark ordinary" : "Mark sensitive") { field.secret = !field.isSecret }
                            Button("Remove field", role: .destructive) { fields.removeAll { $0.id == field.id } }
                        } label: { Image(systemName: field.isSecret ? "lock" : "ellipsis").foregroundStyle(.secondary).frame(width: 44, height: WorkspaceMetrics.controlHeight) }
                            .borderlessMenu().buttonStyle(.plain).accessibilityLabel("Options for \(field.name)")
                    }
                    VariableAssist(text: $field.value, showsReferences: false, insets: EdgeInsets(top: 0, leading: 44, bottom: 6, trailing: 12))
                    Divider().padding(.leading, 44)
                }
                Button { fields.append(Field()) } label: { Label(copy.add, systemImage: "plus").font(.subheadline).frame(maxWidth: .infinity, minHeight: WorkspaceMetrics.controlHeight, alignment: .leading).padding(.horizontal, 12) }
                    .buttonStyle(.plain).foregroundStyle(Palette.mint)
            }
        }
        .textFieldStyle(.plain).noCapitalization().autocorrectionDisabled()
        .background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius).strokeBorder(Palette.border))
    }
}

extension FieldEditor {
    /// Whole phrases per field kind, so translations never splice an English noun into a sentence.
    fileprivate struct Copy { let add, name, value, bulk: LocalizedStringKey }
    fileprivate var copy: Copy {
        switch name {
        case "Parameter": Copy(add: "Add parameter", name: "Parameter name", value: "Parameter value", bulk: "Parameter bulk text")
        case "Path variable": Copy(add: "Add path variable", name: "Path variable name", value: "Path variable value", bulk: "Path variable bulk text")
        case "Variable": Copy(add: "Add variable", name: "Variable name", value: "Variable value", bulk: "Variable bulk text")
        case "Global": Copy(add: "Add global", name: "Global name", value: "Global value", bulk: "Global bulk text")
        case "Field": Copy(add: "Add field", name: "Field name", value: "Field value", bulk: "Field bulk text")
        default: Copy(add: "Add header", name: "Header name", value: "Header value", bulk: "Header bulk text")
        }
    }
}

struct CodeEditor: View {
    @Binding var text: String
    var label: String
    var minimumHeight: CGFloat = 250
    var body: some View {
        TextEditor(text: $text)
            .dismissibleInput()
            .font(.system(.footnote, design: .monospaced))
            .noCapitalization().autocorrectionDisabled()
            .scrollContentBackground(.hidden).padding(10)
            .frame(minHeight: minimumHeight).background(Palette.surface, in: RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius).strokeBorder(Palette.border))
            .accessibilityLabel(LocalizedStringKey(label)).accessibilityIdentifier(label)
    }
}

/// Markdown documentation with an inline-formatting preview.
struct DocsEditor: View {
    @Binding var text: String?
    @State private var preview = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Documentation mode", selection: $preview) { Text("Edit").tag(false); Text("Preview").tag(true) }.pickerStyle(.segmented).frame(maxWidth: 220)
            if preview {
                Group {
                    if let text, !text.isEmpty { Text(Self.render(text)).textSelection(.enabled) }
                    else { Text("No documentation yet.").foregroundStyle(.secondary) }
                }.font(.callout).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading).padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius))
                    .overlay(RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius).strokeBorder(Palette.border))
            } else {
                CodeEditor(text: Binding(get: { text ?? "" }, set: { text = $0.isEmpty ? nil : $0 }), label: "Documentation", minimumHeight: 200)
            }
        }
    }
    static func render(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(markdown)
    }
}

struct PillTabs: View {
    let tabs: [String]
    @Binding var selection: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            #if os(macOS)
            HStack(spacing: 20) {
                ForEach(tabs, id: \.self) { tab in
                    Button { selection = tab } label: {
                        Text(LocalizedStringKey(tab)).font(.app(size: 13, weight: selection == tab ? .semibold : .medium))
                            .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                            .frame(minHeight: 34)
                            .overlay(alignment: .bottom) {
                                if selection == tab { Rectangle().fill(Palette.mint).frame(height: 2) }
                            }
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            #else
            HStack(spacing: 4) {
                ForEach(tabs, id: \.self) { tab in
                    Button { selection = tab } label: {
                        Text(LocalizedStringKey(tab)).font(.footnote.weight(selection == tab ? .semibold : .medium))
                            .foregroundStyle(selection == tab ? Palette.mint : Color.secondary)
                            .padding(.horizontal, 10).frame(minWidth: 44, minHeight: WorkspaceMetrics.controlHeight)
                            .background(selection == tab ? Palette.mint.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }.padding(.vertical, 6)
            #endif
        }.contentMargins(.horizontal, 12).background(Palette.surface)
    }
}

#if os(iOS) || os(visionOS)
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#endif
