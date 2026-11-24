import Foundation
import Testing
@testable import BioMessAppFeature

@Test func iosBleProtocolConstantsMatchFirmwareContract() throws {
    let source = try String(contentsOf: bioMessBleManagerSourceURL(), encoding: .utf8)

    for token in [
        "BioMess",
        "0000af00-0000-1000-8000-00805f9b34fb",
        "0000af01-0000-1000-8000-00805f9b34fb",
        "0000af02-0000-1000-8000-00805f9b34fb",
        "0000af03-0000-1000-8000-00805f9b34fb",
        "0000c000-0000-1000-8000-00805f9b34fb",
        "0000c011-0000-1000-8000-00805f9b34fb",
        "0000c012-0000-1000-8000-00805f9b34fb",
        "0000c013-0000-1000-8000-00805f9b34fb",
        "0000c014-0000-1000-8000-00805f9b34fb",
        "0000c015-0000-1000-8000-00805f9b34fb",
        "0000c017-0000-1000-8000-00805f9b34fb",
        "0000c202-0000-1000-8000-00805f9b34fb",
        "case measurement = 0x01",
        "case batteryManual = 0x02",
        "case getStoredCount = 0x07",
        "case getStoredBatch = 0x08",
        "case clearStored = 0x09",
        "case healthCheck = 0x0A",
        "case ledBlink = 100",
        "withServices: nil",
        "CBAdvertisementDataServiceUUIDsKey",
        "hasBioMessName || advertisesBioMessService",
    ] {
        #expect(source.contains(token), "Missing BLE firmware contract token: \(token)")
    }
}

@Test func iosBleDiscoveryAcceptsBioMessAndMessiAdvertisingNames() throws {
    let source = try String(contentsOf: bioMessBleManagerSourceURL(), encoding: .utf8)

    #expect(source.contains("\"BIOMESS\""))
    #expect(source.contains("\"MESSI\""))
}

@Test func iosBleLittleEndianPayloadHelpersMatchFirmwareWireFormat() {
    let measurementPayload = dataFloat32LE(1000) + dataFloat32LE(42.5) + dataFloat32LE(-15)

    #expect(BioMessBLEManager.float32LE(measurementPayload, 0) == 1000)
    #expect(BioMessBLEManager.float32LE(measurementPayload, 4) == 42.5)
    #expect(BioMessBLEManager.float32LE(measurementPayload, 8) == -15)

    let batteryPayload = Data([0xD8, 0x0E, 0x5F, 0x00])
    #expect(BioMessBLEManager.uint16LE(batteryPayload, 0) == 3800)
    #expect(BioMessBLEManager.uint16LE(batteryPayload, 2) == 95)

    let autoModeIntervalSeconds = UInt16(300)
    let intervalPayload = Data([
        UInt8(autoModeIntervalSeconds & 0xFF),
        UInt8((autoModeIntervalSeconds >> 8) & 0xFF),
    ])
    #expect(intervalPayload == Data([0x2C, 0x01]))
}

@Test func iosConfigurationManagerUsesFirmwareSupportedConfigCharacteristics() throws {
    let source = try String(contentsOf: ad5940ConfigurationManagerSourceURL(), encoding: .utf8)

    #expect(source.contains("0000C017-0000-1000-8000-00805F9B34FB"))
    #expect(!source.localizedCaseInsensitiveContains("0000C010-0000-1000-8000-00805F9B34FB"))
}

@Test func iosMeasurementFlowRequestsFirmwareDefaultSweepShape() throws {
    let bleSource = try String(contentsOf: bioMessBleManagerSourceURL(), encoding: .utf8)
    let viewSource = try String(contentsOf: measurementViewSourceURL(), encoding: .utf8)

    #expect(bleSource.contains("repetitions: UInt8? = nil"))
    #expect(bleSource.contains("try await self.configureNumRepetitions(reps)"))
    #expect(bleSource.contains("let numReps = try await self.readNumRepetitions()"))
    #expect(bleSource.contains("Effective NumRepetitions from firmware"))

    #expect(viewSource.contains("@State private var sweepPoints: Int = 48"))
    #expect(viewSource.contains("@State private var numRepetitions: Int = 5"))
    #expect(viewSource.contains("repetitions: UInt8(numRepetitions)"))
}

private func dataFloat32LE(_ value: Float) -> Data {
    let bitPattern = value.bitPattern
    return Data([
        UInt8(bitPattern & 0xFF),
        UInt8((bitPattern >> 8) & 0xFF),
        UInt8((bitPattern >> 16) & 0xFF),
        UInt8((bitPattern >> 24) & 0xFF),
    ])
}

private func bioMessBleManagerSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/BioMessAppFeature/BLE/BioMessBLEManager.swift")
}

private func ad5940ConfigurationManagerSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/BioMessAppFeature/Services/AD5940ConfigurationManager.swift")
}

private func measurementViewSourceURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/BioMessAppFeature/Views/MeasurementView.swift")
}
