import SwiftUI
import SwiftData

/// Root of the redesigned app: first-use flow, then three tabs.
struct MyohmRootView: View {
    @Environment(BioMessBLEManager.self) private var ble
    @Query(sort: \Athlete.createdAt) private var people: [Athlete]
    @AppStorage("myohm.onboarded") private var onboarded = false
    @AppStorage("myohm.personID") private var selectedPersonID = ""
    @State private var tab: MyohmTab = .measure
    @State private var showPairing = false

    var body: some View {
        Group {
            if !people.isEmpty && (onboarded || PairedDeviceManager.pairedDevice != nil) {
                tabs
            } else {
                OnboardingFlow { person in
                    selectedPersonID = person.id.uuidString
                    onboarded = true
                }
            }
        }
        .preferredColorScheme(.light)
        .tint(MyohmColor.brand)
        .onAppear { ble.startAutoConnectIfNeeded() }
        .sheet(isPresented: $showPairing) {
            NavigationStack { PairingView(onDone: { showPairing = false }) }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            HomeScreen(openPairing: openConnection, tab: $tab)
                .tabItem { Label(L("Measure"), systemImage: "waveform.path") }
                .tag(MyohmTab.measure)
            PeopleScreen(tab: $tab)
                .tabItem { Label(L("People"), systemImage: "person.2") }
                .tag(MyohmTab.people)
            HistoryScreen()
                .tabItem { Label(L("History"), systemImage: "chart.xyaxis.line") }
                .tag(MyohmTab.history)
        }
    }

    private func openConnection() {
        if PairedDeviceManager.pairedDevice != nil, ble.connectionState == .disconnected {
            ble.retryAutoConnect()
        } else if ble.connectionState != .connected && ble.connectionState != .measuring {
            showPairing = true
        }
    }
}

enum MyohmTab: Hashable { case measure, people, history }

/// The person currently selected, falling back to the first one.
struct SelectedPerson {
    static func resolve(_ people: [Athlete], id: String) -> Athlete? {
        people.first { $0.id.uuidString == id } ?? people.first
    }
}

// MARK: - Onboarding

struct OnboardingFlow: View {
    var onFinished: (Athlete) -> Void
    @State private var path: [Step] = []

    enum Step: Hashable { case pairing, person }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.pairing) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .pairing:
                        PairingView(onDone: { path.append(.person) })
                    case .person:
                        PersonFormView(person: nil, onSaved: onFinished)
                    }
                }
        }
    }
}

struct WelcomeView: View {
    var onConnect: () -> Void

    var body: some View {
        ZStack {
            MyohmColor.brandDeep.ignoresSafeArea()
            GeometryReader { proxy in
                Image("hero", bundle: .module)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .init(horizontal: .trailing, vertical: .bottom))
                    .clipped()
            }
            .ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: MyohmColor.brandDeep.opacity(0.6), location: 0),
                    .init(color: MyohmColor.brandDeep.opacity(0), location: 0.38),
                    .init(color: MyohmColor.brandDeep.opacity(0), location: 0.58),
                    .init(color: Color(hex: 0x051238).opacity(0.94), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("myohm")
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.5)
                Text(L("Bioimpedance."))
                    .font(MyohmFont.display(40))
                    .tracking(-1.2)
                    .padding(.top, 24)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Spacer()
                Button(L("Connect my Myohm"), action: onConnect)
                    .buttonStyle(MyohmPrimaryButton(light: true))
                Text(L("Your data stays on this iPhone."))
                    .font(MyohmFont.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
