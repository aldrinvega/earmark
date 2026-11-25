import SwiftUI

extension Color {
    /// 0xRRGGBB.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Colours and type from the design canvas (SPEC.md links it). Serif titles use the system serif.
enum Theme {
    static let paper = Color(hex: 0xF4F1EC)
    static let ink = Color(hex: 0x1C1A1F)
    static let mutedInk = Color(hex: 0x5E5866)
    static let plum = Color(hex: 0x6B2F57)
    static let aubergine = Color(hex: 0x22111E)
    static let gold = Color(hex: 0xE8C77A)
    static let coral = Color(hex: 0xFF9B8F)

    static func serif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// The soft colour behind the glass. Plain colour under Reduce Transparency.
struct BlobBackdrop: View {
    enum Style {
        case light
        case dark
    }

    let style: Style
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            style == .light ? Theme.paper : Theme.aubergine
            if !reduceTransparency {
                switch style {
                case .light:
                    blob(0xE9D3E0, size: 320, blur: 60, x: 140, y: -330)
                    blob(0xF1DDBF, size: 280, blur: 70, x: -150, y: 200)
                case .dark:
                    blob(0x7A3566, size: 380, blur: 70, x: -100, y: -260)
                    blob(0xC98A3C, size: 300, blur: 80, x: 150, y: 90, opacity: 0.6)
                    blob(0x2C2F6B, size: 340, blur: 80, x: -60, y: 340, opacity: 0.85)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ hex: UInt32, size: CGFloat, blur: CGFloat, x: CGFloat, y: CGFloat, opacity: Double = 1) -> some View {
        Circle().fill(Color(hex: hex)).frame(width: size, height: size).blur(radius: blur).opacity(opacity).offset(x: x, y: y)
    }
}
