# Myohm teaching laboratory

This is an isolated fork of the original BioMess teaching prototype. The deployed BioMess application is maintained separately. UI identifiers remain compatible with BioMess devices; this module has not yet undergone the Myohm visual rebrand.


Aplicación React/PWA independiente para la práctica de bioimpedancia. El navegador se comunica directamente con la PCB; no hay servidor de medidas, cuentas ni subida de datos. Fuente de hardware de esta distribución: [`hardware/mainboard`](../hardware/README.md).

## Desarrollo

Requiere Node.js 22 y npm.

```sh
cd web
npm ci
npm run dev
npm test
npm run build
npm run preview
```

Abre la dirección que imprime Vite. Para PCB real usa Chrome en macOS o Chrome/Edge en Windows con Web Bluetooth, HTTPS o localhost y Bluetooth activo. Safari y Firefox pueden usar la simulación, pero no se ofrecen para conexión BLE. El selector debe abrirse desde el botón Conectar PCB. Cierra la app móvil si ya ocupa la placa. Mantén visible la pestaña durante el barrido.

## Organización

- `src/ble`: transporte GATT, configuración efectiva y reconstrucción de notificaciones.
- `src/core`: magnitud/fase a R+jX, simulación, repetibilidad y exportación.
- `src/components`: gráficas y guía docente.
- `src/App.tsx`: flujo de conexión y medición.

Son módulos independientes: `core` no depende de React ni de Bluetooth. Un futuro transporte nativo puede mantener la interfaz y los cálculos.

El contrato procede de [ble-protocol.md](../firmware/nrf5340_zephyr/docs/ble-protocol.md) y del firmware C actual. No se cambia RCAL, no se solicita auto-medida ni sincronización de registros almacenados. El historial se guarda en `localStorage` del navegador y persiste al recargar; no es almacenamiento cifrado de investigación ni copia de seguridad. Otros scripts del mismo origen pueden acceder a él. Usá un origen dedicado, evitá datos personales y borrá el historial/datos del sitio en equipos compartidos. Exportá una copia si necesitás conservarlo. El modo simulado se identifica en la interfaz y las exportaciones.

## Publicación e integración con academicweb

Construye con `npm ci && npm run build` y publica **el contenido de `web/dist`** en un host estático HTTPS. No requiere variables secretas. El `base` relativo permite una raíz de subdominio o una subcarpeta. Para un subdominio en un proyecto Vercel, establece Root Directory `web`, Build Command `npm run build`, Output Directory `dist`. Asigna después el dominio elegido y verifica HTTPS.

La web académica puede enlazar la aplicación mediante `NEXT_PUBLIC_BIOMESS_LAB_URL`; configura la URL efectiva cuando el despliegue esté listo. No incrustar en un iframe: el laboratorio se abre como página propia para permisos Bluetooth y su PWA. La implementación local no publica ni modifica DNS.

El manifiesto y el service worker se generan solo en producción. Tras una primera visita en línea, la aplicación y la simulación pueden abrirse sin red. La disponibilidad del adaptador BLE sigue dependiendo del sistema y navegador. Las actualizaciones del service worker esperan a cerrar las ventanas de la versión anterior, evitando recargar un barrido activo. En desarrollo no se registra service worker.

## Validación de aceptación con PCB

La batería se lee al conectar; no es un indicador continuo. Una exportación completa requiere recibir todos los bytes esperados. Un fallo de recepción obliga a reconectar porque el protocolo no tiene identificadores ni delimitadores de trama.

1. Chrome en Mac: conectar PCB actual, verificar serie/batería y medir un patrón conocido con configuración inicial.
2. Repetir con 2 puntos/1 repetición y 100 puntos/10 repeticiones. Verificar longitud, valores y configuración efectiva en JSON.
3. Comparar CSV contra la app móvil y el patrón, incluyendo signo de fase y unidades. La app móvil debe desconectarse antes de usar la web.
4. Apagar o alejar la PCB durante un barrido: debe fallar sin exportar datos parciales como completos; reconectar y repetir.
5. Repetir las pruebas en Chrome/Edge de Windows.
6. Instalar la PWA desde el navegador que lo permita y comprobar inicio sin red tras una primera carga de producción.

Estas pruebas físicas requieren una PCB encendida y aún no equivalen a las pruebas automatizadas con GATT simulado. El prototipo docente no realiza ajuste de parámetros Cole-Cole ni demuestra exactitud por sí solo: Nyquist muestra R frente a −X, conservando escala idéntica en ambos ejes.

Documentación Web Bluetooth: https://developer.chrome.com/docs/capabilities/bluetooth

## Nombre anunciado de la PCB

La placa verificada el 2026-09-08 se anuncia como **Messi-06**, configurado por `firmware/nrf5340_zephyr/label.conf` y confirmado en la `.config` del build. `BioMess` es solo el nombre por defecto. El firmware actual no anuncia AF00: se descubre por nombre y se valida el servicio GATT al conectar. El selector admite `Messi-` y `BioMess`; elegir **Messi-06** para esta placa.

## Licencias del paquete web

`npm run build` genera `dist/THIRD_PARTY_NOTICES.txt` con los textos exactos de las dependencias de ejecución y del service worker, más Apache-2.0 para el software propio. Conservá ese archivo al desplegar o redistribuir `dist/`. El lockfile fija también las dependencias de desarrollo.
