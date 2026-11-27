#if DEBUG
import SwiftUI
import SwiftData
import UIKit

/// Debug-only review mode, started with the `-myohm-tour` launch argument.
/// Seeds an in-memory store, shows every screen and state on the device and saves
/// a capture of each one to Documents/tour, so the layout can be checked on real hardware.
enum ReviewTour {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-myohm-tour") }

    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: Athlete.self, Anthropometrics.self, Injury.self, MeasurementSession.self, Measurement.self, configurations: config)
    }

    /// Cole-model sweep: Z = R∞ + (R0 − R∞) / (1 + (j f / fc)^α), phase reported negative.
    static func sweep(r0: Double, rInf: Double, fc: Double, alpha: Double, noise: Double = 0) -> ImpedanceData {
        let freqs = (0..<48).map { 4_000 * pow(198_000.0 / 4_000, Double($0) / 47) }
        func rep(_ seed: Double) -> [ImpedanceData.MeasurementPoint] {
            freqs.enumerated().map { i, f in
                let x = pow(f / fc, alpha)
                let a = alpha * .pi / 2
                let denRe = 1 + x * cos(a), denIm = x * sin(a)
                let den = denRe * denRe + denIm * denIm
                let jitter = 1 + noise * sin(Double(i) * 1.7 + seed)
                let re = rInf + (r0 - rInf) * denRe / den * jitter
                let im = -(r0 - rInf) * denIm / den * jitter
                return .init(frequency: Float(f), magnitude: Float((re * re + im * im).squareRoot()), phase: Float(atan2(im, re) * 180 / .pi))
            }
        }
        return ImpedanceData(repetitions: [rep(0), rep(1), rep(2)])
    }

    static func encode(_ data: ImpedanceData) -> Data? { try? JSONEncoder().encode(data) }

    @MainActor
    static func seed(_ context: ModelContext) -> (Athlete, [Measurement]) {
        let cal = Calendar.current
        let ana = Athlete(fullName: "Ana García", dateOfBirth: cal.date(byAdding: .year, value: -34, to: Date())!, biologicalSex: .female)
        ana.heightCm = 168
        ana.weightKg = 61.6
        ana.isAthlete = false
        context.insert(ana)
        let javier = Athlete(fullName: "Javier Ruiz", dateOfBirth: cal.date(byAdding: .year, value: -27, to: Date())!, biologicalSex: .male)
        javier.heightCm = 181; javier.weightKg = 78; javier.isAthlete = true
        context.insert(javier)

        var made: [Measurement] = []
        func add(_ key: String, _ side: String, band: Int?, weight: Double?, daysAgo: Int, _ data: ImpedanceData) {
            let m = Measurement(muscleGroup: key, side: side, perceivedFatigue: 0, rawDataJSON: encode(data),
                                measuredAt: cal.date(byAdding: .day, value: -daysAgo, to: Date())!)
            m.personID = ana.id; m.bandMillimeters = band; m.bodyWeightKg = weight; m.restCompleted = weight == nil ? nil : true
            context.insert(m); made.append(m)
        }
        for (i, d) in [60, 45, 30, 20, 9, 2].enumerated() {
            add(MyohmMuscle.wholeBodyKey, "right", band: nil, weight: 62.4 - Double(i) * 0.16, daysAgo: d,
                sweep(r0: 690 + Double(i) * 3, rInf: 468, fc: 46_000, alpha: 0.72, noise: 0.004))
        }
        for (i, d) in [40, 26, 14, 7, 3, 0].enumerated() {
            add("quadriceps", "right", band: 100, weight: nil, daysAgo: d,
                sweep(r0: 62 + Double(i) * 0.4, rInf: 34, fc: 70_000, alpha: 0.78, noise: 0.003))
        }
        add("biceps", "left", band: 75, weight: nil, daysAgo: 6, sweep(r0: 88, rInf: 52, fc: 75_000, alpha: 0.75))
        try? context.save()
        return (ana, made)
    }
}

/// Shows each step full screen, captures it and moves on.
struct ReviewTourHost: View {
    @Environment(\.modelContext) private var context
    @Environment(BioMessBLEManager.self) private var ble
    @State private var data: (Athlete, [Measurement])?
    @State private var index = 0
    @State private var path: [MeasureRoute] = []
    @State private var tab: MyohmTab = .measure
    @State private var finished = false

    struct Step {
        let name: String
        let tall: Bool
        let view: AnyView
        var wait: Double = 2.2
        var log = false
    }

    var body: some View {
        Group {
            if finished {
                Text("Review finished: \(steps.count) captures").font(.title3).padding()
            } else if let current = steps[safe: index] {
                current.view.id(index)
            } else {
                ProgressView()
            }
        }
        .task {
            if data == nil {
                let seeded = ReviewTour.seed(context)
                data = seeded
                UserDefaults.standard.set(seeded.0.id.uuidString, forKey: "myohm.personID")
            }
        }
        .task(id: index) {
            guard data != nil else { return }
            let wait = steps[safe: index]?.wait ?? 2.2
            if steps[safe: index]?.log == true {
                var lines: [String] = []
                for second in 0..<Int(wait) {
                    try? await Task.sleep(for: .seconds(1))
                    lines.append("\(second)s state=\(ble.connectionState) ready=\(ble.isDeviceReady) progress=\(ble.liveSweepProgress) points=\(ble.liveSweepPoints.count) error=\(ble.lastError ?? "-")")
                    if second % 10 == 9 { Capture.save(name: String(format: "%02d-live-%02ds", index, second + 1), tall: false) }
                }
                try? lines.joined(separator: "\n").write(to: Capture.folder.appendingPathComponent("live.txt"), atomically: true, encoding: .utf8)
            } else {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard let step = steps[safe: index] else { return }
            Capture.save(name: String(format: "%02d-", index) + step.name, tall: false)
            if step.tall {
                try? await Task.sleep(for: .milliseconds(200))
                await Capture.saveTall(name: String(format: "%02d-", index) + step.name + "-full")
            }
            if index + 1 < steps.count { index += 1 } else { finished = true }
        }
    }

    private var steps: [Step] {
        guard let (ana, m) = data else { return [] }
        let body = m.first { $0.isWholeBody && Calendar.current.isDate($0.measuredAt, inSameDayAs: Calendar.current.date(byAdding: .day, value: -2, to: Date())!) } ?? m.last(where: \.isWholeBody)!
        let quad = m.filter { $0.muscleGroup == "quadriceps" }.max { $0.measuredAt < $1.measuredAt }!
        let nav = { (v: AnyView) in AnyView(NavigationStack { v }) }
        return [
            Step(name: "welcome", tall: false, view: AnyView(WelcomeView {})),
            Step(name: "pairing", tall: false, view: nav(AnyView(PairingView {}))),
            Step(name: "person-new", tall: true, view: nav(AnyView(PersonFormView(person: nil) { _ in }))),
            Step(name: "person-edit", tall: true, view: nav(AnyView(PersonFormView(person: ana) { _ in }))),
            Step(name: "home", tall: false, view: AnyView(HomeScreen(openPairing: {}, tab: $tab))),
            Step(name: "home-settings", tall: false, view: AnyView(HomeScreen(openPairing: {}, tab: $tab, showSettings: true))),
            Step(name: "home-picker", tall: false, view: AnyView(HomeScreen(openPairing: {}, tab: $tab, showPersonPicker: true))),
            Step(name: "muscle-front", tall: true, view: nav(AnyView(MuscleSelectView(person: ana) { _ in }))),
            Step(name: "muscle-back", tall: true, view: nav(AnyView(MuscleSelectView(person: ana, onMeasure: { _ in }, view: .back, muscle: .triceps, side: .left, band: 75)))),
            Step(name: "muscle-other", tall: true, view: nav(AnyView(MuscleSelectView(person: ana, onMeasure: { _ in }, view: .front, muscle: .other, side: .right, band: 50)))),
            Step(name: "placement", tall: true, view: nav(AnyView(PlacementView(person: ana) { _ in }))),
            Step(name: "measuring", tall: false, view: nav(AnyView(MyohmMeasuringView(kind: .muscle(.quadriceps, .right, band: 100), person: ana, autoStart: false) { _ in }))),
            Step(name: "local-phase", tall: true, view: nav(AnyView(LocalResultView(measurement: quad, person: ana, path: $path)))),
            Step(name: "local-selected", tall: false, view: nav(AnyView(LocalResultView(measurement: quad, person: ana, path: $path, chart: .phase, selectedFrequency: 50_000)))),
            Step(name: "local-modulus", tall: false, view: nav(AnyView(LocalResultView(measurement: quad, person: ana, path: $path, chart: .modulus)))),
            Step(name: "local-nyquist", tall: false, view: nav(AnyView(LocalResultView(measurement: quad, person: ana, path: $path, chart: .nyquist, selectedFrequency: 50_000)))),
            Step(name: "body-fat", tall: true, view: nav(AnyView(BodyResultView(measurement: body, person: ana, path: $path)))),
            Step(name: "body-water", tall: true, view: nav(AnyView(BodyResultView(measurement: body, person: ana, path: $path, tab: 1)))),
            Step(name: "equation", tall: true, view: nav(AnyView(EquationScreen(measurementID: body.id)))),
            Step(name: "history-all", tall: true, view: AnyView(HistoryScreen())),
            Step(name: "history-body", tall: true, view: AnyView(HistoryScreen(filter: .body))),
            Step(name: "history-muscles", tall: false, view: AnyView(HistoryScreen(filter: .muscles))),
            Step(name: "people", tall: true, view: AnyView(PeopleScreen(tab: $tab))),
            Step(name: "tabs", tall: false, view: AnyView(MyohmRootView())),
            Step(name: "measuring-live", tall: false, view: nav(AnyView(MyohmMeasuringView(kind: .muscle(.biceps, .left, band: 75), person: ana) { _ in })), wait: 50, log: true)
        ]
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

@MainActor
enum Capture {
    static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tour")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var window: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }

    static func save(name: String, tall: Bool) {
        guard let window else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: folder.appendingPathComponent(name + ".png"))
    }

    /// Temporarily makes the window very tall so scroll views lay out all their content.
    static func saveTall(name: String) async {
        guard let window else { return }
        let original = window.frame
        window.frame = CGRect(x: 0, y: 0, width: original.width, height: 2600)
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(900))
        save(name: name, tall: true)
        window.frame = original
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))
    }
}
#endif
