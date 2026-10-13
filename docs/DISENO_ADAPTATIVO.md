# Estudio: diseño adaptativo (iPhone Duo y pantallas grandes)

Objetivo: preparar para una versión futura un diseño que aproveche el iPhone plegable y, de paso, iPad, macOS y la web.
**Estado: estudio, no hay código.** Fecha del estudio: 13/10/2026.

## 1. Qué se sabe (y qué no)
Fuentes secundarias (no he podido abrir la página de Apple); contrastar con la HIG «Designing for iPhone Duo» antes de implementar.
- Apple publicó guía específica en la HIG. Dos *size classes*: **compacta** (pantalla exterior, más ancha y corta que un iPhone) y
  **regular** (pantalla interior). Los diseños deben responder al **espacio disponible**, no al modelo.
- La pose (cerrado, abierto, parcialmente plegado) no debe tener pantallas propias: un único diseño adaptativo.
- Los controles estándar del sistema (barras, menús, alertas) se apartan solos del pliegue; en la pantalla exterior las barras
  pasan a una **tira vertical** lateral para ahorrar altura.
- Zonas reservadas (pliegue, cámara): el contenido crítico no debe quedar bajo ellas. Las APIs (`ReservedRegion`, etc.) llegarían
  con el SDK de iOS 27.1; nombres y detalles **sin confirmar**.
- Fechas de salida contradictorias entre fuentes (anuncio 9/9; venta ~23/10/2026). **HomeView** no he podido confirmarlo en
  ninguna fuente: tratarlo como no verificado.
- **Flutter:** `MediaQuery.displayFeatures` solo se rellena en Android; en iOS está vacío. Existen paquetes pequeños y muy nuevos
  (`foldable`, `nitro_fold_duo`, `iphone_duo_ui_pro`) que añaden la geometría del pliegue por canal nativo (requieren SDK 27.1).
  Hay que evaluar su madurez antes de depender de ellos; la alternativa es un canal propio.

## 2. Cómo es MultiMarket hoy
- Una sola columna: `AppBar` + `Drawer` + lista; la ficha de producto, el cambio de tienda y los ajustes rápidos son
  **hojas modales** (`showModalBottomSheet`); modo compra, comparar e historial son páginas completas.
- Solo iPhone (`TARGETED_DEVICE_FAMILY = 1`); en web y macOS se estira la misma columna.
- No hay puntos de ruptura ni widgets «de dos paneles».

## 3. Propuesta por pantalla
| Pantalla | Compacta (exterior / iPhone) | Regular (interior abierto, iPad, escritorio) |
|---|---|---|
| Lista | Como ahora; tarjeta de cesta plegada por defecto (poca altura) | **Dos paneles**: lista a la izquierda, **detalle** a la derecha (ficha, tiendas candidatas, precio y confianza) |
| Por tienda | Cabeceras de tienda como ahora | Panel izquierdo: tiendas con su total; derecho: productos de la tienda elegida y botón de ruta |
| Ficha de producto | Hoja modal (como ahora) | Panel fijo; sin modales |
| Modo compra | Cámara y resultado alternados | **Cámara a un lado, resultados y equivalentes al otro** |
| Comparar | Una columna con scroll | **Dos columnas** (producto A / B) con el ahorro por kg o litro |
| Historial | Lista por días | Maestro-detalle: días / compra con «Repetir» |
| Ajustes | Lista actual | Categorías a la izquierda, contenido a la derecha |
| Diálogos y hojas | Pantalla completa | Limitados a **un solo panel**, nunca a caballo del pliegue |

Reglas generales: ningún control crítico bajo el pliegue ni la cámara; tipografías y objetivos táctiles iguales en ambos
tamaños; estado compartido entre paneles (seleccionar en uno actualiza el otro); un único árbol de widgets para todas las poses.

## 4. Plan técnico (por fases)
1. **Clases de tamaño propias** (`WindowClass`: compacta < 600 dp, media 600–840, expandida ≥ 840) con `LayoutBuilder`; sin
   depender del dispositivo. **Gana también iPad, macOS y web.**
2. **Extraer la ficha** de la hoja modal a un widget reutilizable (`FichaProducto`) que se pinta en un panel o en una hoja.
3. **`DosPaneles`**: widget maestro-detalle que, en expandida, reparte el ancho (≈ 40/60) y, si hay un pliegue, **parte justo
   por el pliegue** dejando una banda sin contenido. Sin información de pliegue: reparto fijo.
4. **Datos del pliegue en iOS** (cuando exista el SDK 27.1): paquete evaluado o canal propio que entregue
   rectángulos del pliegue/cámara; alimentar `DosPaneles` y los diálogos.
5. **Pruebas:** ventana redimensionable en macOS/web (ya posible hoy), simulador de iPhone Duo cuando Xcode lo incluya, y
   dispositivo real para el early adopter.

Esfuerzo orientativo: fases 1–3 ≈ 4–6 días; fase 4 ≈ 1–2 días (más si el paquete no es estable); fase 5 depende de herramientas.
Riesgo principal: APIs sin documentar y paquetes inmaduros → empezar por lo que no depende de ellas (fases 1–3).

## 5. HomeView (pantalla de hogar con Siri) — hipótesis
Si se confirma y admite apps de terceros o widgets:
- **Modo «de lejos»**: lista de lo que falta en letra grande, solo lectura, agrupada por tienda; al acercarse, detalle (precio, cantidad).
- **Un perfil por persona** encaja con nuestras listas: lista privada de cada uno + listas compartidas del hogar.
- **Widget** (WidgetKit) «Lista de la compra»: sirve en iPhone, iPad y, probablemente, en HomeView. Requiere una extensión
  nativa en Swift y compartir datos por *App Group*; es la vía más realista para estar en HomeView sin una app completa.

## 6. Recomendación
1. Hacer primero las **fases 1–3** (valen para iPad, macOS y web y no dependen de APIs nuevas).
2. Añadir la **conciencia de pliegue** cuando el SDK esté publicado y haya simulador o dispositivo.
3. Valorar el **widget** como pieza aparte (también útil en el iPhone normal).
4. Para los *early adopters*: indicarlo en la ficha solo cuando esté probado en un dispositivo real.
