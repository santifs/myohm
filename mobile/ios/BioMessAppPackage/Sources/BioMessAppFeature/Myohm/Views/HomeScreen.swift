import SwiftUI
import SwiftData

enum MeasureRoute: Hashable {
    case muscle
    case placement
    case measuring(MeasurementKind)
    case result(UUID)
    case equation(UUID)
}

struct HomeScreen: View {
    var openPairing: () -> Void
    @Binding var tab: MyohmTab
    @Environment(BioMessBLEManager.self) private var ble
    @Query(sort: \Athlete.createdAt) private var people: [Athlete]
    @Query(sort: \Measurement.measuredAt, order: .reverse) private var measurements: [Measurement]
    @AppStorage("myohm.personID") private var selectedPersonID = ""
    @State private var path: [MeasureRoute] = []
    @State var showSettings = false
    @State var showPersonPicker = false

    private var person: Athlete? { SelectedPerson.resolve(people, id: selectedPersonID) }
    private var lastMeasurement: Measurement? {
        guard let person else { return nil }
        return measurements.first { $0.personID == person.id }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        MyohmLogo(width: 104)
                        Spacer()
                        ConnectionPill(onTap: openPairing)
                        CircleIconButton(systemName: "gearshape", label: L("Settings")) { showSettings = true }
                    }

                    if let person {
                        Button { showPersonPicker = true } label: {
                            HStack(spacing: 12) {
                                Avatar(initials: person.initials, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("Person")).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                                    Text(person.fullName).font(.system(size: 17, weight: .bold)).foregroundStyle(MyohmColor.ink)
                                }
                                Spacer()
                                Text(L("Change")).font(.system(size: 14, weight: .semibold)).foregroundStyle(MyohmColor.brand)
                            }
                            .myohmCard(padding: 14)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(L("What do you want to measure?"))
                        .font(MyohmFont.title(26))
                        .foregroundStyle(MyohmColor.ink)
                        .padding(.top, 4)

                    choiceCard(
                        title: L("One muscle"),
                        subtitle: L("Phase angle and spectrum with an electrode band."),
                        systemImage: "figure.strengthtraining.traditional",
                        dark: true
                    ) { path.append(.muscle) }

                    choiceCard(
                        title: L("Whole body"),
                        subtitle: L("Body fat and water, with cables from wrist to ankle."),
                        systemImage: "figure.stand",
                        dark: false
                    ) { path.append(.placement) }

                    if let last = lastMeasurement, let route = repeatRoute(for: last) {
                        Button {
                            path.append(route)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(MyohmColor.brand)
                                    .frame(width: 40, height: 40)
                                    .background(MyohmColor.brandSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("Repeat last")).font(.system(size: 15, weight: .semibold)).foregroundStyle(MyohmColor.ink)
                                    Text(repeatSubtitle(last)).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(MyohmColor.muted)
                            }
                            .myohmCard(padding: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(MyohmColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MeasureRoute.self) { route in
                destination(route)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(openPairing: openPairing)
                .tint(MyohmColor.brand)
                .presentationBackground(MyohmColor.background)
        }
        .sheet(isPresented: $showPersonPicker) {
            PersonPicker(people: people, selectedID: $selectedPersonID)
                .tint(MyohmColor.brand)
                .presentationDetents([.medium])
                .presentationBackground(MyohmColor.background)
        }
    }

    /// Whole body goes back to placement because it needs today's weight.
    private func repeatRoute(for m: Measurement) -> MeasureRoute? {
        if m.isWholeBody { return .placement }
        guard let muscle = m.muscle, let side = m.bodySide, let band = m.bandMillimeters else { return nil }
        return .measuring(.muscle(muscle, side, band: band))
    }

    private func repeatSubtitle(_ m: Measurement) -> String {
        var parts = [m.myohmTitle]
        if let band = m.bandMillimeters { parts.append(L("band \(String(band)) mm")) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func destination(_ route: MeasureRoute) -> some View {
        switch route {
        case .muscle:
            MuscleSelectView(person: person) { kind in path.append(.measuring(kind)) }
        case .placement:
            PlacementView(person: person) { kind in path.append(.measuring(kind)) }
        case .measuring(let kind):
            MyohmMeasuringView(kind: kind, person: person) { id in
                path.removeLast()
                path.append(.result(id))
            }
        case .result(let id):
            ResultScreen(measurementID: id, path: $path)
        case .equation(let id):
            EquationScreen(measurementID: id)
        }
    }

    private func choiceCard(title: String, subtitle: String, systemImage: String, dark: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 48, height: 48)
                        .background(dark ? Color.white.opacity(0.14) : MyohmColor.brandSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(dark ? .white : MyohmColor.brand)
                    Text(title).font(.system(size: 22, weight: .bold))
                    Text(subtitle).font(MyohmFont.body).opacity(0.8).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(dark ? Color.white : MyohmColor.brand, in: Circle())
                    .foregroundStyle(dark ? MyohmColor.brand : .white)
            }
            .foregroundStyle(dark ? .white : MyohmColor.ink)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if dark {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(RadialGradient(colors: [MyohmColor.brandMid, MyohmColor.brand, MyohmColor.brandDeep], center: .topLeading, startRadius: 10, endRadius: 420))
                } else {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.white)
                }
            }
            .shadow(color: dark ? MyohmColor.brand.opacity(0.25) : MyohmColor.ink.opacity(0.06), radius: dark ? 14 : 1, y: dark ? 8 : 1)
        }
        .buttonStyle(.plain)
    }
}

struct PersonPicker: View {
    let people: [Athlete]
    @Binding var selectedID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(people) { person in
                Button {
                    selectedID = person.id.uuidString
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Avatar(initials: person.initials, size: 36)
                        VStack(alignment: .leading) {
                            Text(person.fullName).foregroundStyle(MyohmColor.ink)
                            Text(person.profileSummary).font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                        }
                        Spacer()
                        if person.id.uuidString == selectedID || (selectedID.isEmpty && person.id == people.first?.id) {
                            Image(systemName: "checkmark").foregroundStyle(MyohmColor.brand)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MyohmColor.background)
            .navigationTitle(L("Who is being measured?"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SettingsSheet: View {
    var openPairing: () -> Void
    @Environment(BioMessBLEManager.self) private var ble
    @Environment(\.dismiss) private var dismiss
    @State private var confirmForget = false

    var body: some View {
        NavigationStack {
            List {
                Section(L("Device")) {
                    LabeledContent(L("Name"), value: ble.connectedDevice?.name ?? PairedDeviceManager.pairedDevice?.name ?? "—")
                    if let battery = ble.currentBatteryLevel {
                        LabeledContent(L("Battery"), value: "\(battery.percentage) %")
                    }
                    Button(L("Connect another device")) {
                        dismiss()
                        ble.disconnect()
                        openPairing()
                    }
                    Button(L("Forget this device"), role: .destructive) { confirmForget = true }
                }
                Section {
                    NavigationLink(L("Laboratory mode")) {
                        LaboratoryView(selectedTab: .constant(0))
                    }
                } footer: {
                    Text(L("Configurable sweeps and raw data export, without a person."))
                }
                Section {
                    Text(L("Estimates for monitoring, education and research. Not a diagnosis."))
                        .font(MyohmFont.caption)
                        .foregroundStyle(MyohmColor.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MyohmColor.background)
            .navigationTitle(L("Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Done")) { dismiss() } }
            }
            .confirmationDialog(L("Forget this device?"), isPresented: $confirmForget) {
                Button(L("Forget"), role: .destructive) {
                    ble.disconnect()
                    ble.forgetPairedDevice()
                }
            } message: {
                Text(L("You will need to pair it again before measuring."))
            }
        }
    }
}
