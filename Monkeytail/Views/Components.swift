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
    #if os(macOS)
    static let mint = Color(nsColor: NSColor(name: nil) { appearance in appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.36, green: 0.89, blue: 0.75, alpha: 1) : NSColor(red: 0.04, green: 0.43, blue: 0.35, alpha: 1) })
    static let canvas = Color(nsColor: NSColor(name: nil) { appearance in appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.09, green: 0.10, blue: 0.11, alpha: 1) : NSColor(red: 0.96, green: 0.965, blue: 0.96, alpha: 1) })
    static let surface = Color(nsColor: .controlBackgroundColor)
    #else
    static let mint = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.36, green: 0.89, blue: 0.75, alpha: 1) : UIColor(red: 0.04, green: 0.43, blue: 0.35, alpha: 1) })
    static let canvas = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.09, green: 0.10, blue: 0.11, alpha: 1) : UIColor(red: 0.96, green: 0.965, blue: 0.96, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1) : .white })
    #endif
    static let border = Color.primary.opacity(0.09)
    static let warning = adaptive(light: (0.60, 0.34, 0.02), dark: (0.98, 0.72, 0.40))
    static let danger = adaptive(light: (0.72, 0.18, 0.29), dark: (1.0, 0.53, 0.63))
    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
        #else
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
        #endif
    }
    static func method(_ value: String) -> Color {
        switch value { case "GET": return mint; case "POST": return warning; case "PUT", "PATCH": return .blue; case "DELETE": return danger; default: return .purple }
    }
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
    let title: String
    let symbol: String
    var detail = ""
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Palette.mint).accessibilityHidden(true)
            Text(title).fontWeight(.semibold).accessibilityAddTraits(.isHeader)
            Spacer()
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }.font(.subheadline).padding(.horizontal, WorkspaceMetrics.inset).frame(minHeight: 44)
            .background(Palette.surface)
    }
}

struct EditorHeading: View {
    let title: String
    let message: String
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

struct EmptyPanel: View {
    let title: String
    var message = ""
    var symbol = "tray"
    var body: some View {
        #if os(macOS)
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 23)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.medium))
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(16)
        #else
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Palette.mint)
                .frame(width: 64, height: 64).background(Palette.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            Text(title).font(.headline)
            if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
        #endif
    }
}

struct FieldEditor: View {
    @Binding var fields: [Field]
    var name = "Header"
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Value").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 44).padding(.vertical, 7)
                .background(Palette.canvas.opacity(0.7))
            Divider()
            ForEach($fields) { $field in
                HStack(alignment: .center, spacing: 0) {
                    Button { field.enabled.toggle() } label: {
                        Image(systemName: field.enabled ? "checkmark.square.fill" : "square").foregroundStyle(field.enabled ? Palette.mint : Color.secondary).frame(width: 44, height: WorkspaceMetrics.controlHeight)
                    }.buttonStyle(.plain).accessibilityLabel(field.enabled ? "Disable \(field.name)" : "Enable \(field.name)")
                    let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        TextField("\(name) name", text: $field.name).dismissibleInput().frame(maxWidth: .infinity, minHeight: WorkspaceMetrics.controlHeight).accessibilityLabel("\(name) name")
                        Group {
                            if field.isSecret { SecureField("Value", text: $field.value) }
                            else { TextField("Value", text: $field.value) }
                        }.dismissibleInput().frame(maxWidth: .infinity, minHeight: WorkspaceMetrics.controlHeight).accessibilityLabel("\(name) value")
                    }.opacity(field.enabled ? 1 : 0.5)
                        .font(.system(.footnote, design: .monospaced))
                    Menu {
                        Button(field.isSecret ? "Mark ordinary" : "Mark sensitive") { field.secret = !field.isSecret }
                        Button("Remove field", role: .destructive) { fields.removeAll { $0.id == field.id } }
                    } label: { Image(systemName: field.isSecret ? "lock" : "ellipsis").foregroundStyle(.secondary).frame(width: 44, height: WorkspaceMetrics.controlHeight) }
                        .borderlessMenu().buttonStyle(.plain).accessibilityLabel("Options for \(field.name)")
                }
                Divider().padding(.leading, 44)
            }
            Button { fields.append(Field()) } label: { Label("Add \(name.lowercased())", systemImage: "plus").font(.subheadline).frame(maxWidth: .infinity, minHeight: WorkspaceMetrics.controlHeight, alignment: .leading).padding(.horizontal, 12) }
                .buttonStyle(.plain).foregroundStyle(Palette.mint)
        }
        .textFieldStyle(.plain).noCapitalization().autocorrectionDisabled()
        .background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: WorkspaceMetrics.cornerRadius).strokeBorder(Palette.border))
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
            .accessibilityLabel(label).accessibilityIdentifier(label)
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
                        Text(tab).font(.system(size: 12, weight: selection == tab ? .semibold : .medium))
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
                        Text(tab).font(.footnote.weight(selection == tab ? .semibold : .medium))
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
