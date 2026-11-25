# iCloud (copia y muestras de desarrollo)

Contenedor: `iCloud.es.uverse.multimarket` (iCloud Documents). Todo queda en el iCloud de cada usuario; no pasa por nuestro servidor.

- **Copia automática** (Ajustes → Privacidad, opcional): `Copia/multimarket-copia.json` (lista privada, historial, precios). Mismo formato que la copia en archivo.
- **Muestras de tickets** (opción oculta: 7 toques en «Versión»; Ajustes → Desarrollo): `Muestras/AAAA-MM-DD/HHMMSS-fuente/` con `lineas.json`, `resultado.json`, `fragmentos.json` (OCR) e imagen.
- **Borrado automático** (activado por defecto): Inmediato (al volver a abrir la app) · Semanal · Mensual · Trimestral (por defecto) · Anual; botón «Borrar ahora».
- **Revisión desde el Mac:** `dart run tool/revisar_muestras.dart` (por defecto lee
  `~/Library/Mobile Documents/iCloud~es~uverse~multimarket/Documents/Muestras`).

## Configuración (una vez)
1. developer.apple.com → Account → Certificates, Identifiers & Profiles → Identifiers → «+» → **iCloud Containers** → Identifier `iCloud.es.uverse.multimarket`.
2. Identifiers → App IDs → `es.uverse.multimarket` → Capabilities → **iCloud** → Configure → asignar ese contenedor → Save.
3. Xcode → `ios/Runner.xcworkspace` → Runner → Signing & Capabilities: iCloud (iCloud Documents) con el contenedor marcado. `Runner.entitlements` ya está en el repositorio.
4. iPhone: Ajustes → tu nombre → iCloud → iCloud Drive activado.
