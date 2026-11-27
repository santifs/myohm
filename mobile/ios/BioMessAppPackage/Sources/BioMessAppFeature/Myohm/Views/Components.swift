import SwiftUI
import SwiftData

// MARK: - People helpers

extension Athlete {
    var initials: String {
        let parts = fullName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var firstName: String { fullName.split(separator: " ").first.map(String.init) ?? fullName }

    var effectiveHeightCm: Double? { heightCm ?? latestAnthropometrics?.heightCm }
    var effectiveWeightKg: Double? { weightKg ?? latestAnthropometrics?.weightKg }

    var bmiValue: Double? {
        guard let h = effectiveHeightCm, let w = effectiveWeightKg, h > 0 else { return nil }
        return w / pow(h / 100, 2)
    }

    /// Age in years with a fractional part, consistent with `age` (whole years by calendar).
    func ageYears(at date: Date = Date()) -> Double {
        let cal = Calendar.current
        let years = cal.dateComponents([.year], from: dateOfBirth, to: date).year ?? 0
        let lastBirthday = cal.date(byAdding: .year, value: years, to: dateOfBirth) ?? dateOfBirth
        return Double(years) + date.timeIntervalSince(lastBirthday) / (365.2425 * 24 * 3600)
    }

    var profileSummary: String {
        var parts: [String] = []
        if let sex = biologicalSex { parts.append(sex == .male ? L("Male") : L("Female")) }
        parts.append(L("\(String(age)) years"))
        parts.append(isAthlete == true ? L("athlete") : L("not an athlete"))
        return parts.joined(separator: " · ")
    }
}

struct Avatar: View {
    let initials: String
    var size: CGFloat = 28
    var inverted = false

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.42, weight: .bold))
            .frame(width: size, height: size)
            .foregroundStyle(inverted ? .white : MyohmColor.brand)
            .background(inverted ? Color.white.opacity(0.16) : MyohmColor.brandSoft, in: Circle())
    }
}

// MARK: - Connection

struct ConnectionPill: View {
    @Environment(BioMessBLEManager.self) private var ble
    var onTap: () -> Void

    private var status: (text: String, color: Color, busy: Bool) {
        switch ble.connectionState {
        case .connected:
            if let battery = ble.currentBatteryLevel {
                return (L("Connected · \(String(battery.percentage) + " %")"), MyohmColor.success, false)
            }
            return (L("Connected"), MyohmColor.success, false)
        case .measuring: return (L("Measuring"), MyohmColor.success, true)
        case .connecting: return (L("Connecting…"), MyohmColor.muted, true)
        case .scanning: return (L("Looking for Myohm…"), MyohmColor.muted, true)
        case .error: return (L("Bluetooth unavailable"), MyohmColor.accent, false)
        case .disconnected:
            return (PairedDeviceManager.pairedDevice == nil ? L("No device") : L("Not connected · retry"), MyohmColor.accent, false)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if status.busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().fill(status.color).frame(width: 8, height: 8)
                }
                Text(status.text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MyohmColor.ink)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(.white, in: Capsule())
            .overlay(Capsule().stroke(MyohmColor.line))
        }
        .buttonStyle(.plain)
    }
}

struct CircleIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MyohmColor.ink)
                .frame(width: 44, height: 44)
                .background(.white, in: Circle())
                .shadow(color: MyohmColor.ink.opacity(0.08), radius: 1, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct ScreenHeader: View {
    let kicker: String?
    let title: String
    var back: (() -> Void)?
    var backIcon = "chevron.left"

    var body: some View {
        HStack(spacing: 12) {
            if let back {
                CircleIconButton(systemName: backIcon, label: L("Back"), action: back)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let kicker {
                    Text(kicker).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                }
                Text(title).font(MyohmFont.title()).foregroundStyle(MyohmColor.ink)
            }
            Spacer(minLength: 0)
        }
    }
}

struct CheckRow: View {
    let text: String
    let done: Bool
    var trailing: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(MyohmColor.success)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Circle().stroke(Color(hex: 0xC9D1E4), lineWidth: 2)
                }
            }
            .frame(width: 24, height: 24)
            Text(text).font(MyohmFont.body).foregroundStyle(MyohmColor.ink)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(MyohmColor.brand)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(MyohmColor.brandSoft, in: Capsule())
            }
        }
        .padding(.vertical, 12)
    }
}

/// Shows the most relevant headline value of a saved measurement.
struct MeasurementValue {
    static func headline(for measurement: Measurement, person: Athlete?) -> String {
        guard let data = measurement.impedanceData, let sweep = SweepAnalysis(data), let ref = sweep.atReference else { return "—" }
        if measurement.isWholeBody, let person, let estimate = bodyEstimate(measurement: measurement, person: person, reference: ref) {
            return MyohmFormat.percent(estimate.fatPercent)
        }
        return MyohmFormat.degrees(ref.phaseAngle)
    }

    static func bodyInputs(measurement: Measurement, person: Athlete, reference: SweepPoint) -> BodyInputs? {
        guard let height = person.effectiveHeightCm,
              let weight = measurement.bodyWeightKg ?? person.effectiveWeightKg,
              let sex = person.biologicalSex else { return nil }
        return BodyInputs(
            heightCm: height, weightKg: weight,
            ageYears: person.ageYears(at: measurement.measuredAt),
            isMale: sex == .male, isAthlete: person.isAthlete == true,
            r50: reference.resistance, xc50: reference.reactance
        )
    }

    static func bodyEstimate(measurement: Measurement, person: Athlete, reference: SweepPoint) -> FatEstimate? {
        bodyInputs(measurement: measurement, person: person, reference: reference).flatMap { BodyComposition.estimate($0) }
    }
}
