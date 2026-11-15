import SwiftUI
import UIKit

// MARK: - Palette

extension Color {
    fileprivate static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let canvas = dynamic(0xF4F6FA, 0x0D1015)
    static let card = dynamic(0xFFFFFF, 0x181C24)
    static let ink = dynamic(0x101828, 0xF2F4F7)
    static let inkSecondary = dynamic(0x667085, 0x98A2B3)
    static let hairline = dynamic(0xE4E7EC, 0x2A303B)
    static let chip = dynamic(0xEEF0F4, 0x232934)

    static let gain = dynamic(0x0B7A3E, 0x3DCB7E)
    static let gainSoft = dynamic(0xEAF7EF, 0x10291B)
    static let loss = dynamic(0xC0351F, 0xF2735D)
    static let lossSoft = dynamic(0xFDEEEB, 0x331713)
    static let darkButton = dynamic(0x101828, 0xF2F4F7)
    static let darkButtonText = dynamic(0xFFFFFF, 0x101828)
    static let warn = dynamic(0xB54708, 0xF5A15B)
    static let warnSoft = dynamic(0xFEF3E6, 0x2E1E0E)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Type

extension Font {
    /// Large money figures: rounded, tabular digits.
    static func money(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var radius: CGFloat = 24
    var fill: Color = .card
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(fill == .card ? 0.05 : 0), radius: 14, y: 6)
    }
}

extension View {
    func card(radius: CGFloat = 24, fill: Color = .card, padding: CGFloat = 18) -> some View {
        modifier(CardModifier(radius: radius, fill: fill, padding: padding))
    }
}

/// Subtle scale on press for tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Large full-width primary button (56 pt).
struct BigButtonStyle: ButtonStyle {
    enum Kind { case green, dark, outline }
    var kind: Kind = .green
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(foreground)
            .background(background, in: .capsule)
            .overlay {
                if kind == .outline { Capsule().strokeBorder(Color.hairline, lineWidth: 1.5) }
            }
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .green: .white
        case .dark: .darkButtonText
        case .outline: .ink
        }
    }

    private var background: Color {
        switch kind {
        case .green: .gain
        case .dark: .darkButton
        case .outline: .card
        }
    }
}

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.inkSecondary)
                .tracking(0.4)
            Spacer()
            if let action, let onAction {
                Button(action, action: onAction)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.gain)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct IconBadge: View {
    let systemName: String
    var tint: Color = .gain
    var fill: Color = .gainSoft
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill, in: .rect(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            IconBadge(systemName: icon, tint: .inkSecondary, fill: .chip, size: 56)
            Text(title).font(.headline).foregroundStyle(Color.ink)
            Text(message).font(.subheadline).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }
}
