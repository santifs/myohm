import SwiftUI
import SwiftData
import Charts

// MARK: - Whole-body placement

struct PlacementView: View {
    let person: Athlete?
    var onStart: (MeasurementKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var supine = false
    @State private var noMetal = false
    @State private var fasted = false
    @State private var restStart = Date()
    @State private var now = Date()

    private static let restSeconds: TimeInterval = 5 * 60
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var remaining: TimeInterval { max(0, Self.restSeconds - now.timeIntervalSince(restStart)) }
    private var weightValue: Double? { Double(weight.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(kicker: person.map { L("\($0.fullName) · whole body") }, title: L("Attach the cables"), back: { dismiss() })

                VStack(alignment: .leading, spacing: 12) {
                    ElectrodeDiagram()
                        .aspectRatio(1536.0 / 1100.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MyohmColor.hairline))
                    HStack(alignment: .top, spacing: 10) {
                        legend(color: MyohmColor.brand, title: L("Current (I)"), text: L("Back of the hand and base of the toes"))
                        legend(color: MyohmColor.accent, title: L("Sensing (V)"), text: L("Wrist and ankle, between the bones"))
                    }
                    Text(L("Leave at least 5 cm between the electrodes of each pair."))
                        .font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                }
                .myohmCard()

                VStack(alignment: .leading, spacing: 0) {
                    Text(L("Before measuring")).font(MyohmFont.headline).padding(.top, 6).padding(.bottom, 2)
                    toggleRow(L("Lying on the back, arms and legs apart"), $supine)
                    Divider().overlay(MyohmColor.hairline)
                    CheckRow(text: L("5 minutes of rest"), done: remaining == 0, trailing: remaining > 0 ? Self.clock(remaining) : nil)
                    Divider().overlay(MyohmColor.hairline)
                    toggleRow(L("No metal objects, not touching a metal frame"), $noMetal)
                    Divider().overlay(MyohmColor.hairline)
                    toggleRow(L("No hard exercise or large meal in the last hours, empty bladder"), $fasted)
                }
                .myohmCard(padding: 16)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Today's weight")).font(MyohmFont.headline)
                        if let last = person?.effectiveWeightKg {
                            Text(L("Last time: \(MyohmFormat.kg(last))")).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                        }
                    }
                    Spacer()
                    TextField("0", text: $weight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 12)
                        .frame(width: 96, height: 48)
                        .background(MyohmColor.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MyohmColor.line))
                    Text("kg").foregroundStyle(MyohmColor.muted)
                }
                .myohmCard()

                VStack(spacing: 10) {
                    Button(L("Start measurement")) {
                        guard let w = weightValue else { return }
                        onStart(.wholeBody(weightKg: w, restCompleted: remaining == 0))
                    }
                    .buttonStyle(MyohmPrimaryButton())
                    .disabled(weightValue == nil)
                    .opacity(weightValue == nil ? 0.5 : 1)
                    Text(L("You can start earlier; the measurement will be marked as incomplete rest."))
                        .font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MyohmColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(timer) { now = $0 }
        .onAppear {
            if weight.isEmpty, let w = person?.effectiveWeightKg { weight = MyohmFormat.number(w) }
        }
    }

    private func toggleRow(_ text: String, _ value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            CheckRow(text: text, done: value.wrappedValue)
        }
        .buttonStyle(.plain)
    }

    private func legend(color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(color).frame(width: 12, height: 12).padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(text).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Right hand and right foot with the four electrode positions.
struct ElectrodeDiagram: View {
    private let canvas = CGSize(width: 1536, height: 1100)
    private let electrodes: [(CGPoint, Bool)] = [
        (CGPoint(x: 432, y: 405), true), (CGPoint(x: 432, y: 790), false),
        (CGPoint(x: 1102, y: 330), true), (CGPoint(x: 1102, y: 740), false)
    ]

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / canvas.width
            ZStack(alignment: .topLeading) {
                Color.white
                Image("limbs", bundle: .module)
                    .resizable()
                    .frame(width: 1536 * s, height: 1024 * s)
                Path { p in
                    p.move(to: CGPoint(x: 432 * s, y: 455 * s)); p.addLine(to: CGPoint(x: 432 * s, y: 745 * s))
                    p.move(to: CGPoint(x: 1102 * s, y: 375 * s)); p.addLine(to: CGPoint(x: 1102 * s, y: 695 * s))
                }
                .stroke(MyohmColor.muted, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [1, 4]))
                Text("≥ 5 cm").font(.system(size: 10, weight: .semibold)).foregroundStyle(MyohmColor.muted)
                    .position(x: 520 * s, y: 600 * s)
                Text("≥ 5 cm").font(.system(size: 10, weight: .semibold)).foregroundStyle(MyohmColor.muted)
                    .position(x: 1190 * s, y: 535 * s)
                ForEach(Array(electrodes.enumerated()), id: \.offset) { _, e in
                    ZStack {
                        Circle().fill((e.1 ? MyohmColor.brand : MyohmColor.accent).opacity(0.18)).frame(width: 116 * s, height: 116 * s)
                        Circle().fill(e.1 ? MyohmColor.brand : MyohmColor.accent).frame(width: 80 * s, height: 80 * s)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                        Text(e.1 ? "I" : "V").font(.system(size: 46 * s, weight: .bold)).foregroundStyle(.white)
                    }
                    .position(x: e.0.x * s, y: e.0.y * s)
                }
                Text(L("Right hand")).font(.system(size: 11, weight: .bold)).foregroundStyle(MyohmColor.ink)
                    .position(x: 432 * s, y: 1066 * s)
                Text(L("Right foot")).font(.system(size: 11, weight: .bold)).foregroundStyle(MyohmColor.ink)
                    .position(x: 1102 * s, y: 1066 * s)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L("Right hand and foot seen from above: current electrodes on the back of the hand and the base of the toes; sensing electrodes on the wrist and the ankle."))
    }
}

// MARK: - Measuring

struct MyohmMeasuringView: View {
    let kind: MeasurementKind
    let person: Athlete?
    var autoStart = true
    var onFinished: (UUID) -> Void
    @Environment(BioMessBLEManager.self) private var ble
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var task: Task<Void, Never>?
    @State private var errorText: String?
    @State private var started = false

    static let sweep = (points: UInt32(48), start: Float(4_000), stop: Float(198_000), repetitions: UInt8(3))

    private var ready: Bool { (ble.connectionState == .connected || ble.connectionState == .measuring) && ble.isDeviceReady }

    var body: some View {
        VStack(spacing: 20) {
            ScreenHeader(kicker: subtitle, title: L("Measuring"), back: cancel, backIcon: "xmark")

            Spacer(minLength: 0)

            ZStack {
                Circle().stroke(MyohmColor.brandSoft, lineWidth: 14)
                if waitingForData {
                    TimelineView(.animation) { context in
                        Circle()
                            .trim(from: 0, to: 0.18)
                            .stroke(MyohmColor.brand, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4 * 360))
                    }
                } else {
                    Circle()
                        .trim(from: 0, to: ble.liveSweepProgress)
                        .stroke(MyohmColor.brand, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: ble.liveSweepProgress)
                }
                VStack(spacing: 4) {
                    Text("\(Int((ble.liveSweepProgress * 100).rounded())) %")
                        .font(MyohmFont.display(44))
                        .foregroundStyle(MyohmColor.ink)
                        .contentTransition(.numericText())
                    Text(statusText).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                }
            }
            .frame(width: 220, height: 220)

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Phase angle · live")).font(MyohmFont.micro).foregroundStyle(MyohmColor.muted)
                if ble.liveSweepPoints.isEmpty {
                    Text(L("The curve will appear as frequencies arrive."))
                        .font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                Chart(ble.liveSweepPoints) { point in
                    LineMark(x: .value("Hz", Double(point.frequency)), y: .value("°", abs(Double(point.phase))))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(MyohmColor.brand)
                }
                .chartXScale(domain: 4_000...200_000, type: .log)
                .chartXAxis {
                    AxisMarks(values: [5_000, 10_000, 20_000, 50_000, 100_000, 200_000]) { value in
                        AxisGridLine().foregroundStyle(MyohmColor.hairline)
                        AxisValueLabel { Text(MyohmFormat.frequency(value.as(Double.self) ?? 0)) }
                    }
                }
                .frame(height: 140)
                }
            }
            .myohmCard()

            if let errorText {
                VStack(spacing: 12) {
                    Text(errorText).font(MyohmFont.body).foregroundStyle(MyohmColor.accent).multilineTextAlignment(.center)
                    Button(L("Try again")) { start(force: true) }.buttonStyle(MyohmPrimaryButton())
                }
            } else if !ready {
                VStack(spacing: 12) {
                    Text(L("Waiting for the device…")).font(MyohmFont.body).foregroundStyle(MyohmColor.muted)
                    Button(L("Reconnect")) { ble.retryAutoConnect() }.buttonStyle(MyohmSecondaryButton())
                }
            } else {
                Text(L("Stay still and relaxed until it finishes."))
                    .font(MyohmFont.body).foregroundStyle(MyohmColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(MyohmColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { start(force: false) }
        .onChange(of: ready) { if ready { start(force: false) } }
        .onDisappear { task?.cancel() }
    }

    private var subtitle: String {
        switch kind {
        case .muscle(let muscle, let side, let band):
            return L("\(muscle.name) \(side.name.lowercased()) · band \(String(band)) mm")
        case .wholeBody:
            return L("Whole body · right side")
        }
    }

    private var statusText: String {
        if errorText != nil { return L("Stopped") }
        if ble.connectionState == .measuring {
            return ble.liveSweepProgress > 0 ? L("Sweep 4–198 kHz") : L("Starting the sweep…")
        }
        if started && ble.liveSweepProgress >= 1 { return L("Saving…") }
        return ready ? L("Preparing…") : L("Not connected")
    }

    private var waitingForData: Bool { ble.liveSweepProgress == 0 && errorText == nil }

    private func cancel() {
        task?.cancel()
        if ble.connectionState == .measuring {
            // Aborting a sweep closes the link; reconnect to the paired device straight away.
            ble.cancelStreamingMeasurement()
            ble.retryAutoConnect()
        }
        dismiss()
    }

    private func start(force: Bool) {
        guard ready, force || (autoStart && !started) else { return }
        started = true
        errorText = nil
        task = Task {
            do {
                let data = try await ble.performMeasurement(
                    numPoints: Self.sweep.points,
                    startFreq: Self.sweep.start,
                    stopFreq: Self.sweep.stop,
                    repetitions: Self.sweep.repetitions
                )
                let id = try save(data)
                onFinished(id)
            } catch is CancellationError {
                return
            } catch {
                errorText = L("The measurement failed: \(error.localizedDescription)")
            }
        }
    }

    private func save(_ data: ImpedanceData) throws -> UUID {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let json = try encoder.encode(data)
        let measurement: Measurement
        switch kind {
        case .muscle(let muscle, let side, let band):
            measurement = Measurement(muscleGroup: muscle.rawValue, side: side.rawValue, perceivedFatigue: 0, rawDataJSON: json)
            measurement.bandMillimeters = band
        case .wholeBody(let weight, let rest):
            measurement = Measurement(muscleGroup: MyohmMuscle.wholeBodyKey, side: LimbSide.right.rawValue, perceivedFatigue: 0, rawDataJSON: json)
            measurement.bodyWeightKg = weight
            measurement.restCompleted = rest
            person?.weightKg = weight
        }
        measurement.personID = person?.id
        context.insert(measurement)
        try context.save()
        return measurement.id
    }
}
