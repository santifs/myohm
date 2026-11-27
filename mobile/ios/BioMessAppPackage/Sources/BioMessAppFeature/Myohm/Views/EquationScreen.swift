import SwiftUI
import SwiftData

struct EquationScreen: View {
    let measurementID: UUID
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [Measurement]
    @Query(sort: \Athlete.createdAt) private var people: [Athlete]

    init(measurementID: UUID) {
        self.measurementID = measurementID
        _matches = Query(filter: #Predicate<Measurement> { $0.id == measurementID })
    }

    private var measurement: Measurement? { matches.first }
    private var person: Athlete? { measurement.flatMap { m in people.first { $0.id == m.personID } } }
    private var inputs: BodyInputs? {
        guard let measurement, let person,
              let ref = measurement.impedanceData.flatMap(SweepAnalysis.init)?.atReference else { return nil }
        return MeasurementValue.bodyInputs(measurement: measurement, person: person, reference: ref)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let inputs, case .equation(let eq) = BodyComposition.select(for: inputs) {
                    ScreenHeader(kicker: L("How it was calculated"), title: L("\(eq.shortName) equation"), back: { dismiss() })
                    formulaCard(eq, inputs)
                    validityCard(eq, inputs)
                    selectionCard(eq)
                    reference(eq)
                } else {
                    ScreenHeader(kicker: nil, title: L("Equation"), back: { dismiss() })
                    Text(L("No equation applies to this measurement.")).foregroundStyle(MyohmColor.muted)
                }
            }
            .padding(20)
        }
        .background(MyohmColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func formulaText(_ eq: BodyEquation) -> String {
        switch eq {
        case .geneva:
            return L("FFM = −4.104\n+ 0.518 · height² / R\n+ 0.231 · weight\n+ 0.130 · Xc\n+ 4.229 · sex")
        case .athletes:
            return L("FFM = −2.261\n+ 0.327 · height² / R\n+ 0.525 · weight\n+ 5.462 · sex")
        case .youth:
            return L("FFM = 0.61 · height² / R\n+ 0.25 · weight\n+ 1.31")
        }
    }

    private func c(_ value: Double, _ digits: Int = 3) -> String { MyohmFormat.number(value, digits: digits) }

    private func terms(_ eq: BodyEquation, _ i: BodyInputs) -> [(String, Double)] {
        let h = MyohmFormat.number(i.heightCm, digits: 0)
        let r = MyohmFormat.number(i.r50, digits: 0)
        let w = MyohmFormat.kg(i.weightKg)
        let sexLabel = i.isMale ? L("male (1)") : L("female (0)")
        let index = i.heightCm * i.heightCm / i.r50
        switch eq {
        case .geneva:
            return [
                ("\(c(0.518)) · \(h)² / \(r)", 0.518 * index),
                ("\(c(0.231)) · \(w)", 0.231 * i.weightKg),
                ("\(c(0.130)) · \(MyohmFormat.ohms(i.xc50))", 0.130 * i.xc50),
                ("\(c(4.229)) · \(sexLabel)", i.isMale ? 4.229 : 0),
                (L("Constant"), -4.104)
            ]
        case .athletes:
            return [
                ("\(c(0.327)) · \(h)² / \(r)", 0.327 * index),
                ("\(c(0.525)) · \(w)", 0.525 * i.weightKg),
                ("\(c(5.462)) · \(sexLabel)", i.isMale ? 5.462 : 0),
                (L("Constant"), -2.261)
            ]
        case .youth:
            return [
                ("\(c(0.61, 2)) · \(h)² / \(r)", 0.61 * index),
                ("\(c(0.25, 2)) · \(w)", 0.25 * i.weightKg),
                (L("Constant"), 1.31)
            ]
        }
    }

    private func formulaCard(_ eq: BodyEquation, _ i: BodyInputs) -> some View {
        let estimate = BodyComposition.estimate(i, using: eq)
        return VStack(alignment: .leading, spacing: 14) {
            Text(formulaText(eq))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(MyohmColor.brand)
                .lineSpacing(4)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MyohmColor.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(L("FFM: fat-free mass (kg). Height in cm, weight in kg, R and Xc in Ω at 50 kHz. Sex: male = 1, female = 0."))
                .font(.system(size: 12)).foregroundStyle(MyohmColor.muted)

            Text(L("With \(person?.firstName ?? "")'s data")).font(MyohmFont.headline).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(terms(eq, i).enumerated()), id: \.offset) { _, term in
                    row(term.0, (term.1 < 0 ? "−" : "") + MyohmFormat.number(abs(term.1), digits: 2))
                }
                HStack {
                    Text(L("Fat-free mass")).font(.system(size: 15, weight: .bold))
                    Spacer()
                    Text(MyohmFormat.kg(estimate.fatFreeMassKg)).font(.system(size: 17, weight: .heavy)).foregroundStyle(MyohmColor.brand)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(MyohmColor.hairline).frame(height: 1) }
                row(L("Fat = \(MyohmFormat.number(i.weightKg)) − \(MyohmFormat.number(estimate.fatFreeMassKg))"),
                    MyohmFormat.kg(estimate.fatMassKg) + " · " + MyohmFormat.percent(estimate.fatPercent), last: true)
            }
        }
        .myohmCard(padding: 18)
    }

    private func row(_ label: String, _ value: String, last: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(MyohmColor.muted)
            Spacer()
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(MyohmColor.ink)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(MyohmColor.hairline).frame(height: 1) } }
    }

    private func validityCard(_ eq: BodyEquation, _ i: BodyInputs) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Is it valid for \(person?.firstName ?? "")?")).font(MyohmFont.headline)
            ForEach(EquationChecks.checks(eq, i).filter { $0.id != "see" }) { check in
                HStack(spacing: 10) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(check.ok ? MyohmColor.success : MyohmColor.accent)
                    Text(check.label).font(.system(size: 14))
                    Spacer()
                    Text(check.detail).font(.system(size: 14)).foregroundStyle(MyohmColor.muted)
                }
            }
            Text(studySummary(eq)).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted).padding(.top, 4)
        }
        .myohmCard(padding: 18)
    }

    private func studySummary(_ eq: BodyEquation) -> String {
        switch eq {
        case .geneva: return L("Typical error ± 1.72 kg of fat-free mass (r = 0.986), in 343 healthy adults compared with DXA.")
        case .athletes: return L("Developed in athletes against a 4-compartment model. Typical error not yet verified by Myohm.")
        case .youth: return L("Developed and cross-validated in children and adolescents. Typical error not yet verified by Myohm.")
        }
    }

    private func selectionCard(_ current: BodyEquation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("How the app chooses")).font(MyohmFont.headline).padding(.bottom, 6)
            selectionRow(L("Adult, BMI 17–34"), "Geneva 2001", highlighted: current == .geneva)
            selectionRow(L("Athlete"), "Matias–Campa 2021", highlighted: current == .athletes)
            selectionRow(L("10–19 years"), "Houtkooper 1992", highlighted: current == .youth)
            selectionRow(L("Under 10 years"), L("No fat; phase only"), warning: true)
            selectionRow(L("BMI above 34"), L("Water only (spectrum)"), warning: true, last: true)
            Text(L("Each measurement keeps the data used, so the calculation can be repeated."))
                .font(.system(size: 12)).foregroundStyle(MyohmColor.muted).padding(.top, 8)
        }
        .myohmCard(padding: 18)
    }

    private func selectionRow(_ who: String, _ eq: String, highlighted: Bool = false, warning: Bool = false, last: Bool = false) -> some View {
        HStack {
            Text(who).font(.system(size: 14))
            Spacer()
            Text(eq).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(highlighted ? MyohmColor.brand : (warning ? MyohmColor.accentInk : MyohmColor.ink))
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(MyohmColor.hairline).frame(height: 1) } }
    }

    private func reference(_ eq: BodyEquation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(L("Reference"))
            Text(eq.citation).font(MyohmFont.caption).foregroundStyle(MyohmColor.ink)
            if let doi = eq.doi, let url = URL(string: "https://doi.org/\(doi)") {
                Link("doi:\(doi)", destination: url).font(.system(size: 13, weight: .semibold)).frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 4)
    }
}
