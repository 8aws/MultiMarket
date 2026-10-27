// Datos de ejemplo SOLO para hacer las capturas de la ficha de la tienda.
// Se activan compilando con --dart-define=MM_CAPTURAS=1; en una compilación normal este código no se ejecuta.
import 'models.dart';
import 'sources.dart';
import 'state.dart';

const capturasActivas = bool.fromEnvironment('MM_CAPTURAS');

Future<void> sembrarCapturas(AppState s) async {
  if (s.items.isNotEmpty) return;
  s.cfg.alias = 'Ana';
  final nombres = <(String, int)>[
    ('Leche entera 1L', 1),
    ('Yogur natural x4', 2),
    ('Pechuga de pollo 1kg', 1),
    ('Huevos docena', 2),
    ('Plátanos 1kg', 2),
    ('Pan de molde', 3),
    ('Arroz 1kg', 3),
    ('Aceite de oliva 1L', 2),
    ('Tomate frito', 3),
    ('Papel higiénico 12u', 3),
  ];
  for (final (n, urg) in nombres) {
    final p = demoCatalog.firstWhere((x) => x.name == n);
    final it = s.add(p);
    it.urg = urg;
    final ops = await s.options(p);
    if (ops.isNotEmpty) s.assign(it, ops.first);
  }
  // un par ya comprados, para que se vea la cesta
  for (final it in s.items.where(
    (i) => i.name == 'Huevos docena' || i.name == 'Pan de molde',
  )) {
    s.toggleDone(it);
  }
  // compras de meses anteriores, para el historial plegable (año > mes > ticket)
  final antes = <(int, String, String, double, int)>[
    // (días atrás, tienda, producto, precio, cantidad)
    (9, 'Mercadona', 'Leche entera 1L', 0.89, 6),
    (9, 'Mercadona', 'Arroz 1kg', 1.35, 2),
    (9, 'Mercadona', 'Tomate frito', 1.10, 3),
    (24, 'Lidl', 'Pan de molde', 1.29, 1),
    (24, 'Lidl', 'Yogur natural x4', 1.15, 2),
    (24, 'Lidl', 'Plátanos 1kg', 1.69, 1),
    (49, 'Dia', 'Aceite de oliva 1L', 7.49, 2),
    (49, 'Dia', 'Huevos docena', 2.45, 1),
    (84, 'Mercadona', 'Pechuga de pollo 1kg', 6.90, 1),
    (84, 'Mercadona', 'Papel higiénico 12u', 4.95, 1),
    (160, 'Carrefour Express', 'Leche entera 1L', 0.95, 6),
    (160, 'Carrefour Express', 'Atún en lata x3', 3.60, 2),
    (410, 'Aldi', 'Detergente', 5.20, 1),
    (410, 'Aldi', 'Arroz 1kg', 1.25, 3),
  ];
  var n = 0;
  for (final (dias, tienda, nombre, precio, qty) in antes) {
    s.compras.add(
      Compra(
        id: 'demo${(n++).toString().padLeft(11, '0')}',
        itemId: 'demo$n',
        key: nombre.toLowerCase(),
        name: nombre,
        qty: qty,
        price: precio,
        storeName: tienda,
        storeId: 'demo:${tienda.toLowerCase()}',
        ms: DateTime.now()
            .subtract(Duration(days: dias, hours: 3))
            .millisecondsSinceEpoch,
      ),
    );
  }
  s.addOffer(
    Offer(
      key: 'aceite de oliva 1l',
      name: 'Aceite de oliva 1L',
      chain: s.stores.first.chain,
      price: 6.49,
      until: DateTime.now().add(const Duration(days: 4)),
    ),
  );
  s.changed();
}
