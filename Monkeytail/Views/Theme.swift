import SwiftUI
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Colour roles from the Monkeytail design system; each has a light and a dark value.
enum ThemeToken: String, CaseIterable, Codable, Identifiable {
    case accent, canvas, surface, warning, danger, info, other, error
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .accent: "Accent"
        case .canvas: "Canvas"
        case .surface: "Surface"
        case .warning: "Warning"
        case .danger: "Danger"
        case .info: "Info"
        case .other: "Other methods"
        case .error: "Error"
        }
    }
    var detail: LocalizedStringKey {
        switch self {
        case .accent: "GET, success, Send and selection"
        case .canvas: "Behind panes and the sidebar"
        case .surface: "Cards, fields and the response pane"
        case .warning: "POST, 4xx and 5xx, JSON literals"
        case .danger: "DELETE"
        case .info: "PUT and PATCH"
        case .other: "HEAD, OPTIONS and custom verbs"
        case .error: "Failed requests and validation"
        }
    }
}

struct ColorPair: Codable, Hashable {
    var light: String, dark: String
    init(_ light: String, _ dark: String) { self.light = light; self.dark = dark }
}

struct ThemePreset: Identifiable {
    let id: String
    /// Preset names are product names and stay in English in every language.
    let name: String
    let colors: [ThemeToken: ColorPair]

    static let monkeytail = ThemePreset(id: "monkeytail", name: "Monkeytail", colors: [
        .accent: ColorPair("#0A6E59", "#5CE3BF"), .canvas: ColorPair("#F5F6F5", "#17191C"), .surface: ColorPair("#FFFFFF", "#1F2124"),
        .warning: ColorPair("#995705", "#FAB866"), .danger: ColorPair("#B82E4A", "#FF87A1"), .info: ColorPair("#007AFF", "#0A84FF"),
        .other: ColorPair("#AF52DE", "#BF5AF2"), .error: ColorPair("#FF3B30", "#FF453A")
    ])
    static let all: [ThemePreset] = [
        monkeytail,
        monkeytail.with(id: "navy", name: "Navy", [.canvas: ColorPair("#F2F5F8", "#09111A"), .surface: ColorPair("#FFFFFF", "#101C28")]),
        monkeytail.with(id: "ocean", name: "Ocean", [.accent: ColorPair("#0B5CAD", "#6CB6FF"), .info: ColorPair("#6B3FB8", "#B79CFF")]),
        monkeytail.with(id: "ember", name: "Ember", [.accent: ColorPair("#B0431A", "#FF9466"), .warning: ColorPair("#8A6100", "#F5C451")]),
        monkeytail.with(id: "grape", name: "Grape", [.accent: ColorPair("#6B3FB8", "#C2A5FF"), .other: ColorPair("#0A6E59", "#5CE3BF")]),
        monkeytail.with(id: "graphite", name: "Graphite", [.accent: ColorPair("#3B4048", "#D0D6DE"), .canvas: ColorPair("#F2F2F3", "#141517"), .surface: ColorPair("#FFFFFF", "#1C1D20")])
    ]
    static func named(_ id: String) -> ThemePreset { all.first { $0.id == id } ?? monkeytail }
    private func with(id: String, name: String, _ changes: [ThemeToken: ColorPair]) -> ThemePreset {
        ThemePreset(id: id, name: name, colors: colors.merging(changes) { $1 })
    }
}

enum ThemeAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: LocalizedStringKey { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

struct ThemeSettings: Codable, Equatable {
    var preset = ThemePreset.monkeytail.id
    var appearance = ThemeAppearance.system
    var colors: [ThemeToken: ColorPair] = [:]
    var interfaceFont: String?
    var codeFont: String?
    func pair(_ token: ThemeToken) -> ColorPair { colors[token] ?? ThemePreset.named(preset).colors[token] ?? ThemePreset.monkeytail.colors[token]! }
}

/// The user's theme. Reading it inside a view body (through `Palette` or a `Font`) subscribes that view to changes.
@Observable final class ThemeStore {
    static let shared = ThemeStore()
    private static let key = "theme"
    var settings: ThemeSettings { didSet { if settings != oldValue { save() } } }
    private init(defaults: UserDefaults = .standard) {
        settings = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(ThemeSettings.self, from: $0) } ?? ThemeSettings()
    }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: Self.key) }
}

enum Theme {
    private static var colorCache: [ColorPair: Color] = [:]
    static func color(_ token: ThemeToken) -> Color {
        let pair = ThemeStore.shared.settings.pair(token)
        if let cached = colorCache[pair] { return cached }
        let light = rgb(pair.light) ?? (0, 0, 0), dark = rgb(pair.dark) ?? (1, 1, 1)
        #if os(macOS)
        let color = Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        })
        #else
        let color = Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
        #endif
        colorCache[pair] = color
        return color
    }

    static func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat)? {
        let digits = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (CGFloat((value >> 16) & 0xFF) / 255, CGFloat((value >> 8) & 0xFF) / 255, CGFloat(value & 0xFF) / 255)
    }
    static func hex(_ color: Color) -> String {
        #if os(macOS)
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "#000000" }
        let (r, g, b) = (c.redComponent, c.greenComponent, c.blueComponent)
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        let byte = { (v: CGFloat) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    // MARK: Fonts

    static var interfaceFamily: String? { ThemeStore.shared.settings.interfaceFont }
    static var codeFamily: String? { ThemeStore.shared.settings.codeFont }

    /// A concrete face for a family, so SwiftUI, AppKit and UIKit all resolve it.
    private static var faceCache: [String: String] = [:]
    static func faceName(_ family: String) -> String? {
        if let cached = faceCache[family] { return cached }
        #if os(macOS)
        let face = (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).first { ($0[3] as? UInt).map { $0 & NSFontTraitMask.italicFontMask.rawValue == 0 } ?? true }?[0] as? String
        #else
        let names = UIFont.fontNames(forFamilyName: family)
        let face = names.first { !$0.localizedCaseInsensitiveContains("italic") && ($0.hasSuffix("-Regular") || !$0.contains("-")) } ?? names.first
        #endif
        if let face { faceCache[family] = face }
        return face
    }

    static func families(monospacedOnly: Bool) -> [String] {
        #if os(macOS)
        let all = NSFontManager.shared.availableFontFamilies
        guard monospacedOnly else { return all.filter { !$0.hasPrefix(".") }.sorted() }
        return all.filter { family in faceName(family).flatMap { NSFont(name: $0, size: 12) }?.isFixedPitch == true }.sorted()
        #else
        let all = UIFont.familyNames
        guard monospacedOnly else { return all.sorted() }
        return all.filter { family in faceName(family).flatMap { UIFont(name: $0, size: 12) }?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true }.sorted()
        #endif
    }

    #if os(macOS)
    static func platformMonoFont(size: CGFloat) -> NSFont {
        codeFamily.flatMap(faceName).flatMap { NSFont(name: $0, size: size) } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    #else
    static func platformMonoFont(size: CGFloat) -> UIFont {
        codeFamily.flatMap(faceName).flatMap { UIFont(name: $0, size: size) } ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
    #endif

    fileprivate static func family(for design: Font.Design?) -> String? {
        switch design {
        case .monospaced?: codeFamily.flatMap(faceName)
        case nil, .default?: interfaceFamily.flatMap(faceName)
        default: nil
        }
    }

    // SwiftUI's own text-style initializer, reached through its exact type because this module shadows `Font.system(_:design:weight:)`.
    fileprivate static let swiftUIStyle: (Font.TextStyle, Font.Design) -> Font = Font.system(_:design:)

    #if os(macOS)
    /// macOS ignores Dynamic Type and sets captions at 10 pt, so the Mac app uses a slightly larger type scale.
    fileprivate static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 28
        case .title: 24
        case .title2: 18
        case .title3: 16
        case .callout: 13
        case .subheadline, .footnote: 12
        case .caption, .caption2: 11
        default: 14
        }
    }
    #else
    fileprivate static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
    #endif
}

/// Routes every text style in this module through the theme's font families. These shadow SwiftUI's styles inside the module.
extension Font {
    static var largeTitle: Font { .system(.largeTitle) }
    static var title: Font { .system(.title) }
    static var title2: Font { .system(.title2) }
    static var title3: Font { .system(.title3) }
    static var headline: Font { .system(.headline) }
    static var body: Font { .system(.body) }
    static var callout: Font { .system(.callout) }
    static var subheadline: Font { .system(.subheadline) }
    static var footnote: Font { .system(.footnote) }
    static var caption: Font { .system(.caption) }
    static var caption2: Font { .system(.caption2) }

    static func system(_ style: Font.TextStyle, design: Font.Design? = nil, weight: Font.Weight? = nil) -> Font {
        let resolvedWeight = weight ?? (style == .headline ? .semibold : nil)
        let base: Font
        #if os(macOS)
        if let face = Theme.family(for: design) { base = .custom(face, fixedSize: Theme.size(style)) }
        else { base = .system(size: Theme.size(style), weight: .regular, design: design ?? .default) }
        #else
        if let face = Theme.family(for: design) { base = .custom(face, size: Theme.size(style), relativeTo: style) }
        else { base = Theme.swiftUIStyle(style, design ?? .default) }
        #endif
        return resolvedWeight.map { base.weight($0) } ?? base
    }

    /// A fixed-size font in the theme's families. `Font.system(size:)` is left unshadowed so it always reaches SwiftUI.
    static func app(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        let base = Theme.family(for: design).map { Font.custom($0, fixedSize: size) } ?? .system(size: size, weight: .regular, design: design ?? .default)
        return weight.map { base.weight($0) } ?? base
    }
}

/// Semantic colours. Read through the theme so a change redraws every view that uses them.
enum Palette {
    static var mint: Color { Theme.color(.accent) }
    static var canvas: Color { Theme.color(.canvas) }
    static var surface: Color { Theme.color(.surface) }
    static var warning: Color { Theme.color(.warning) }
    static var danger: Color { Theme.color(.danger) }
    static var info: Color { Theme.color(.info) }
    static var error: Color { Theme.color(.error) }
    static let border = Color.primary.opacity(0.09)
    static func method(_ value: String) -> Color {
        switch value { case "GET": return mint; case "POST": return warning; case "PUT", "PATCH": return info; case "DELETE": return danger; default: return Theme.color(.other) }
    }
}

private struct ThemedModifier: ViewModifier {
    private var theme = ThemeStore.shared
    func body(content: Content) -> some View {
        content.tint(Palette.mint).preferredColorScheme(theme.settings.appearance.scheme)
    }
}

extension View {
    /// Applies the user's accent, appearance and fonts to a window.
    func themed() -> some View { modifier(ThemedModifier()) }
}

struct ThemeSettingsView: View {
    @Bindable private var theme = ThemeStore.shared
    @State private var interfaceFamilies: [String] = []
    @State private var codeFamilies: [String] = []
    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $theme.settings.appearance) {
                    ForEach(ThemeAppearance.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("Theme", selection: Binding(get: { theme.settings.preset }, set: { theme.settings.preset = $0; theme.settings.colors = [:] })) {
                    ForEach(ThemePreset.all) { Text(verbatim: $0.name).tag($0.id) }
                }
            } header: { Text("Theme") }
            Section {
                HStack {
                    Spacer()
                    Text("Light").frame(width: 52)
                    Text("Dark").frame(width: 52)
                }.font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                ForEach(ThemeToken.allCases) { token in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(token.title)
                            Text(token.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        colorPicker(token, dark: false)
                        colorPicker(token, dark: true)
                    }
                }
                if !theme.settings.colors.isEmpty {
                    Button("Reset colours", role: .destructive) { theme.settings.colors = [:] }
                }
            } header: { Text("Colours") } footer: { Text("Changes apply to every window straight away.") }
            Section {
                fontPicker("Interface font", selection: $theme.settings.interfaceFont, families: interfaceFamilies)
                fontPicker("Code font", selection: $theme.settings.codeFont, families: codeFamilies)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your next request starts here").font(.headline)
                    HStack(spacing: 8) {
                        MethodBadge(method: "GET"); MethodBadge(method: "POST"); MethodBadge(method: "PUT"); MethodBadge(method: "DELETE")
                        StatusBadge(status: 200, showsLabel: false); StatusBadge(status: 404, showsLabel: false)
                    }
                    Text(verbatim: "{ \"id\": 42, \"name\": \"Monkeytail\" }").font(.system(.footnote, design: .monospaced))
                }.padding(.vertical, 4)
                if theme.settings.interfaceFont != nil || theme.settings.codeFont != nil {
                    Button("Use system fonts") { theme.settings.interfaceFont = nil; theme.settings.codeFont = nil }
                }
            } header: { Text("Fonts") }
        }.formStyle(.grouped)
            .navigationTitle("Theme & fonts").inlineTitle()
            .task {
                guard interfaceFamilies.isEmpty else { return }
                interfaceFamilies = Theme.families(monospacedOnly: false)
                codeFamilies = Theme.families(monospacedOnly: true)
            }
    }

    private func colorPicker(_ token: ThemeToken, dark: Bool) -> some View {
        let binding = Binding<Color>(get: {
            let pair = theme.settings.pair(token)
            let rgb = Theme.rgb(dark ? pair.dark : pair.light) ?? (0, 0, 0)
            return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        }, set: { color in
            var pair = theme.settings.pair(token)
            if dark { pair.dark = Theme.hex(color) } else { pair.light = Theme.hex(color) }
            theme.settings.colors[token] = pair == ThemePreset.named(theme.settings.preset).colors[token] ? nil : pair
        })
        return ColorPicker(selection: binding, supportsOpacity: false) { dark ? Text("\(Text(token.title)), dark") : Text("\(Text(token.title)), light") }
            .labelsHidden().frame(width: 52)
    }

    private func fontPicker(_ title: LocalizedStringKey, selection: Binding<String?>, families: [String]) -> some View {
        Picker(title, selection: selection) {
            Text("System").tag(String?.none)
            if let current = selection.wrappedValue, !families.contains(current) { Text(verbatim: current).tag(String?.some(current)) }
            ForEach(families, id: \.self) { Text(verbatim: $0).tag(String?.some($0)) }
        }
    }
}
