import SwiftUI

/// Reusable row component for displaying athlete information in lists
struct AthleteRowView: View {
    let athlete: Athlete
    let isActive: Bool
    let onSelect: (() -> Void)?

    init(athlete: Athlete, isActive: Bool = false, onSelect: (() -> Void)? = nil) {
        self.athlete = athlete
        self.isActive = isActive
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatarView

            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Name
                Text(athlete.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Details (age, weight, height)
                Text(detailsText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Active badge
                if isActive {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                        Text("Activo")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.green)
                }
            }

            Spacer()

            // Selection indicator (radio button style)
            if let onSelect = onSelect {
                Button(action: onSelect) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isActive ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Subviews

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(isActive ? Color.green.opacity(0.15) : Color.systemGray5)
                .frame(width: 50, height: 50)

            Image(systemName: "person.fill")
                .font(.title2)
                .foregroundStyle(isActive ? .green : .secondary)
        }
    }

    // MARK: - Computed Properties

    private var detailsText: String {
        var parts: [String] = []

        // Age
        let age = athlete.age
        if age > 0 {
            parts.append("\(age) años")
        }

        // Weight from latest anthropometrics
        if let weight = athlete.latestAnthropometrics?.weightKg {
            parts.append(String(format: "%.0f kg", weight))
        }

        // Height from latest anthropometrics
        if let height = athlete.latestAnthropometrics?.heightCm {
            parts.append(String(format: "%.0f cm", height))
        }

        return parts.isEmpty ? "Sin detalles" : parts.joined(separator: " \u{2022} ")
    }
}

// MARK: - Compact Variant

/// A more compact version of the row for smaller spaces
struct AthleteRowCompactView: View {
    let athlete: Athlete
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Small avatar
            ZStack {
                Circle()
                    .fill(isActive ? Color.green.opacity(0.15) : Color.systemGray5)
                    .frame(width: 36, height: 36)

                Image(systemName: "person.fill")
                    .font(.body)
                    .foregroundStyle(isActive ? .green : .secondary)
            }

            // Name only
            Text(athlete.displayName)
                .font(.subheadline)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            // Active indicator
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview("Regular Row") {
    List {
        AthleteRowView(
            athlete: previewAthlete(name: "Juan Garcia", age: 25),
            isActive: true,
            onSelect: {}
        )
        AthleteRowView(
            athlete: previewAthlete(name: "Maria Lopez", age: 22),
            isActive: false,
            onSelect: {}
        )
        AthleteRowView(
            athlete: previewAthlete(name: "Pedro Sanchez", age: 28),
            isActive: false,
            onSelect: {}
        )
    }
}

#Preview("Compact Row") {
    List {
        AthleteRowCompactView(
            athlete: previewAthlete(name: "Juan Garcia", age: 25),
            isActive: true
        )
        AthleteRowCompactView(
            athlete: previewAthlete(name: "Maria Lopez", age: 22),
            isActive: false
        )
    }
}

// MARK: - Preview Helpers

private func previewAthlete(name: String, age: Int) -> Athlete {
    let calendar = Calendar.current
    let birthDate = calendar.date(byAdding: .year, value: -age, to: Date()) ?? Date()

    let athlete = Athlete(
        fullName: name,
        dateOfBirth: birthDate
    )

    // Add sample anthropometrics
    let anthropometrics = Anthropometrics(
        athlete: athlete,
        weightKg: Double.random(in: 60...90),
        heightCm: Double.random(in: 165...190)
    )
    athlete.anthropometrics = [anthropometrics]

    return athlete
}
