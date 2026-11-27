import SwiftUI
import SwiftData
import Charts

// MARK: - History

struct HistoryScreen: View {
    @Query(sort: \Athlete.createdAt) private var people: [Athlete]
    @Query(sort: \Measurement.measuredAt, order: .reverse) private var measurements: [Measurement]
    @AppStorage("myohm.personID") private var selectedPersonID = ""
    @State private var filter: Filter = .all
    @State private var path: [MeasureRoute] = []
    @State private var selectedDate: Date?

    enum Filter: Hashable { case all, muscles, body }

    private var person: Athlete? { SelectedPerson.resolve(people, id: selectedPersonID) }

    private var personMeasurements: [Measurement] {
        guard let person else { return [] }
        return measurements.filter { $0.personID == person.id && $0.impedanceData != nil }
    }

    private var rows: [Measurement] {
        switch filter {
        case .all: return personMeasurements
        case .muscles: return personMeasurements.filter { !$0.isWholeBody }
        case .body: return personMeasurements.filter(\.isWholeBody)
        }
    }

    /// Series shown in the trend chart: whole-body fat, or the most recent muscle/side/band.
    private var trend: (title: String, kicker: String, unit: String, points: [(Date, Double)])? {
        guard let person else { return nil }
        if filter == .body {
            var points: [(Date, Double)] = []
            var equation: BodyEquation?
            for m in personMeasurements.filter(\.isWholeBody).reversed() {
                guard let ref = m.impedanceData.flatMap(SweepAnalysis.init)?.atReference,
                      let e = MeasurementValue.bodyEstimate(measurement: m, person: person, reference: ref) else { continue }
                points.append((m.measuredAt, e.fatPercent))
                equation = e.equation
            }
            guard points.count >= 2, let equation else { return nil }
            return (L("Body fat"), L("\(equation.shortName) equation · \(String(equation.year))"), "%", points)
        }
        guard let latest = personMeasurements.first(where: { !$0.isWholeBody }) else { return nil }
        let series = personMeasurements.filter {
            $0.muscleGroup == latest.muscleGroup && $0.side == latest.side && $0.bandMillimeters == latest.bandMillimeters
        }.reversed().compactMap { m -> (Date, Double)? in
            guard let ref = m.impedanceData.flatMap(SweepAnalysis.init)?.atReference else { return nil }
            return (m.measuredAt, ref.phaseAngle)
        }
        guard series.count >= 2 else { return nil }
        var title = latest.myohmTitle
        if let band = latest.bandMillimeters { title += " · \(band) mm" }
        return (title, L("Phase angle at 50 kHz"), "°", series)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(L("History")).font(MyohmFont.title(28)).foregroundStyle(MyohmColor.ink)
                        Spacer()
                        if let person { Text(person.fullName).font(.system(size: 14, weight: .semibold)).foregroundStyle(MyohmColor.brand) }
                    }
                    HStack(spacing: 8) {
                        ChipButton(title: L("All"), selected: filter == .all) { filter = .all }
                        ChipButton(title: L("Muscles"), selected: filter == .muscles) { filter = .muscles }
                        ChipButton(title: L("Whole body"), selected: filter == .body) { filter = .body }
                    }
                    if let trend { trendCard(trend) }
                    if rows.isEmpty {
                        ContentUnavailableView(L("No measurements yet"), systemImage: "waveform.path", description: Text(L("Measurements you take will appear here.")))
                            .padding(.top, 40)
                    }
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { m in
                            Button { path.append(.result(m.id)) } label: { MyohmMeasurementRow(measurement: m, person: person) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(MyohmColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MeasureRoute.self) { route in
                switch route {
                case .result(let id): ResultScreen(measurementID: id, path: $path)
                case .equation(let id): EquationScreen(measurementID: id)
                default: EmptyView()
                }
            }
        }
    }

    private func trendCard(_ t: (title: String, kicker: String, unit: String, points: [(Date, Double)])) -> some View {
        let values = t.points.map(\.1)
        let lo = (values.min() ?? 0) - 1, hi = (values.max() ?? 1) + 1
        let selected = selectedDate.flatMap { d in t.points.min { abs($0.0.timeIntervalSince(d)) < abs($1.0.timeIntervalSince(d)) } }
        let shown = selected ?? t.points.last!
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.kicker).font(MyohmFont.micro).foregroundStyle(MyohmColor.muted)
                    Text(t.title).font(.system(size: 17, weight: .bold)).foregroundStyle(MyohmColor.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(MyohmFormat.number(shown.1) + (t.unit == "%" ? " %" : "°"))
                        .font(.system(size: 22, weight: .heavy)).foregroundStyle(MyohmColor.brand)
                    Text(shown.0.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 11)).foregroundStyle(MyohmColor.muted)
                }
            }
            Chart {
                ForEach(Array(t.points.enumerated()), id: \.offset) { _, p in
                    AreaMark(x: .value("d", p.0), yStart: .value("v", lo), yEnd: .value("v", p.1))
                        .foregroundStyle(LinearGradient(colors: [MyohmColor.brand.opacity(0.16), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("d", p.0), y: .value("v", p.1))
                        .foregroundStyle(MyohmColor.brand).lineStyle(StrokeStyle(lineWidth: 2.5)).interpolationMethod(.monotone)
                    PointMark(x: .value("d", p.0), y: .value("v", p.1))
                        .foregroundStyle(MyohmColor.brand).symbolSize(p.0 == shown.0 ? 110 : 40)
                }
                if let selected {
                    RuleMark(x: .value("d", selected.0)).foregroundStyle(MyohmColor.muted.opacity(0.4))
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXSelection(value: $selectedDate)
            .frame(height: 160)
            Text(t.unit == "%"
                 ? L("Same equation for every measurement. Changes smaller than the error band are not meaningful.")
                 : L("Only measurements with the same muscle, side and band."))
                .font(.system(size: 12)).foregroundStyle(MyohmColor.muted)
        }
        .myohmCard()
    }
}

struct MyohmMeasurementRow: View {
    let measurement: Measurement
    let person: Athlete?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: measurement.isWholeBody ? "figure.stand" : "figure.strengthtraining.traditional")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 40, height: 40)
                .foregroundStyle(measurement.isWholeBody ? MyohmColor.accentInk : MyohmColor.brand)
                .background(measurement.isWholeBody ? MyohmColor.accentBg : MyohmColor.brandSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.myohmTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(MyohmColor.ink)
                Text(subtitle).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
            }
            Spacer()
            Text(MeasurementValue.headline(for: measurement, person: person))
                .font(.system(size: 16, weight: .bold)).foregroundStyle(MyohmColor.ink)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: MyohmColor.ink.opacity(0.06), radius: 1, y: 1)
    }

    private var subtitle: String {
        var parts = [measurement.measuredAt.formatted(date: .abbreviated, time: .shortened)]
        if let band = measurement.bandMillimeters { parts.append(L("band \(String(band)) mm")) }
        if let w = measurement.bodyWeightKg { parts.append(MyohmFormat.kg(w)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - People

struct PeopleScreen: View {
    @Binding var tab: MyohmTab
    @Environment(\.modelContext) private var context
    @Query(sort: \Athlete.createdAt) private var people: [Athlete]
    @Query(sort: \Measurement.measuredAt, order: .reverse) private var measurements: [Measurement]
    @AppStorage("myohm.personID") private var selectedPersonID = ""
    @State private var editing: Athlete?
    @State private var adding = false
    @State private var path: [MeasureRoute] = []
    @State private var confirmDelete = false

    private var person: Athlete? { SelectedPerson.resolve(people, id: selectedPersonID) }
    private var personMeasurements: [Measurement] {
        guard let person else { return [] }
        return measurements.filter { $0.personID == person.id }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(L("People")).font(MyohmFont.title(28)).foregroundStyle(MyohmColor.ink)
                        Spacer()
                        Button { adding = true } label: {
                            Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(MyohmColor.brand, in: Circle())
                        }
                        .accessibilityLabel(L("Add person"))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(people) { p in
                                let selected = p.id == person?.id
                                Button { selectedPersonID = p.id.uuidString } label: {
                                    HStack(spacing: 8) {
                                        Avatar(initials: p.initials, size: 28, inverted: selected)
                                        Text(p.firstName).font(.system(size: 14, weight: .semibold))
                                    }
                                    .padding(.leading, 6).padding(.trailing, 14).frame(height: 40)
                                    .foregroundStyle(selected ? .white : MyohmColor.ink)
                                    .background(selected ? MyohmColor.brand : .white, in: Capsule())
                                    .overlay(Capsule().stroke(selected ? .clear : MyohmColor.line))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if let person { profile(person) }
                }
                .padding(20)
            }
            .background(MyohmColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MeasureRoute.self) { route in
                switch route {
                case .result(let id): ResultScreen(measurementID: id, path: $path)
                case .equation(let id): EquationScreen(measurementID: id)
                default: EmptyView()
                }
            }
        }
        .sheet(item: $editing) { p in
            NavigationStack { PersonFormView(person: p) { _ in editing = nil } }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                PersonFormView(person: nil) { p in
                    selectedPersonID = p.id.uuidString
                    adding = false
                }
            }
        }
    }

    private func profile(_ p: Athlete) -> some View {
        let lastBody = personMeasurements.first(where: \.isWholeBody)
        let muscles = Dictionary(grouping: personMeasurements.filter { !$0.isWholeBody }) { "\($0.muscleGroup)|\($0.side)|\($0.bandMillimeters ?? 0)" }
            .values.compactMap { group in group.max { $0.measuredAt < $1.measuredAt }.map { ($0, group.count) } }
            .sorted { $0.0.measuredAt > $1.0.measuredAt }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Avatar(initials: p.initials, size: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.fullName).font(.system(size: 20, weight: .bold))
                        Text(p.profileSummary).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                    }
                    Spacer()
                    Menu {
                        Button(L("Edit")) { editing = p }
                        Button(L("Delete person"), role: .destructive) { confirmDelete = true }
                    } label: {
                        Text(L("Edit")).font(.system(size: 14, weight: .semibold)).foregroundStyle(MyohmColor.brand)
                    }
                }
                HStack(spacing: 8) {
                    metric(L("Height"), p.effectiveHeightCm.map { MyohmFormat.number($0, digits: 0) + " cm" } ?? "—")
                    metric(L("Weight"), p.effectiveWeightKg.map(MyohmFormat.kg) ?? "—")
                    metric(L("BMI"), p.bmiValue.map { MyohmFormat.number($0) } ?? "—")
                }
            }
            .myohmCard(padding: 18)

            if let lastBody {
                SectionLabel(L("Latest values"))
                Button { path.append(.result(lastBody.id)) } label: {
                    HStack(spacing: 10) {
                        valueTile(L("Body fat"), MeasurementValue.headline(for: lastBody, person: p), lastBody.measuredAt)
                        valueTile(L("Whole-body phase"), lastBody.impedanceData.flatMap(SweepAnalysis.init)?.atReference.map { MyohmFormat.degrees($0.phaseAngle) } ?? "—", lastBody.measuredAt)
                    }
                }
                .buttonStyle(.plain)
            }

            if !muscles.isEmpty {
                SectionLabel(L("Muscles measured"))
                VStack(spacing: 0) {
                    ForEach(Array(muscles.enumerated()), id: \.offset) { index, item in
                        Button { path.append(.result(item.0.id)) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.0.myohmTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(MyohmColor.ink)
                                    Text(L("Band \(String(item.0.bandMillimeters ?? 0)) mm · \(String(item.1)) measurements"))
                                        .font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                                }
                                Spacer()
                                Text(MeasurementValue.headline(for: item.0, person: p)).font(.system(size: 16, weight: .bold)).foregroundStyle(MyohmColor.ink)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .overlay(alignment: .bottom) { if index < muscles.count - 1 { Rectangle().fill(MyohmColor.hairline).frame(height: 1) } }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: MyohmColor.ink.opacity(0.06), radius: 1, y: 1)
            }

            Button(L("Measure \(p.firstName)")) { tab = .measure }
                .buttonStyle(MyohmPrimaryButton())
        }
        .confirmationDialog(L("Delete \(p.fullName)?"), isPresented: $confirmDelete) {
            Button(L("Delete"), role: .destructive) {
                for m in personMeasurements { context.delete(m) }
                context.delete(p)
                try? context.save()
                selectedPersonID = ""
            }
        } message: {
            Text(L("Their measurements will also be deleted from this iPhone. This cannot be undone."))
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(MyohmColor.muted)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundStyle(MyohmColor.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MyohmColor.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func valueTile(_ label: String, _ value: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(MyohmFont.micro).foregroundStyle(MyohmColor.muted)
            Text(value).font(.system(size: 28, weight: .heavy)).foregroundStyle(MyohmColor.ink)
            Text(date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 12)).foregroundStyle(MyohmColor.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: MyohmColor.ink.opacity(0.06), radius: 1, y: 1)
    }
}
