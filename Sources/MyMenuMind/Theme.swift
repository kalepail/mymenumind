import SwiftUI

enum Theme {
    static let paper        = Color(red: 0.957, green: 0.937, blue: 0.890)
    static let paperRaised  = Color(red: 0.984, green: 0.969, blue: 0.937)
    static let paperSunken  = Color(red: 0.929, green: 0.902, blue: 0.847)
    static let ink          = Color(red: 0.110, green: 0.090, blue: 0.078)
    static let inkSoft      = Color(red: 0.396, green: 0.345, blue: 0.290)
    static let inkFaded     = Color(red: 0.612, green: 0.557, blue: 0.486)
    static let hairline     = Color(red: 0.847, green: 0.812, blue: 0.741)
    static let coral        = Color(red: 0.820, green: 0.345, blue: 0.255)
    static let coralPressed = Color(red: 0.694, green: 0.267, blue: 0.192)
    static let success      = Color(red: 0.349, green: 0.482, blue: 0.349)

    enum Typography {
        static func wordmark(_ size: CGFloat = 22) -> Font {
            .system(size: size, weight: .regular, design: .serif).italic()
        }
        static func serifPrompt(_ size: CGFloat = 14) -> Font {
            .system(size: size, weight: .regular, design: .serif).italic()
        }
        static func sectionLabel() -> Font {
            .system(size: 13, weight: .regular, design: .serif).italic()
        }
        static func body() -> Font {
            .system(size: 13, weight: .regular)
        }
        static func itemTitle() -> Font {
            .system(size: 13, weight: .medium)
        }
        static func caption() -> Font {
            .system(size: 11, weight: .regular)
        }
        static func chip() -> Font {
            .system(size: 11, weight: .regular, design: .monospaced)
        }
        static func fieldLabel() -> Font {
            .system(size: 10, weight: .medium).smallCaps()
        }
    }
}

struct InkButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? Theme.paper : Theme.ink)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        prominent
                            ? (configuration.isPressed ? Theme.coralPressed : Theme.coral)
                            : Theme.paperRaised
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(prominent ? Color.clear : Theme.hairline, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed && !prominent ? 0.75 : 1)
    }
}

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.chip())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(Theme.inkSoft)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? Theme.paperSunken : Theme.paperRaised)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
    }
}

struct GhostIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 26)
            .foregroundStyle(Theme.inkSoft)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Theme.paperSunken : Color.clear)
            )
    }
}

struct SectionDivider: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Theme.Typography.sectionLabel())
                .foregroundStyle(Theme.inkSoft)
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 0.5)
            if let trailing { trailing }
        }
    }
}

struct InkSearchField: View {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    let onClear: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.inkFaded)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(Theme.Typography.serifPrompt())
                        .foregroundStyle(Theme.inkFaded)
                        .allowsHitTesting(false)
                }
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .focused($focused)
                    .onSubmit(onSubmit)
            }

            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaded)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.paperRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Theme.ink.opacity(0.35) : Theme.hairline, lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.15), value: focused)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}

struct InkField: View {
    let label: String
    @Binding var text: String
    var secure: Bool = false
    var monospaced: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.fieldLabel())
                .tracking(0.5)
                .foregroundStyle(Theme.inkFaded)

            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: monospaced ? .monospaced : .default))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.paperRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
            )
        }
    }
}
