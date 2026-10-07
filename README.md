# MultiMarket

Lista de la compra multi-supermercado para España. Eliges tus súper (por cercanía, cadena o
preferencia), añades productos y la app te propone dónde comprar cada uno según **precio,
distancia o preferencia**. Marca blanca y productos exclusivos se asignan a su cadena.

- **Vista por compra** o **por tienda**, siempre ordenadas por urgencia.
- **Filtro de frío**: solo refrigerados, solo no refrigerados, o todo.
- **Cesta** con total comprado / pendiente.
- **Temporizador de frío**: arranca al marcar como comprado el primer producto refrigerado,
  avisa a los 20 min y cuando quedan 10 min. Ajustable (bolsa isotérmica / petaca) o desactivable.
- **GPS** para tiendas cercanas y apertura en Google Maps, Waze, Apple Maps u OpenStreetMap.
- Multiplataforma con Flutter: iOS, Android, web, macOS, Windows y Linux.

## Datos: libres y sin scraping

| Dato | Fuente | Licencia |
|---|---|---|
| Tiendas | [OpenStreetMap](https://www.openstreetmap.org) (Overpass) | ODbL |
| Productos / códigos de barras | [Open Food Facts](https://world.openfoodfacts.org) | ODbL |
| Precios | [Open Prices](https://prices.openfoodfacts.org) | ODbL |
| Precios anotados por el usuario | Local en el dispositivo | — |

No se usa scraping ni APIs no públicas de cadenas. Cada precio muestra su **fecha y origen**.
Los datos abiertos de precios en España son aún escasos: hay un modo «precios de ejemplo»
(etiquetados como tal) para poder probar la app.

### Estado y hoja de ruta
- Hecho: listas privadas y compartidas (PocketBase), fotos y productos nuevos con moderación, escáner de códigos,
  cantidad e historial de compras, política de privacidad y borrado de cuenta, copias de seguridad diarias.
- Próximo: recompra (sugerencias «fantasma» a partir del historial), OCR de tickets en el dispositivo,
  modo escáner durante la compra, comparativa de productos por precio/kg o litro, pasillos, API pública de la base común.
- Servidor: ver `server/README.md`. Los datos privados (servidor, correo de administración) van **fuera** del repositorio,
  en `../MultiMarket-privado/config.env`.

## Desarrollo

```bash
flutter pub get
flutter run -d chrome     # web
flutter run -d ios        # simulador / iPhone
flutter test
```

`prototype/index.html` es el prototipo web original de una sola página.

## Licencia

MIT. Los datos de terceros conservan sus licencias (ver tabla).
