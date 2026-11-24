import SwiftUI

/// Reusable fatigue slider component with linear 0-10 scale
/// Used for both general fatigue and muscle-specific fatigue measurements
struct FatigueSliderView: View {
    @Binding var value: Int
    var label: String = "Fatiga"
    var showLabel: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showLabel {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            // Value display
            HStack {
                Text("Nivel:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("\(value)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.brandPrimary)
                    .frame(minWidth: 40)

                Text("/ 10")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                // Fatigue description badge
                Text(fatigueDescription)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.brandPrimary, in: Capsule())
            }

            // Slider with labels
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = Int($0.rounded()) }
                    ),
                    in: 0...10,
                    step: 1
                )
                .tint(Color.brandPrimary)

                // Labels at key points
                HStack {
                    Text("0")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("5")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("10")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Descriptive labels
                HStack {
                    Text("Sin fatiga")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Moderada")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Máxima")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Computed Properties

    private var fatigueDescription: String {
        switch value {
        case 0:
            return "Sin fatiga"
        case 1...3:
            return "Baja"
        case 4...6:
            return "Moderada"
        case 7...9:
            return "Alta"
        case 10:
            return "Máxima"
        default:
            return "---"
        }
    }
}

// MARK: - Compact Variant

/// A more compact version of the fatigue slider for inline use
struct CompactFatigueSliderView: View {
    @Binding var value: Int
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(value)/10")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.brandPrimary)
            }

            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: 0...10,
                step: 1
            )
            .tint(Color.brandPrimary)
        }
    }
}

// MARK: - Preview

#Preview("Fatigue Slider") {
    struct PreviewWrapper: View {
        @State private var fatigue = 5

        var body: some View {
            VStack(spacing: 20) {
                FatigueSliderView(
                    value: $fatigue,
                    label: "Fatiga general"
                )

                CompactFatigueSliderView(
                    value: $fatigue,
                    label: "Cuadriceps derecho"
                )
                .padding()
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
