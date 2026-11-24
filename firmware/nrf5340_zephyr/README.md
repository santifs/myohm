# Myohm nRF5340 firmware

Research/teaching candidate for the nRF5340 + AD5941 + nPM1304 mainboard. The AD5940 family API name is retained in code; the populated schematic part is AD5941BCPZ.

Start with [the repository firmware instructions](../README.md), [BLE protocol](docs/ble-protocol.md), [hardware pinout](docs/hardware-v2.md) and [engineering audit](../../docs/hardware-audit.md).

## Build

Use nRF Connect SDK 3.3.0 / Zephyr 4.3.99 with its matching toolchain. From repository root, in an initialized NCS shell:

```sh
west build --sysbuild -b biomess_nrf5340/nrf5340/cpuapp firmware/nrf5340_zephyr -d firmware/nrf5340_zephyr/build -- -DBOARD_ROOT="$PWD/firmware/nrf5340_zephyr"
python3 tools/verify_firmware_offline.py
```

The USB-C connector is power-only. Programming requires a compatible SWD/J-Link connection; USB alone does not provide flashing or UART. No flashing is part of offline verification.

## Candidate power policy

BUCK1 is disabled in the real board target because its switching path is not populated. BUCK2 supplies the shared rail. Automatic charging is withheld and application initialization requests charge disable; R7 is a fixed 10k resistor, not a cell thermistor. These changes compile but have not been validated on hardware. See the audit for startup and bus-failure limitations.

## Excitation amplitude and contact check

`CONFIG_MYOHM_EXCITATION_MVPP` sets the default HSDAC amplitude of the sweep in mVpp (range 50-800). The default, 800, is the setting used for all published data: 1.6 Vpp at CE0 and 0.57 mA rms into a short through RL1, outside the +/-607 mV range over which the AD5941 output is specified. **500 (1.0 Vpp at CE0, 0.35 mA rms into a short) is recommended for measurements on people**, for example by adding `CONFIG_MYOHM_EXCITATION_MVPP=500` to `prj.conf` or passing `-Dnrf5340_zephyr_CONFIG_MYOHM_EXCITATION_MVPP=500` to a sysbuild `west build`. Clients can also override it at run time through the optional characteristic `0xC018`.

BLE command `0x0B` runs a two-wire contact check of the pairs `I+`/`I-`, `V+`/`V-`, `I+`/`V+` and `I-`/`V-` at 10 and 100 kHz with a fixed 40 mVpp excitation, and flags entries above `CONFIG_MYOHM_CONTACT_HIGH_OHMS` (default 3000 ohm). Both features compile but have not been validated on hardware. Payloads and routing are in [the BLE protocol](docs/ble-protocol.md).

## Compatibility

The board target and BLE UUIDs retain BioMess identifiers. The default advertising name is BioMess; a physical unit may use a local name override such as Messi-06. Service UUIDs are not advertised. Determine identity by GATT after connection, not by assuming a name. Do not commit per-device label.conf.

The imported detailed documents describe the prior platform and its workflows. This README and the engineering audit take precedence for Myohm; new Android/iOS clients are included in [`mobile/`](../../mobile/README.md). Prior release/readiness reports do not establish validation of this candidate.
