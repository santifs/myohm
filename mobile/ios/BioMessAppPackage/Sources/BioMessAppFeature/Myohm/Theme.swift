import SwiftUI

/// Localised string from the package bundle. Source language is English; Spanish lives in es.lproj.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

enum MyohmColor {
    static let brand = Color(hex: 0x092568)
    static let brandDeep = Color(hex: 0x071A4D)
    static let brandMid = Color(hex: 0x1B3C94)
    static let brandSoft = Color(hex: 0xE7ECF8)
    static let background = Color(hex: 0xF4F6FA)
    static let card = Color.white
    static let ink = Color(hex: 0x0B1533)
    static let muted = Color(hex: 0x5A6480)
    static let line = Color(hex: 0xDCE1EC)
    static let hairline = Color(hex: 0xEEF1F7)
    static let accent = Color(hex: 0xC4580F)
    static let accentSoft = Color(hex: 0xF2A25C)
    static let accentBg = Color(hex: 0xFDEBDC)
    static let accentInk = Color(hex: 0x8A3C08)
    static let success = Color(hex: 0x1E7A4C)
    static let successBg = Color(hex: 0xE3F2EA)
    static let leanOnDark = Color(hex: 0x9FB4F2)
    static let waterOnDark = Color(hex: 0x6FD3E6)
    static let chartBlue = Color(hex: 0x3E63C9)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum MyohmFont {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .default) }
    static func title(_ size: CGFloat = 22) -> Font { .system(size: size, weight: .bold) }
    static let headline = Font.system(size: 17, weight: .bold)
    static let body = Font.system(size: 15)
    static let caption = Font.system(size: 13)
    static let micro = Font.system(size: 12, weight: .semibold)
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MyohmColor.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: MyohmColor.ink.opacity(0.06), radius: 1, y: 1)
    }
}

extension View {
    func myohmCard(padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

struct MyohmPrimaryButton: ButtonStyle {
    var light = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(light ? MyohmColor.brand : .white)
            .background(light ? Color.white : MyohmColor.brand, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct MyohmSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(MyohmColor.ink)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(MyohmColor.line))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Segmented control matching the design (white pill on a grey track).
struct PillSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { option in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = option.0 }
                } label: {
                    Text(option.1)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(selection == option.0 ? MyohmColor.brand : MyohmColor.muted)
                        .background {
                            if selection == option.0 {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white)
                                    .shadow(color: MyohmColor.ink.opacity(0.12), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.0 ? .isSelected : [])
            }
        }
        .padding(3)
        .background(MyohmColor.hairline, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ChipButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .foregroundStyle(selected ? .white : MyohmColor.ink)
                .background(selected ? MyohmColor.brand : .white, in: Capsule())
                .overlay(Capsule().stroke(selected ? MyohmColor.brand : MyohmColor.line))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(MyohmColor.muted)
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

enum MyohmFormat {
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
    static func degrees(_ value: Double) -> String { number(value) + "°" }
    static func percent(_ value: Double) -> String { number(value) + " %" }
    static func kg(_ value: Double) -> String { number(value) + " kg" }
    static func litres(_ value: Double) -> String { number(value) + " L" }
    static func ohms(_ value: Double) -> String { number(value, digits: 0) + " Ω" }
    static func frequency(_ hz: Double) -> String {
        let k = hz / 1000
        let digits = hz >= 1000 && abs(k - k.rounded()) > 0.05 ? 1 : 0
        return hz >= 1000 ? number(k, digits: digits) + " kHz" : number(hz, digits: 0) + " Hz"
    }
}
