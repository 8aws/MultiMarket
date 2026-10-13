# Publicar MultiMarket en la App Store (iPhone)

Todo lo técnico del paquete está listo y el IPA compila (`build/ios/ipa/*.ipa`, 49 MB). Lo que sigue son pasos en
App Store Connect, que haces tú con tu cuenta.

## 1. Datos del paquete (ya fijados en el proyecto)
| Campo | Valor |
|---|---|
| Bundle ID | `es.uverse.multimarket` |
| Nombre bajo el icono | MultiMarket |
| Nombre en la App Store | MultiMarket: Lista de súper |
| Versión / build | 1.0.0 (1) — súbele el build en cada envío: `flutter build ipa --release --export-method app-store --build-number=2` |
| iOS mínimo | 16.0 |
| Dispositivos | solo iPhone (no pide capturas de iPad) |
| Idioma de la interfaz | español (España) |
| Cifrado | solo HTTPS estándar: `ITSAppUsesNonExemptEncryption = NO` ya incluido |
| Privacy manifest | `ios/Runner/PrivacyInfo.xcprivacy` (sin seguimiento; ID de usuario, contenido de usuario y fotos, funcionalidad de la app) |

## 2. Antes de crear la app
1. **Certificates, Identifiers & Profiles → Identifiers → +** → App IDs → App → descripción «MultiMarket», Bundle ID
   explícito `es.uverse.multimarket`. Sin capacidades especiales por ahora (push se añadirá en una versión futura).
2. Tu **Team ID** ya está en `ios/Flutter/Signing.xcconfig` (ignorado por Git), que es lo que usa la firma automática.

## 3. Crear la app en App Store Connect (My Apps → +)
- **Plataformas:** iOS · **Nombre:** `MultiMarket: Lista de súper` (aceptado; «MultiMarket» a secas ya existe). Bajo el icono sigue saliendo «MultiMarket»
- **Idioma principal:** español (España) · **Bundle ID:** `es.uverse.multimarket`
- **SKU:** `multimarket-ios-001` · **Acceso:** completo

## 4. Ficha (copiar y pegar)
- Textos en español: `store/ficha_es.md` · en inglés (U.S./U.K.): `store/ficha_en.md`
- Capturas iPhone: `store/capturas_iphone_6.3/` (**1206 × 2622**, tamaño que acepta App Store Connect ahora) y
  `store/capturas_iphone_6.9/` (1320 × 2868). Sube las 5 de `6.3` en este orden: lista, tienda, menú, ficha, oscuro.
  Las vistas previas (vídeo) son opcionales: 886 × 1920 o 1920 × 886.
- Imagen de cabecera 21:9: `store/cabecera_3840x1646.png` · resultados de búsqueda 3:2: `store/busqueda_3840x2560.png`
- URLs: soporte y marketing `https://multimarket.uverse.es/info/` · privacidad `https://multimarket.uverse.es/privacidad/`
- **Categoría:** Compras (principal) y Estilo de vida · **Precio:** gratis · **Disponibilidad:** España (amplía luego si quieres)
- **Derechos de contenido:** «contiene contenido de terceros» (Open Food Facts, Open Prices y OpenStreetMap, licencia ODbL).
- **Clasificación por edades:** sin contenido objetable; contenido generado por usuarios con moderación previa → 4+.
- **Privacidad de la app:** respuestas en `store/etiquetas_privacidad.md` (revísalas, son una declaración tuya).
  Añade «Contenido del usuario → Otro contenido» por los precios que se aportan de forma anónima desde los tickets.
- **Información de revisión:** contacto (tu nombre, teléfono y multimarket@uverse.es). No hace falta cuenta ni contraseña.
  Notas para el revisor: ver el final de `store/ficha_es.md`.
- **Contenido generado por usuarios (guideline 1.2):** moderación previa, botón «Reportar», sanciones progresivas y contacto.

## 5. Subir el build
```bash
flutter build ipa --release --export-method app-store
open build/ios/ipa            # arrastra el .ipa a la app Transporter y pulsa «Entregar»
```
(o `xcrun altool --upload-app --type ios -f build/ios/ipa/*.ipa --apiKey … --apiIssuer …`).
El build tarda unos minutos en aparecer en TestFlight.

## 6. TestFlight (beta de una semana) y envío
1. TestFlight → Pruebas internas: añade tu ID de Apple y a las 2–3 personas de la beta.
2. Cuando la beta esté bien: versión 1.0 → elegir el build → «Añadir para revisión».
3. Primera revisión: 24–48 h habitualmente. Si piden cambios suelen ser de ficha o de moderación.

## 7. Comprobaciones previas al envío
- [ ] Probar en el iPhone una sanción real desde moderación y «reportar foto».
- [ ] Probar una sincronización con dos dispositivos de personas distintas.
- [ ] Confirmar que la política de privacidad dice lo que hace la versión enviada (precios de tickets, errores, copia).
- [ ] Activar el interruptor `permitirFotoTicket` solo cuando el OCR de fotos esté a punto (ahora desactivado).
- [ ] Comprobar que el backup diario y el pull del QNAP siguen funcionando.
