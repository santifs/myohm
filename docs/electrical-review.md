# Revisión eléctrica — 20 de septiembre de 2026

Primera corrección de semántica ERC sobre el candidato Myohm. No modifica cobre,
componentes, valores ni conexiones. La revisión física completa continúa abierta.

## Correcciones justificadas

| Elemento | Cambio | Base técnica |
| --- | --- | --- |
| U3 AD5941 | Clasificados los 49 pines antes `unspecified`: alimentación/masa, SPI, GPIO, matriz analógica, desacoplos y DNC. | [ADI Rev. G, tabla 7 y figura 5](https://www.analog.com/media/en/technical-documentation/data-sheets/AD5940-5941.pdf), pp. 19–21. |
| CN1, SW1 | Ocho contactos mecánicos pasan a `passive`. | Conector y pulsador sin electrónica activa; no generan ni interpretan niveles lógicos. No acredita sus dimensiones. |
| U1 nRF5340 | DCC/DCCD/DCCH pasan a `power_out`; seis terminales DEC pasan a `passive`. | [Nordic, asignación aQFN94](https://docs.nordicsemi.com/r/bundle/ps_nrf5340/page/chapters/pin.html): salidas de convertidor y terminales de desacoplo, respectivamente. |
| U2 nPM1304 | SW1, SW2, VSYS y VBUSOUT pasan a `power_out`. | [Nordic, asignación QFN32](https://docs.nordicsemi.com/r/bundle/ps_npm1304/page/pin.html). La clasificación restante del PMIC requiere completar la revisión del circuito. |
| U1 AJ1, AL21, R31 | Retiradas tres marcas NC contradictorias. | Ya conectados, respectivamente, a AD_SCLK, PWR_BTN_nPM y LED. Se conservan los cables. |

Los terminales analógicos de la matriz se modelan como `bidirectional` porque pueden
conducir excitación o recibir señal según los interruptores internos. Los terminales
dedicados a condensadores/realimentación se modelan como `passive`: no son entradas
de alimentación externas. Esto no valida su tensión ni su carga; esas condiciones
se deben comprobar contra la ficha. Los pines DNC del AD5941 pasan a `no_connect`
para detectar conexiones indebidas futuras. Alimentaciones y masas conservan
`power_in`; no se añadieron PWR_FLAG para eliminar indiscriminadamente avisos.

Los NC A25/B12/B26/G1/H2/J31 de U1 continúan a masa, como recomienda Nordic.
K2 existe en la huella, pero no en el símbolo importado; es NC según el fabricante y también está omitido en el símbolo del esquema de referencia QKAA 1.2.
La revisión de integridad geométrica del símbolo/huella debe incluir esa omisión,
sin confundirla con una señal funcional ausente.

## Evidencia y límites

- 70 cambios de tipo registrados en [el registro por pin](../reports/symbol-corrections.json).
- ERC: de **20 errores / 65 avisos** a **10 errores / 21 avisos**.
- DRC: **0 violaciones, 0 conexiones pendientes, 0 discrepancias esquema/PCB**.
- Los **137 conjuntos de conexiones referencia/pin** son idénticos antes/después.
- Archivo PCB idéntico byte a byte al commit `c73e60e`; ver [integridad](../reports/electrical-review-integrity.json).
- Bibliotecas locales sincronizadas con los símbolos embebidos. Sin nuevas exclusiones ERC.
- Ocho suites offline de firmware satisfactorias. No se ha programado ni probado la placa.

Quedan seis errores de alimentación sin fuente declarada y cuatro pines abiertos
del PMIC (SW1 y LED0–2). Los avisos restantes son 16 nombres de red múltiples y cinco
etiquetas aisladas. El [triage](../reports/erc-triage.md) se regenera con cada ejecución
de `python3 tools/check_hardware.py`; el comando sigue fallando mientras haya incidencias.

## Decisiones pendientes del diseñador

1. Confirmar BUCK2 como única alimentación de 3,0 V y BUCK1 sin uso. Conservar por
   ahora VSET1 a masa, SW1 abierto y VOUT1 a VSYS; contrastar la terminación del
   convertidor inactivo con el esquema Nordic, además de comprobar estado retenido.
2. R7 aclarada por el diseñador el 2026-09-24: sustituye deliberadamente al NTC
   porque la batería no lo incorpora. Esta opción está documentada en el kit Nordic;
   falta acreditar las protecciones de la batería. El 2026-09-24 se aclara: USB permitido
   para medir patrones R/C en banco, pero desconectado en medidas sobre personas;
   los criterios por modo figuran en [validación](validation.md).
   No habilitar carga de la batería desconocida por inferencia.
3. Revisar L3 entre DCCH y la alimentación común VDD/VDDH: en la referencia Nordic
   QKAA, configuración 2, ese inductor no es necesario para modo de tensión normal.
   El diseñador no recuerda su motivo específico y se basó en ejemplos oficiales.
   Se conserva; no se considera un fallo demostrado por diferir de una configuración.
4. Identificar antena exacta y pasivos críticos para poder aprobar huellas, RF y BOM.

La referencia descargada de [Nordic](https://www.nordicsemi.com/Products/nRF5340/Downloads)
es el paquete global 1.3, que contiene QKAA 1.2; no confundir ambas revisiones.
No se incorpora material de terceros adicional al repositorio ni se cambia su licencia.

## Aclaración del diseñador y contraste — 24 de septiembre de 2026

El diseñador cree haber seguido esquemas de documentación/application notes;
no identifica la referencia exacta para BUCK1 o L3. No se registra esa memoria como
confirmación de una configuración concreta.

La [guía del nPM1304 EK](https://docs.nordicsemi.com/r/bundle/ug_npm1304_ek/page/ug/npm1300_ek/ntc.html)
contempla expresamente una resistencia de 10 kΩ cuando la batería carece de NTC.
R7 es por tanto una sustitución intencionada y documentada para evaluación, no un
termistor conectado erróneamente. No mide la temperatura real de la celda.

La [ficha del nPM1304, Supported battery types](https://docs.nordicsemi.com/r/bundle/ps_npm1304/page/product_overview.html)
exige protección de sobretensión, subtensión y sobrecorriente de descarga en el
pack; en ausencia de NTC, también fusible térmico. La protección térmica interna
del PMIC mide su propio chip y no acredita la protección térmica de la batería.
Para la celda AliExpress sin ficha no están demostradas estas condiciones. La
inhibición de carga del candidato se mantiene por esa incertidumbre, no porque
una resistencia fija esté prohibida por Nordic.

Para L3, [Nordic también documenta la consulta sobre una DK con inductor DCCH y alimentación normal](https://devzone.nordicsemi.com/f/nordic-q-a/103725/nrf5340-in-the-nrf7002-dk-is-supplyed-in-normal-mode-but-seems-to-have-a-high-voltage-schematic).
Su presencia puede proceder de un diseño que admite otras configuraciones; la
referencia QKAA de modo normal no lo necesita. No se retira cobre ni se cambia
montaje sin cerrar el análisis de la configuración completa.
