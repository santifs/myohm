import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Apple-Style Color System

extension Color {
    // Primary Colors - Minimal, elegant palette
    static let systemIndigo = Color(red: 88/255, green: 86/255, blue: 214/255)
    static let systemTeal = Color(red: 48/255, green: 176/255, blue: 199/255)
    static let systemMint = Color(red: 0/255, green: 199/255, blue: 190/255)

    // Accent Colors
    static let accentBlue = Color(red: 0/255, green: 122/255, blue: 255/255)
    static let accentPurple = Color(red: 175/255, green: 82/255, blue: 222/255)

    // Brand Primary (iOS Blue)
    static let brandPrimary = Color(red: 0/255, green: 122/255, blue: 255/255)

    // Cross-platform system grays (adaptive for dark mode)
    #if os(iOS)
    static let systemGray4 = Color(UIColor.systemGray4)
    static let systemGray5 = Color(UIColor.systemGray5)
    static let systemGray6 = Color(UIColor.systemGray6)
    #else
    static let systemGray4 = Color(red: 209/255, green: 209/255, blue: 214/255)
    static let systemGray5 = Color(red: 229/255, green: 229/255, blue: 234/255)
    static let systemGray6 = Color(red: 242/255, green: 242/255, blue: 247/255)
    #endif

    // Cross-platform system backgrounds
    #if os(iOS)
    static let systemBackground = Color(UIColor.systemBackground)
    static let systemGroupedBackground = Color(UIColor.systemGroupedBackground)
    static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
    static let secondarySystemGroupedBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)
    static let tertiarySystemGroupedBackground = Color(UIColor.tertiarySystemGroupedBackground)
    #else
    static let systemBackground = Color.white
    static let systemGroupedBackground = Color(red: 242/255, green: 242/255, blue: 247/255)
    static let secondarySystemBackground = Color(red: 242/255, green: 242/255, blue: 247/255)
    static let secondarySystemGroupedBackground = Color.white
    static let tertiarySystemBackground = Color.white
    static let tertiarySystemGroupedBackground = Color(red: 242/255, green: 242/255, blue: 247/255)
    #endif

    // Semantic Colors for Parameters
    static let parameterPrimary = Color.systemIndigo
    static let parameterSecondary = Color.systemTeal
    static let parameterTertiary = Color.systemMint

    // Quality Indicators
    static let qualityExcellent = Color.green
    static let qualityGood = Color.mint
    static let qualityFair = Color.orange
    static let qualityPoor = Color.red

    // Gradients
    static let heroGradient = LinearGradient(
        colors: [.systemIndigo, .systemTeal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [.systemIndigo.opacity(0.1), .systemTeal.opacity(0.1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Typography System

extension Font {
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .default)
    static let title1 = Font.system(size: 28, weight: .bold, design: .default)
    static let title2 = Font.system(size: 22, weight: .bold, design: .default)
    static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)
    static let body = Font.system(size: 17, weight: .regular, design: .default)
    static let callout = Font.system(size: 16, weight: .regular, design: .default)
    static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
    static let footnote = Font.system(size: 13, weight: .regular, design: .default)
    static let caption1 = Font.system(size: 12, weight: .regular, design: .default)
    static let caption2 = Font.system(size: 11, weight: .regular, design: .default)

    // Monospaced for values
    static let monoLarge = Font.system(size: 28, weight: .semibold, design: .monospaced)
    static let monoBody = Font.system(size: 17, weight: .regular, design: .monospaced)
    static let monoCaption = Font.system(size: 13, weight: .regular, design: .monospaced)
}

// MARK: - Modern Components

/// Stat card with large number and label
struct StatCard: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.monoLarge)
                .fontWeight(.semibold)

            Text(label)
                .font(.caption1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Metric row with label and value
struct MetricRow: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.monoBody)
                .fontWeight(.semibold)
            +
            Text(" ")
            +
            Text(unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

/// Large parameter display card
struct ParameterCard: View {
    let label: String
    let value: String
    let unit: String
    let description: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(color, lineWidth: 2)
                    )
            }

            Text(description)
                .font(.caption1)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)

                Text(unit)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Quality indicator
struct QualityIndicator: View {
    let score: Float

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.caption1)
            Text(qualityText)
                .font(.caption1)
                .fontWeight(.medium)
        }
        .foregroundStyle(qualityColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(qualityColor.opacity(0.15), in: Capsule())
    }

    private var iconName: String {
        if score >= 0.9 { return "checkmark.circle.fill" }
        if score >= 0.8 { return "checkmark.circle" }
        if score >= 0.6 { return "exclamationmark.circle" }
        return "xmark.circle"
    }

    private var qualityText: String {
        if score >= 0.9 { return "Excellent" }
        if score >= 0.8 { return "Good" }
        if score >= 0.6 { return "Fair" }
        return "Poor"
    }

    private var qualityColor: Color {
        if score >= 0.9 { return .qualityExcellent }
        if score >= 0.8 { return .qualityGood }
        if score >= 0.6 { return .qualityFair }
        return .qualityPoor
    }
}

/// Small value chip
struct ValuePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption1)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.tertiary.opacity(0.3), in: Capsule())
            .foregroundStyle(.secondary)
    }
}

// MARK: - Share Sheet

#if os(iOS)
/// UIKit share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}
#else
struct ShareSheet: View {
    let items: [Any]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export ready")
                .font(.headline)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(String(describing: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(minWidth: 320)
    }
}
#endif

// MARK: - Muscle Icons

/// Muscle group icon showing a standing figure with the target zone highlighted
struct MuscleIcon: View {
    let muscle: MuscleGroup
    let highlighted: Bool
    var size: CGFloat = 44

    private var accentColor: Color {
        highlighted ? .brandPrimary : .secondary
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(accentColor.opacity(highlighted ? 0.15 : 0.08))
                .frame(width: size, height: size)

            // Standing figure
            Image(systemName: "figure.stand")
                .font(.system(size: size * 0.5))
                .foregroundStyle(accentColor.opacity(0.4))

            // Zone indicator badge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(muscle == .quadriceps ? "F" : "P")
                        .font(.system(size: size * 0.22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: size * 0.36, height: size * 0.36)
                        .background(accentColor, in: Circle())
                }
            }
            .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Button Styles

/// Primary button style - filled with brand color
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(isEnabled ? Color.brandPrimary : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(12)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

/// Secondary button style - text only with brand color
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundColor(.brandPrimary)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Keyboard Dismiss

#if os(iOS)
extension View {
    /// Dismisses the keyboard when tapping outside of text fields.
    /// Uses a high-priority gesture on a background layer so it doesn't
    /// swallow taps on buttons, sliders, or other interactive controls.
    func dismissKeyboardOnTap() -> some View {
        self.background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
        )
    }

    /// Adds interactive keyboard dismissal to ScrollViews and tap dismissal
    func keyboardDismissible() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
    }
}
#else
extension View {
    func dismissKeyboardOnTap() -> some View { self }
    func keyboardDismissible() -> some View { self }
}
#endif
