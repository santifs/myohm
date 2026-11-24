# Myohm firmware

The active application is [nrf5340_zephyr](nrf5340_zephyr/README.md). Use nRF Connect SDK 3.3.0 with board `biomess_nrf5340/nrf5340/cpuapp`.

```sh
west build --sysbuild -b biomess_nrf5340/nrf5340/cpuapp firmware/nrf5340_zephyr -d firmware/nrf5340_zephyr/build -- -DBOARD_ROOT="$PWD/firmware/nrf5340_zephyr"
```

The system image is `firmware/nrf5340_zephyr/build/merged.hex`. No image has been flashed as part of this migration. Read [bring-up](nrf5340_zephyr/docs/bring-up.md), [verification](nrf5340_zephyr/docs/verification.md) and the [engineering audit](../docs/hardware-audit.md) first.

The imported helper scripts retain optional mobile compatibility workflows for the original BioMess repository; the new public clients are in [`mobile/`](../mobile/README.md). Use the standalone offline checks documented in the audit. BLE name overrides belong in an untracked local config. An existing physical unit may advertise `Messi-06`; the default name is not a hardware identity and service UUIDs are not advertised.
