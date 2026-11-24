# Licencias y procedencia

Myohm es una plataforma de investigación y enseñanza. Uso licencias por componente; no hay una licencia global para todo el repositorio. El alcance exacto está en [LICENSE.md](../LICENSE.md).

## Hardware propio

El diseño original de `hardware/mainboard/` y, desde el 2026-10-14, `hardware/electrodes/` (conexiones del circuito, layout, configuración del proyecto y lista de materiales) se publica bajo CERN-OHL-S-2.0 desde el 2026-09-28. La licencia permite fabricar y vender derivados, pero exige que las mejoras distribuidas se publiquen con los mismos términos. No se extiende al software ni a material de terceros.

Texto oficial conservado sin cambios en `LICENSES/CERN-OHL-S-2.0.txt`; SHA-256 `253ad3f89603e728abfa60c36fbcaf8225cf55c1eab12725f19fb3d74d647f3a`. Fuente: https://ohwr.org/licences/.

Por qué esta licencia y no otra:

| Objetivo | Opción | Consecuencia |
| --- | --- | --- |
| Mantener abiertas las mejoras distribuidas | CERN-OHL-S-2.0 | Permite fabricación y venta con reciprocidad. Elegida. |
| Prohibir uso comercial | Licencia no comercial propia | Sería código disponible, no open source. La [definición OSHWA](https://oshwa.org/definition/) exige permitir fabricar y vender derivados, y [CERN OHL](https://ohwr.org/licences/) no tiene variante no comercial. |
| Evitar que lo divulgado se patente como nuevo | Publicación técnica fechada y suficiente | Aporta estado de la técnica según las [directrices EPO](https://www.epo.org/en/legal/guidelines-epc/2026/g_iv_1.html); no garantiza libertad de operación. |

## Material de terceros

- **Código de Analog Devices** (`firmware/nrf5340_zephyr/src/ad5940/`): conserva sus avisos originales. La [licencia upstream](https://github.com/analogdevicesinc/ad5940lib/blob/master/LICENSE) limita el uso a productos ADI; el texto está en `LICENSES/LicenseRef-ADI-reference.txt` y es idéntico byte a byte al de la revisión upstream `818c54822ad35c57ec277e1503cd45e9dc4e554f` ([comparación](../reports/adi-provenance.json)). `ad5940.c` y `ad5940.h` difieren de esa revisión. No se relicencia como MIT, Apache ni GPL.
- **Símbolos y huellas** (`hardware/library/`, `Messi.pretty`, `US.pretty` y sus copias embebidas en esquema y PCB): proceden de recursos gratuitos de fabricantes y portales de CAD (SnapEDA, Mouser/SamacSys y similares) y de diseños de referencia. No quedan cubiertos por CERN-OHL-S-2.0. El responsable confirmó el 2026-10-14 que solicitó y obtuvo el permiso de publicación de los recursos CAD. Se registra esa confirmación; la correspondencia de aprobación no fue revisada de forma independiente en esta auditoría. No se mantiene como bloqueo por falta de permiso. Inventario con hashes en [third-party-cad.csv](third-party-cad.csv).
- **Modelos 3D** (`hardware/3D/`): modelos importados incluidos en la confirmación de permiso del responsable; conservan los términos y atribuciones aplicables.
- **Bibliotecas estándar de KiCad**: se usan desde la instalación de KiCad 10; se respeta su licencia y excepción.

## Pendiente

- Las licencias del hardware y software propio ya están elegidas y aplicadas localmente. No se ha concedido una licencia nueva a documentación narrativa ni datos.
- Cerrar inventario transitivo y avisos de los artefactos finales antes de publicarlos.
- Avisos de modificación ADI incorporados; falta identificar la revisión original exacta de los ejemplos importados.
- Añadir la URL exacta de descarga de cada símbolo, huella y modelo cuando esté disponible.

## Software propio: decisión del 14 de octubre de 2026

Apache-2.0 se aplica a las contribuciones originales de firmware, apps iOS/Android/web y scripts. Los avisos locales de cada componente delimitan el alcance; ADI, Nordic y demás terceros conservan sus términos. Véase `../THIRD_PARTY_NOTICES.md`. No equivale a una licencia Apache de todo el binario.

## Aclaración del responsable — 2026-10-14

El objetivo es que cualquiera pueda utilizar el diseño y el software mediante
licencias abiertas estándar, sin redactar una licencia propia. El responsable
confirma que los permisos de los archivos CAD fueron solicitados y aprobados.
Se acepta esta confirmación como base de publicación; completar URLs y referencias
del inventario es una mejora de trazabilidad, no una nueva solicitud de permiso.

La licencia ADI permite redistribución de fuentes y binarios bajo sus condiciones.
Su presencia no impide por sí sola publicar Myohm: deben conservarse los avisos,
marcarse modificaciones y respetarse la restricción a productos ADI. El diseño
utiliza AD5941. No hace falta sustituir esa dependencia para publicar las fuentes
con sus condiciones correctamente delimitadas.

Recomendación: mantener Apache-2.0 para software original y CERN-OHL-S-2.0 para
hardware original; añadir CC-BY-4.0 para documentación e ilustraciones propias.
CERN-OHL-S permite uso comercial y exige reciprocidad al distribuir derivados;
si se prefiere permitir también derivados cerrados, CERN-OHL-P-2.0 es la variante
permisiva a considerar. Esta recomendación no cambia por sí sola las licencias
ya concedidas ni aplica todavía CC-BY-4.0.

Conservar la autoría real y los avisos de terceros. Para privacidad, se recomienda
un correo GitHub noreply en el historial público, sin borrar los nombres ni los
créditos. No se ha reescrito el historial.
