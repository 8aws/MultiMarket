// Reconocimiento de productos a partir de datos abiertos (Open Food Facts).
// Funciones puras: no hacen red, para poder probarlas.
import 'models.dart';

/// Cantidad normalizada a g, ml o unidades («ud»): «1,5 L» → (1500, 'ml'), «400 g» → (400, 'g'),
/// «3 x 125 g» → (375, 'g'), «6 uds» → (6, 'ud'). Null si no se entiende.
({double n, String u})? parseQuantity(String? q) {
  if (q == null) return null;
  final s = q.toLowerCase();
  double? num(String? x) =>
      x == null ? null : double.tryParse(x.replaceAll(',', '.'));
  ({double n, String u}) norm(double n, String u) => switch (u) {
    'kg' => (n: n * 1000, u: 'g'),
    'g' => (n: n, u: 'g'),
    'l' => (n: n * 1000, u: 'ml'),
    'cl' => (n: n * 10, u: 'ml'),
    'ml' => (n: n, u: 'ml'),
    _ => (n: n, u: 'ud'),
  };
  // pack: «3 x 125 g», «4×200ml»
  final pack = RegExp(
    r'(\d+)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*(kg|g|ml|cl|l)\b',
  ).firstMatch(s);
  if (pack != null) {
    final veces = num(pack.group(1)), cada = num(pack.group(2));
    if (veces != null && cada != null) {
      final r = norm(cada, pack.group(3)!);
      return (n: r.n * veces, u: r.u);
    }
  }
  final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*(kg|g|ml|cl|l)\b').firstMatch(s);
  if (m != null) {
    final n = num(m.group(1));
    if (n != null) return norm(n, m.group(2)!);
  }
  final ud = RegExp(r'(\d+)\s*(?:uds?\.?|unidades|unid\.?|u)\b').firstMatch(s);
  if (ud != null) {
    final n = num(ud.group(1));
    if (n != null && n > 0) return (n: n, u: 'ud');
  }
  return null;
}

/// Precio por kg, por litro o por unidad a partir del precio del envase y su cantidad.
/// `dimension` agrupa lo comparable entre sí: «kg», «L» o «ud».
({double valor, String dimension, String etiqueta})? precioUnitario(
  double? precio,
  String? cantidad,
) {
  if (precio == null || precio <= 0) return null;
  final q = parseQuantity(cantidad);
  if (q == null || q.n <= 0) return null;
  switch (q.u) {
    case 'g':
      return (valor: precio / (q.n / 1000), dimension: 'kg', etiqueta: '€/kg');
    case 'ml':
      return (valor: precio / (q.n / 1000), dimension: 'L', etiqueta: '€/L');
    default:
      return (valor: precio / q.n, dimension: 'ud', etiqueta: '€/ud');
  }
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[áàä]'), 'a')
    .replaceAll(RegExp(r'[éèë]'), 'e')
    .replaceAll(RegExp(r'[íìï]'), 'i')
    .replaceAll(RegExp(r'[óòö]'), 'o')
    .replaceAll(RegExp(r'[úùü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

/// Clave de equivalencia entre marcas: «leche entera de 1 L» de Hacendado, Dia y Gaza comparten clave.
/// Se forma con la categoría más específica y la cantidad normalizada.
String? genericKey({
  List<dynamic>? categories,
  String? quantity,
  String? fallbackName,
  String? brands,
}) {
  // 1º el nombre genérico (sin marca ni cantidad): es más estable entre marcas que las categorías
  String? cat;
  if (fallbackName != null && fallbackName.trim().isNotEmpty) {
    final marca = {
      for (final b in (brands ?? '').split(','))
        ..._slug(b).split('-').where((t) => t.isNotEmpty),
    };
    final tokens = _slug(fallbackName)
        .split('-')
        .where(
          (t) =>
              t.isNotEmpty &&
              !marca.contains(t) &&
              !RegExp(r'^\d+[a-z]*$').hasMatch(t) &&
              !const {'de', 'del', 'la', 'el', 'y'}.contains(t),
        )
        .toList();
    if (tokens.isNotEmpty) cat = tokens.join('-');
  }
  // 2º la categoría más específica
  if (cat == null) {
    for (final c in (categories ?? const []).reversed) {
      final s = '$c';
      if (s.contains(':')) {
        cat = s.substring(s.indexOf(':') + 1);
        break;
      }
    }
  }
  if (cat == null || cat.isEmpty) return null;
  final q = parseQuantity(quantity);
  if (q == null) return cat;
  final n = q.n == q.n.roundToDouble()
      ? q.n.round().toString()
      : q.n.toStringAsFixed(1);
  return '$cat|$n${q.u}';
}

/// Sugerencia de «va en nevera». Es solo una sugerencia: el usuario la corrige y se recuerda.
bool suggestCold(List<dynamic>? categories, {String? name}) {
  final n = (name ?? '').toLowerCase();
  // el nombre manda cuando dice claramente que es de larga duración
  if (RegExp(
    r'esterili[sz]ad|\buht\b|larga duraci[oó]n|en conserva|en polvo',
  ).hasMatch(n)) {
    return false;
  }
  final t = (categories ?? const []).join(' ').toLowerCase();
  if (t.isNotEmpty) {
    if (RegExp(r'frozen|ice-cream').hasMatch(t)) return true;
    // larga duración: no necesita frío aunque sea lácteo o carne
    if (RegExp(
      r'uht|sterili[sz]ed|long-life|shelf-stable|canned|dried|powder|cured|ambient|conserve',
    ).hasMatch(t)) {
      return false;
    }
    if (RegExp(
      r'fresh|chilled|dairies|yogurts|cheeses|butters|creams|meats|poultry|fishes|seafood|charcuteries|sausages|hams',
    ).hasMatch(t)) {
      return true;
    }
    return false;
  }
  return RegExp(
    r'leche fresca|yogur|queso|carne|pollo|pavo|cerdo|ternera|pescado|salm[oó]n|helado|congelad|jam[oó]n|embutido|mantequilla|nata|lonchas|kefir',
  ).hasMatch((name ?? '').toLowerCase());
}

const _marcasBlancas = {
  'hacendado': 'mercadona',
  'deliplus': 'mercadona',
  'bosque verde': 'mercadona',
  'compy': 'mercadona',
  'mercadona': 'mercadona',
  'milbona': 'lidl',
  'lidl': 'lidl',
  'dia': 'dia',
  'carrefour': 'carrefour',
  'alcampo': 'alcampo',
  'auchan': 'alcampo',
  'eroski': 'eroski',
  'consum': 'consum',
  'aldi': 'aldi',
};

/// Cadena exclusiva por marca o por tienda única. Usa la marca y, si hace falta, el campo «tiendas».
String? ownChainFrom(String? brands, [String? stores]) {
  for (final b in (brands ?? '').toLowerCase().split(',')) {
    final c = _marcasBlancas[b.trim()];
    if (c != null) return c;
  }
  final ss = (stores ?? '')
      .toLowerCase()
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (ss.length == 1) return _marcasBlancas[ss.first];
  return null;
}

/// Producto a partir de un registro de Open Food Facts.
Product? productFromOff(Map<String, dynamic> p) {
  final name =
      ((p['product_name_es'] ?? p['product_name']) as String?)?.trim() ?? '';
  if (name.isEmpty) return null;
  final brandsRaw = p['brands'];
  final brands = brandsRaw is List ? brandsRaw.join(',') : brandsRaw as String?;
  final brand = brands?.split(',').first.trim();
  final full =
      brand != null &&
          brand.isNotEmpty &&
          !name.toLowerCase().contains(brand.toLowerCase())
      ? '$name · $brand'
      : name;
  final cats = p['categories_tags'] as List?;
  final quantity = p['quantity'] as String?;
  final storesRaw = p['stores'];
  final stores = storesRaw is List ? storesRaw.join(',') : storesRaw as String?;
  return Product(
    name: full,
    barcode: (p['code'] as String?)?.isEmpty == true
        ? null
        : p['code'] as String?,
    cold: suggestCold(cats, name: name),
    ownChain: ownChainFrom(brands, stores),
    imageUrl: (p['image_front_small_url'] ?? p['image_front_url']) as String?,
    quantity: quantity,
    genericKey: genericKey(
      categories: cats,
      quantity: quantity,
      fallbackName: name,
      brands: brands,
    ),
  );
}

/// Resultado de comparar: por cada dimensión (kg, L, ud) el orden de las líneas de más barata a más cara.
class ResultadoComparacion {
  ResultadoComparacion(this.porDimension, this.sinDatos);
  final Map<String, List<LineaComparar>> porDimension;
  final List<LineaComparar> sinDatos; // les falta precio o tamaño

  /// La más barata de su dimensión (solo si hay al menos dos comparables).
  bool esMejor(LineaComparar l) {
    for (final lista in porDimension.values) {
      if (lista.length >= 2 && identical(lista.first, l)) return true;
    }
    return false;
  }

  /// Cuánto más cara es respecto a la mejor de su dimensión (0 = es la mejor), en porcentaje.
  double? sobrecoste(LineaComparar l) {
    for (final lista in porDimension.values) {
      if (lista.length < 2 || !lista.any((x) => identical(x, l))) continue;
      final mejor = precioUnitario(
        lista.first.precio,
        lista.first.cantidad,
      )!.valor;
      final suyo = precioUnitario(l.precio, l.cantidad)!.valor;
      return (suyo / mejor - 1) * 100;
    }
    return null;
  }
}

ResultadoComparacion comparar(List<LineaComparar> lineas) {
  final grupos = <String, List<LineaComparar>>{};
  final sin = <LineaComparar>[];
  for (final l in lineas) {
    final u = precioUnitario(l.precio, l.cantidad);
    if (u == null) {
      sin.add(l);
    } else {
      grupos.putIfAbsent(u.dimension, () => []).add(l);
    }
  }
  for (final g in grupos.values) {
    g.sort(
      (a, b) => precioUnitario(
        a.precio,
        a.cantidad,
      )!.valor.compareTo(precioUnitario(b.precio, b.cantidad)!.valor),
    );
  }
  return ResultadoComparacion(grupos, sin);
}

/// Extrae un tamaño del texto («Leche entera 1 L» → «1 L», «Bote 450g» → «450g») para rellenar el campo editable.
String? extraerTamano(String texto) {
  final m = RegExp(
    r'(\d+\s*[x×]\s*)?\d+(?:[.,]\d+)?\s*(?:kg|g|ml|cl|l)\b|\d+\s*(?:uds?\.?|unidades)\b',
    caseSensitive: false,
  ).firstMatch(texto);
  return m?.group(0)?.trim();
}
