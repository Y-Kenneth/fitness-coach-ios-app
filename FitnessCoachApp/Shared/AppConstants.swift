import SwiftUI

// MARK: - AppConstants (v2 redesign — bioluminescent teal-black)
//
// Visual language: premium editorial. White cards float on a near-black
// teal-tinted background. Teal accent (#00C9B1) used sparingly as a light
// source, not a fill. Bebas Neue display type with a SF condensed fallback.
enum AppConstants {

    // MARK: Spacing
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    // MARK: Corner radii
    enum CornerRadius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22
        static let card: CGFloat = 22
        static let pill: CGFloat = 999
    }

    // MARK: Color tokens
    //
    // Legacy names (brand, brandDark, onBrand, pageBackground, cardBackground,
    // brandGradient, cardStroke) are preserved so existing call sites keep
    // compiling — they now resolve to v2 values.
    enum Color {
        // Page surface — deep teal-black, never neutral #0A0A0A.
        static let pageBase       = SwiftUI.Color(red: 0x02/255, green: 0x0D/255, blue: 0x0B/255)
        static let pageBackground = pageBase

        // White cards (applied as a 100% → 96% vertical gradient in FCCard).
        static let cardPrimary    = SwiftUI.Color.white
        static let cardSecondary  = SwiftUI.Color(red: 0xF2/255, green: 0xF2/255, blue: 0xF2/255)
        static let cardBackground = cardPrimary
        static let divider        = SwiftUI.Color(red: 0xE6/255, green: 0xE6/255, blue: 0xE6/255)

        // Brand accent — used as a light source.
        static let accent     = SwiftUI.Color(red: 0x00/255, green: 0xC9/255, blue: 0xB1/255)
        static let accentDark = SwiftUI.Color(red: 0x00/255, green: 0xA0/255, blue: 0x90/255)
        static let accentLight = SwiftUI.Color(red: 0x1A/255, green: 0xE4/255, blue: 0xCB/255)

        // Legacy aliases (point at the new teal palette).
        static let brand     = accent
        static let brandDark = accentDark
        static let onBrand   = SwiftUI.Color.black
        static let primary   = accent

        // Text on white cards.
        static let textOnCard  = SwiftUI.Color(red: 0x0D/255, green: 0x0D/255, blue: 0x0D/255)
        static let mutedOnCard = SwiftUI.Color(red: 0x88/255, green: 0x88/255, blue: 0x88/255)
        static let muted2      = SwiftUI.Color(red: 0xC0/255, green: 0xC0/255, blue: 0xC0/255)

        // Status colors.
        static let danger = SwiftUI.Color(red: 0xFF/255, green: 0x6B/255, blue: 0x6B/255)
        static let warn   = SwiftUI.Color(red: 0xF2/255, green: 0xB5/255, blue: 0x44/255)
        static let success = SwiftUI.Color(red: 0x4A/255, green: 0xD9/255, blue: 0x8A/255)

        // Soft accent stroke (legacy).
        static let cardStroke = accent.opacity(0.12)

        // Two-stop teal gradient — used on the AI Coach hero and Health
        // recommendation card. The single "lit surface" per screen.
        static let brandGradient = LinearGradient(
            colors: [accent, accentDark],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: Animations
    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.75)
    }

    // MARK: Accessibility
    enum MinTapSize: CGFloat {
        case standard = 44
    }

    // MARK: Legacy background (still referenced from a few views)
    /// Wraps the new bioluminescent PageBackground for backwards compatibility
    /// with views that haven't migrated to `PageBackground` directly yet.
    struct BrandBackground: View {
        var body: some View { PageBackground() }
    }
}

// MARK: - Hex helper

extension Color {
    /// Build a Color from a 6- or 8-digit hex string. Tolerant of a leading "#".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - FCFont (Bebas Neue with SF condensed fallback)
//
// The handoff doc calls for Bebas Neue for hero words and big stat numbers.
// The font file isn't in the project yet — we use system condensed heavy as a
// stand-in. Swap by dropping BebasNeue-Regular.ttf into the target and
// registering it in Info.plist UIAppFonts; this helper falls back automatically
// because Font.custom honors registered fonts.
enum FCFont {
    /// True if a font named `name` is registered with the system at runtime.
    private static func isFontAvailable(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }

    static let bebasName = "BebasNeue-Regular"

    /// Bebas Neue if available, otherwise SF Pro with .heavy + condensed width.
    static func hero(_ size: CGFloat) -> Font {
        if isFontAvailable(bebasName) {
            return .custom(bebasName, size: size)
        }
        return .system(size: size, weight: .heavy, design: .default).width(.condensed)
    }

    /// Stat number — same logic as hero, slightly tighter weight.
    static func stat(_ size: CGFloat) -> Font {
        if isFontAvailable(bebasName) {
            return .custom(bebasName, size: size)
        }
        return .system(size: size, weight: .heavy, design: .default).width(.condensed)
    }

    /// Section / chip label — SF semibold, uppercased, generous tracking.
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold)
    }

    /// Monospaced micro caption (loading state, "running on local hardware…").
    static func mono(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

// MARK: - PageBackground (bioluminescent teal-black)
//
// Every top-level screen wraps its content in this. Set `bloom: true` for the
// AI Coach loading state — the whole phone reads as lit from within.
struct PageBackground: View {
    var bloom: Bool = false

    var body: some View {
        ZStack {
            AppConstants.Color.pageBase

            // Primary top-center radial — the light source.
            RadialGradient(
                colors: [
                    AppConstants.Color.accent.opacity(bloom ? 0.38 : 0.22),
                    AppConstants.Color.accent.opacity(bloom ? 0.18 : 0.10),
                    .clear
                ],
                center: bloom ? UnitPoint(x: 0.5, y: 0.38) : .top,
                startRadius: 0,
                endRadius: bloom ? 380 : 260
            )

            // Secondary bottom-center wash.
            RadialGradient(
                colors: [AppConstants.Color.accent.opacity(0.10), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 240
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - FCCard (the white card)
//
// 100% → 96% vertical gradient, 0.5px top-edge inner highlight, no drop shadow.
// The page contrast + top highlight is enough to carry the float.
struct FCCard<Content: View>: View {
    var padding: CGFloat = 20
    var radius: CGFloat = AppConstants.CornerRadius.card
    var background: Color = AppConstants.Color.cardPrimary
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [background, background.opacity(0.96)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - HeroWord (giant Bebas Neue word bleeding off the edge)
//
// Per-screen "FITCOACH", "WORKOUTS", "PROGRESS", etc. Fades horizontally toward
// the bleeding edge via a mask — never hard-cropped.
struct HeroWord: View {
    let text: String
    var size: CGFloat = 108
    var side: HorizontalEdge = .leading
    var top: CGFloat = 60
    var opacity: Double = 0.10

    enum HorizontalEdge { case leading, trailing }

    var body: some View {
        Text(text)
            .font(FCFont.hero(size))
            .foregroundStyle(Color.white)
            .opacity(opacity)
            .lineLimit(1)
            .fixedSize()
            .mask(
                LinearGradient(
                    colors: side == .leading
                        ? [.clear, .black, .black]
                        : [.black, .black, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .padding(.leading,  side == .leading  ? -18 : 0)
            .padding(.trailing, side == .trailing ? -18 : 0)
            .padding(.top, top)
            .frame(maxWidth: .infinity, alignment: side == .leading ? .leading : .trailing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Section label (SF Pro semibold uppercase, +0.12 tracking)

struct FCSectionLabel: View {
    let text: String
    var color: Color = AppConstants.Color.muted2

    var body: some View {
        Text(text.uppercased())
            .font(FCFont.label(11))
            .tracking(1.3)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Stat pill (small grey pill used in plan card etc.)

struct FCStatPill: View {
    let icon: String
    let text: String
    var tint: Color = AppConstants.Color.textOnCard

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.05))
        .clipShape(Capsule())
    }
}

// MARK: - Primary CTA (filled teal pill with bloom shadow)

struct FCPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FCFont.hero(20))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AppConstants.Color.accent)
            .clipShape(Capsule())
            .shadow(color: AppConstants.Color.accent.opacity(0.35), radius: 14)
            .shadow(color: AppConstants.Color.accent.opacity(0.25), radius: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Secondary CTA (outlined dark pill)

struct FCSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.04))
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Top bar chip button (back / heart / refresh / close)

struct FCTopBarChip: View {
    let systemImage: String
    var action: () -> Void
    var label: String? = nil
    var tint: Color = Color.white.opacity(0.85)

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.06))
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
                .clipShape(Circle())
        }
        .accessibilityLabel(label ?? systemImage)
    }
}

// MARK: - Teal progress ring (bloomed + crisp double-stroke)

struct FCProgressRing: View {
    let progress: Double             // 0...1
    var lineWidth: CGFloat = 8
    var size: CGFloat = 88

    var body: some View {
        let clamped = max(0, min(1, progress))
        ZStack {
            Circle()
                .stroke(AppConstants.Color.divider, lineWidth: lineWidth)

            // Bloom layer (blurred)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(AppConstants.Color.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .blur(radius: 3.5)
                .opacity(0.55)

            // Crisp layer
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(AppConstants.Color.accent,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .rotationEffect(.degrees(-90))
        .frame(width: size, height: size)
        .animation(AppConstants.Animation.spring, value: clamped)
    }
}
