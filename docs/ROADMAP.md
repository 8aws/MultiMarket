# Hoja de ruta (después de la versión 1.0)

Lo de la 1.0 está en el README. Aquí queda lo acordado para versiones posteriores, en el orden previsto.

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
