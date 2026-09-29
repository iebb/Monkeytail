import SwiftUI
import UIKit
import MonkeytailCore

private struct InputDismissalKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var inputDismissal: Int {
        get { self[InputDismissalKey.self] }
        set { self[InputDismissalKey.self] = newValue }
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

enum Palette {
    static let mint = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.36, green: 0.89, blue: 0.75, alpha: 1) : UIColor(red: 0.04, green: 0.43, blue: 0.35, alpha: 1) })
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.045, green: 0.065, blue: 0.09, alpha: 1) : UIColor(red: 0.96, green: 0.97, blue: 0.975, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.075, green: 0.10, blue: 0.13, alpha: 1) : .white })
    static let border = Color.primary.opacity(0.09)
    static func method(_ value: String) -> Color {
        switch value { case "GET": return mint; case "POST": return .orange; case "PUT", "PATCH": return .blue; case "DELETE": return .pink; default: return .purple }
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

struct EmptyPanel: View {
    let title: String
    var message = ""
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline)
            if !message.isEmpty { Text(message).font(.caption).multilineTextAlignment(.center) }
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
    }
}

struct FieldEditor: View {
    @Binding var fields: [Field]
    var name = "Header"
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Value").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 44).padding(.vertical, 7)
            Divider()
            ForEach($fields) { $field in
                HStack(alignment: .center, spacing: 0) {
                    Button { field.enabled.toggle() } label: {
                        Image(systemName: field.enabled ? "checkmark.square.fill" : "square").foregroundStyle(field.enabled ? Palette.mint : Color.secondary).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(field.enabled ? "Disable \(field.name)" : "Enable \(field.name)")
                    let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        TextField("\(name) name", text: $field.name).dismissibleInput().frame(maxWidth: .infinity, minHeight: 44).accessibilityLabel("\(name) name")
                        Group {
                            if field.isSecret { SecureField("Value", text: $field.value) }
                            else { TextField("Value", text: $field.value) }
                        }.dismissibleInput().frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(.secondary).accessibilityLabel("\(name) value")
                    }.opacity(field.enabled ? 1 : 0.5)
                        .font(.system(.footnote, design: .monospaced))
                    Menu {
                        Button(field.isSecret ? "Allow iCloud sync" : "Keep value on this device") { field.secret = !field.isSecret }
                        Button("Remove field", role: .destructive) { fields.removeAll { $0.id == field.id } }
                    } label: { Image(systemName: field.isSecret ? "lock" : "ellipsis").foregroundStyle(.secondary).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Options for \(field.name)")
                }
                Divider().padding(.leading, 44)
            }
            Button { fields.append(Field()) } label: { Label("Add \(name.lowercased())", systemImage: "plus").font(.subheadline).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 12) }
                .buttonStyle(.plain).foregroundStyle(Palette.mint)
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
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
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .scrollContentBackground(.hidden).padding(6)
            .frame(minHeight: minimumHeight).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border))
            .accessibilityLabel(label).accessibilityIdentifier(label)
    }
}

struct PillTabs: View {
    let tabs: [String]
    @Binding var selection: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.self) { tab in
                    Button { selection = tab } label: {
                        Text(tab).font(.subheadline.weight(selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? Palette.mint : .secondary)
                            .padding(.horizontal, 8).frame(minWidth: 44, minHeight: 44)
                            .overlay(alignment: .bottom) { if selection == tab { Rectangle().fill(Palette.mint).frame(height: 2) } }
                    }.buttonStyle(.plain).accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
        }.contentMargins(.horizontal, 4)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
