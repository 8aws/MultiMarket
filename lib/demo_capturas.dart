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
