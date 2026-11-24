# BioMess iOS App

Aplicacion iOS de BioMess para conectar con el firmware BioMess por BLE, configurar sweeps AD5940, visualizar mediciones, sincronizar registros almacenados y procesar bioimpedancia.

## Requisitos

- Xcode 16 o toolchain Swift compatible con Swift 6.1.
- iOS 17 o superior para el paquete principal `BioMessAppPackage`.
- Dispositivo iOS fisico para pruebas BLE; el simulador no puede validar Bluetooth real.
- Firmware nRF5340 flasheado y anunciando como `BioMess`.

## Estructura

```text
ios/
├── BioMess/                 # App iOS principal e Info.plist
├── BioMess.xcodeproj/       # Proyecto Xcode
├── BioMessAppPackage/          # Swift Package actual de la app
│   ├── Package.swift
│   ├── Sources/BioMessAppFeature/
│   │   ├── BLE/BioMessBLEManager.swift
│   │   ├── BLE/MockBioMessBLEManager.swift
│   │   ├── Models/StoredMeasurement.swift
│   │   ├── Processing/BioimpedanceProcessor.swift
│   │   ├── Services/AD5940ConfigurationManager.swift
│   │   └── Views/
│   └── Tests/BioMessAppFeatureTests/
└── BioMessCorePackage/             # Paquete legacy/compartido usado como dependencia local
```

## Contrato BLE

El contrato que debe coincidir con el firmware nRF5340 esta en:

- `BioMessAppPackage/Sources/BioMessAppFeature/BLE/BioMessBLEManager.swift`: UUIDs, escaneo por nombre `BioMess` o servicio anunciado `AF00`, conexion, notificaciones, comandos y sync.
- `BioMessAppPackage/Sources/BioMessAppFeature/Services/AD5940ConfigurationManager.swift`: escritura/lectura de configuracion de sweep.
- `BioMessAppPackage/Sources/BioMessAppFeature/Models/StoredMeasurement.swift`: parser little-endian del layout almacenado.
- `../../firmware/nrf5340_zephyr/docs/mobile-integration.md`: referencia compartida Android/iOS/firmware.

Servicios y caracteristicas principales:

```text
AF00 control: C000 command/notify, C001 serial
AF01 config:  C011 rcal, C012 sweep enable, C013 start Hz, C014 stop Hz, C015 points, C017 repetitions
AF02 data:    C110..C13F measurement slots/reserved
AF03 env:     C201 IMU quaternion, C202 battery, C203 IMU variance
```

Comandos soportados por `BioMessCommands`:

```text
0x01 measurement
0x02 batteryManual
0x03 imuSingle
0x04 imuStats
0x05 startAutoMode
0x06 stopAutoMode
0x07 getStoredCount
0x08 getStoredBatch
0x09 clearStored
0x0A healthCheck
0x64 ledBlink
```

Los payloads de medicion son little-endian y llegan como triples `Float32`: `frequency_hz`, `magnitude_ohm`, `phase_deg`. El firmware limita sweep points a `2..100` y repeticiones a `1..10`; la app debe usar los valores efectivos confirmados por firmware.

## Compilar

Desde `mobile/ios/BioMessAppPackage`:

```bash
swift build
swift test
```

Desde la raiz del repo, el check recomendado para asegurar que Android, iOS y firmware siguen alineados es:

```bash
make firmware-verify-mobile
make firmware-verify-mobile-tests
```

Para abrir la app:

```bash
cd mobile/ios
open BioMess.xcodeproj
```

Seleccionar un dispositivo iOS fisico, configurar signing si hace falta y ejecutar el scheme `BioMess`.

## Flujo de prueba con placa

1. Flashear `firmware/nrf5340_zephyr/build/merged.hex` en la nRF5340.
2. Confirmar que la placa anuncia como `BioMess`.
3. Abrir la app en un iPhone fisico con Bluetooth activado.
4. Escanear, conectar y esperar discovery de `AF00`, `AF01`, `AF02` y `AF03`.
5. Configurar start/stop frequency, points y repetitions desde la UI.
6. Lanzar `measurement` y verificar que se reciben puntos `frequency_hz`, `magnitude_ohm`, `phase_deg`.
7. Ejecutar `healthCheck` o `batteryManual` si se esta validando PMIC/AD5940.
8. Probar `getStoredCount`, `getStoredBatch` y `clearStored` si se esta validando sync offline.

## Permisos y background

`BioMess/Info.plist` declara uso de Bluetooth. Las pruebas BLE reales requieren dispositivo fisico, Bluetooth activado y que la placa no este conectada a otra app.

## Diagnostico rapido

- Si no aparece `BioMess`, verificar primero el firmware con `make firmware-ble` o `tools/ble_probe.py`.
- Si conecta pero no mide, comprobar UUIDs/comandos contra `../../firmware/nrf5340_zephyr/docs/ble-protocol.md`.
- Si los sweeps llegan incompletos, revisar que la app usa los points/repetitions efectivos del firmware y no solo los solicitados.
- Si falla la sincronizacion almacenada, revisar `StoredMeasurement.expectedSize`, CRC16 y el comando `getStoredBatch`.
- Si se cambian UUIDs, opcodes o layout de datos, actualizar iOS, Android y `../../firmware/nrf5340_zephyr/tools/test_protocol_contract.py` en el mismo cambio.
