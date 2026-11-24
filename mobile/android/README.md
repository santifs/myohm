# BioMess Android App

Aplicacion Android de VolumHealth para conectar con el firmware BioMess por BLE, lanzar sweeps AD5940, leer bateria PMIC, sincronizar mediciones almacenadas y guardar resultados locales.

## Requisitos

- Android Studio con JDK 17.
- Android SDK 34 instalado.
- Dispositivo Android fisico para pruebas BLE.
- Firmware nRF5340 anunciando como `BioMess`.

## Estructura

```text
android/
├── app/              # App Compose, navegacion, permisos BLE y pantallas
├── core-ble/         # Contrato BLE y BioMessBleManager
├── core-model/       # Modelos compartidos: impedancia, mediciones, sync
├── core-processing/  # Procesado Cole-Cole y calidad de senal
├── core-database/    # Persistencia local
└── core-common/      # Utilidades compartidas
```

## Contrato BLE

El contrato con el firmware nRF5340 vive en `core-ble`:

- `core-ble/src/main/kotlin/com/volumhealth/core/ble/BioMessBleUuids.kt`: servicios `AF00`, `AF01`, `AF02`, `AF03` y caracteristicas `C000`, `C011`-`C017`, `C201`-`C203`.
- `core-ble/src/main/kotlin/com/volumhealth/core/ble/BioMessCommand.kt`: opcodes `MEASUREMENT`, `BATTERY_MANUAL`, `GET_STORED_COUNT`, `GET_STORED_BATCH`, `CLEAR_STORED`, `HEALTH_CHECK` y `LED_BLINK`.
- `core-ble/src/main/kotlin/com/volumhealth/core/ble/BioMessBleManager.kt`: escaneo por nombre `BioMess` o servicio anunciado `AF00`, conexion, configuracion de sweep, reensamblado de notificaciones y sincronizacion de mediciones almacenadas.

La referencia completa compartida con iOS y firmware esta en `firmware/nrf5340_zephyr/docs/mobile-integration.md`.

## Compilar

Desde `mobile/android`:

```bash
./gradlew :core-ble:compileDebugKotlin
./gradlew :core-ble:testDebugUnitTest
./gradlew assembleDebug
```

Desde la raiz del repo, el check recomendado para asegurar compatibilidad Android/iOS con firmware es:

```bash
make firmware-verify-mobile
make firmware-verify-mobile-tests
```

## Flujo de prueba con placa

1. Flashear `firmware/nrf5340_zephyr/build/merged.hex` en la nRF5340.
2. Abrir la app en un dispositivo Android fisico con Bluetooth activado.
3. Escanear y conectar al anuncio `BioMess` / servicio `AF00`.
4. Configurar el sweep desde la app; el firmware limita puntos a `2..100` y repeticiones a `1..10`.
5. Lanzar una medicion y comprobar que llegan triples little-endian `frequency_hz`, `magnitude_ohm`, `phase_deg`.
6. Ejecutar lectura de bateria y health check si se esta validando PMIC/AD5940.

## Diagnostico rapido

- Si no aparecen dispositivos en Android 11 o inferior, comprobar que el permiso de ubicacion esta concedido y que la ubicacion del sistema esta activada.
- Si el dispositivo aparece pero no mide, verificar que `BioMessBleUuids.kt` coincide con `firmware/nrf5340_zephyr/docs/ble-protocol.md`.
- Si Android compila pero no iOS, ejecutar `make firmware-verify-mobile` desde la raiz para ver ambos lados.
- Si el contrato BLE compila pero el parser o buffer cambian, ejecutar `make firmware-verify-mobile-tests` para correr `:core-ble:testDebugUnitTest` junto con `swift test`.
- Si el firmware cambia opcodes, UUIDs o layout de mediciones almacenadas, actualizar Android, iOS y `firmware/nrf5340_zephyr/tools/test_protocol_contract.py` en el mismo cambio.
