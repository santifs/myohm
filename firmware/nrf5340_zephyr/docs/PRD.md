# PRD: Medicion de Bioimpedancia con AD5940 sobre nRF5340 DK

**Proyecto:** `ad5940_bia`
**Plataforma:** nRF5340 DK (cpuapp) + AD5940 Eval Board
**SDK:** nRF Connect SDK con Zephyr RTOS
**Fecha:** 2026-03-11

---

## 1. Objetivo del proyecto

Desarrollar una aplicacion embebida sobre Zephyr RTOS que realice mediciones de bioimpedancia (BIA) utilizando el chip AD5940 de Analog Devices conectado por SPI al nRF5340 DK. El sistema ejecuta un barrido de frecuencia logaritmico de 4 kHz a 198 kHz, midiendo magnitud y fase de la impedancia en cada punto. Los resultados se transmiten por BLE usando el protocolo BioMess consumido por las apps Android e iOS del repositorio; la UART queda como canal de log y diagnostico.

---

## 2. Requisitos Funcionales

| ID     | Requisito | Detalle |
|--------|-----------|---------|
| RF-001 | Comunicacion SPI con AD5940 usando Zephyr SPI API | Utilizar `spi_transceive()` sobre SPIM2 (`&spi2` en devicetree) a 1 MHz. Configuracion: `SPI_WORD_SET(8) \| SPI_TRANSFER_MSB`. |
| RF-002 | Control manual de CS, RST e INT via Zephyr GPIO API | PCB v2: CS en `P0.16` (ACTIVE_LOW), RST en `P0.02` (ACTIVE_LOW), INT en `P0.03` (ACTIVE_LOW, PULL_UP). Pines definidos en el devicetree overlay como nodos `cs_pin`, `rst_pin`, `int_pin` bajo `ad5940_gpios`. CS incluye delay post-asercion de 100 us para wake de hibernate. |
| RF-003 | Barrido de frecuencia configurable | Rango por defecto: 4 kHz a 198 kHz. Numero de puntos configurable (por defecto 48). Escala logaritmica (`SweepLog = bTRUE`). Parametros modificables via variables `cfgSweepStart`, `cfgSweepStop`, `cfgSweepPoints`. |
| RF-004 | Medicion de impedancia (magnitud y fase) | Para cada punto de frecuencia, el AD5940 ejecuta una DFT de 8192 puntos sobre la senal muestreada. Se miden dos canales: corriente (RCAL) y voltaje (Rz). El firmware calcula magnitud (Ohm) y fase (radianes, convertida a grados para salida). |
| RF-005 | Salida de resultados por BLE y logs por UART | Cada punto se transmite por notificaciones de `0xC000` como `float32 frequency_hz`, `float32 magnitude_ohm`, `float32 phase_deg` little-endian. UART queda habilitada con `CONFIG_UART_CONSOLE=y` para logs y diagnostico. |
| RF-006 | Ciclo autonomo de medicion | Secuencia: WUPT trigger -> wake AD5940 -> ejecutar secuencia de medicion (SEQID_0) -> escribir resultado DFT al FIFO -> entrar a hibernate (`AD5940_EnterSleepS()`). El MCU detecta datos via interrupcion GPIO (GP0, flanco activo) y lee el FIFO. |
| RF-007 | Calibracion RTIA por frecuencia | Antes de iniciar mediciones, el sistema calibra la RTIA del HSTIA para cada punto de frecuencia del barrido. Los valores calibrados (magnitud y fase) se almacenan en `RtiaCalTable[48][2]` y se aplican al calcular la impedancia. |
| RF-008 | Inicializacion de hardware AD5940 | Secuencia de inicio: hardware reset -> configuracion de clocks (HFOSC 16 MHz, LFOSC 32 kHz) -> FIFO (4 KB, fuente DFT, threshold 4) -> interrupciones (INTC0: FIFO threshold, INTC1: all) -> GPIOs del AD5940 (GP0 como INT). |
| RF-009 | Almacenamiento temporal de resultados | Los puntos medidos se almacenan en `g_measurement_buffer` hasta `AD5940_MAX_SWEEP_POINTS` y se emiten por callback BLE durante el sweep. |
| RF-010 | Shutdown del AD5940 al finalizar | Al completar el barrido, el firmware detiene el WUPT (`AD5940_WUPTCtrl(bFALSE)`) y ejecuta `AD5940_ShutDownS()` para poner el chip en modo hibernate. |
| RF-011 | BLE GATT compatible con apps moviles | El dispositivo anuncia `BioMess`, expone servicios `0xAF00-0xAF03`, recibe comandos en `0xC000` y envia puntos BIA por notificaciones de `0xC000`. |
| RF-012 | Configuracion de sweep por BLE | Las caracteristicas `0xC011-0xC017` permiten leer/escribir RCAL, habilitacion de sweep, frecuencia inicial/final, numero de puntos y repeticiones. |
| RF-013 | Verificacion de PMIC por BLE | El comando `0x02` dispara lectura del nPM1304 y notifica `0xC202` con `uint16 voltage_mv` y `uint16 percentage` little-endian. |
| RF-014 | Sincronizacion de mediciones almacenadas | Los comandos `0x07/0x08/0x09` exponen un ring buffer RAM de 4 registros en formato `StoredMeasurement` de 2974 bytes con CRC16. |
| RF-015 | Auto-mode BLE | Los comandos `0x05/0x06` activan/desactivan mediciones periodicas usando el mismo path de sweep y streaming que `0x01`. |

---

## 3. Requisitos No Funcionales

| ID      | Requisito | Especificacion |
|---------|-----------|----------------|
| RNF-001 | Frecuencia SPI | 1 MHz. Se usa SPIM2 (periferico simple) en lugar de SPIM4 porque SPIM4 se deshabilita en el overlay. SPIM2 no soporta DMA de alta velocidad, limitando la frecuencia maxima practica. |
| RNF-002 | Precision de medicion | Error menor al 5% comparado con impedancia conocida (resistor de referencia). Rcal de la PCB BioMess = 30 ohms. |
| RNF-003 | Tamano de stack | Main thread: `CONFIG_MAIN_STACK_SIZE=8192` bytes. System workqueue: `CONFIG_SYSTEM_WORKQUEUE_STACK_SIZE=4096` bytes. |
| RNF-004 | Consumo energetico | El AD5940 entra en modo hibernate entre cada ciclo de medicion. El secuenciador interno ejecuta `AD5940_EnterSleepS()` al final de cada secuencia de medicion. El MCU usa `k_usleep(100)` en el loop de polling. |
| RNF-005 | Resolucion DFT | 8192 puntos (`DFTNUM_8192`), fuente SINC3 (`DFTSRC_SINC3`), ventana de Hanning habilitada. |
| RNF-006 | Tasa de muestreo | ODR = 20 Hz (configurable). Limitada por la duracion de la secuencia de medicion. El firmware calcula `MaxODR` y ajusta automaticamente si el ODR solicitado excede el maximo. |
| RNF-007 | Soporte de punto flotante | `CONFIG_FPU=y` habilitado. Se usa Newlib con soporte de `float` en `printf` (`CONFIG_NEWLIB_LIBC_FLOAT_PRINTF=y`). |
| RNF-008 | Tiempo de inicio | Delay de 3 segundos al arranque (`k_msleep(3000)`) para permitir conexion del terminal serial antes de la primera salida. |

---

## 4. Restricciones

| # | Restriccion | Descripcion |
|---|-------------|-------------|
| 1 | Hardware | Target actual: PCB BioMess v2 con nRF5340, AD5940 y nPM1304. Board Zephyr out-of-tree `biomess_nrf5340/nrf5340/cpuapp`. Pinout AD5940: SCK=P0.09, MOSI=P0.13, MISO=P0.19, CS=P0.16, INT=P0.03, RST=P0.02. |
| 2 | SDK | nRF Connect SDK con Zephyr RTOS. Build system CMake con `find_package(Zephyr)`. Board target: `biomess_nrf5340/nrf5340/cpuapp`. |
| 3 | Vendor library | El archivo `ad5940.c` y `ad5940.h` son la libreria propietaria de Analog Devices y no se modifican. Solo se implementan las 7+2 funciones de plataforma en `ZephyrPort.c`. |
| 4 | Maximo de puntos de barrido | 100 puntos (`AD5940_MAX_SWEEP_POINTS`), limitado por el tamano de `RtiaCalTable` en SRAM. Valor por defecto: 48 puntos. |
| 5 | Memoria SRAM del AD5940 | 2 KB para secuenciador (`SEQMEMSIZE_2KB`), 4 KB para FIFO de datos (`FIFOSIZE_4KB`). Total 6 KB de SRAM interna del AD5940. |
| 6 | Modo de potencia | Modo low-power (`AFEPWR_LP`) del AFE. Ancho de banda limitado a 250 kHz (`AFEBW_250KHZ`). |

---

## 5. Criterios de aceptacion

| # | Criterio | Verificacion |
|---|----------|--------------|
| CA-001 | El sistema detecta el AD5940 al arranque | `AD5940_MCUResourceInit()` retorna 0 y se imprime `"SPI device ready"` en consola. |
| CA-002 | Se completa un barrido completo de 48 puntos | La app o `tools/test_ad5940_sweep.py` recibe exactamente `puntos × repeticiones × 12` bytes por notificaciones de `0xC000`, cubriendo frecuencias desde ~4 kHz hasta ~198 kHz. |
| CA-003 | Los valores de magnitud son fisicamente razonables | Para una carga resistiva conocida de 1 kOhm, la magnitud medida esta entre 950 y 1050 Ohm (error < 5%) en todo el rango de frecuencia. |
| CA-004 | La fase es consistente con la carga | Para una carga puramente resistiva, la fase medida esta entre -5 y +5 grados en todas las frecuencias. |
| CA-005 | El AD5940 entra en hibernate al finalizar | Despues de completar el barrido, se imprime `"AD5940 shutdown - chip in hibernation"`. No se observan mas interrupciones GP0. |
| CA-006 | No hay errores de SPI durante la ejecucion | No se imprime ningun mensaje `"SPI err:"` durante todo el ciclo de medicion. |
| CA-007 | La calibracion RTIA se ejecuta correctamente | Se calibran los 48 puntos de frecuencia antes de iniciar el barrido de medicion, sin errores. |
| CA-008 | El firmware compila | `west build` completa y genera `build/merged.hex`. Warnings conocidos del vendor `ad5940.c` no bloquean. |
| CA-009 | Las apps descubren el dispositivo | Android/iOS detectan un periférico cuyo nombre empieza por `BioMess` y encuentran la caracteristica `0xC000`. |
| CA-010 | PMIC verificable | `tools/test_pmic_battery.py` devuelve un voltaje mayor que 0 mV y porcentaje entre 0 y 100. |

---

## 6. Fuera de alcance

Los siguientes elementos **no** forman parte de esta version del proyecto:

- **Almacenamiento persistente:** El historico actual es RAM-backed y se pierde al reiniciar; no hay flash, SD card ni ningun medio no volatil.
- **Soporte multi-sensor:** Solo se soporta un AD5940 conectado por SPI.
- **IMU real:** Los comandos IMU responden con quaternion cero hasta integrar el sensor correspondiente.
- **Procesamiento avanzado de datos:** No se realiza calculo de composicion corporal (agua, grasa, musculo). Solo se reportan magnitud y fase crudos.
- **Over-the-air updates (DFU/OTA):** No se implementa actualizacion de firmware remota.
