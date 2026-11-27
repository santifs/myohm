import SwiftUI
import SwiftData
@preconcurrency import CoreBluetooth

// MARK: - Pairing

struct PairingView: View {
    @Environment(BioMessBLEManager.self) private var ble
    @Environment(\.dismiss) private var dismiss
    var onDone: () -> Void
    @State private var selected: UUID?
    @State private var pulse = false

    private var isConnected: Bool { ble.connectionState == .connected || ble.connectionState == .measuring }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(kicker: nil, title: isConnected ? L("Myohm connected") : L("Looking for your Myohm"), back: { dismiss() })
            Text(isConnected
                 ? L("Ready to measure. From now on the app will connect to it automatically.")
                 : L("Turn it on and keep it within a metre. Pick yours; the name matches the label on the device."))
                .font(MyohmFont.body)
                .foregroundStyle(MyohmColor.muted)

            radar
                .frame(maxWidth: .infinity)
                .frame(height: 170)

            VStack(spacing: 10) {
                if isConnected, let device = ble.connectedDevice {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(MyohmColor.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name ?? "Myohm").font(.system(size: 15, weight: .bold)).foregroundStyle(MyohmColor.ink)
                            Text(ble.currentBatteryLevel.map { L("Connected · \(String($0.percentage) + " %")") } ?? L("Connected"))
                                .font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                ForEach(ble.discoveredDevices.filter { !isConnected || $0.identifier != ble.connectedDevice?.identifier }, id: \.identifier) { device in
                    deviceRow(device)
                }
                if ble.discoveredDevices.isEmpty && !isConnected {
                    Text(ble.connectionState == .scanning ? L("Searching…") : L("No devices found yet."))
                        .font(MyohmFont.caption)
                        .foregroundStyle(MyohmColor.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }

            if let error = ble.lastError, !isConnected {
                Text(error).font(MyohmFont.caption).foregroundStyle(MyohmColor.accent)
            }

            Spacer(minLength: 0)

            if isConnected {
                Button(L("Continue"), action: onDone).buttonStyle(MyohmPrimaryButton())
            } else {
                Button(L("Connect")) {
                    if let id = selected, let device = ble.discoveredDevices.first(where: { $0.identifier == id }) {
                        ble.connect(to: device)
                    }
                }
                .buttonStyle(MyohmPrimaryButton())
                .disabled(selected == nil || ble.connectionState == .connecting)
                .opacity(selected == nil ? 0.5 : 1)

                HStack {
                    Button(L("Search again")) { ble.startScanning() }
                    Spacer()
                    Button(L("Set up later"), action: onDone)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MyohmColor.brand)
            }
        }
        .padding(20)
        .background(MyohmColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if !isConnected { ble.startScanning() }
            pulse = true
        }
        .onDisappear { if ble.connectionState == .scanning { ble.stopScanning() } }
        .onChange(of: ble.discoveredDevices.count) {
            if selected == nil { selected = ble.discoveredDevices.first?.identifier }
        }
    }

    private var radar: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .stroke(MyohmColor.brand.opacity(0.12), lineWidth: 1.5)
                    .frame(width: CGFloat(60 + ring * 50), height: CGFloat(60 + ring * 50))
            }
            Circle()
                .stroke(MyohmColor.brand.opacity(0.25), lineWidth: 2)
                .frame(width: 160, height: 160)
                .scaleEffect(pulse && !isConnected ? 1.0 : 0.4)
                .opacity(pulse && !isConnected ? 0 : 0.8)
                .animation(isConnected ? .default : .easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
            Circle()
                .fill(isConnected ? MyohmColor.success : MyohmColor.brand)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: isConnected ? "checkmark" : "dot.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                )
        }
        .accessibilityHidden(true)
    }

    private func deviceRow(_ device: CBPeripheral) -> some View {
        let isSelected = selected == device.identifier
        let isThisConnected = ble.connectedDevice?.identifier == device.identifier && isConnected
        return Button {
            selected = device.identifier
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name ?? "Myohm").font(.system(size: 15, weight: .bold)).foregroundStyle(MyohmColor.ink)
                    Text(isThisConnected ? L("Connected") : (ble.connectedDevice?.identifier == device.identifier && ble.connectionState == .connecting ? L("Connecting…") : L("Nearby")))
                        .font(MyohmFont.caption).foregroundStyle(MyohmColor.muted)
                }
                Spacer()
                Image(systemName: isThisConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .foregroundStyle(isThisConnected ? MyohmColor.success : MyohmColor.brand)
            }
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isSelected ? MyohmColor.brand : .clear, lineWidth: 2))
        }
        .buttonStyle(MyohmPlainButton())
    }
}

// MARK: - Person form

struct PersonFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let person: Athlete?
    var onSaved: (Athlete) -> Void

    @State private var name = ""
    @State private var sex: BiologicalSex = .female
    @State private var birth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var height = ""
    @State private var weight = ""
    @State private var athlete = false
    @State private var loaded = false

    private var heightValue: Double? { Double(height.replacingOccurrences(of: ",", with: ".")) }
    private var weightValue: Double? { Double(weight.replacingOccurrences(of: ",", with: ".")) }
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (heightValue.map { (50...250).contains($0) } ?? false)
            && (weightValue.map { (10...300).contains($0) } ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(kicker: person == nil ? L("Before the first measurement") : nil,
                             title: person == nil ? L("Who are we measuring?") : L("Edit person"),
                             back: { dismiss() })

                VStack(alignment: .leading, spacing: 14) {
                    field(L("Name")) {
                        TextField(L("Name and surname"), text: $name)
                            .textContentType(.name)
                            .font(.system(size: 17))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Biological sex")).font(MyohmFont.micro).foregroundStyle(MyohmColor.muted)
                        PillSegmented(options: [(BiologicalSex.female, L("Female")), (.male, L("Male"))], selection: $sex)
                        Text(L("Body-composition equations need it."))
                            .font(.system(size: 12)).foregroundStyle(MyohmColor.muted)
                    }
                    HStack {
                        Text(L("Date of birth")).font(.system(size: 15, weight: .semibold)).foregroundStyle(MyohmColor.ink)
                        Spacer()
                        DatePicker("", selection: $birth, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                    }
                    HStack(spacing: 12) {
                        field(L("Height")) {
                            HStack {
                                TextField("170", text: $height).keyboardType(.decimalPad).font(.system(size: 17))
                                Text("cm").foregroundStyle(MyohmColor.muted)
                            }
                        }
                        field(L("Weight")) {
                            HStack {
                                TextField("65", text: $weight).keyboardType(.decimalPad).font(.system(size: 17))
                                Text("kg").foregroundStyle(MyohmColor.muted)
                            }
                        }
                    }
                    Toggle(isOn: $athlete) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Athlete")).font(.system(size: 15, weight: .semibold))
                            Text(L("Trains regularly at a competitive level. Uses an athlete-specific equation."))
                                .font(.system(size: 12)).foregroundStyle(MyohmColor.muted)
                        }
                    }
                    .tint(MyohmColor.brand)
                }
                .myohmCard(padding: 18)

                Label(L("Data is stored only on this iPhone."), systemImage: "lock.fill")
                    .font(MyohmFont.caption)
                    .foregroundStyle(MyohmColor.muted)

                Button(person == nil ? L("Save and continue") : L("Save"), action: save)
                    .buttonStyle(MyohmPrimaryButton())
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.5)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(MyohmColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: load)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(MyohmFont.micro).foregroundStyle(MyohmColor.muted)
            content()
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(MyohmColor.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MyohmColor.line))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let person else { return }
        name = person.fullName
        sex = person.biologicalSex ?? .female
        birth = person.dateOfBirth
        athlete = person.isAthlete == true
        if let h = person.effectiveHeightCm { height = MyohmFormat.number(h, digits: h.rounded() == h ? 0 : 1) }
        if let w = person.effectiveWeightKg { weight = MyohmFormat.number(w) }
    }

    private func save() {
        let target = person ?? Athlete(fullName: name, dateOfBirth: birth)
        target.fullName = name.trimmingCharacters(in: .whitespaces)
        target.dateOfBirth = birth
        target.biologicalSex = sex
        target.isAthlete = athlete
        target.heightCm = heightValue
        target.weightKg = weightValue
        target.updatedAt = Date()
        if person == nil { context.insert(target) }
        try? context.save()
        onSaved(target)
    }
}
