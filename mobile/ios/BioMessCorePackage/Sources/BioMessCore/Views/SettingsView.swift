import SwiftUI

/// Settings and configuration view
public struct SettingsView: View {
    @State private var useRealBLE = false
    @State private var processingTier: ProcessingTierSetting = .automatic
    @State private var exportFormat: ExportFormat = .csv
    @State private var showAbout = false
    
    public init() {}
    
    enum ProcessingTierSetting: String, CaseIterable {
        case immediate = "immediate"
        case complete = "complete"
        case automatic = "automatic"
        
        var displayName: String {
            switch self {
            case .immediate: return "Immediate (Fast)"
            case .complete: return "Complete (Accurate)"
            case .automatic: return "Automatic"
            }
        }
    }
    
    enum ExportFormat: String, CaseIterable {
        case csv = "csv"
        case json = "json"
        case pdf = "pdf"
        
        var displayName: String {
            switch self {
            case .csv: return "CSV"
            case .json: return "JSON"
            case .pdf: return "PDF Report"
            }
        }
    }
    
    public var body: some View {
        NavigationView {
            Form {
                // Device Section
                Section("Device") {
                    Toggle("Use Real BLE Device", isOn: $useRealBLE)
                    
                    if !useRealBLE {
                        Label("Using mock device for development", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Processing Section
                Section("Processing") {
                    Picker("Processing Mode", selection: $processingTier) {
                        ForEach(ProcessingTierSetting.allCases, id: \.rawValue) { tier in
                            Text(tier.displayName)
                                .tag(tier)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Processing Explanation")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        switch processingTier {
                        case .immediate:
                            Text("Fast results in <1 second with ~85% accuracy")
                        case .complete:
                            Text("Complete analysis in 2-5 seconds with >95% accuracy")
                        case .automatic:
                            Text("Show immediate results, then complete analysis")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                // Data Section
                Section("Data Management") {
                    Picker("Export Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.rawValue) { format in
                            Text(format.displayName)
                                .tag(format)
                        }
                    }
                    
                    Button("Export All Data") {
                        // Export functionality
                    }
                    .foregroundStyle(.blue)
                    
                    Button("Clear All Data") {
                        // Clear data with confirmation
                    }
                    .foregroundStyle(.red)
                }
                
                // Privacy Section
                Section("Privacy & Security") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(.green)
                            Text("Local Processing")
                                .fontWeight(.medium)
                        }
                        
                        Text("All bioimpedance analysis is performed locally on your device. No data is sent to external servers.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundStyle(.blue)
                            Text("Device Storage Only")
                                .fontWeight(.medium)
                        }
                        
                        Text("Your measurement data is stored securely on this device using iOS encryption.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // About Section
                Section("About") {
                    Button("About BioMess") {
                        showAbout = true
                    }
                    .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Version 1.0.0 (1)")
                        Text("Build for iOS 18.0+")
                        Text("© 2025 BioMess")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
    }
}

private struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // App Icon and Title
                    VStack(spacing: 12) {
                        Image(systemName: "cross.vial.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.blue.gradient)
                        
                        Text("BioMess")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Bioimpedance Analysis Platform")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
                    
                    // Description
                    VStack(alignment: .leading, spacing: 12) {
                        Text("About the Technology")
                            .font(.headline)
                        
                        Text("BioMess uses advanced bioimpedance analysis to measure body composition and tissue properties. The app implements Cole model fitting with multi-start Levenberg-Marquardt optimization for clinical-grade accuracy.")
                            .font(.body)
                        
                        Text("All processing is performed locally on your device using optimized algorithms ported from validated MATLAB research implementations.")
                            .font(.body)
                    }
                    
                    // Device Info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Device Compatibility")
                            .font(.headline)
                        
                        Text("• Nordic nRF5340 dual-core microcontroller")
                        Text("• Bluetooth Low Energy 5.4")
                        Text("• 16-frequency bioimpedance measurement")
                        Text("• Integrated IMU for movement detection")
                        Text("• Medical device grade accuracy")
                    }
                    .font(.body)
                    
                    // Research Credits
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Research Foundation")
                            .font(.headline)
                        
                        Text("Based on biomedical engineering research from Swarthmore College, with algorithms validated against clinical gold standards including SFB7 and BIS systems.")
                            .font(.body)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: {
                    #if os(iOS)
                    .topBarTrailing
                    #else
                    .primaryAction
                    #endif
                }()) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}