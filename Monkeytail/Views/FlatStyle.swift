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

extension View {
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
