import SwiftUI

// MARK: - Step Configuration

/// Configuration for a single step in a StepFlowView.
struct StepConfig {
    let title: String
    let subtitle: String?
    let isOptional: Bool
    let autoAdvance: Bool

    init(
        title: String,
        subtitle: String? = nil,
        isOptional: Bool = false,
        autoAdvance: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isOptional = isOptional
        self.autoAdvance = autoAdvance
    }
}

// MARK: - StepFlowView

/// A generic step-by-step container that displays a progress bar, title area,
/// centered content, and a "Siguiente" / custom last-step button pinned at the bottom.
///
/// Usage:
/// ```swift
/// StepFlowView(
///     steps: [
///         StepConfig(title: "Peso", subtitle: "Ingresa tu peso actual"),
///         StepConfig(title: "Hidratación", isOptional: true),
///         StepConfig(title: "Resumen")
///     ],
///     currentStep: $currentStep,
///     canProceed: isStepValid,
///     lastButtonTitle: "Comenzar",
///     onComplete: { handleComplete() }
/// ) { stepIndex in
///     // Return content for each step
/// }
/// ```
struct StepFlowView<Content: View>: View {
    let steps: [StepConfig]
    @Binding var currentStep: Int
    let canProceed: Bool
    let lastButtonTitle: String
    let onComplete: () -> Void
    let onSkip: (() -> Void)?
    @ViewBuilder let content: (Int) -> Content

    init(
        steps: [StepConfig],
        currentStep: Binding<Int>,
        canProceed: Bool = true,
        lastButtonTitle: String = "Finalizar",
        onComplete: @escaping () -> Void,
        onSkip: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Int) -> Content
    ) {
        self.steps = steps
        self._currentStep = currentStep
        self.canProceed = canProceed
        self.lastButtonTitle = lastButtonTitle
        self.onComplete = onComplete
        self.onSkip = onSkip
        self.content = content
    }

    private var isLastStep: Bool {
        currentStep >= steps.count - 1
    }

    private var currentConfig: StepConfig? {
        guard steps.indices.contains(currentStep) else { return nil }
        return steps[currentStep]
    }

    @State private var navigatingBack = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: back button + progress bar
            HStack(spacing: 12) {
                // Back button (hidden on step 0)
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .opacity(currentStep > 0 ? 1 : 0)
                .disabled(currentStep <= 0)

                progressBar
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Scrollable content area (fills space above pinned button)
            GeometryReader { geo in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Flexible top spacer — centers content when shorter than screen
                        Spacer(minLength: 20)

                        // Title area
                        titleArea
                            .padding(.horizontal, 24)
                            .padding(.bottom, 28)

                        // Step content
                        content(currentStep)
                            .id(currentStep)
                            .frame(maxWidth: .infinity)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: navigatingBack ? .leading : .trailing).combined(with: .opacity),
                                    removal: .move(edge: navigatingBack ? .trailing : .leading).combined(with: .opacity)
                                )
                            )
                            .animation(.easeInOut(duration: 0.3), value: currentStep)

                        // Flexible bottom spacer — works with top spacer to center
                        Spacer(minLength: 32)
                    }
                    .frame(minHeight: geo.size.height)
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
            }

            // Pinned bottom area: divider + Skip + Action Button
            Divider()

            bottomArea
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 12)
        }
        .background(Color.systemGroupedBackground)
        .dismissKeyboardOnTap()
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<steps.count, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.brandPrimary : Color.systemGray4)
                    .frame(height: 4)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: currentStep)
    }

    // MARK: - Title Area

    private var titleArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let config = currentConfig {
                Text(config.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                if let subtitle = config.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom Area

    private var bottomArea: some View {
        VStack(spacing: 12) {
            // Skip link for optional steps
            if let config = currentConfig, config.isOptional {
                Button {
                    if let onSkip {
                        onSkip()
                    } else {
                        advanceStep()
                    }
                } label: {
                    Text("Omitir")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.brandPrimary)
                }
            }

            // Main action button
            Button {
                if isLastStep {
                    onComplete()
                } else {
                    advanceStep()
                }
            } label: {
                Text(isLastStep ? lastButtonTitle : "Siguiente")
            }
            .buttonStyle(.primary)
            .disabled(!canProceed)
        }
    }

    // MARK: - Navigation

    private func advanceStep() {
        navigatingBack = false
        withAnimation(.easeInOut(duration: 0.3)) {
            if currentStep < steps.count - 1 {
                currentStep += 1
            }
        }
    }

    private func goBack() {
        guard currentStep > 0 else { return }
        navigatingBack = true
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep -= 1
        }
    }
}

// MARK: - VisualStepper

/// A large number display with plus/minus buttons for numeric input.
/// Designed for quickly adjusting values like weight, reps, etc.
///
/// Features:
/// - Tap the number to type a value directly
/// - Long-press +/- for accelerating repeat
struct VisualStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let format: String

    @State private var isEditing = false
    @State private var editText = ""
    @FocusState private var isTextFieldFocused: Bool

    // Long-press acceleration state
    @State private var repeatTimer: Timer?
    @State private var repeatStart: Date?

    init(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        unit: String = "",
        format: String = "%.0f"
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.format = format
    }

    private var hasDecimals: Bool {
        format.contains(".1")
    }

    private var integerPart: Int {
        Int(value)
    }

    private var decimalPart: Int {
        let rounded = (value * 10).rounded() / 10
        return abs(Int((rounded - Double(Int(rounded))) * 10))
    }

    var body: some View {
        VStack(spacing: 4) {
            if isEditing {
                editView
            } else if hasDecimals {
                decimalStepperView
            } else {
                integerStepperView
            }

            if !unit.isEmpty {
                Text(unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .animation(.easeInOut(duration: 0.15), value: value)
    }

    // MARK: - Decimal Mode (two columns)

    private var decimalStepperView: some View {
        HStack(spacing: 2) {
            digitColumn(
                displayValue: "\(integerPart)",
                canIncrement: value + 1.0 <= range.upperBound,
                canDecrement: value - 1.0 >= range.lowerBound,
                stepSize: 1.0
            )

            Text(",")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .offset(y: 2)

            digitColumn(
                displayValue: "\(decimalPart)",
                canIncrement: value + 0.1 <= range.upperBound,
                canDecrement: value - 0.1 >= range.lowerBound,
                stepSize: 0.1
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            beginEdit()
        }
    }

    // MARK: - Integer Mode (single column)

    private var integerStepperView: some View {
        digitColumn(
            displayValue: String(format: "%.0f", value),
            canIncrement: value + step <= range.upperBound,
            canDecrement: value - step >= range.lowerBound,
            stepSize: step
        )
        .contentShape(Rectangle())
        .onTapGesture {
            beginEdit()
        }
    }

    // MARK: - Digit Column

    private func digitColumn(
        displayValue: String,
        canIncrement: Bool,
        canDecrement: Bool,
        stepSize: Double
    ) -> some View {
        VStack(spacing: 8) {
            // Up arrow
            Image(systemName: "chevron.up")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(canIncrement ? Color.brandPrimary : Color.systemGray4)
                .frame(width: 56, height: 36)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canIncrement else { return }
                    applyStep(direction: 1, stepSize: stepSize)
                }
                .onLongPressGesture(minimumDuration: 0.3, pressing: { pressing in
                    if pressing && canIncrement {
                        startRepeating(direction: 1, stepSize: stepSize)
                    } else {
                        stopRepeating()
                    }
                }, perform: {})
                .opacity(canIncrement ? 1.0 : 0.4)

            // Value
            Text(displayValue)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            // Down arrow
            Image(systemName: "chevron.down")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(canDecrement ? Color.brandPrimary : Color.systemGray4)
                .frame(width: 56, height: 36)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canDecrement else { return }
                    applyStep(direction: -1, stepSize: stepSize)
                }
                .onLongPressGesture(minimumDuration: 0.3, pressing: { pressing in
                    if pressing && canDecrement {
                        startRepeating(direction: -1, stepSize: stepSize)
                    } else {
                        stopRepeating()
                    }
                }, perform: {})
                .opacity(canDecrement ? 1.0 : 0.4)
        }
    }

    // MARK: - Edit Mode

    private var editView: some View {
        VStack(spacing: 2) {
            TextField("", text: $editText)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .focused($isTextFieldFocused)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Hecho") {
                            commitEdit()
                        }
                    }
                }
                .onSubmit {
                    commitEdit()
                }
                .onChange(of: isTextFieldFocused) { _, focused in
                    if !focused {
                        commitEdit()
                    }
                }
        }
        .frame(minWidth: 100)
    }

    // MARK: - Tap-to-Edit

    private func beginEdit() {
        editText = String(format: format, value)
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTextFieldFocused = true
        }
    }

    private func commitEdit() {
        defer {
            isEditing = false
            isTextFieldFocused = false
        }
        let normalized = editText.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized) else { return }
        let clamped = min(max(parsed, range.lowerBound), range.upperBound)
        if hasDecimals {
            value = (clamped * 10).rounded() / 10
        } else {
            let stepsFromLower = ((clamped - range.lowerBound) / step).rounded()
            let snapped = range.lowerBound + stepsFromLower * step
            value = min(max(snapped, range.lowerBound), range.upperBound)
        }
    }

    // MARK: - Step Application

    private func applyStep(direction: Double, stepSize: Double) {
        withAnimation(.easeInOut(duration: 0.15)) {
            let raw = value + stepSize * direction
            // Round to 1 decimal place to avoid floating-point drift
            let newValue = (raw * 10).rounded() / 10
            value = min(max(newValue, range.lowerBound), range.upperBound)
        }
    }

    // MARK: - Long-Press Acceleration

    private func startRepeating(direction: Double, stepSize: Double) {
        repeatStart = Date()
        applyStep(direction: direction, stepSize: stepSize)
        scheduleRepeat(direction: direction, stepSize: stepSize)
    }

    private func scheduleRepeat(direction: Double, stepSize: Double) {
        let elapsed = Date().timeIntervalSince(repeatStart ?? Date())
        let interval: TimeInterval
        if elapsed > 2.0 {
            interval = 0.05
        } else if elapsed > 1.0 {
            interval = 0.1
        } else {
            interval = 0.3
        }

        repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            DispatchQueue.main.async {
                applyStep(direction: direction, stepSize: stepSize)
                scheduleRepeat(direction: direction, stepSize: stepSize)
            }
        }
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        repeatStart = nil
    }
}

// MARK: - SelectionCard

/// A large tappable card with icon, title, and checkmark when selected.
/// Used for single-selection choices like muscle groups, sides, etc.
struct SelectionCard: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.brandPrimary : .secondary)
                    .frame(width: 32)

                Text(title)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.brandPrimary)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding()
            .background(
                isSelected ? Color.brandPrimary.opacity(0.1) : Color.secondarySystemGroupedBackground,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - ChipRow

/// A horizontal scrollable row of selectable chips for single selection.
/// Each chip shows an optional icon and a label.
struct ChipRow: View {
    let options: [(label: String, icon: String?)]
    @Binding var selected: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.label) { option in
                    chipButton(label: option.label, icon: option.icon)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    private func chipButton(label: String, icon: String?) -> some View {
        let isSelected = selected == label

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selected = label
            }
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.brandPrimary.opacity(0.15) : Color.secondarySystemGroupedBackground,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.brandPrimary : .primary)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MultiSelectChipGrid

/// A grid of chips for multi-selection, laid out using FlowLayout.
/// Each chip shows an optional icon and a label; tapping toggles selection.
struct MultiSelectChipGrid: View {
    let options: [(label: String, icon: String?)]
    @Binding var selected: Set<String>

    var body: some View {
        StepFlowLayout(spacing: 8) {
            ForEach(options, id: \.label) { option in
                chipButton(label: option.label, icon: option.icon)
            }
        }
    }

    private func chipButton(label: String, icon: String?) -> some View {
        let isSelected = selected.contains(label)

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSelected {
                    selected.remove(label)
                } else {
                    selected.insert(label)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? Color.brandPrimary.opacity(0.15) : Color.secondarySystemGroupedBackground,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.brandPrimary : .primary)
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (local copy)

/// A simple flow layout that wraps items to the next line.
/// Local copy for use by MultiSelectChipGrid and other step-flow components.
struct StepFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.width ?? 0,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )

        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            )
            subview.place(at: point, proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxX: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                maxX = max(maxX, currentX - spacing)
            }

            size = CGSize(width: maxX, height: currentY + lineHeight)
        }
    }
}

// MARK: - Previews

#Preview("StepFlowView") {
    struct PreviewWrapper: View {
        @State private var step = 0

        var body: some View {
            StepFlowView(
                steps: [
                    StepConfig(title: "Peso corporal", subtitle: "Registra tu peso actual"),
                    StepConfig(title: "Hidratación", subtitle: "Nivel de hidratación", isOptional: true),
                    StepConfig(title: "Resumen")
                ],
                currentStep: $step,
                canProceed: true,
                lastButtonTitle: "Comenzar"
            ) {
                // complete
            } content: { stepIndex in
                switch stepIndex {
                case 0:
                    Text("Contenido del paso 1")
                case 1:
                    Text("Contenido del paso 2")
                default:
                    Text("Contenido del paso 3")
                }
            }
        }
    }

    return PreviewWrapper()
}

#Preview("VisualStepper") {
    struct PreviewWrapper: View {
        @State private var weight: Double = 75.0

        var body: some View {
            VisualStepper(
                value: $weight,
                range: 30...200,
                step: 0.5,
                unit: "kg",
                format: "%.1f"
            )
            .padding()
        }
    }

    return PreviewWrapper()
}

#Preview("SelectionCard") {
    VStack(spacing: 12) {
        SelectionCard(
            title: "Cuadriceps",
            icon: "figure.strengthtraining.traditional",
            isSelected: true
        ) {}

        SelectionCard(
            title: "Biceps",
            icon: "figure.arms.open",
            isSelected: false
        ) {}
    }
    .padding()
}

#Preview("ChipRow") {
    struct PreviewWrapper: View {
        @State private var selected = "Leve"

        var body: some View {
            ChipRow(
                options: [
                    (label: "Ninguna", icon: nil),
                    (label: "Leve", icon: "drop"),
                    (label: "Moderada", icon: "drop.fill"),
                    (label: "Intensa", icon: "flame")
                ],
                selected: $selected
            )
            .padding()
        }
    }

    return PreviewWrapper()
}

#Preview("MultiSelectChipGrid") {
    struct PreviewWrapper: View {
        @State private var selected: Set<String> = ["Pecho"]

        var body: some View {
            MultiSelectChipGrid(
                options: [
                    (label: "Pecho", icon: nil),
                    (label: "Espalda", icon: nil),
                    (label: "Hombros", icon: nil),
                    (label: "Brazos", icon: nil),
                    (label: "Piernas", icon: nil),
                    (label: "Core", icon: nil)
                ],
                selected: $selected
            )
            .padding()
        }
    }

    return PreviewWrapper()
}
