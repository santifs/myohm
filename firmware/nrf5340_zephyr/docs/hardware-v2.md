# BioMess PCB v2 hardware notes

These notes are extracted from the schematic screenshots received on 2026-05-22.

## Main changes from the old PCB

- MCU changes from nRF52832 to nRF5340.
- Firmware moves from nRF5 SDK / SEGGER Embedded Studio to nRF Connect SDK / Zephyr / Visual Studio Code.
- AD5940 remains as the only sensor.
- BNO055 is removed.
- nPM1304 is added for battery charging and power management.
- The physical power button is connected to nPM1304 `SHPHLD`. Firmware sees it through
  nPM1304 `SHPHLD` press/release events on the PMIC interrupt line.

## nRF5340 pinout used by firmware

| Net | nRF5340 GPIO | Firmware use |
| --- | --- | --- |
| `RESET_AD` | `P0.02` | AD5940 reset, active low |
| `AD_INT` | `P0.03` | AD5940 interrupt, active low with pull-up |
| `AD_SCLK` | `P0.09` | SPI SCK |
| `AD_MOSI` | `P0.13` | SPI MOSI |
| `AD_CS` | `P0.16` | AD5940 chip select, active low |
| `AD_MISO` | `P0.19` | SPI MISO |
| `SCL_nPM` | `P0.24` | nPM1304 I2C SCL |
| `SDA_nPM` | `P0.26` | nPM1304 I2C SDA |
| `INT_nPM` | `P0.28` | nPM1304 interrupt into nRF5340 |
| `SHPHLD` | `nPM1304 SHPHLD` | Physical power button input to the PMIC |
| `LED` | `P1.10` | Status LED, active high |
| `XL1` | `P0.00` | 32.768 kHz crystal |
| `XL2` | `P0.01` | 32.768 kHz crystal |

## Zephyr mapping

- AD5940 SPI uses `spi2` with manual GPIO chip select.
- nPM1304 uses `i2c1` at address `0x6b`.
- The nPM1304 `SHPHLD` interrupt path is handled in firmware: a 3 s held press shows one long LED pulse and turns the LED off; ship mode is requested only after `SHPHLD` is released and USB VBUS is not present.
- The firmware should be built with NCS `v3.3.0` or newer so Zephyr can use the native `nordic,npm1304` devicetree bindings.
- `pmic-int-pin = <0>` matches the schematic: nPM1304 GPIO0 is wired to `INT_nPM`, which reaches nRF5340 `P0.28`.
- `host-int-gpios = <&gpio0 28 0>` matches the nPM13xx driver/sample model: the driver configures the host GPIO interrupt as edge-to-active and the PMIC `GPOIRQ` output is not declared `GPIO_ACTIVE_LOW`.

## Schematic captures

The original captures should live in `hardware/schematics/pcb_v2_captures/`.

This session only exposes the images visually in the chat, not as filesystem attachments, so the exact PNG files could not be copied directly. The electrical information visible in those captures is preserved in this document.
