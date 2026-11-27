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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let logoWidth = min(proxy.size.width - 64, 320)
            let scale = logoWidth / MyohmLogoShape.canvas.width
            let logoCenterY = proxy.size.height * 0.40
            let oCenter = CGPoint(x: proxy.size.width / 2 - 10 * scale, y: logoCenterY)

            ZStack {
                LinearGradient(colors: [Color(hex: 0x0C2C78), MyohmColor.brand, Color(hex: 0x04103A)], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Color(hex: 0x3E63C9).opacity(0.45), .clear], center: UnitPoint(x: oCenter.x / proxy.size.width, y: oCenter.y / proxy.size.height), startRadius: 0, endRadius: proxy.size.width * 0.8)

                SignalRings(center: oCenter, innerRadius: MyohmLogoShape.oRadius * scale, maxRadius: proxy.size.height * 0.75, animated: !reduceMotion)

                VStack(spacing: 22) {
                    MyohmLogo(width: logoWidth, color: .white)
                    // Product descriptor, kept in English in every language.
                    Text(verbatim: "BIOIMPEDANCE SPECTROSCOPY")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(2.6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: logoWidth + 24)
                }
                .position(x: proxy.size.width / 2, y: logoCenterY + 22)

                VStack(spacing: 12) {
                    Spacer()
                    Button(L("Connect my Myohm"), action: onConnect)
                        .buttonStyle(MyohmPrimaryButton(light: true))
                    Text(L("Your data stays on this iPhone."))
                        .font(MyohmFont.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, proxy.safeAreaInsets.bottom + 12)
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Concentric rings spreading from the o of the logo, like a signal passing through tissue.
struct SignalRings: View {
    let center: CGPoint
    let innerRadius: CGFloat
    let maxRadius: CGFloat
    var animated = true
    private let count = 6
    private let period = 7.0

    var body: some View {
        TimelineView(.animation(paused: !animated)) { context in
            let time = animated ? context.date.timeIntervalSinceReferenceDate : 0
            Canvas { ctx, _ in
                for i in 0..<count {
                    let t = (time / period + Double(i) / Double(count)).truncatingRemainder(dividingBy: 1)
                    let radius = innerRadius * 1.5 + CGFloat(t) * (maxRadius - innerRadius * 1.5)
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    let fade = (1 - t) * min(1, t * 6)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.16 * fade)), lineWidth: 1.2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
