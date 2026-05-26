import SwiftUI

// ─────────────────────────────────────────────
//  AppTheme  —  BeautyBrief design system
//  Primary:   Beige
//  Secondary: Mocha Chocolate
//  Accent:    Baby Pink
// ─────────────────────────────────────────────

enum AppTheme {

    // MARK: — Colours
    static let beige      = Color(hex: "#F7EFE5")
    static let beigeMid   = Color(hex: "#EDE0D0")
    static let beigeDark  = Color(hex: "#DDD0BF")

    static let mocha      = Color(hex: "#6B4C3B")
    static let mochaDark  = Color(hex: "#4E3328")
    static let mochaLight = Color(hex: "#9B7060")

    static let pink       = Color(hex: "#F2B8C6")
    static let pinkLight  = Color(hex: "#FAE3EA")
    static let pinkDark   = Color(hex: "#E592A8")

    static let textMain   = Color(hex: "#3A2A20")
    static let textSoft   = Color(hex: "#7A5C4A")

    // Semantic
    static let success    = Color(hex: "#7BAE8F")
    static let danger     = Color(hex: "#C97070")
    static let warning    = Color(hex: "#D4A96A")
    static let info       = Color(hex: "#7A9EBE")

    // MARK: — Typography
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Georgia", size: size).weight(weight)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    // MARK: — Shadows
    static let cardShadow = Color.black.opacity(0.06)
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 4

    // MARK: — Corner Radii
    static let radiusSm:  CGFloat = 8
    static let radiusMd:  CGFloat = 14
    static let radiusLg:  CGFloat = 20

    // MARK: — Spacing
    static let spacingXS: CGFloat = 6
    static let spacingSm: CGFloat = 12
    static let spacingMd: CGFloat = 20
    static let spacingLg: CGFloat = 32
}

// MARK: — Hex colour helper
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var int: UInt64 = 0
        scanner.scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: — View Modifiers
struct BeautyCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
            .shadow(color: AppTheme.cardShadow, radius: AppTheme.shadowRadius, x: 0, y: AppTheme.shadowY)
    }
}

struct PinkAccentBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.pinkDark, AppTheme.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
    }
}

extension View {
    func beautyCard() -> some View {
        modifier(BeautyCardStyle())
    }
    func pinkAccentBar() -> some View {
        modifier(PinkAccentBar())
    }
}

// MARK: — Button Styles

/// Large filled mocha button — primary CTA.
struct PrimaryButtonStyle: ButtonStyle {
    var isDestructive: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.sans(16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isDestructive ? AppTheme.danger : AppTheme.mocha)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

/// Outlined mocha button — secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.sans(15, weight: .medium))
            .foregroundStyle(AppTheme.mocha)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.clear)
            .overlay {

                RoundedRectangle(cornerRadius: AppTheme.radiusMd)
                .stroke(AppTheme.beigeDark, lineWidth: 1.5)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: — Reusable Components

/// Circular SF Symbol badge with a tinted background.
struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 36
    var iconSize: CGFloat = 15

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

/// Standard section header used across all tabs.
struct ThemedSectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon = systemImage {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.mochaLight)
            }
            Text(title.uppercased())
                .font(AppTheme.sans(11, weight: .semibold))
                .foregroundStyle(AppTheme.mochaLight)
                .tracking(1.0)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}

/// Full-screen empty state with icon, headline, and optional message.
struct EmptyStateView: View {
    let systemName: String
    let title: String
    var message: String? = nil
    var iconColor: Color = AppTheme.beigeDark

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: systemName)
                .font(.system(size: 52, weight: .thin))
                .foregroundStyle(iconColor)
            Text(title)
                .font(AppTheme.serif(20, weight: .semibold))
                .foregroundStyle(AppTheme.mochaDark)
                .multilineTextAlignment(.center)
            if let msg = message {
                Text(msg)
                    .font(AppTheme.sans(14))
                    .foregroundStyle(AppTheme.textSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
    }
}

/// Inline loading indicator with label.
struct LoadingStateView: View {
    var message: String = "Loading…"

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(AppTheme.mocha)
                .scaleEffect(1.2)
            Text(message)
                .font(AppTheme.sans(14))
                .foregroundStyle(AppTheme.textSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}
