import SwiftUI

/// View shown after completing a measurement session
/// Displays summary statistics and allows starting a new session
struct SessionSummaryView: View {
    let measurements: [MuscleMeasurement]
    let statistics: SessionStatistics?
    let athleteName: String
    let onNewSession: () -> Void
    let onViewHistory: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Quick stats
                if let stats = statistics {
                    quickStatsSection(stats: stats)
                }

                // Measurements breakdown
                measurementsBreakdownSection

                // Bilateral analysis
                if let stats = statistics, !stats.bilateralDifferences.isEmpty {
                    bilateralAnalysisSection(stats: stats)
                }

                // Warnings
                if let stats = statistics, stats.hasBilateralImbalance {
                    warningsSection(stats: stats)
                }

                // Action buttons
                actionButtonsSection
            }
            .padding()
        }
        .background(Color.systemGroupedBackground)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 8) {
                Text("Sesión Completada")
                    .font(.title)
                    .fontWeight(.bold)

                Text(athleteName)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(Date().formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Quick Stats Section

    private func quickStatsSection(stats: SessionStatistics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            QuickStatCard(
                value: "\(stats.totalMeasurements)",
                label: "Mediciones",
                icon: "waveform.path.ecg",
                color: .blue
            )

            QuickStatCard(
                value: String(format: "%.1f", stats.averageFatigue),
                label: "Fatiga Promedio",
                icon: "gauge",
                color: fatigueColor(for: stats.averageFatigue)
            )

            QuickStatCard(
                value: stats.formattedDuration,
                label: "Duración",
                icon: "clock",
                color: .purple
            )

            QuickStatCard(
                value: stats.fatigueLevel,
                label: "Nivel",
                icon: "chart.bar",
                color: fatigueColor(for: stats.averageFatigue)
            )
        }
    }

    // MARK: - Measurements Breakdown Section

    private var measurementsBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Detalle de Mediciones")
                .font(.headline)

            VStack(spacing: 12) {
                ForEach(measurements) { measurement in
                    MeasurementRow(measurement: measurement)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Bilateral Analysis Section

    private func bilateralAnalysisSection(stats: SessionStatistics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.blue)
                Text("Análisis Bilateral")
                    .font(.headline)
            }

            VStack(spacing: 12) {
                ForEach(MuscleGroup.allCases) { muscle in
                    if let diff = stats.bilateralDifferences[muscle] {
                        BilateralComparisonRow(
                            muscle: muscle,
                            difference: diff,
                            leftFatigue: getMeasurementFatigue(muscle: muscle, side: BodySide.left),
                            rightFatigue: getMeasurementFatigue(muscle: muscle, side: BodySide.right)
                        )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Warnings Section

    private func warningsSection(stats: SessionStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Alertas")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(stats.imbalanceWarnings, id: \.self) { warning in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)

                        Text(warning)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                }

                Text("Una diferencia de 3 o más puntos entre lados puede indicar un desequilibrio que requiere atención.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button {
                onNewSession()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Nueva Sesión")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.gradient)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                onViewHistory()
            } label: {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Ver Historial")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.ultraThinMaterial)
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Helper Methods

    private func fatigueColor(for value: Double) -> Color {
        switch value {
        case 0...3: return .green
        case 4...6: return .orange
        case 7...10: return .red
        default: return .secondary
        }
    }

    private func getMeasurementFatigue(muscle: MuscleGroup, side: BodySide) -> Int? {
        measurements.first {
            $0.target.muscle == muscle && $0.target.side == side
        }?.perceivedFatigue
    }
}

// MARK: - Quick Stat Card

private struct QuickStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Measurement Row

private struct MeasurementRow: View {
    let measurement: MuscleMeasurement

    var body: some View {
        HStack {
            // Muscle icon
            ZStack {
                Circle()
                    .fill(muscleColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: measurement.target.muscle.iconName)
                    .foregroundStyle(muscleColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(measurement.target.fullDisplayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(measurement.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Fatigue badge
            FatigueBadge(value: measurement.perceivedFatigue)
        }
        .padding(.vertical, 4)
    }

    private var muscleColor: Color {
        switch measurement.target.muscle {
        case .quadriceps, .vastusLateralis: return .blue
        case .hamstring, .bicepsFemoris: return .purple
        case .bicepsBrachii: return .orange
        }
    }
}

// MARK: - Fatigue Badge

private struct FatigueBadge: View {
    let value: Int

    var body: some View {
        Text("\(value)/10")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(fatigueColor, in: Capsule())
    }

    private var fatigueColor: Color {
        switch value {
        case 0...3: return .green
        case 4...6: return .orange
        case 7...10: return .red
        default: return .secondary
        }
    }
}

// MARK: - Bilateral Comparison Row

private struct BilateralComparisonRow: View {
    let muscle: MuscleGroup
    let difference: Int
    let leftFatigue: Int?
    let rightFatigue: Int?

    var body: some View {
        VStack(spacing: 8) {
            // Muscle name
            HStack {
                Image(systemName: muscle.iconName)
                    .foregroundStyle(.secondary)
                Text(muscle.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()

                // Difference badge
                if difference > 0 {
                    Text("\(difference >= 3 ? "!" : "") \(difference)pt")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(difference >= 3 ? .orange : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(difference >= 3 ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1))
                        )
                }
            }

            // Left/Right comparison
            HStack(spacing: 16) {
                // Left side
                HStack {
                    Text("I")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    if let left = leftFatigue {
                        FatigueBar(value: left)
                        Text("\(left)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(width: 20)
                    } else {
                        Text("-")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                // Right side
                HStack {
                    Text("D")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    if let right = rightFatigue {
                        FatigueBar(value: right)
                        Text("\(right)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(width: 20)
                    } else {
                        Text("-")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.systemGroupedBackground)
        )
    }
}

// MARK: - Fatigue Bar

private struct FatigueBar: View {
    let value: Int

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.2))

                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: geometry.size.width * CGFloat(value) / 10)
            }
        }
        .frame(height: 8)
    }

    private var barColor: Color {
        switch value {
        case 0...3: return .green
        case 4...6: return .orange
        case 7...10: return .red
        default: return .secondary
        }
    }
}

// MARK: - Preview

#Preview("Session Summary") {
    SessionSummaryView(
        measurements: [
            MuscleMeasurement(
                target: MuscleTarget(muscle: MuscleGroup.quadriceps, side: BodySide.right),
                perceivedFatigue: 3
            ),
            MuscleMeasurement(
                target: MuscleTarget(muscle: MuscleGroup.quadriceps, side: BodySide.left),
                perceivedFatigue: 5
            ),
            MuscleMeasurement(
                target: MuscleTarget(muscle: MuscleGroup.hamstring, side: BodySide.right),
                perceivedFatigue: 7
            ),
            MuscleMeasurement(
                target: MuscleTarget(muscle: MuscleGroup.hamstring, side: BodySide.left),
                perceivedFatigue: 4
            )
        ],
        statistics: SessionStatistics(
            totalMeasurements: 4,
            averageFatigue: 4.75,
            maxFatigue: 7,
            minFatigue: 3,
            bilateralDifferences: [
                MuscleGroup.quadriceps: 2,
                MuscleGroup.hamstring: 3
            ],
            sessionDuration: 185
        ),
        athleteName: "Juan Garcia",
        onNewSession: {},
        onViewHistory: {}
    )
}

#Preview("Empty Session") {
    SessionSummaryView(
        measurements: [],
        statistics: nil,
        athleteName: "Juan Garcia",
        onNewSession: {},
        onViewHistory: {}
    )
}
