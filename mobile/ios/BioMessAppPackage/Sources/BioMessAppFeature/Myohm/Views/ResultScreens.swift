import SwiftUI
import SwiftData
import Charts

/// Loads a saved measurement and shows the matching result screen.
struct ResultScreen: View {
    let measurementID: UUID
    @Binding var path: [MeasureRoute]
    @Query private var matches: [Measurement]
    @Query(sort: \Athlete.createdAt) private var people: [Athlete]

    init(measurementID: UUID, path: Binding<[MeasureRoute]>) {
        self.measurementID = measurementID
        self._path = path
        _matches = Query(filter: #Predicate<Measurement> { $0.id == measurementID })
    }

    var body: some View {
        Group {
            if let measurement = matches.first {
                let person = people.first { $0.id == measurement.personID }
                if measurement.isWholeBody {
                    BodyResultView(measurement: measurement, person: person, path: $path)
                } else {
                    LocalResultView(measurement: measurement, person: person, path: $path)
                }
            } else {
                ContentUnavailableView(L("Measurement not found"), systemImage: "questionmark.circle")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(MyohmColor.background.ignoresSafeArea())
    }
}

/// Cole fit of a measurement, computed once per screen.
@MainActor
final class ColeFitLoader: ObservableObject {
    @Published var parameters: ColeFit?
    @Published var failed = false
    private var started = false

    func load(_ sweep: SweepAnalysis?) {
        guard !started, let sweep else { return }
        started = true
        if let fit = ColeFit.fit(sweep) { parameters = fit } else { failed = true }
    }
}

@MainActor
private func resultHeader(_ measurement: Measurement, close: @escaping @MainActor () -> Void) -> some View {
    var kicker = measurement.measuredAt.formatted(date: .abbreviated, time: .shortened)
    if let band = measurement.bandMillimeters { kicker += " · " + L("band \(String(band)) mm") }
    if let w = measurement.bodyWeightKg { kicker += " · " + MyohmFormat.kg(w) }
    return ScreenHeader(kicker: kicker, title: measurement.myohmTitle, back: close, backIcon: "xmark")
}

// MARK: - Local result

enum SpectrumChartKind: Hashable { case phase, modulus, nyquist }

struct LocalResultView: View {
    let measurement: Measurement
    let person: Athlete?
    @Binding var path: [MeasureRoute]
    @Query(sort: \Measurement.measuredAt, order: .reverse) private var all: [Measurement]
    @StateObject private var fit = ColeFitLoader()
    @State var chart: SpectrumChartKind = .phase
    @State var selectedFrequency: Double?
    @State private var compare = true

    private var sweep: SweepAnalysis? { measurement.impedanceData.flatMap(SweepAnalysis.init) }

    private var previous: Measurement? {
        all.first {
            $0.id != measurement.id && $0.measuredAt < measurement.measuredAt && $0.personID == measurement.personID
                && $0.muscleGroup == measurement.muscleGroup && $0.side == measurement.side
                && $0.bandMillimeters == measurement.bandMillimeters
        }
    }
    private var previousSweep: SweepAnalysis? { previous?.impedanceData.flatMap(SweepAnalysis.init) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                resultHeader(measurement) { path.removeAll() }
                if let sweep, let ref = sweep.atReference {
                    if !sweep.looksLikeTissue { ContactWarning() }
                    hero(ref)
                    spectrumCard(sweep)
                    coleCard
                    actions(sweep)
                } else {
                    ContentUnavailableView(L("No data in this measurement"), systemImage: "waveform.slash")
                }
            }
            .padding(20)
        }
        .background(MyohmColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { fit.load(sweep) }
    }

    private func hero(_ ref: SweepPoint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Phase angle at 50 kHz")).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(MyohmFormat.degrees(ref.phaseAngle)).font(MyohmFont.display(60)).tracking(-1.5)
                if let prev = previousSweep?.atReference {
                    let delta = ref.phaseAngle - prev.phaseAngle
                    Text((delta >= 0 ? "+" : "−") + MyohmFormat.degrees(abs(delta)))
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                }
            }
            HStack(spacing: 16) {
                stat(L("Resistance"), MyohmFormat.ohms(ref.resistance))
                stat(L("Reactance"), MyohmFormat.ohms(ref.reactance))
                stat(L("Modulus"), MyohmFormat.ohms(ref.magnitude))
            }
            if let prev = previous {
                Text(L("Compared with \(prev.measuredAt.formatted(date: .abbreviated, time: .omitted)), same muscle, side and band."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroBackground())
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).opacity(0.75)
            Text(value).font(.system(size: 16, weight: .bold))
        }
    }

    private func spectrumCard(_ sweep: SweepAnalysis) -> some View {
        let selected = selectedFrequency.flatMap { sweep.interpolated(at: $0) }
        let prevPoints = compare ? (previousSweep?.points ?? []) : []
        return VStack(alignment: .leading, spacing: 12) {
            PillSegmented(options: [(SpectrumChartKind.phase, L("Phase")), (.modulus, L("Modulus")), (.nyquist, "Nyquist")], selection: $chart)

            HStack(alignment: .firstTextBaseline) {
                if let selected {
                    Text(MyohmFormat.frequency(selected.frequencyHz)).font(.system(size: 13, weight: .semibold)).foregroundStyle(MyohmColor.muted)
                    Spacer()
                    Text(readout(selected)).font(.system(size: 15, weight: .bold)).foregroundStyle(MyohmColor.ink)
                } else {
                    Text(L("Touch the chart to read any frequency")).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                    Spacer()
                }
            }
            .frame(height: 20)

            Group {
                switch chart {
                case .phase, .modulus:
                    spectrumChart(sweep.points, prevPoints, selected: selected)
                case .nyquist:
                    nyquistChart(sweep.points, prevPoints, selected: selected)
                }
            }
            .frame(height: 220)

            if previous != nil {
                Toggle(isOn: $compare) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(MyohmColor.accentSoft).frame(width: 18, height: 4)
                        Text(L("Show previous measurement")).font(MyohmFont.caption)
                    }
                }
                .tint(MyohmColor.brand)
            }
        }
        .myohmCard()
    }

    private func readout(_ p: SweepPoint) -> String {
        switch chart {
        case .phase: return MyohmFormat.degrees(p.phaseAngle)
        case .modulus: return MyohmFormat.ohms(p.magnitude)
        case .nyquist: return "R " + MyohmFormat.ohms(p.resistance) + " · Xc " + MyohmFormat.ohms(p.reactance)
        }
    }

    private func yValue(_ p: SweepPoint) -> Double { chart == .phase ? p.phaseAngle : p.magnitude }

    private func spectrumChart(_ points: [SweepPoint], _ prev: [SweepPoint], selected: SweepPoint?) -> some View {
        Chart {
            ForEach(prev) { p in
                LineMark(x: .value("Hz", p.frequencyHz), y: .value("v", yValue(p)), series: .value("s", "prev"))
                    .foregroundStyle(MyohmColor.accentSoft)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { p in
                AreaMark(x: .value("Hz", p.frequencyHz), yStart: .value("v", yMin(points + prev)), yEnd: .value("v", yValue(p)))
                    .foregroundStyle(LinearGradient(colors: [MyohmColor.brand.opacity(0.18), MyohmColor.brand.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Hz", p.frequencyHz), y: .value("v", yValue(p)), series: .value("s", "now"))
                    .foregroundStyle(MyohmColor.brand)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.monotone)
            }
            if let selected {
                RuleMark(x: .value("Hz", selected.frequencyHz)).foregroundStyle(MyohmColor.muted.opacity(0.4))
                PointMark(x: .value("Hz", selected.frequencyHz), y: .value("v", yValue(selected)))
                    .foregroundStyle(MyohmColor.brand).symbolSize(90)
            }
        }
        .chartXScale(domain: 4_000...200_000, type: .log)
        .chartYScale(domain: yMin(points + prev)...yMax(points + prev))
        .chartXAxis {
            AxisMarks(values: [5_000, 10_000, 20_000, 50_000, 100_000, 200_000]) { value in
                AxisGridLine().foregroundStyle(MyohmColor.hairline)
                AxisValueLabel { Text(MyohmFormat.frequency(value.as(Double.self) ?? 0)) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(MyohmColor.hairline)
                AxisValueLabel { Text(chart == .phase ? "\(value.as(Double.self).map { MyohmFormat.number($0, digits: 0) } ?? "")°" : (value.as(Double.self).map { MyohmFormat.number($0, digits: 0) } ?? "")) }
            }
        }
        .chartXSelection(value: $selectedFrequency)
    }

    private func nyquistChart(_ points: [SweepPoint], _ prev: [SweepPoint], selected: SweepPoint?) -> some View {
        Chart {
            ForEach(prev) { p in
                PointMark(x: .value("R", p.resistance), y: .value("Xc", p.reactance))
                    .foregroundStyle(MyohmColor.accentSoft).symbolSize(16)
            }
            ForEach(points) { p in
                PointMark(x: .value("R", p.resistance), y: .value("Xc", p.reactance))
                    .foregroundStyle(MyohmColor.brand).symbolSize(26)
            }
            if let selected {
                PointMark(x: .value("R", selected.resistance), y: .value("Xc", selected.reactance))
                    .foregroundStyle(MyohmColor.accent).symbolSize(110)
            }
        }
        .chartXAxisLabel("R (Ω)")
        .chartYAxisLabel("Xc (Ω)")
        .chartXScale(domain: .automatic(includesZero: false))
        .chartYScale(domain: .automatic(includesZero: true))
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { value in
                guard let r: Double = proxy.value(atX: value.location.x) else { return }
                selectedFrequency = points.min { abs($0.resistance - r) < abs($1.resistance - r) }?.frequencyHz
            }
        }
    }

    private func yMin(_ points: [SweepPoint]) -> Double {
        let v = points.map(yValue).min() ?? 0
        return chart == .phase ? max(0, (v - 1).rounded(.down)) : v * 0.95
    }

    private func yMax(_ points: [SweepPoint]) -> Double {
        let v = points.map(yValue).max() ?? 1
        return chart == .phase ? (v + 1).rounded(.up) : v * 1.05
    }

    private var coleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("Cole model")).font(MyohmFont.headline)
                Spacer()
                if fit.parameters == nil && !fit.failed { ProgressView().controlSize(.small) }
            }
            if let p = fit.parameters {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    tile("R₀", MyohmFormat.ohms(p.r0), L("extracellular"))
                    tile("R∞", MyohmFormat.ohms(p.rInf), L("total"))
                    tile("fc", MyohmFormat.number(p.fc / 1000) + " kHz", L("characteristic frequency"))
                    tile("α", MyohmFormat.number(p.alpha, digits: 2), L("dispersion"))
                }
            } else if fit.failed {
                Text(L("The Cole model could not be fitted to this sweep.")).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
            }
        }
        .myohmCard()
    }

    private func tile(_ symbol: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(MyohmColor.muted)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(MyohmColor.ink)
            Text(caption).font(.system(size: 11)).foregroundStyle(MyohmColor.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyohmColor.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actions(_ sweep: SweepAnalysis) -> some View {
        HStack(spacing: 10) {
            ShareLink(item: CSVExport.file(for: measurement, sweep: sweep)) {
                Label(L("Export CSV"), systemImage: "square.and.arrow.up")
                    .foregroundStyle(MyohmColor.ink)
            }
            .buttonStyle(MyohmSecondaryButton())
            Button(L("Repeat")) {
                if let muscle = measurement.muscle, let side = measurement.bodySide {
                    path.removeAll()
                    path.append(.measuring(.muscle(muscle, side, band: measurement.bandMillimeters ?? 100)))
                }
            }
            .buttonStyle(MyohmPrimaryButton())
        }
    }
}

struct ContactWarning: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MyohmColor.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("The signal does not look like tissue")).font(.system(size: 15, weight: .bold)).foregroundStyle(MyohmColor.accentInk)
                Text(L("Check that every electrode touches the skin and the cables are connected, then repeat. These values are not reliable."))
                    .font(MyohmFont.caption).foregroundStyle(MyohmColor.accentInk.opacity(0.85))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyohmColor.accentBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct HeroBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(RadialGradient(colors: [MyohmColor.brandMid, MyohmColor.brand, MyohmColor.brandDeep], center: .topLeading, startRadius: 10, endRadius: 460))
            .shadow(color: MyohmColor.brand.opacity(0.25), radius: 15, y: 10)
    }
}

enum CSVExport {
    static func file(for measurement: Measurement, sweep: SweepAnalysis) -> URL {
        var lines = ["frequency_hz,modulus_ohm,phase_deg,resistance_ohm,reactance_ohm"]
        for p in sweep.points {
            lines.append(String(format: "%.1f,%.4f,%.4f,%.4f,%.4f", p.frequencyHz, p.magnitude, -p.phaseAngle, p.resistance, p.reactance))
        }
        let stamp = measurement.measuredAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("myohm-\(measurement.muscleGroup)-\(stamp).csv")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Whole-body result

struct BodyResultView: View {
    let measurement: Measurement
    let person: Athlete?
    @Binding var path: [MeasureRoute]
    @StateObject private var fit = ColeFitLoader()
    @State private var editingProfile = false
    /// Equation picked by the user to compare; nil uses the automatic choice.
    @State private var chosenEquation: BodyEquation?
    @State var tab = 0

    private var sweep: SweepAnalysis? { measurement.impedanceData.flatMap(SweepAnalysis.init) }
    private var reference: SweepPoint? { sweep?.atReference }
    private var inputs: BodyInputs? {
        guard let person, let reference,
              var i = MeasurementValue.bodyInputs(measurement: measurement, person: person, reference: reference) else { return nil }
        i.r0 = fit.parameters?.r0
        i.rInf = fit.parameters?.rInf
        return i
    }
    private var selection: EquationSelection? { inputs.map(BodyComposition.select) }
    private var automaticEquation: BodyEquation? { selection?.equation }
    private var activeEquation: BodyEquation? { chosenEquation ?? automaticEquation }
    private var signalOK: Bool { inputs.map { WholeBodySignal.isPlausible(r50: $0.r50, xc50: $0.xc50) } ?? false }
    private var estimate: FatEstimate? {
        guard let inputs, let eq = activeEquation else { return nil }
        return BodyComposition.checkedEstimate(inputs, using: eq)
    }
    private var water: BodyWater? {
        guard let p = fit.parameters, let inputs, signalOK else { return nil }
        return BodyWater.estimate(heightCm: inputs.heightCm, weightKg: inputs.weightKg, r0: p.r0, rInf: p.rInf)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    resultHeader(measurement) { path.removeAll() }
                    if measurement.restCompleted == false {
                        Text(L("Short rest"))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(MyohmColor.accentInk)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(MyohmColor.accentBg, in: Capsule())
                    }
                }

                if let sweep, !sweep.looksLikeTissue { ContactWarning() }
                if inputs == nil {
                    missingData
                } else {
                    PillSegmented(options: [(0, activeEquation?.usesSpectrum == true ? L("Fat · spectrum") : L("Fat · 50 kHz")), (1, L("Water · spectrum"))], selection: $tab)
                    if tab == 0 { fatCard } else { waterCard }
                    equationCard
                }

                if let reference {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Phase angle at 50 kHz")).font(MyohmFont.micro).foregroundStyle(MyohmColor.muted)
                            Text(MyohmFormat.degrees(reference.phaseAngle)).font(.system(size: 28, weight: .heavy)).foregroundStyle(MyohmColor.ink)
                            Text("R " + MyohmFormat.ohms(reference.resistance) + " · Xc " + MyohmFormat.ohms(reference.reactance))
                                .font(.system(size: 12)).foregroundStyle(MyohmColor.muted)
                        }
                        Spacer()
                        if let sweep {
                            ShareLink(item: CSVExport.file(for: measurement, sweep: sweep)) {
                                Label(L("Export"), systemImage: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MyohmColor.brand)
                                    .padding(.horizontal, 14).frame(minHeight: 40)
                                    .background(MyohmColor.brandSoft, in: Capsule())
                            }
                        }
                    }
                    .myohmCard()
                }

                Text(L("Estimate for monitoring, education or research. Not a diagnosis."))
                    .font(.system(size: 12)).foregroundStyle(MyohmColor.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(MyohmColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            fit.load(sweep)
            if case .highBMI = selection { tab = 1 }
        }
    }

    private var missingData: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Missing data")).font(MyohmFont.headline)
            let missing = MeasurementValue.missingFields(person: person, measurement: measurement)
            Text(L("Body composition needs height, weight and biological sex. Missing: \(missing.joined(separator: ", "))."))
                .font(MyohmFont.body).foregroundStyle(MyohmColor.muted)
            if let person {
                Button(L("Complete profile")) { editingProfile = true }
                    .buttonStyle(MyohmSecondaryButton())
                    .padding(.top, 4)
                    .sheet(isPresented: $editingProfile) {
                        NavigationStack { PersonFormView(person: person) { _ in editingProfile = false } }
                    }
            }
        }
        .myohmCard()
    }

    @ViewBuilder
    private var fatCard: some View {
        if !signalOK {
            notice(L("Not calculated"), L("This reading is outside the range of living tissue, so Myohm does not estimate body composition from it. Repeat the measurement."))
        } else if chosenEquation == nil, selection == .tooYoung {
            notice(L("No validated equation under 10 years"), L("Myohm shows only the phase angle for children under 10."))
        } else if chosenEquation == nil, selection == .highBMI {
            notice(L("BMI above 34"), L("Prediction equations are not valid with this BMI. Use the water view, calculated from the spectrum."))
        } else if activeEquation?.usesSpectrum == true, inputs?.r0 == nil {
            if fit.failed {
                notice(L("Water not available"), L("The Cole model could not be fitted to this sweep."))
            } else {
                HStack { ProgressView(); Text(L("Fitting the spectrum…")).foregroundStyle(MyohmColor.muted) }.myohmCard()
            }
        } else if let estimate {
            fatHero(estimate)
        } else {
            notice(L("Result out of range"), L("This equation gives an implausible value for this person. Try another equation or repeat the measurement."))
        }
    }

    private func notice(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(MyohmFont.headline)
            Text(text).font(MyohmFont.body).foregroundStyle(MyohmColor.muted)
        }
        .myohmCard()
    }

    private func fatHero(_ e: FatEstimate) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Estimated body fat · \(MyohmFormat.kg(inputs?.weightKg ?? 0))")).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 18) {
                Donut(
                    segments: [(e.fatMassKg, MyohmColor.accentSoft), (e.fatFreeMassKg, MyohmColor.leanOnDark)],
                    center: MyohmFormat.percent(e.fatPercent),
                    caption: e.fatPercentError.map { L("± \(MyohmFormat.number($0)) points") } ?? L("body fat")
                )
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 0) {
                    legendRow(MyohmColor.accentSoft, L("Fat mass"), MyohmFormat.kg(e.fatMassKg), e.tissues == nil ? L("weight − fat-free mass") : L("75 % of adipose tissue"))
                    legendRow(MyohmColor.leanOnDark, L("Fat-free mass"), MyohmFormat.kg(e.fatFreeMassKg), e.equation.standardErrorKg.map { "± " + MyohmFormat.kg($0) } ?? "")
                }
            }
            if let t = e.tissues {
                HStack(spacing: 8) {
                    darkTile(L("Lean tissue"), MyohmFormat.kg(t.leanTissueKg))
                    darkTile(L("Adipose tissue"), MyohmFormat.kg(t.adiposeTissueKg))
                    darkTile(L("Excess fluid"), MyohmFormat.kg(t.excessFluidKg))
                }
                Text(t.excessFluidIsUnusual
                     ? L("Unusual excess fluid. In a healthy person this usually means a poor spectrum; repeat the measurement before trusting the fat value.")
                     : L("From R₀ and R∞ of the whole spectrum. Typical error not yet verified by Myohm."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            }
            if let err = e.fatPercentError {
                ErrorBand(value: e.fatPercent, error: err)
                Text(L("The light band is the typical error of the equation. Compare measurements taken in the same conditions."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HeroBackground())
    }

    @ViewBuilder
    private var waterCard: some View {
        if let w = water {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Body water · Cole fit")).font(.system(size: 14)).foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 18) {
                    Donut(
                        segments: [(w.extracellularL, MyohmColor.waterOnDark), (w.intracellularL, MyohmColor.leanOnDark)],
                        center: MyohmFormat.litres(w.totalL),
                        caption: L("total water")
                    )
                    .frame(width: 150, height: 150)
                    VStack(alignment: .leading, spacing: 0) {
                        legendRow(MyohmColor.waterOnDark, L("Extracellular"), MyohmFormat.litres(w.extracellularL), L("outside the cells"))
                        legendRow(MyohmColor.leanOnDark, L("Intracellular"), MyohmFormat.litres(w.intracellularL), L("inside the cells"))
                    }
                }
                HStack(spacing: 8) {
                    darkTile(L("Extra / total"), MyohmFormat.number(w.extracellularRatio, digits: 2))
                    darkTile(L("Fat-free mass (from water)"), "≈ " + MyohmFormat.kg(w.fatFreeMassKg))
                }
                Text(L("Uses R₀ and R∞ from the whole spectrum instead of a single frequency."))
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HeroBackground())
        } else if fit.failed {
            notice(L("Water not available"), L("The Cole model could not be fitted to this sweep."))
        } else {
            HStack { ProgressView(); Text(L("Fitting the spectrum…")).foregroundStyle(MyohmColor.muted) }.myohmCard()
        }
    }

    private func darkTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).opacity(0.75)
            Text(value).font(.system(size: 20, weight: .heavy))
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func legendRow(_ color: Color, _ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(label).font(.system(size: 12)).opacity(0.78)
            }
            Text(value).font(.system(size: 22, weight: .heavy))
            if !note.isEmpty { Text(note).font(.system(size: 11)).opacity(0.6) }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
    }

    @ViewBuilder
    private var equationCard: some View {
        if tab == 0, let eq = activeEquation, let inputs {
            Button { path.append(.equation(measurement.id, chosenEquation)) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "function")
                            .foregroundStyle(MyohmColor.brand)
                            .frame(width: 36, height: 36)
                            .background(MyohmColor.brandSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(chosenEquation == nil ? L("Equation chosen automatically") : L("Equation chosen by you"))
                                .font(MyohmFont.micro).foregroundStyle(MyohmColor.muted)
                            Text("\(eq.shortName) · \(String(eq.year))").font(.system(size: 16, weight: .bold)).foregroundStyle(MyohmColor.ink)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(MyohmColor.muted)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(EquationChecks.checks(eq, inputs)) { check in
                            Text(check.short)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(check.ok ? MyohmColor.success : MyohmColor.accentInk)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(check.ok ? MyohmColor.successBg : MyohmColor.accentBg, in: Capsule())
                        }
                    }
                }
                .myohmCard()
            }
            .buttonStyle(MyohmPlainButton())
            equationPicker
        } else if tab == 0, inputs != nil {
            equationPicker
        } else if tab == 1 {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Spectroscopy model")).font(MyohmFont.micro).foregroundStyle(MyohmColor.muted)
                Text("Moissl et al. · 2006").font(.system(size: 16, weight: .bold))
                Text(L("Extra and intracellular water from R₀ and R∞, validated against isotope dilution."))
                    .font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
            }
            .myohmCard()
        }
    }
}

extension BodyResultView {
    /// Lets the user compare equations; the automatic one stays marked.
    var equationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Compare with another equation")).font(MyohmFont.micro).foregroundStyle(MyohmColor.muted)
            FlowLayout(spacing: 6) {
                ForEach(BodyEquation.allCases, id: \.self) { eq in
                    let isActive = eq == activeEquation
                    let isAuto = eq == automaticEquation
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { chosenEquation = isAuto ? nil : eq }
                    } label: {
                        Text(isAuto ? L("\(eq.shortName) · automatic") : eq.shortName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isActive ? .white : MyohmColor.ink)
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .background(isActive ? MyohmColor.brand : .white, in: Capsule())
                            .overlay(Capsule().stroke(MyohmColor.hairline, lineWidth: isActive ? 0 : 1))
                    }
                    .buttonStyle(MyohmPlainButton())
                }
            }
            if let eq = chosenEquation, let inputs, EquationChecks.checks(eq, inputs).contains(where: { !$0.ok }) {
                Text(L("This equation was not validated for this person. Use it only to compare."))
                    .font(.system(size: 12)).foregroundStyle(MyohmColor.accentInk)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct Donut: View {
    let segments: [(Double, Color)]
    let center: String
    let caption: String

    var body: some View {
        ZStack {
            Chart(Array(segments.enumerated()), id: \.offset) { _, segment in
                SectorMark(angle: .value("v", segment.0), innerRadius: .ratio(0.78), angularInset: 1.5)
                    .foregroundStyle(segment.1)
                    .cornerRadius(3)
            }
            .chartLegend(.hidden)
            VStack(spacing: 2) {
                Text(center).font(.system(size: 26, weight: .heavy)).minimumScaleFactor(0.6).lineLimit(1)
                Text(caption).font(.system(size: 11, weight: .semibold)).opacity(0.75)
            }
            .padding(.horizontal, 24)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ErrorBand: View {
    let value: Double
    let error: Double
    var range: ClosedRange<Double> = 10...45

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let x = { (v: Double) in w * (min(max(v, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound) }
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [MyohmColor.leanOnDark.opacity(0.25), MyohmColor.accentSoft.opacity(0.35)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8).offset(y: -9)
                Capsule().fill(.white.opacity(0.28))
                    .frame(width: max(8, x(value + error) - x(value - error)), height: 16)
                    .offset(x: x(value - error), y: -9)
                Circle().fill(.white).overlay(Circle().stroke(MyohmColor.accentSoft, lineWidth: 3))
                    .frame(width: 14, height: 14).offset(x: x(value) - 7, y: -9)
                HStack {
                    Text("\(Int(range.lowerBound)) %")
                    Spacer()
                    Text("\(Int(range.upperBound)) %")
                }
                .font(.system(size: 10)).opacity(0.7).offset(y: 12)
                Text(MyohmFormat.number(value - error) + " – " + MyohmFormat.percent(value + error))
                    .font(.system(size: 10, weight: .semibold))
                    .fixedSize()
                    .position(x: min(max(x(value), 40), w - 40), y: proxy.size.height / 2 + 12)
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel(L("Error range: \(MyohmFormat.number(value - error)) to \(MyohmFormat.percent(value + error))"))
    }
}

struct EquationCheck: Identifiable {
    let id: String
    let ok: Bool
    let short: String
    let label: String
    let detail: String
}

enum EquationChecks {
    static func checks(_ eq: BodyEquation, _ inputs: BodyInputs) -> [EquationCheck] {
        var result: [EquationCheck] = []
        let age = Int(inputs.ageYears)
        if let range = eq.ageRange {
            let ok = range.contains(inputs.ageYears)
            result.append(EquationCheck(id: "age", ok: ok,
                short: ok ? L("Age \(String(age)) · in range") : L("Age \(String(age)) · out of range"),
                label: L("Age \(String(age)) years"),
                detail: L("validated \(String(Int(range.lowerBound)))–\(String(Int(range.upperBound)))")))
        }
        let bmi = MyohmFormat.number(inputs.bmi)
        if let range = eq.bmiRange {
            let ok = range.contains(inputs.bmi)
            result.append(EquationCheck(id: "bmi", ok: ok,
                short: ok ? L("BMI \(bmi) · in range") : L("BMI \(bmi) · out of range"),
                label: L("BMI \(bmi)"),
                detail: L("validated \(MyohmFormat.number(range.lowerBound))–\(MyohmFormat.number(range.upperBound))")))
        }
        if eq == .geneva {
            result.append(EquationCheck(id: "side", ok: true, short: L("Right side"), label: L("Right hand and foot"), detail: L("as in the study")))
            if inputs.isAthlete {
                result.append(EquationCheck(id: "athlete", ok: false, short: L("Athlete · not the target"), label: L("Athlete"), detail: L("developed in non-athletes")))
            } else {
                result.append(EquationCheck(id: "athlete", ok: true, short: L("Not an athlete"), label: L("Not an athlete"), detail: L("athletes use another equation")))
            }
        }
        if eq == .spectroscopy, let t = BodyComposition.estimate(inputs, using: eq)?.tissues {
            let v = MyohmFormat.kg(t.excessFluidKg)
            let ok = !t.excessFluidIsUnusual
            result.append(EquationCheck(id: "fluid", ok: ok,
                short: ok ? L("Excess fluid \(v)") : L("Excess fluid \(v) · unusual"),
                label: L("Excess fluid"),
                detail: ok ? v : L("\(v) · check the spectrum")))
        }
        if eq == .athletes {
            result.append(EquationCheck(id: "athlete", ok: inputs.isAthlete,
                short: inputs.isAthlete ? L("Athlete") : L("Not an athlete · not the target"),
                label: inputs.isAthlete ? L("Athlete") : L("Not an athlete"),
                detail: L("developed in athletes")))
        }
        if let see = eq.standardErrorKg {
            result.append(EquationCheck(id: "see", ok: true, short: L("Typical error ± \(MyohmFormat.kg(see))"), label: L("Typical error"), detail: "± " + MyohmFormat.kg(see)))
        }
        return result
    }
}
