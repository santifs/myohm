# Myohm: auditoría de preparación para publicación

Fecha inicial: 2026-09-17. Actualización eléctrica: 2026-09-20. Aclaración de batería: 2026-09-24. Herramienta: KiCad 10.0.3. Resultado: **candidato de ingeniería, no aprobado para fabricación ni conexión a personas**. La migración y la revisión estática no equivalen a validación física.

## Fuentes y alcance

La PCB vigente procede del repositorio de origen del hardware, checkout `VolumHWv3`. Se tomó la copia local `AllInOne-corrected`, que incluye correcciones del 12 de septiembre y no estaba seguida por Git. Se registraron hashes del árbol de trabajo, no se atribuye falsamente ese contenido al commit remoto. El firmware procede del árbol de trabajo de `biomess/firmware/nrf5340_zephyr`. Los originales no se modificaron.

Se revisaron netlist, ERC, DRC con relleno y paridad, esquemático exportado, bibliotecas locales, modelos referenciados, PCB abierta en el editor KiCad, vistas 3D superior/inferior y contrato de pines con firmware. No se hicieron medidas, flash, prueba BLE física, ensayos EMC/ESD/térmicos, verificación metrológica ni aprobación por fabricante. No se auditó por completo cada land pattern frente a su dibujo mecánico original.

La PCB histórica nRF52832 en `biomess/hardware/pcb` queda excluida. Las placas de electrodos, batería y variantes mecánicas del repositorio hardware tampoco se incluyen como si fueran accesorios validados: su selección/revisión será una ampliación identificada de Myohm. El laboratorio web importado es el prototipo local, no la aplicación desplegada posteriormente.

## Resumen de comprobaciones

| Comprobación | Resultado |
| --- | --- |
| ERC antes de recuperar bibliotecas | 20 errores, 233 avisos |
| ERC tras recuperar bibliotecas (baseline) | 20 errores, 65 avisos |
| ERC tras revisión de tipos y marcas NC | 10 errores, 21 avisos; [correcciones y fuentes](electrical-review.md) |
| DRC, conexiones y paridad | 0 / 0 / 0 tras sustituir logo y reforzar regla de pista; `reports/checks.json` |
| Símbolos recuperados | 72 definiciones exactas, 4 bibliotecas por hoja, incluidos alternativos `lib_name` |
| Conectividad antes/después de bibliotecas | Igualdad de conjuntos de pares referencia/pin de todas las redes |
| Huellas personalizadas | Messi.pretty y dos encapsulados US recuperados; Volum no usada eliminada |
| Modelos | Rutas personales reemplazadas por rutas de proyecto; KiCad 10. Prueba reubicada con configuración de usuario vacía: 0 incidencias de bibliotecas |
| Firmware | Compilación sysbuild CPUAPP+CPUNET y comprobación de merged.hex satisfactorias |
| Web | 19 tests y build/PWA satisfactorios; BLE simulado |
| Secretos/rutas CAD | Escaneo heurístico sin incidencias; no sustituye revisión humana ni derechos |

Las categorías ERC pendientes son 6 entradas de alimentación sin driver, 4 pines sin conexión, 16 nombres de red múltiples y 5 etiquetas aisladas. Se han corregido 70 tipos eléctricos con justificación y tres marcas NC contradictorias, manteniendo los 137 conjuntos de conexiones y la PCB byte a byte. El detalle actual está en [triage por hoja y pin](../reports/erc-triage.md) y la justificación en [revisión eléctrica](electrical-review.md). No todos los errores restantes representan fallos físicos; deben resolverse con ficha y función del circuito, no añadiendo PWR_FLAG indiscriminadamente.

El proyecto hereda cuatro reglas ERC ignoradas: etiqueta global única, unión de cuatro puntos, modelo SPICE y filtro de huella. Se declaran en los informes. La paridad PCB sí comprueba los filtros de huella. Los filtros importados de Altium se ampliaron con los nombres KiCad ya asignados, conservando los originales; esto no certifica dimensiones.

## Hallazgos priorizados

| ID | Prioridad | Evidencia y consecuencia | Resolución necesaria |
| --- | --- | --- | --- |
| HW-01 | Bloquea validación de carga | U2.18 NTC conecta R7=10k fija a GND; CN2 tiene dos contactos. La batería es de AliExpress, sin ficha técnica. R7 es intencional: la batería no tiene NTC (confirmado 2026-09-24). Nordic documenta esta sustitución en su EK; no proporciona medida de temperatura de celda. | Batería trazable y límites documentados; acreditar protecciones de sobretensión, subtensión y sobrecorriente de descarga y, sin NTC, fusible térmico exigido por Nordic. Ver la aclaración en [revisión eléctrica](electrical-review.md). Ensayos de temperatura/fallos. En el candidato se retira habilitación automática y se solicita inhibición por API. |
| HW-02 | Alta | VSET1=GND, SW1 abierto, VOUT1=VSYS; BUCK2 usa L5=2.2uH y R5=150k. Firmware importado tenía `regulator-boot-on` en BUCK1. | Corregido el nodo BUCK1 a disabled en el target real. Revisar conexión del convertidor no usado contra circuito Nordic exacto y confirmar arranque/estado de PMIC. No se afirma que dos bucks estén físicamente en paralelo. |
| HW-03 | Bloquea uso corporal | IC1 protege las cuatro redes externas de CN1 y conecta a GND/AVDD_2, del lado del electrodo respecto a C2–C5. | Analizar caminos de fuga/fallo y transitorios a los raíles: esos caminos no quedan aislados por los condensadores serie. Uso confirmado: USB permitido durante medidas R/C de banco sin personas; desconectado para medidas corporales. Verificar selección explícita de modo, bloqueo por VBUS en modo corporal y transición accidental; validar protección, capacidad, fuga y corriente en fallos, incluyendo USB/SWD. Un TVS no demuestra seguridad corporal. |
| HW-04 | Alta | C2–C5=4.7uF; RL1=1k en excitación; RCAL1=30 ohm 0.1%. | Establecer amplitud/frecuencia/corriente máxima, tolerancias, rating/derating de condensadores, calibración y condiciones de saturación. El valor por defecto de firmware es 30 ohm; se corrigió un comentario heredado que lo llamaba RCAL2. Verificar el valor realmente montado antes de medir. No copiar límites de una nota de aplicación como certificado. |
| HW-05 | Alta | 10 errores/21 avisos ERC siguen abiertos tras corregir 70 tipos eléctricos y tres NC; etiquetas SW1/PVSS1 en BUCK2 confusas. | Completar semántica de alimentación y pines abiertos del PMIC; confirmar intención de BUCK1. Renombrar redes coherentemente en esquema/PCB, con comparación de netlists. |
| HW-06 | Alta | AE1 solo dice Antenna, huella Johanson_2450AT18x100; red C38/L4/C41 y keepout visible en borde. | Especificar MPN exacto, validar área libre en todas las capas, plano de referencia/apilado, impedancia de línea y ajuste con batería/carcasa. DRC y render no miden RF. |
| HW-07 | Alta | U1 huella QKAA personalizada; U2/U3 huellas US recuperadas; J1 variante GCT, SW1 TS24CA y pogo CN1. | Contrastar numeración/pin 1, pads expuestos, máscara/pasta, taladros y cotas con fichas exactas. La paridad numérica no detecta una huella físicamente equivocada. |
| HW-08 | Alta | BOM heredada sin cualificación completa de MPN; L5 tiene valor pero no DCR/Isat garantizados. | BOM comprable con fabricante, MPN, tolerancia, tensión, dieléctrico y DNP. Para BUCK, contrastar L5 y capacidad efectiva con requisitos Nordic. `reports/components.csv` es inventario, no BOM aprobada. |
| HW-09 | Alta | Reglas heredadas: clearance 0.1mm, borde 0.3mm, track mínimo configurado 0, silk clearance 0; vías reales mínimas 0.6/0.3mm y pistas reales mínimas 0.15mm. | Seleccionar fabricante/apilado y establecer reglas DFM explícitas. Se refuerza el mínimo de pista a 0.15mm para evitar regresiones; no se presenta como aceptación de fabricante. |
| HW-10 | Media | USB-C es power-only; SWD por Tag-Connect. Instrucciones heredadas sugieren programación/UART por USB. | Documentación principal corregida: USB no programa esta PCB ni proporciona UART por sí solo. Confirmar acceso mecánico de SWD. |
| HW-11 | Media | Topología separa zonas funcionales, desacoplos próximos y keepout de antena visible; PCB compacta de aprox. 39 × 33mm. | Revisar retornos/loops de conmutación por capa, acoplo de reloj/RF a AFE, térmicas, fijación y acceso a conectores con carcasa real. Inspección visual no equivale a simulación/medición. |
| HW-12 | Bloquea publicación | CERN-OHL-S-2.0 aceptada para hardware propio; licencias de software pendientes, ADI restrictiva, procedencia de CAD/modelos incompleta, logotipo MESSI heredado. | Matriz de derechos y decisión de licencia. Logo retirado de la copia y sustituido por texto Myohm. Ver [licencias](licensing.md). |

## Cambios efectuados en la copia

- Repositorio Git local nuevo, sin historia con datos científicos/personales. Lista explícita de fuentes importadas y hashes; no se borró material de los repositorios originales.
- Rutas de bibliotecas y modelos portables. Se recuperaron los símbolos desde las copias embebidas, incluyendo variantes locales; la recuperación inicial preservó sus tipos eléctricos; después se corrigieron los tipos contrastados con las fichas en la revisión eléctrica enlazada.
- Huellas US copiadas de las instancias de la PCB mediante KiCad. No se presentan como dibujos aprobados por fabricante.
- Se sustituyó el gráfico MESSI por texto Myohm en serigrafía posterior; no se modificaron pistas, vías ni conexiones.
- Firmware del target real: BUCK1 deshabilitado; habilitación de carga retirada; `sensor_attr_set(...SENSOR_CHAN_GAUGE_DESIRED_CHARGING_CURRENT, SENSOR_ATTR_CONFIGURATION, 0)` solicita apagar carga retenida cuando el driver está listo. Error de escritura se registra. No garantiza seguridad ante fallo del bus o antes de inicializar el firmware; no conectar batería desconocida a USB basándose solo en este parche.
- Contrato BLE estático adaptado a firmware+web; no se importan apps Android/iOS para satisfacer pruebas de un monorepo anterior.
- Se mantienen UUIDs, tramas BLE y nombres de target para compatibilidad. La marca pública es Myohm; el prototipo web mantiene su interfaz BioMess identificada como pendiente de migración visual.

## Fuentes primarias consultadas

- [Nordic nPM1304: referencias y PCB](https://docs.nordicsemi.com/r/bundle/ps_npm1304/page/chapters/hw_layout/pegasus_ref_circuitry/frontpage.html).
- [Nordic BUCK](https://docs.nordicsemi.com/r/bundle/ps_npm1304/page/chapters/core_components/buck/doc/frontpage.html): VSET1 a masa desactiva en arranque, VSET2=150k selecciona 3.0V; comprobar componentes y margen de caída.
- [Nordic pinout](https://docs.nordicsemi.com/r/bundle/ps_npm1304/page/pin.html).
- [ADI AD5941](https://www.analog.com/en/products/AD5941.html) y [AN-1557](https://www.analog.com/en/resources/app-notes/an-1557.html): referencia de arquitectura y cálculos, no validación de esta PCB.
- [KiCad 10 esquemáticos](https://docs.kicad.org/10.0/en/eeschema/eeschema.html).
- Drivers locales NCS 3.3.0: `zephyr/drivers/regulator/regulator_npm13xx.c` y `zephyr/drivers/sensor/nordic/npm13xx_charger/npm13xx_charger.c`, usados para verificar semántica de arranque y deshabilitación de carga.

## Dictamen

Se puede continuar el desarrollo y revisión en el repositorio aislado. No hay evidencia suficiente para afirmar que la PCB cumple todos los requisitos o que sea segura sobre personas. La publicación de fuentes y la aprobación de fabricación son gates distintos: la primera depende de licencia/procedencia y documentación honesta; la segunda necesita cerrar diseño eléctrico/DFM y ensayos. La batería desconocida no se puede cualificar mediante software.
