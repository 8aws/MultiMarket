# Estudio: diseño adaptativo (iPhone Duo, iPad, escritorio)

Objetivo: preparar para una versión futura un diseño que aproveche el iPhone plegable y, de paso, iPad, macOS y la web.
**Estado: estudio, no hay código.** Basado en la guía oficial «Designing for iPhone Duo» (HIG), pegada por el propietario el
14/10/2026. Documentación de desarrollo: «Preparing your app for iPhone Duo» (technologyoverviews).

## 1. Qué dice la guía oficial
- **Dos pantallas:** exterior (cerrado; más ancha y corta que un iPhone) e interior. Cada una con su cámara frontal.
- **Clases de tamaño en vez de un diseño por pose:** ancho **compacto** para la exterior y **regular** para la interior; la app
  debe crecer con el espacio disponible, sin rediseñarse. También hay **Split View** (dos apps en la interior).
- **Controles verticales:** barras de herramientas, barras de pestañas y navegación pasan a un **lado** para ahorrar altura;
  en horizontal en la interior se quedan al lado. **Excepción:** la interior en vertical conserva las barras horizontales.
  El lado está fijado a la **cámara/hardware** (también en idiomas de derecha a izquierda).
- **Regiones reservadas:** cámara exterior (siempre; se ensancha en la Dynamic Island), cámara interior (solo con la cámara
  activa) y **pliegue** (condicional: al plegar parcialmente divide la interior en zonas usables).
  Alertas, menús contextuales y hojas se apartan solos; las **vistas divididas** ajustan columnas y márgenes.
  Para componentes propios: `ReservedRegion` (SwiftUI) / `UIView.ReservedRegion` (UIKit).
- **Vistas de disposición (`ArrangementView`):** contenedor con vista primaria y secundaria: *split* (divide el espacio, en
  horizontal si es más ancha que alta y en vertical si es más alta) y *overlay* (una sobre otra; al plegar parcialmente, cada
  una a un lado). La navegación va **fuera** del contenedor.
- **Buenas prácticas:** mismo estado y funciones en las dos pantallas; un nivel más de jerarquía en la interior (como Mail: lista
  o correo cerrado, ambos abiertos); cuadrículas con **número par de columnas**; **evitar cambios extremos** al plegar;
  no cambiar la posición por defecto de las barras; prioridad de visibilidad de elementos de barra (primero la acción más
  usada); menú de desbordamiento del sistema; título **y** símbolo en cada botón; pocos botones de solo texto.
- **Herramienta:** Device Hub de Xcode previsualiza la app en el iPhone Duo y en sus poses.

## 2. Qué implica para MultiMarket (Flutter)
La guía promete que, con **componentes estándar del sistema**, la app «se adapta casi sola». MultiMarket dibuja su propia
interfaz (Material en Flutter), así que **no hereda** nada de eso:
- Las barras a un lado, el desplazamiento de hojas/diálogos y las vistas divididas **no son automáticas**: hay que replicarlas.
- Las **regiones reservadas** solo se obtienen por API nativa; Flutter no las expone en iOS (`MediaQuery.displayFeatures`
  está vacío fuera de Android). Haría falta un pequeño **puente nativo** (Swift) que entregue esos rectángulos.
- Lo mínimo para no estropearse: respetar `SafeArea` y no depender de anchos fijos (hoy, parcialmente cierto).
- Hoy MultiMarket es solo iPhone; en un Duo se ejecuta como app de iPhone normal. Hay que **mirarla en Device Hub** antes de prometer nada.

## 3. Propuesta por pantalla
| Pantalla | Compacta (exterior) | Regular (interior abierto, iPad, escritorio) |
|---|---|---|
| Navegación | Barra lateral propia (acciones arriba: atrás / «voy yo» / escáner), el menú actual como lista de destinos | Igual, en el lado de la cámara; en la interior **vertical** se mantienen barras horizontales |
| Lista | Una columna; tarjeta de cesta plegada (poca altura) | **Split**: lista a un lado, **detalle** (ficha, tiendas candidatas, precio y confianza) al otro |
| Por tienda | Cabeceras como ahora | Tiendas con su total a un lado; productos de la tienda y ruta al otro |
| Ficha | Hoja modal | Panel fijo (sin modales) |
| Modo compra | Cámara y resultado alternados | **Overlay/split**: cámara y resultados lado a lado |
| Comparar | Una columna | Dos columnas (producto A / B) con ahorro por kg o litro |
| Historial | Lista por días | Maestro-detalle: días / compra con «Repetir» |
| Ajustes | Lista actual | Categorías y contenido |
| Hojas y diálogos | Pantalla completa | Limitados a **un solo panel**, apartados del pliegue |

Reglas: mismas funciones y estado en todas las poses; movimientos pequeños al plegar; número par de columnas en cuadrículas;
acciones con título y símbolo; la acción más usada («Voy yo», escáner) con mayor prioridad de visibilidad.

## 4. Plan técnico (por fases)
1. **Clases de tamaño propias** (`WindowClass`: compacta / media / expandida) con `LayoutBuilder`. Gana iPad, macOS y web.
2. **Extraer la ficha** de la hoja modal a un widget reutilizable (`FichaProducto`), en panel o en hoja.
3. **`DosPaneles`** (equivalente a un *split arrangement*): reparte el ancho (~40/60) o, si el alto manda, en vertical.
4. **Barras laterales propias** en compacta (reordenación estándar: navegación arriba, acciones principales, resto en menú
   de desbordamiento) y horizontales en la interior vertical.
5. **Puente nativo de regiones reservadas** (SDK de iOS 27.1 o posterior): rectángulos de pliegue y cámaras → alimentan
   `DosPaneles`, hojas y diálogos. Primero evaluar si los paquetes `foldable` / `nitro_fold_duo` bastan.
6. **Pruebas:** ventana redimensionable en macOS y web (ya posible), **Device Hub** con el iPhone Duo cuando Xcode lo incluya
   y un dispositivo real.

Esfuerzo orientativo: fases 1–3 ≈ 4–6 días; fase 4 ≈ 2–3 días; fase 5 ≈ 1–3 días (según API y paquete); fase 6 depende
de las herramientas. Riesgo: replicar a mano lo que UIKit/SwiftUI dan gratis; mitigarlo empezando por lo que no depende de APIs nuevas.

## 5. HomeView (pantalla de hogar con Siri)
No he podido confirmarlo en fuentes públicas. Dato aportado por el propietario (14/10/2026): internamente funciona como un
**destino de CarPlay**, con widgets y audio de CarPlay. Es decir, el camino sería el de CarPlay (plantillas, no interfaz libre)
más widgets; encaja con el widget propuesto y con avisos de voz. Para el futuro:
- **Widget** (WidgetKit) «Lista de la compra»: extensión nativa en Swift + *App Group*; sirve en iPhone, iPad y, probablemente, HomeView.
- **De lejos:** lo que falta, en letra grande y solo lectura, agrupado por tienda; al acercarse, el detalle.
- **Un perfil por persona** encaja con nuestras listas (privada de cada uno + compartidas del hogar).

## 6. Recomendación
1. Fases 1–3 primero: valen para iPad, macOS y web y no dependen de APIs nuevas.
2. Revisar la app actual en Device Hub en cuanto esté disponible, para ver qué se rompe sin tocar nada.
3. Barras laterales y regiones reservadas después, con la API real documentada.
4. Widget como pieza independiente.
5. Para *early adopters*: mencionarlo en la ficha solo cuando esté probado en un dispositivo real.

## 7. Primeras pruebas en el simulador de iPhone Duo (15/10/2026)
Entorno: Xcode 27.0 + runtime iOS 27.2, dispositivo «iPhone Duo» del simulador. La app se instaló desde una copia sin
`google_mlkit_text_recognition` (ML Kit no tiene versión para simulador arm64). Datos de ejemplo.
- **Pantalla exterior:** 466 × 678 pt (1398 × 2034 px a 3×). La app se ejecuta como app de iPhone normal.
- **Barra de estado a un lado:** el sistema mueve hora y estado de red/batería a una **tira vertical a la derecha** (~17 % del ancho)
  y recorta el contenido con esquina redondeada. Flutter respeta esa zona: **nada queda debajo de la tira**.
- **Nuestras barras** (AppBar y menú propios) siguen horizontales arriba. Funciona, pero no sigue el patrón del sistema.
- **Hallazgos a corregir:**
  1. El botón «+» tapa el importe de las últimas filas (también pasa en iPhone con la lista larga).
  2. Los filtros («Todo / Solo fríos / Sin refrigerar») quedan cortados por el borde; se desplazan, pero «Sin refrigerar» se corta.
  3. La **ficha** (hoja modal) ocupa toda la altura y su último bloque (tienda) queda cortado hasta hacer scroll.
  4. Con el ancho mayor, la lista queda con mucho aire entre nombre e importe: mejor candidata a dos paneles.
- **Pendiente de probar:** pantalla interior abierta y poses parcialmente plegadas (el simulador expone dos pantallas; la
  interior sale en negro con el dispositivo cerrado). Requiere el control de pose de Device Hub (interfaz gráfica).
- **Aviso práctico:** los dos simuladores iPhone Duo se comparten entre hilos de trabajo (MultiMarket, OneDay, LoyWallet,
  uFeed); usar uno distinto por proyecto para no pisarse.

## 8. Primera implementación (20/10/2026, versión 1.1.0)
Hecho (fases 1–3 del plan, sin depender de APIs nuevas):
- `lib/ui/adaptativo.dart`: clases de tamaño por ancho (compacta < 600, media < 840, expandida) y umbral de **dos paneles a 700 dp**.
- La **ficha de producto** es ahora un widget reutilizable (`FichaProducto`): hoja modal en pantallas estrechas y **panel fijo** en las anchas.
- **Pantalla principal en dos paneles** (lista 5/9 · detalle 4/9) con el producto elegido resaltado; en pantallas estrechas todo sigue igual.
- Los **filtros** (Todo / Solo fríos / Sin refrigerar) pasan a otra línea en lugar de cortarse; la hoja usa `useSafeArea`.
- Pruebas: tests de widget a 1000 y 420 px (panel vs hoja) y comprobación visual en el navegador a 900 px.

Pendiente: barras laterales propias (fase 4), puente nativo de regiones reservadas (fase 5), modo compra y comparar en dos columnas,
historial y ajustes en maestro-detalle. **Pantalla interior del iPhone Duo:** en el simulador se pueden encender/apagar las pantallas
(`xcrun simctl io <dispositivo> screenConfig --display=primary-1 power on`; `primary` = exterior 1398×2034, `primary-1` = interior
2007×2853), pero la captura de la interior falla y no se puede cambiar la pose desde la línea de comandos: hay que usar la interfaz
de Device Hub. Con el ancho de la interior (≈ 670 pt @3x) el diseño de dos paneles se activaría (umbral 700 dp); **falta medirlo**.
