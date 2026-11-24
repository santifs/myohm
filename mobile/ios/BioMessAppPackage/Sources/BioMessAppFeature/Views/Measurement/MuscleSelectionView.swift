import SwiftUI

// Note: MuscleGroup is defined in Models/Anthropometrics.swift

/// Side of the body for bilateral measurements
public enum BodySide: String, CaseIterable, Codable, Identifiable, Sendable {
    case left = "left"
    case right = "right"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .left: return "Izquierdo"
        case .right: return "Derecho"
        }
    }

    public var shortName: String {
        switch self {
        case .left: return "I"
        case .right: return "D"
        }
    }

    public var legLabel: String {
        switch self {
        case .left: return "Pierna Izquierda"
        case .right: return "Pierna Derecha"
        }
    }

    public var iconName: String {
        switch self {
        case .left: return "arrow.left.circle.fill"
        case .right: return "arrow.right.circle.fill"
        }
    }
}

/// Represents a specific muscle measurement target
struct MuscleTarget: Identifiable, Equatable, Hashable {
    let muscle: MuscleGroup
    let side: BodySide

    var id: String { "\(muscle.rawValue)_\(side.rawValue)" }

    var displayName: String {
        "\(muscle.displayName) \(side.shortName)"
    }

    var fullDisplayName: String {
        "\(muscle.displayName) \(side.displayName)"
    }

    /// All possible muscle targets for a full measurement session
    static var allTargets: [MuscleTarget] {
        var targets: [MuscleTarget] = []
        for muscle in MuscleGroup.allCases {
            for side in BodySide.allCases {
                targets.append(MuscleTarget(muscle: muscle, side: side))
            }
        }
        return targets
    }
}

/// View for selecting which muscle to measure and entering muscle-specific fatigue
struct MuscleSelectionView: View {
    @Binding var selectedMuscle: MuscleTarget?
    @Binding var perceivedFatigue: Int
    let completedMuscles: Set<MuscleTarget>
    let onStartMeasurement: () -> Void
    let onFinishSession: () -> Void

    /// Muscles available for selection (defaults to quadriceps only for first test phase)
    var availableMuscles: [MuscleGroup] = [.quadriceps]

    /// Sides available for selection (defaults to both)
    var availableSides: [BodySide] = [.left, .right]

    /// Pre-selected side based on athlete's dominant leg
    var dominantSide: BodySide?

    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var selectedSide: BodySide?
    @State private var hasInitialized: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // Muscle selection (only shown if multiple muscles available)
                if availableMuscles.count > 1 {
                    muscleGridSection
                }

                // Side selection
                sideSelectionSection

                // Fatigue slider (shown after side selected)
                if selectedMuscle != nil {
                    fatigueSection
                }

                // Action buttons
                actionButtons

                // Progress indicator
                if !availableTargets.isEmpty {
                    progressSection
                }
            }
            .padding()
        }
        .background(Color.systemGroupedBackground)
        .animation(.easeInOut(duration: 0.3), value: selectedMuscleGroup)
        .animation(.easeInOut(duration: 0.3), value: selectedSide)
        .onChange(of: selectedMuscleGroup) { _, _ in
            updateSelectedMuscle()
        }
        .onChange(of: selectedSide) { _, _ in
            updateSelectedMuscle()
        }
        .onAppear {
            initializeSelections()
        }
    }

    // MARK: - Initialization

    private func initializeSelections() {
        guard !hasInitialized else { return }
        hasInitialized = true

        // Auto-select if only one muscle available
        if availableMuscles.count == 1 {
            selectedMuscleGroup = availableMuscles.first
        }

        // Pre-select dominant side if provided
        if let dominant = dominantSide {
            selectedSide = dominant
        }

        updateSelectedMuscle()
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            if let muscle = selectedMuscleGroup {
                MuscleIcon(muscle: muscle, highlighted: true, size: 80)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.brandPrimary.opacity(0.15))
                        .frame(width: 100, height: 100)

                    Image(systemName: "figure.stand")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.brandPrimary)
                }
            }

            VStack(spacing: 6) {
                if let muscle = selectedMuscleGroup {
                    Text(muscle.displayName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(muscle.location)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Seleccionar Músculo")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Elige el grupo muscular a medir")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Muscle Grid Section

    private var muscleGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grupo Muscular")
                .font(.headline)

            ForEach(availableMuscles) { muscle in
                MuscleGroupCard(
                    muscle: muscle,
                    isSelected: selectedMuscleGroup == muscle,
                    completedCount: completedCountFor(muscle: muscle),
                    onSelect: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedMuscleGroup = muscle
                            selectedSide = nil
                        }
                    }
                )
            }
        }
    }

    // MARK: - Side Selection Section

    private var sideSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("¿Qué pierna medir?")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(availableSides) { side in
                    SideSelectionButton(
                        side: side,
                        isSelected: selectedSide == side,
                        isCompleted: isSideCompleted(side),
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedSide = side
                            }
                        }
                    )
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Fatigue Section

    private var fatigueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fatiga Percibida")
                    .font(.headline)

                Spacer()

                if let target = selectedMuscle {
                    Text(target.fullDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            CompactFatigueSliderView(
                value: $perceivedFatigue,
                label: "¿Cómo sientes este músculo?"
            )
            .padding()
            .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Start measurement button
            Button {
                onStartMeasurement()
            } label: {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                    Text("Medir \(selectedMuscle?.fullDisplayName ?? "")")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(selectedMuscle != nil ? Color.brandPrimary : Color.gray)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(selectedMuscle == nil)

            // Finish session button (shown if at least one measurement done)
            if !completedMuscles.isEmpty {
                Button {
                    onFinishSession()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Finalizar Sesión")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Progress Section

    private var availableTargets: [MuscleTarget] {
        var targets: [MuscleTarget] = []
        for muscle in availableMuscles {
            for side in availableSides {
                targets.append(MuscleTarget(muscle: muscle, side: side))
            }
        }
        return targets
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progreso")
                    .font(.headline)

                Spacer()

                Text("\(completedMuscles.count)/\(availableTargets.count)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.brandPrimary)
            }

            ForEach(availableTargets) { target in
                HStack(spacing: 10) {
                    Image(systemName: completedMuscles.contains(target) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(completedMuscles.contains(target) ? Color.green : Color.secondary.opacity(0.4))

                    Text(target.fullDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(completedMuscles.contains(target) ? .primary : .secondary)

                    Spacer()

                    if completedMuscles.contains(target) {
                        Text("Completado")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .padding()
        .background(Color.secondarySystemGroupedBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helper Methods

    private func updateSelectedMuscle() {
        guard let muscle = selectedMuscleGroup, let side = selectedSide else {
            selectedMuscle = nil
            return
        }
        selectedMuscle = MuscleTarget(muscle: muscle, side: side)
    }

    private func completedCountFor(muscle: MuscleGroup) -> Int {
        completedMuscles.filter { $0.muscle == muscle }.count
    }

    private func isSideCompleted(_ side: BodySide) -> Bool {
        guard let muscle = selectedMuscleGroup else { return false }
        return completedMuscles.contains(MuscleTarget(muscle: muscle, side: side))
    }
}

// MARK: - Muscle Group Card

private struct MuscleGroupCard: View {
    let muscle: MuscleGroup
    let isSelected: Bool
    let completedCount: Int
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                MuscleIcon(muscle: muscle, highlighted: isSelected, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(muscle.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(muscle.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if completedCount > 0 {
                    Text("\(completedCount)/2")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.brandPrimary)
                }
            }
            .padding()
            .background(
                isSelected
                    ? Color.brandPrimary.opacity(0.08)
                    : Color.secondarySystemGroupedBackground,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Side Selection Button

private struct SideSelectionButton: View {
    let side: BodySide
    let isSelected: Bool
    let isCompleted: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.brandPrimary.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 56, height: 56)

                    Image(systemName: side.iconName)
                        .font(.title2)
                        .foregroundStyle(isSelected ? Color.brandPrimary : .secondary)
                }

                Text(side.legLabel)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                if isCompleted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption2)
                        Text("Medido")
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                isSelected
                    ? Color.brandPrimary.opacity(0.08)
                    : Color.secondarySystemGroupedBackground,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Muscle Selection") {
    struct PreviewWrapper: View {
        @State private var selectedMuscle: MuscleTarget?
        @State private var fatigue: Int = 5
        @State private var completed: Set<MuscleTarget> = [
            MuscleTarget(muscle: MuscleGroup.quadriceps, side: BodySide.right)
        ]

        var body: some View {
            MuscleSelectionView(
                selectedMuscle: $selectedMuscle,
                perceivedFatigue: $fatigue,
                completedMuscles: completed,
                onStartMeasurement: {},
                onFinishSession: {}
            )
        }
    }

    return PreviewWrapper()
}
