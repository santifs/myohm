import SwiftUI

public struct ContentView: View {
    public var body: some View {
        BioMess()
    }
    
    public init() {}
}

/// Main app view using environment-based architecture (no ViewModels)
struct BioMess: View {
    
    // Shared services via environment
    @State private var bleManager = MockBioMessCoreBLEManager()  // Use mock for development
    @State private var processor = BioimpedanceProcessor()
    @State private var storageService = MeasurementStorageService()
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            MainView()
                .environment(bleManager)
                .environment(processor)
                .environment(storageService)
                .environment(\.navigationPath, $navigationPath)
        }
    }
}

/// Main navigation view
struct MainView: View {
    @Environment(MockBioMessCoreBLEManager.self) private var bleManager
    @Environment(MeasurementStorageService.self) private var storageService
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MeasurementView()
                .tabItem {
                    Label("Measure", systemImage: "waveform.path.ecg")
                }
                .tag(0)
            
            CalibrationView()
                .tabItem {
                    Label("Calibration", systemImage: "tuningfork")
                }
                .tag(1)
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .navigationTitle("BioMess")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .onAppear {
            // Configure storage service with model context
            storageService.configure(with: modelContext)
        }
    }
}

#Preview {
    ContentView()
}
