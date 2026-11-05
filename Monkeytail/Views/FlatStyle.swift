import SwiftUI

/// Flat controls for the Mac: hairline borders, small radii, no glass or capsules.
struct FlatButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size
    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        configuration.label
            .font(.subheadline.weight(prominent ? .semibold : .regular)).lineLimit(1)
            .padding(.horizontal, size == .small ? 8 : 10).frame(minHeight: size == .small ? 22 : 26)
            .foregroundStyle(prominent ? Palette.surface : destructive ? Palette.error : Color.primary)
            .background(prominent ? AnyShapeStyle(Palette.mint) : AnyShapeStyle(Palette.surface), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(prominent ? Color.clear : Palette.border))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.45)
            .contentShape(Rectangle())
    }
}

struct FlatTextFieldStyle: TextFieldStyle {
    @FocusState private var focused: Bool
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).focused($focused)
            .padding(.horizontal, 7).frame(minHeight: 26)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(focused ? Palette.mint : Palette.border, lineWidth: focused ? 1.5 : 1))
    }
}

/// Two-to-four options in a row. Flat on the Mac, the system segmented control elsewhere.
struct SegmentedChoice<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value
    let options: [(value: Value, label: LocalizedStringKey)]
    var body: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index], selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1)
                        .foregroundStyle(selected ? Palette.mint : Color.secondary)
                        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 24)
                        .background(selected ? Palette.mint.opacity(0.10) : .clear)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                if index < options.count - 1 { Rectangle().fill(Palette.border).frame(width: 1, height: 24) }
            }
        }.background(Palette.surface, in: RoundedRectangle(cornerRadius: 5))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.border))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain).accessibilityLabel(title)
        #else
        Picker(title, selection: $selection) { ForEach(options.indices, id: \.self) { Text(options[$0].label).tag(options[$0].value) } }
            .pickerStyle(.segmented)
        #endif
    }
}

/// Settings row icons in one fixed-width column, so titles line up whatever the symbol's width.
struct SettingsIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(Palette.mint).frame(width: 22, alignment: .center)
            configuration.title
        }
    }
}

#if os(macOS)
/// Settings without panels: a caption header, hairline-divided rows, and a footer.
@available(macOS 15, *)
struct FlatFormStyle: FormStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(sections: configuration.content) { section in
                    VStack(alignment: .leading, spacing: 0) {
                        if !section.header.isEmpty {
                            section.header.font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary).padding(.bottom, 6)
                        }
                        Rectangle().fill(Palette.border).frame(height: 1)
                        ForEach(subviews: section.content) { row in
                            row.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).padding(.vertical, 5)
                            Rectangle().fill(Palette.border).frame(height: 1)
                        }
                        if !section.footer.isEmpty { section.footer.font(.caption).foregroundStyle(.secondary).padding(.top, 6) }
                    }
                }
            }.padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading)
        }.background(Palette.surface)
    }
}

/// Label leading, control trailing.
struct FlatLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) { configuration.label; Spacer(minLength: 12); configuration.content.foregroundStyle(.secondary) }
    }
}

/// A square-cornered switch.
struct FlatToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label.foregroundStyle(.primary)
                Spacer(minLength: 12)
                RoundedRectangle(cornerRadius: 3).fill(configuration.isOn ? Palette.mint : Color.primary.opacity(0.14)).frame(width: 30, height: 16)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) { RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 12, height: 12).padding(2) }
                    .animation(.easeOut(duration: 0.12), value: configuration.isOn)
            }.contentShape(Rectangle()).opacity(enabled ? 1 : 0.45)
        }.buttonStyle(.plain).accessibilityAddTraits(configuration.isOn ? .isSelected : []).accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}
#endif

/// A colour well: a flat swatch on the Mac with the system picker underneath to open the colour panel.
struct ColorWell: View {
    @Binding var color: Color
    let label: Text
    var body: some View {
        #if os(macOS)
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 34, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.border))
            ColorPicker(selection: $color, supportsOpacity: false) { label }.labelsHidden().opacity(0.02)
        }.frame(width: 52)
        #else
        ColorPicker(selection: $color, supportsOpacity: false) { label }.labelsHidden().frame(width: 52)
        #endif
    }
}

extension View {
    /// Settings forms: flat sections with no rounded panels on the Mac.
    @ViewBuilder func settingsForm() -> some View {
        #if os(macOS)
        if #available(macOS 15, *) {
            formStyle(FlatFormStyle()).labeledContentStyle(FlatLabeledContentStyle()).toggleStyle(FlatToggleStyle()).labelStyle(SettingsIconLabelStyle())
        } else {
            formStyle(.grouped).toggleStyle(.switch).labelStyle(SettingsIconLabelStyle())
        }
        #else
        formStyle(.grouped).toggleStyle(.switch).labelStyle(SettingsIconLabelStyle())
        #endif
    }
    /// One flat settings section: rows sit on the window background, divided by hairlines.
    @ViewBuilder func flatSection() -> some View {
        #if os(macOS)
        listRowBackground(Color.clear).listRowSeparator(.visible)
        #else
        self
        #endif
    }
    @ViewBuilder func prominentButton() -> some View {
        #if os(macOS)
        buttonStyle(FlatButtonStyle(prominent: true))
        #else
        buttonStyle(.borderedProminent)
        #endif
    }
    @ViewBuilder func secondaryButton() -> some View {
        #if os(macOS)
        buttonStyle(FlatButtonStyle())
        #else
        buttonStyle(.bordered)
        #endif
    }
    @ViewBuilder func fieldStyle() -> some View {
        #if os(macOS)
        textFieldStyle(FlatTextFieldStyle())
        #else
        textFieldStyle(.roundedBorder)
        #endif
    }
    /// The Mac default for buttons without an explicit style.
    @ViewBuilder func flatControls() -> some View {
        #if os(macOS)
        buttonStyle(FlatButtonStyle())
        #else
        self
        #endif
    }
}
