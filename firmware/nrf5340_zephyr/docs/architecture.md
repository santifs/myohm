# Arquitectura del Proyecto AD5940 BIA sobre nRF5340

Este documento describe la arquitectura del sistema de medición de bioimpedancia (BIA)
basado en el chip AD5940 de Analog Devices, controlado por el nRF5340 de la PCB BioMess v2
bajo Zephyr RTOS. El target de build principal es `biomess_nrf5340/nrf5340/cpuapp`.

---

## 1. Diagrama de bloques hardware

```
 ┌──────────────────────────────────┐         ┌──────────────────────────┐
 │          nRF5340                 │         │        AD5940            │
 │        (Application Core)        │         │   (Analog Front-End)     │
 │                                  │         │                          │
 │   P0.09 (SCK)  ────────SPI──────────────── SCK                       │
 │   P0.13 (MOSI) ────────SPI──────────────── MOSI                      │
 │   P0.19 (MISO) ────────SPI──────────────── MISO                      │
 │   P0.16 (CS)   ────────GPIO─────────────── CS  (manual, ACTIVE_LOW)  │
 │                                  │         │                          │
 │   P0.02 (RST)  ────────GPIO─────────────── RESET (ACTIVE_LOW)        │
 │   P0.03 (INT)  ←───────GPIO─────────────── GP0   (ACTIVE_LOW,       │
 │                  (falling edge)  │         │       pull-up interno)   │
 │                                  │         │                          │
 │   UART (USB)   ── consola ──→ PC│         │   Electrodos ↔ cuerpo   │
 └──────────────────────────────────┘         └──────────────────────────┘

 Señales PCB v2:
   AD_SCLK = P0.09       AD_MOSI = P0.13
   AD_MISO = P0.19       AD_CS   = P0.16
   RESET_AD = P0.02      AD_INT  = P0.03
```

**Señales:**
- **SPI:** 3 líneas manejadas por el periférico SPIM2 a 1 MHz.
- **CS:** GPIO manual (no gestionado por el driver SPI de Zephyr) — ver sección 4.
- **RST:** Reset por hardware del AD5940, activo en bajo.
- **INT/GP0:** Interrupción del AD5940 hacia el nRF5340, flanco descendente con pull-up.

---

## 2. Diagrama de bloques software

```
┌─────────────────────────────────────────────────────────────┐
│  Capa 5: Integración del Sistema                            │
│  src/main.c                                                 │
│  Punto de entrada, inicializa PMIC, BLE y recursos AD5940   │
├─────────────────────────────────────────────────────────────┤
│  Capa 4: Comunicación                                       │
│  src/ble_service.c — GATT, comandos, notificaciones         │
│  UART consola — logs y diagnostico                          │
├─────────────────────────────────────────────────────────────┤
│  Capa 3: Lógica de Aplicación                               │
│  src/ad5940/AD5940Main.c   — config AD5940, loop principal  │
│  src/ad5940/BodyImpedance.c — barrido frecuencia, DFT, cal  │
├─────────────────────────────────────────────────────────────┤
│  Capa 2: Driver / Capa de Portabilidad                      │
│  src/ad5940/ZephyrPort.c  — 7+2 funciones de plataforma    │
│  src/ad5940/ad5940.c/.h   — librería vendor (no modificada) │
├─────────────────────────────────────────────────────────────┤
│  Capa 1: Configuración de Hardware                          │
│  boards/biomess/biomess_nrf5340/*.dts — board BioMess       │
│  prj.conf — Kconfig (GPIO, SPI, LOG, FPU, NEWLIB_LIBC)     │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Capa 1: Configuración de Hardware

### Devicetree board BioMess

El archivo `boards/biomess/biomess_nrf5340/biomess_nrf5340_nrf5340_cpuapp.dts`
define el hardware de la PCB BioMess en el sistema de devicetree de Zephyr:

**Periférico SPI:**
- Se deshabilita `spi4` (SPIM4) y se habilita `spi2` (SPIM2).
- Se definen los pines SPI mediante `pinctrl` con las macros `NRF_PSEL(SPIM_SCK, 0, 9)`, etc.
- Se elimina `cs-gpios` del nodo SPI con `/delete-property/` porque CS se maneja manualmente.

**GPIOs del AD5940:**
- Se usa el `compatible = "gpio-leds"` como truco para definir nodos GPIO arbitrarios
  en devicetree. No son LEDs reales — es la forma más simple de declarar pines GPIO
  con la macro `GPIO_DT_SPEC_GET()` en el código C.
- Tres nodos: `cs_pin` (P0.16), `rst_pin` (P0.02), `int_pin` (P0.03).
- Todos usan `GPIO_ACTIVE_LOW`: cuando el código escribe lógico `1` con
  `gpio_pin_set_dt()`, el pin físico va a LOW.

### Kconfig (prj.conf)

| Opción                              | Propósito                                                  |
|--------------------------------------|------------------------------------------------------------|
| `CONFIG_GPIO=y`                      | Habilita el subsistema GPIO de Zephyr                      |
| `CONFIG_SPI=y`                       | Habilita el driver SPI                                     |
| `CONFIG_LOG=y`                       | Sistema de logging de Zephyr                               |
| `CONFIG_FPU=y`                       | Unidad de punto flotante (cálculos de impedancia)          |
| `CONFIG_NEWLIB_LIBC=y`              | Librería C completa (necesaria para `printf` con floats)   |
| `CONFIG_NEWLIB_LIBC_FLOAT_PRINTF=y` | Soporte de `%f` en printf                                  |
| `CONFIG_MAIN_STACK_SIZE=8192`        | Stack del hilo main (8 KB, necesario por la librería AD5940)|
| `CONFIG_SERIAL=y`, `CONFIG_CONSOLE=y`| Salida por UART USB                                       |

---

## 4. Capa 2: Driver / Capa de Portabilidad

### ZephyrPort.c

Este archivo implementa las **7+2 funciones de plataforma** que `ad5940.c` (la librería
vendor) llama para comunicarse con el hardware. Es el único archivo que usa APIs de Zephyr
directamente para hablar con el AD5940.

**Funciones de plataforma:**

| Función                      | API de Zephyr utilizada                  | Propósito                          |
|------------------------------|------------------------------------------|------------------------------------|
| `AD5940_ReadWriteNBytes()`   | `spi_transceive()`                       | Transferencia SPI bidireccional    |
| `AD5940_CsClr()`            | `gpio_pin_set_dt(&cs_gpio, 1)`           | Aserta CS (pin LOW)                |
| `AD5940_CsSet()`            | `gpio_pin_set_dt(&cs_gpio, 0)`           | Desaserta CS (pin HIGH)            |
| `AD5940_RstClr()`           | `gpio_pin_set_dt(&rst_gpio, 1)`          | Aserta reset (pin LOW)             |
| `AD5940_RstSet()`           | `gpio_pin_set_dt(&rst_gpio, 0)`          | Desaserta reset (pin HIGH)         |
| `AD5940_Delay10us()`        | `k_busy_wait()`                          | Retardo de precisión en µs         |
| `AD5940_GetMCUIntFlag()`    | Lee variable `ucInterrupted`             | Consulta flag de interrupción      |
| `AD5940_ClrMCUIntFlag()`    | Limpia `ucInterrupted`                   | Limpia flag de interrupción        |
| `AD5940_MCUResourceInit()`  | Configura SPI, GPIOs, ISR                | Inicialización de recursos MCU     |

### ¿Por qué CS manual?

El protocolo SPI del AD5940 requiere **múltiples transferencias dentro de un mismo ciclo CS**.
Para leer un registro, la secuencia es:

```
CS LOW  →  SPI: enviar SETADDR (2 bytes)  →  SPI: leer dato (2-4 bytes)  →  CS HIGH
```

El driver SPI de Zephyr, cuando maneja `cs-gpios`, desaserta CS automáticamente después
de cada `spi_transceive()`. Esto rompería el protocolo del AD5940. Por eso:

1. Se elimina `cs-gpios` del nodo SPI en el overlay (`/delete-property/ cs-gpios`).
2. Se define CS como GPIO independiente en el nodo `ad5940_gpios`.
3. `ad5940.c` llama explícitamente a `CsClr()` y `CsSet()` alrededor de las transferencias.

### Retardo de 100 µs en CsClr()

```c
void AD5940_CsClr(void)
{
    k_busy_wait(50);   /* Inter-CS: tiempo entre ciclos CS */
    gpio_pin_set_dt(&cs_gpio, 1);  /* assert CS */
    k_busy_wait(100);  /* Post-assertion: AD5940 necesita 14-40µs para despertar */
}
```

Cuando el AD5940 está en modo hibernate, necesita entre 14 y 40 µs después de que CS
baje para despertar su interfaz SPI interna. Sin este retardo, los primeros bytes SPI
se pierden y las lecturas de registros devuelven valores corruptos. Se usa 100 µs como
margen de seguridad. Adicionalmente, hay un retardo de 50 µs antes de asertar CS para
dar tiempo entre ciclos CS consecutivos.

### Buffers dummy en SPI

La API `spi_transceive()` de Zephyr requiere buffers TX y RX no-NULL. Cuando `ad5940.c`
solo necesita enviar (TX) o solo recibir (RX), `ZephyrPort.c` provee buffers dummy
estáticos de 8 bytes para el lado que no se usa.

---

## 5. Capa 3: Lógica de Aplicación

### AD5940Main.c

Este archivo orquesta todo el flujo de medición BIA:

1. **`AD5940PlatformCfg()`** — Configura los bloques internos del AD5940:
   - Reset por hardware (`AD5940_HWReset()`)
   - Reloj interno: HFOSC a 16 MHz para ADC y sistema
   - FIFO: modo FIFO de 4 KB, fuente DFT, umbral de 4 muestras
   - Interrupciones: habilita `DATAFIFOTHRESH` en INTC0 (conectado a GP0 → nRF5340)
   - GPIO del AD5940: GP0 como salida de interrupción

2. **`AD5940BIAStructInit()`** — Configura parámetros del barrido BIA:
   - Resistencia de calibracion de la PCB BioMess (Rcal = 30 ohms)
   - DFT de 8192 puntos
   - Barrido logarítmico de 4 kHz a 198 kHz

3. **`AD5940_RunSweep()`** — Sweep bajo demanda usado por BLE:

```
AD5940PlatformCfg()  →  AD5940BIAStructInit()  →  AppBIAInit()  →  AppBIACtrl(START)
                                                                         │
    ┌────────────────────────────────────────────────────────────────────┘
    │
    ▼
┌──────────────────────────────────────────┐
│  while (!BIAend):                        │
│    ¿Flag interrupción activo?            │
│    │ NO → k_usleep(100), volver          │
│    │ SI ↓                                │
│    │ Limpiar flag                        │
│    │ AppBIAISR() → despertar chip,       │
│    │   leer FIFO, procesar DFT,          │
│    │   re-hibernar chip                  │
│    │ BIAShowResult() → guardar punto     │
│    │   y llamar callback BLE             │
│    └─────────────────────────────────────│
└──────────────────────────────────────────┘
    │
    ▼
AD5940_ShutDownS()  →  chip en hibernación permanente
```

`AD5940_RunSweep()` recibe un `AD5940SweepConfig` y un callback. `ble_service.c`
usa ese callback para empaquetar cada punto como tres `float32` little-endian y
notificarlo por `0xC000`; UART queda para trazas de diagnóstico.

### BodyImpedance.c

Librería de aplicación BIA proporcionada por Analog Devices. Maneja:

- **Secuencias del AD5940:** programa el secuenciador interno para excitar con señal
  sinusoidal y muestrear la respuesta.
- **Calibración RTIA:** calibra la resistencia de transimpedancia para mediciones precisas.
- **Barrido de frecuencia:** recorre las frecuencias configuradas en escala logarítmica.
- **Procesamiento DFT:** convierte las muestras del ADC a impedancia compleja (magnitud y fase).
- **Ciclo hibernate/wake:** después de cada medición, envía el AD5940 a modo hibernate
  para ahorrar energía. El WUPT (Wake-Up Timer) interno lo despierta para la siguiente medición.

### Ciclo hibernate/wake

El AD5940 pasa la mayor parte del tiempo en modo hibernate (~µA de consumo).
El flujo es:

```
Hibernate  ──(WUPT expira)──→  Wake  ──→  Ejecutar secuencia  ──→  Generar INT
    ▲                                                                    │
    │                                                                    ▼
    └────────────────────  AppBIAISR() lee FIFO  ◄──── nRF5340 detecta INT
                           y re-hiberna el chip
```

---

## 6. Capa 4: Comunicación

### BLE GATT

`src/ble_service.c` implementa el protocolo BioMess consumido por las apps Android e iOS del repositorio:

- Anuncio BLE con nombre `BioMess` y servicio primario `0000af00-0000-1000-8000-00805f9b34fb`.
- Característica de comandos `0xC000` con `write` y `notify`.
- Configuración de sweep en `0xC011-0xC017`.
- Batería nPM1304 en `0xC202`.
- Streaming BIA por notificaciones de `0xC000`.
- Sincronización de mediciones almacenadas por comandos `0x07/0x08/0x09`.
- Auto-mode por comandos `0x05/0x06`, ejecutado por el mismo hilo de comandos.

El callback GATT solo encola comandos. Un hilo dedicado consume la cola y ejecuta operaciones lentas como el sweep AD5940, evitando bloquear el contexto BLE.

Las mediciones completadas se copian a un ring buffer RAM de 4 registros en el formato `StoredMeasurement` de las apps (`5 x 48` puntos, quaternions y CRC16). Esto valida el flujo de sincronización móvil; la persistencia en flash queda como trabajo posterior.

Formato de punto de medición:

```
float32 frequency_hz
float32 magnitude_ohm
float32 phase_deg
```

Todos los valores son little-endian. Ver `docs/ble-protocol.md`.

### UART

La UART queda para logs y diagnostico:

- `printf()` para mensajes de la aplicación AD5940.
- `LOG_INF()` / `LOG_ERR()` del sistema de logging de Zephyr.

---

## 7. Capa 5: Integración del Sistema

### main.c

El punto de entrada de la aplicación:

```c
int main(void)
{
    k_msleep(3000);              // Esperar conexión serial
    board_power_init();          // PMIC, charger y power button
    ble_service_init();          // GATT, advertising e hilo de comandos
    AD5940_MCUResourceInit();    // SPI, GPIOs e ISR del AD5940
    while (1) {                  // Idle; las mediciones llegan por BLE
        k_msleep(1000);
    }
}
```

**Características:**
- **BLE-first:** el firmware queda anunciando como `BioMess`; las apps o scripts
  disparan mediciones escribiendo comandos en `0xC000`.
- **Hilo de comandos BLE:** `ble_service.c` define un hilo dedicado que consume una
  `k_msgq`. El callback GATT solo encola opcodes y no ejecuta sweeps largos en contexto BLE.
- **AD5940 bajo demanda:** `AD5940_MCUResourceInit()` configura SPI/GPIO/ISR al arranque,
  pero el sweep se ejecuta solo cuando llega `0x01` o cuando auto-mode dispara una medición.
- **PMIC al arranque:** `board_power_init()` registra callbacks del nPM1304, prepara
  lectura de batería para el comando `0x02`, inicializa el estado VBUS y gestiona
  pulsación de 3 s de `SHIPHOLD` para entrar en ship mode cuando no hay USB conectado.
- **Retardo inicial de 3 segundos:** permite conectar un terminal serial antes de que
  aparezcan los primeros mensajes.

---

## 8. Decisiones de diseño (ADR)

### ADR-1: SPIM2 en lugar de SPIM4

**Contexto:** El nRF5340 tiene SPIM4 (alta velocidad, EasyDMA con scatter/gather) y
SPIM2 (periférico simple).

**Decisión:** Usar SPIM2.

**Justificación:** SPIM4 con EasyDMA causaba problemas con las transferencias pequeñas
(1-4 bytes) típicas del protocolo AD5940. SPIM2 es más simple y funciona de forma
fiable a 1 MHz. El overlay deshabilita SPIM4 explícitamente (`status = "disabled"`)
y configura SPIM2 con los mismos pines del Arduino header.

### ADR-2: CS manual en lugar de Zephyr cs-gpios

**Contexto:** Zephyr permite declarar `cs-gpios` en el nodo SPI para manejo automático
de chip select.

**Decisión:** Manejar CS como GPIO independiente.

**Justificación:** El protocolo del AD5940 necesita ciclos CS que envuelven múltiples
transferencias SPI (SETADDR + READ/WRITE). El manejo automático de Zephyr desaserta CS
después de cada `spi_transceive()`, lo que rompe el protocolo. Se usa
`/delete-property/ cs-gpios` en el overlay y se define CS en el nodo `ad5940_gpios`.

### ADR-3: Retardo de 100 µs en CsClr()

**Contexto:** El AD5940 en modo hibernate no responde a SPI inmediatamente al bajar CS.

**Decisión:** Agregar `k_busy_wait(100)` después de asertar CS.

**Justificación:** La datasheet especifica que el AD5940 necesita entre 14 y 40 µs
para despertar de hibernate después del flanco descendente de CS. Sin este retardo,
las lecturas SPI devuelven datos corruptos. Se usa 100 µs como margen de seguridad.

### ADR-4: Convención ACTIVE_LOW en Zephyr

**Contexto:** CS, RST e INT del AD5940 son todos activos en bajo.

**Decisión:** Declarar los pines como `GPIO_ACTIVE_LOW` en devicetree.

**Justificación:** Con `GPIO_ACTIVE_LOW`, la API de Zephyr invierte la lógica
automáticamente: `gpio_pin_set_dt(pin, 1)` pone el pin en LOW físico (activo),
y `gpio_pin_set_dt(pin, 0)` lo pone en HIGH (inactivo). Esto hace que el código C
sea más legible: `1` = activo, `0` = inactivo, sin importar la polaridad eléctrica.

---

## 9. Mapeo de archivos a capas

| Archivo                                              | Capa                        | Responsabilidad                                     |
|------------------------------------------------------|-----------------------------|-----------------------------------------------------|
| `boards/biomess/biomess_nrf5340/`                    | 1 - Configuración Hardware  | Board Zephyr BioMess: CPUAPP/CPUNET, SPI2, PMIC, GPIOs |
| `boards/nrf5340dk_nrf5340_cpuapp.overlay`            | 1 - Configuración Hardware  | Overlay DK conservado como referencia/fallback      |
| `prj.conf`                                           | 1 - Configuración Hardware  | Kconfig: habilita subsistemas de Zephyr             |
| `CMakeLists.txt`                                     | 1 - Configuración Hardware  | Build system: lista de fuentes e includes           |
| `src/ad5940/ZephyrPort.c`                            | 2 - Driver / Port Layer     | 7+2 funciones de plataforma (SPI, GPIO, delay, ISR) |
| `src/ad5940/ad5940.c`                                | 2 - Driver / Port Layer     | Librería vendor: acceso a registros, secuenciador   |
| `src/ad5940/ad5940.h`                                | 2 - Driver / Port Layer     | Definiciones de registros y API de la librería      |
| `src/ad5940/AD5940Main.c`                            | 3 - Lógica de Aplicación    | Configuración del AD5940, loop de medición          |
| `src/ad5940/AD5940Main.h`                            | 3 - Lógica de Aplicación    | Interfaz del módulo de aplicación                   |
| `src/ad5940/BodyImpedance.c`                         | 3 - Lógica de Aplicación    | BIA: barrido, calibración, DFT                      |
| `src/ad5940/BodyImpedance.h`                         | 3 - Lógica de Aplicación    | Interfaz y estructuras de configuración BIA         |
| `src/ble_service.c`                                  | 4 - Comunicación            | BLE GATT, comandos, streaming, batería              |
| `src/ble_service.h`                                  | 4 - Comunicación            | API interna del servicio BLE                        |
| *(UART consola — sin archivo propio)*                | 4 - Comunicación            | Logs por printf/LOG_INF                             |
| `src/board_power.c`                                  | 5 - Integración del Sistema | nPM1304 init, eventos y lectura de batería          |
| `src/main.c`                                         | 5 - Integración del Sistema | Punto de entrada, secuencia de inicialización       |
