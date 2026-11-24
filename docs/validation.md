# Requisitos y criterios de liberación

Uso previsto confirmado: investigación y enseñanza, sin venta. Esto no exime de validar la seguridad si se conectan electrodos a personas. Primera etapa: cargas patrón de banco, sin sujetos.

## Modos de uso confirmados — 2026-09-24

El diseñador distingue dos escenarios:

- **Banco con cargas R/C, sin conexión a personas:** permitir medición con USB
  conectado. Este modo sirve para caracterización y depuración de laboratorio.
- **Medidas sobre personas:** alimentación por batería, USB desconectado. La carga
  se realiza fuera de estas medidas. Este escenario continúa pendiente de validación.

Criterios de aceptación pendientes de implementación/verificación:

- El modo de banco debe seleccionarse explícitamente e indicar que admite USB y
  que no debe emplearse con personas. La placa no puede inferir por sí sola si la
  carga conectada es un patrón R/C o una persona.
- En el modo para personas, rechazar el inicio con VBUS presente o desconocido;
  si aparece USB durante una medida, detener excitación y adquisición. Medir y
  justificar el tiempo de respuesta antes de aprobar ese comportamiento.
- Comprobar arranque, reinicio, cambios de modo y conexión/desconexión de USB durante
  barrido; impedir que una autorización de banco habilite silenciosamente el otro modo.
- En banco, comparar patrones R/C con batería y con USB para cuantificar diferencias
  de ruido, magnitud y fase; documentar las conexiones de masa de los instrumentos.
- Documentar la retirada de electrodos de la persona antes de cargar como condición
  de uso propuesta para la versión docente. Detener adquisición no desconecta
  físicamente los electrodos ni demuestra aislamiento de los caminos de IC1.

Esta distinción reemplaza la restricción universal de USB formulada antes en esta
misma fecha. Es un requisito, no una protección ya implementada o validada. Permitir
alimentación USB en banco no autoriza habilitar la carga de la batería desconocida.
El firmware contiene detección de VBUS en `board_power.c`; queda pendiente integrar
la política de modos en todas las rutas de medición y validar el comportamiento.

## Requisitos pendientes de cuantificar

- Rango de impedancias, frecuencias, precisión, fase, repetibilidad y duración de barrido.
- Amplitud/corriente máxima por frecuencia; estados de fallo, saturación y electrodos desconectados.
- Modelo exacto de batería, protección, corriente/tensión de carga, temperatura y documentación del proveedor.
- Autonomía objetivo, presupuesto de corriente, ruido de alimentación y comportamiento de apagado.
- Fabricante PCB, apilado, espesor y reglas DFM reales; montaje, encapsulado y tolerancias de carcasa.

## Gates separados

1. **Publicación de fuentes**: titularidad y licencia decididas; derechos de terceros acreditados; revisión de secretos/datos personales; clon independiente abre fuentes y compila; documentación declara los límites reales. Una versión experimental puede publicarse con defectos declarados si supera estos requisitos, sin presentarse como validada.
2. **Fabricación de revisión**: ERC/DRC revisados y exclusiones justificadas por incidencia; huellas verificadas frente a dibujos de fabricante; BOM completa con MPN y tolerancias; apilado/impedancia RF acordados; Gerber, taladros y posiciones generados desde el mismo commit y revisados visualmente.
3. **Validación de banco**: inspección y continuidad sin energía; fuente limitada; tensiones y arranque; corriente idle/medida/BLE; carga y protecciones con batería cualificada; patrones R y RC trazables en todo el rango y temperatura; fugas/DC, ESD y fallos; RF con batería/carcasa.
4. **Uso sobre personas**: análisis de riesgos específico, límites y ensayos de interfaz corporal, aislamiento frente a USB/SWD/instrumentos, revisión competente y requisitos éticos/institucionales aplicables. No se afirma CE/FCC/IEC ni seguridad clínica.

Registrar en cada prueba: revisión PCB, hash firmware, instrumentos/calibración, condiciones, criterio numérico previo, datos crudos, resultado y responsable. Las pruebas BLE simuladas y los tests estáticos no validan la conexión a la PCB física.

## Flujo de contribución y releases

Mantener una revisión de hardware explícita. No reutilizar Gerbers de otra revisión. Cambios de pinout o BLE requieren pruebas de contrato. Preservar informes fallidos y su resolución, sin desactivar reglas para lograr una pantalla verde. Etiquetar firmware y hardware de forma independiente y publicar una matriz de compatibilidad. Publicar artefactos derivados como release después de cerrar su gate; mantener fuentes editables como referencia.
