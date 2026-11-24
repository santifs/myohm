import Foundation
@preconcurrency import CoreBluetooth

/// Information about a paired BioMess device for automatic reconnection
public struct PairedDevice: Codable, Sendable {
    /// Device identifier (UUID)
    public let identifier: String
    
    /// Device name as advertised
    public let name: String
    
    /// Last successful connection timestamp
    public let lastConnected: Date
    
    /// Connection count for prioritization
    public let connectionCount: Int
    
    /// Device serial number if available
    public let serialNumber: String?
    
    public init(
        identifier: String,
        name: String,
        lastConnected: Date = Date(),
        connectionCount: Int = 1,
        serialNumber: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.lastConnected = lastConnected
        self.connectionCount = connectionCount
        self.serialNumber = serialNumber
    }
    
    /// Update device info after successful connection
    public func updated(serialNumber: String? = nil) -> PairedDevice {
        PairedDevice(
            identifier: identifier,
            name: name,
            lastConnected: Date(),
            connectionCount: connectionCount + 1,
            serialNumber: serialNumber ?? self.serialNumber
        )
    }
}

/// Manager for paired device persistence
public final class PairedDeviceManager: @unchecked Sendable {
    private static let storageKey = "paired_biomess_device"
    nonisolated(unsafe) private static let userDefaults = UserDefaults.standard
    
    /// Get currently paired device
    public static var pairedDevice: PairedDevice? {
        guard let data = userDefaults.data(forKey: storageKey),
              let device = try? JSONDecoder().decode(PairedDevice.self, from: data) else {
            return nil
        }
        return device
    }
    
    /// Save paired device
    public static func setPairedDevice(_ device: PairedDevice) {
        guard let data = try? JSONEncoder().encode(device) else { return }
        userDefaults.set(data, forKey: storageKey)
        print("✅ Paired device saved: \(device.name)")
    }
    
    /// Update existing paired device
    public static func updatePairedDevice(serialNumber: String? = nil) {
        guard let currentDevice = pairedDevice else { return }
        setPairedDevice(currentDevice.updated(serialNumber: serialNumber))
    }
    
    /// Clear paired device
    public static func clearPairedDevice() {
        userDefaults.removeObject(forKey: storageKey)
        print("🗑️ Paired device cleared")
    }
    
    /// Check if device matches paired device
    public static func isDevicePaired(_ peripheral: CBPeripheral) -> Bool {
        guard let pairedDevice = pairedDevice else { return false }
        return peripheral.identifier.uuidString == pairedDevice.identifier
    }
}
