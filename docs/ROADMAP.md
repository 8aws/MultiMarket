# Hoja de ruta (después de la versión 1.0)

Lo de la 1.0 está en el README. Aquí queda lo acordado para versiones posteriores, en el orden previsto.

## 1.0.1 (20/10/2026)
- Tiendas cercanas: varios servidores de Overpass con respaldo escalonado (el principal se saturó) y mensajes de error distintos
  (mapas ocupado / sin ubicación / sin permiso). Para muchos usuarios convendrá una **caché propia** de tiendas por zona en el servidor.
- Tickets: OCR nativo de Apple (Vision) en lugar de ML Kit (la app pesa 18 MB menos y se puede probar en simulador); el lector
  entiende tablas de Supercor/El Corte Inglés, pesos sin «EUR/kg», totales sin etiqueta (fila «Suma» / «IMP.»), letras de IVA mal
  leídas y nombres perdidos; las líneas se pueden **corregir, quitar o añadir a mano** antes de aplicar.

## 1.1 · Ticket después de la compra (casar con la lista)
Al importar o escanear un ticket **después** de haber comprado:
1. **Casar con la lista, también con lo ya marcado como comprado** (hoy y ayer): rellenar precio, cantidad y tienda reales
   del ticket en los productos ya marcados, y marcar como comprados —con el precio del ticket— los que se quedaron
   pendientes. Solo cuando el emparejamiento es seguro; lo dudoso se pregunta.
2. **Ticket repetido:** detectar que ya se importó (cadena + fecha + total) y no duplicar compras.
3. **Diferencias de precio:** avisar si se pagó más que el precio anotado, o más que en otra tienda que usa.
4. **Lo que no salió en el ticket:** si algo marcado como comprado no aparece, preguntar si se quedó sin comprar y devolverlo a pendiente.
5. **Compras no planificadas:** lo que sale en el ticket y no estaba en la lista pasa al catálogo y al historial, y alimenta la recompra con fechas y cantidades exactas.
6. **Tienda correcta:** la cadena impresa en el ticket manda sobre el GPS al atribuir la compra.
7. **Resumen de ahorro:** lo pagado frente a la opción más barata que habría propuesto la app.
8. **Foto del ticket con la cámara** (`permitirFotoTicket`) cuando el OCR de fotos sea fiable.

## 1.2 · Información nutricional (fase 1, tras la beta)
- Mostrar valores de Open Food Facts en la ficha (por 100 g / 100 ml; extrapolar al envase) y Nutri-Score.
- Después: comparar por nutriente («más proteína por euro»).

## Emplazamientos de compra (idea, sin diseñar)
Poder organizar los supermercados **por lugares** que el usuario define: «cerca de casa», «cerca del trabajo», «cerca del gimnasio»,
«casa de verano», «casa de los abuelos»… y elegir en cada momento con cuál se compra (o «ubicación actual» para compras rápidas).
Cada emplazamiento tendría su propia lista de tiendas (fijada, con aviso al actualizarla), su radio y sus preferencias.
Preguntas abiertas: ¿una lista de la compra por emplazamiento o una sola que reparte por tienda según dónde estés?; cómo elegir el
emplazamiento activo (manual, por GPS al llegar, por horario); y cómo se comparte con una lista compartida. Aprovecha que la lista
de supermercados ya está fijada y la caché de OpenStreetMap por zonas (cada emplazamiento = una celda más).

## Diseño adaptativo (iPhone Duo, iPad, escritorio)
Estudio en `docs/DISENO_ADAPTATIVO.md`: clases de tamaño, maestro-detalle (lista + ficha), modo compra y comparar en dos
columnas, conciencia de pliegue cuando exista el SDK 27.1, y un widget (WidgetKit) como posible vía para HomeView.

## Más adelante (pendiente de decidir)
- **Reconocimiento avanzado en el servidor** (tickets y etiquetas nutricionales): cola asíncrona con modelo propio
  (OpenVINO sobre iGPU/NPU), aviso con la imagen y los valores para validar, referencia siempre por 100 g. Requiere
  avisar al usuario de que la imagen se envía al servidor y se borra al terminar, y resolver el riesgo de que contenga
  datos privados. Primero confirmar con infra el hardware y la pila.
- **Notificaciones push** nativas (FCM / APNs) para «voy yo» y avisos con la app cerrada.
- **Loywallet:** abrir directamente la tarjeta de la cadena (necesita un esquema de URL en Loywallet).
- **Descuentos generales por tienda** (p. ej. 5 % de socio), a meditar.
- **Sincronización:** espaciar el sondeo (~3 min) cuando el tiempo real esté conectado.
- Pasillos y ruta en tienda, votos de la comunidad, Android, Windows y Linux.
