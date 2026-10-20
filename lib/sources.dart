import 'dart:async';
// Fuentes de datos ABIERTAS y sin scraping:
//  - OpenStreetMap (Overpass): tiendas cercanas. Datos © colaboradores de OpenStreetMap, ODbL.
//  - Open Food Facts: catálogo de productos y códigos de barras. ODbL / DbCL.
//  - Open Prices: precios colaborativos. ODbL.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog.dart';
import 'models.dart';

const _ua = {
  'User-Agent':
      'MultiMarket/0.1 (proyecto abierto MIT; github.com/multimarket)',
};

const knownChains = [
  'mercadona',
  'dia',
  'carrefour',
  'lidl',
  'aldi',
  'alcampo',
  'eroski',
  'consum',
  'bonpreu',
  'condis',
  'ahorramas',
  'supersol',
  'gadis',
  'hipercor',
  'caprabo',
  'froiz',
  'masymas',
  'spar',
  'family cash',
];

/// Marcas blancas conocidas -> cadena exclusiva.
const _ownBrands = {
  'hacendado': 'mercadona',
  'deliplus': 'mercadona',
  'bosque verde': 'mercadona',
  'compy': 'mercadona',
  'milbona': 'lidl',
  'dia': 'dia',
  'carrefour': 'carrefour',
  'alcampo': 'alcampo',
  'eroski': 'eroski',
  'consum': 'consum',
  'lidl': 'lidl',
  'aldi': 'aldi',
};

String? chainOf(String? text) {
  final t = (text ?? '').toLowerCase();
  for (final c in knownChains) {
    if (RegExp('(^|[^a-z])${RegExp.escape(c)}([^a-z]|\$)').hasMatch(t)) {
      return c;
    }
  }
  return null;
}

/// Abreviatura de prefijos genéricos para que quepa en lista: «Supermercado Lo Compro Todo» → «Súper Lo Compro Todo».
String shortStoreName(String n) {
  var s = n.trim();
  const prefijos = {
    r'^supermercados?\s+': 'Súper ',
    r'^hipermercados?\s+': 'Hiper ',
    r'^autoservicio\s+': 'Auto ',
  };
  prefijos.forEach((re, rep) {
    s = s.replaceFirstMapped(RegExp(re, caseSensitive: false), (_) => rep);
  });
  return s;
}

String prettyChain(String c) =>
    c.split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');

String? ownChainFromBrands(String? brands) {
  for (final b in (brands ?? '').toLowerCase().split(',')) {
    final own = _ownBrands[b.trim()];
    if (own != null) return own;
  }
  return null;
}

bool looksCold(String name) => RegExp(
  r'leche|yogur|queso|carne|pollo|pavo|cerdo|ternera|pescado|salm[oó]n|helado|congelad|jam[oó]n|embutido|mantequilla|nata|huevo|fresco|lonchas|kefir',
).hasMatch(name.toLowerCase());

bool coldFromCategories(List<dynamic>? cats) {
  final t = (cats ?? []).join(' ');
  return RegExp(
    r'dairies|meats|fishes|frozen|fresh|cheeses|yogurts|eggs|charcuteries|seafood',
  ).hasMatch(t);
}

// ---------------------------------------------------------------- Demo
/// Catálogo de EJEMPLO para poder probar sin red. Se etiqueta como "ejemplo".
final _demoDate = DateTime(2026, 1, 1);
Map<String, double> _p(
  double mer,
  double dia,
  double car,
  double lid,
  double ald,
) => {'mercadona': mer, 'dia': dia, 'carrefour': car, 'lidl': lid, 'aldi': ald};

final demoPrices = <String, Map<String, double>>{
  'leche entera 1l': _p(.89, .85, .95, .79, .82),
  'yogur natural x4': _p(1.35, 1.29, 1.45, 1.19, 1.25),
  'queso lonchas': _p(2.10, 2.25, 2.40, 1.99, 2.20),
  'pechuga de pollo 1kg': _p(6.90, 7.20, 7.50, 6.49, 6.75),
  'helado vainilla': _p(2.95, 3.10, 3.40, 2.49, 2.70),
  'huevos docena': _p(2.35, 2.40, 2.60, 2.15, 2.20),
  'plátanos 1kg': _p(1.79, 1.99, 1.89, 1.65, 1.70),
  'pan de molde': _p(1.55, 1.49, 1.75, 1.29, 1.35),
  'arroz 1kg': _p(1.35, 1.39, 1.55, 1.19, 1.25),
  'aceite de oliva 1l': _p(8.90, 9.20, 9.50, 8.49, 8.75),
  'tomate frito': _p(.99, .95, 1.10, .89, .92),
  'atún en lata x3': _p(3.10, 2.95, 3.30, 2.85, 2.99),
  'papel higiénico 12u': _p(4.60, 4.35, 5.20, 3.99, 4.10),
  'detergente': _p(5.90, 5.50, 6.40, 4.99, 5.30),
  'leche hacendado 1l': {'mercadona': .86},
  'leche milbona 1l': {'lidl': .79},
  'pasta bosque verde': {'mercadona': .95},
  'yogur carrefour classic x4': {'carrefour': .99},
};

const demoCatalog = <Product>[
  Product(name: 'Leche entera 1L', cold: true, demo: true),
  Product(
    name: 'Leche Hacendado 1L',
    cold: true,
    ownChain: 'mercadona',
    demo: true,
  ),
  Product(name: 'Leche Milbona 1L', cold: true, ownChain: 'lidl', demo: true),
  Product(name: 'Yogur natural x4', cold: true, demo: true),
  Product(
    name: 'Yogur Carrefour Classic x4',
    cold: true,
    ownChain: 'carrefour',
    demo: true,
  ),
  Product(name: 'Queso lonchas', cold: true, demo: true),
  Product(name: 'Pechuga de pollo 1kg', cold: true, demo: true),
  Product(name: 'Helado vainilla', cold: true, demo: true),
  Product(name: 'Huevos docena', demo: true),
  Product(name: 'Plátanos 1kg', demo: true),
  Product(name: 'Pan de molde', demo: true),
  Product(name: 'Arroz 1kg', demo: true),
  Product(name: 'Pasta Bosque Verde', ownChain: 'mercadona', demo: true),
  Product(name: 'Aceite de oliva 1L', demo: true),
  Product(name: 'Tomate frito', demo: true),
  Product(name: 'Atún en lata x3', demo: true),
  Product(name: 'Papel higiénico 12u', demo: true),
  Product(name: 'Detergente', demo: true),
];

Quote? demoQuote(Product p, String chain) {
  final v = demoPrices[p.name.toLowerCase()]?[chain];
  return v == null
      ? null
      : Quote(v, _demoDate, QuoteSource.ejemplo, conf: Confianza.baja);
}

/// Tiendas de ejemplo (Madrid centro) cuando no hay ubicación ni red.
List<Store> demoStores() => [
  Store(
    id: 'demo:mer',
    name: 'Mercadona',
    chain: 'mercadona',
    lat: 40.4190,
    lon: -3.7050,
  ),
  Store(id: 'demo:dia', name: 'Dia', chain: 'dia', lat: 40.4200, lon: -3.7000),
  Store(
    id: 'demo:car',
    name: 'Carrefour Express',
    chain: 'carrefour',
    lat: 40.4230,
    lon: -3.7100,
  ),
  Store(
    id: 'demo:lid',
    name: 'Lidl',
    chain: 'lidl',
    lat: 40.4300,
    lon: -3.7000,
  ),
  Store(
    id: 'demo:ald',
    name: 'Aldi',
    chain: 'aldi',
    lat: 40.4100,
    lon: -3.6900,
  ),
];

// ------------------------------------------------------- Open Food Facts
const _ofFields =
    'code,product_name,product_name_es,brands,quantity,image_front_small_url,categories_tags,stores,countries_tags';

/// Búsqueda de texto con la API nueva (search-a-licious), solo productos de España.
Future<List<Product>> searchProducts(String q) async {
  final uri = Uri.https('search.openfoodfacts.org', '/search', {
    'q': '$q countries_tags:"en:spain"',
    'page_size': '10',
    'langs': 'es',
    'fields': _ofFields,
  });
  final r = await http
      .get(uri, headers: _ua)
      .timeout(const Duration(seconds: 8));
  if (r.statusCode != 200) return [];
  final hits = (jsonDecode(r.body)['hits'] as List?) ?? [];
  return [
    for (final h in hits) ?productFromOff((h as Map).cast<String, dynamic>()),
  ];
}

/// Un producto por su código de barras (EAN/UPC).
Future<Product?> productByBarcode(String code) async {
  final uri = Uri.https(
    'world.openfoodfacts.org',
    '/api/v2/product/$code.json',
    {'fields': _ofFields},
  );
  final r = await http
      .get(uri, headers: _ua)
      .timeout(const Duration(seconds: 8));
  if (r.statusCode != 200) return null;
  final j = jsonDecode(r.body) as Map<String, dynamic>;
  if (j['status'] != 1) return null;
  return productFromOff((j['product'] as Map).cast<String, dynamic>());
}

final esCodigoDeBarras = RegExp(r'^\d{8,14}$');

// ------------------------------------------------------------ Open Prices
/// Último precio conocido por cadena para un código de barras (solo España, EUR).
Future<Map<String, Quote>> openPrices(String barcode) async {
  final uri = Uri.https('prices.openfoodfacts.org', '/api/v1/prices', {
    'product_code': barcode,
    'currency': 'EUR',
    'order_by': '-date',
    'size': '50',
  });
  final r = await http
      .get(uri, headers: _ua)
      .timeout(const Duration(seconds: 8));
  if (r.statusCode != 200) return {};
  final out = <String, Quote>{};
  for (final i in (jsonDecode(r.body)['items'] as List? ?? [])) {
    final loc = i['location'] as Map<String, dynamic>?;
    if (loc == null || loc['osm_address_country_code'] != 'ES') continue;
    final chain =
        chainOf(loc['osm_brand'] as String?) ??
        chainOf(loc['osm_name'] as String?);
    final price = (i['price'] as num?)?.toDouble();
    final date = DateTime.tryParse(i['date'] ?? '');
    if (chain == null || price == null || date == null) continue;
    final prev = out[chain];
    if (prev == null || date.isAfter(prev.date)) {
      out[chain] = Quote(
        price,
        date,
        QuoteSource.openPrices,
        conf: Confianza.media, // colaborativo y sin verificar
      );
    }
  }
  return out;
}

/// Precios de Open Prices de productos EQUIVALENTES (misma clave genérica: mismo nombre y cantidad,
/// otra marca) para las cadenas donde no hay precio del producto exacto. Marcados como «similar».
Future<Map<String, Quote>> equivalentOpenPrices(Product p) async {
  final gk = p.genericKey;
  if (gk == null) return {};
  final nombre = gk.split('|').first.replaceAll('-', ' ');
  if (nombre.trim().length < 3) return {};
  final candidatos = (await searchProducts(nombre))
      .where(
        (x) =>
            x.genericKey == gk && x.barcode != null && x.barcode != p.barcode,
      )
      .take(6)
      .toList();
  final listas = await Future.wait([
    for (final c in candidatos)
      openPrices(c.barcode!).catchError((_) => <String, Quote>{}),
  ]);
  final out = <String, Quote>{};
  for (final m in listas) {
    m.forEach((chain, q) {
      final prev = out[chain];
      if (prev == null || q.date.isAfter(prev.date)) {
        out[chain] = Quote(q.price, q.date, q.source, equivalente: true);
      }
    });
  }
  return out;
}

// -------------------------------------------------------------- Overpass
/// Servidores públicos de Overpass, por orden de preferencia. El principal (`overpass-api.de`) se satura con frecuencia
/// (502, 23–40 s de respuesta), así que se lanzan varios con retraso escalonado y gana el primero que responde bien.
const overpassServidores = [
  'overpass.openstreetmap.fr',
  'overpass-api.de',
  'z.overpass-api.de',
  'overpass.kumi.systems',
  'overpass.private.coffee',
];

class OverpassOcupado implements Exception {
  OverpassOcupado(this.detalle);
  final String detalle;
  @override
  String toString() => 'Servicio de mapas ocupado ($detalle)';
}

/// Lanza la consulta en varios servidores escalonados (cada 4 s) y devuelve el primer JSON correcto.
Future<Map<String, dynamic>> consultarOverpass(
  String q, {
  http.Client? cliente,
  List<String> servidores = overpassServidores,
  Duration escalon = const Duration(seconds: 4),
  Duration limite = const Duration(seconds: 20),
}) {
  final c = cliente ?? http.Client();
  final fin = Completer<Map<String, dynamic>>();
  var pendientes = servidores.length;
  final errores = <String>[];
  for (var i = 0; i < servidores.length; i++) {
    final host = servidores[i];
    Future<void>(() async {
      await Future<void>.delayed(escalon * i);
      if (fin.isCompleted) return;
      try {
        final r = await c
            .post(
              Uri.https(host, '/api/interpreter'),
              headers: _ua,
              body: {'data': q},
            )
            .timeout(limite);
        if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final remark = '${j['remark'] ?? ''}';
        if (remark.contains('runtime error') || remark.contains('timed out')) {
          throw Exception('consulta rechazada: $remark');
        }
        if (!fin.isCompleted) fin.complete(j);
      } catch (e) {
        errores.add('$host: $e');
      } finally {
        if (--pendientes == 0 && !fin.isCompleted) {
          fin.completeError(OverpassOcupado(errores.take(3).join('; ')));
        }
      }
    });
  }
  return fin.future;
}

Future<List<Store>> nearbyStores(
  double lat,
  double lon,
  double radiusKm,
) async {
  final m = (radiusKm * 1000).round();
  final q =
      '[out:json][timeout:25];nwr["shop"="supermarket"](around:$m,$lat,$lon);out center tags 300;';
  final r = await consultarOverpass(q);
  final out = <Store>[];
  for (final e in (r['elements'] as List)) {
    final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? {};
    final c = e['center'] as Map?;
    final la = (e['lat'] ?? c?['lat']) as num?,
        lo = (e['lon'] ?? c?['lon']) as num?;
    if (la == null || lo == null) continue;
    final name = (tags['name'] ?? tags['brand'] ?? 'Supermercado') as String;
    final chain =
        chainOf(tags['brand'] as String?) ??
        chainOf(name) ??
        name.toLowerCase();
    out.add(
      Store(
        id: 'osm:${e['type']}/${e['id']}',
        name: name,
        chain: chain,
        lat: la.toDouble(),
        lon: lo.toDouble(),
        km: haversineKm(lat, lon, la.toDouble(), lo.toDouble()),
      ),
    );
  }
  out.sort((a, b) => a.km.compareTo(b.km));
  return out
      .take(80)
      .toList(); // las 80 más cercanas (Overpass no ordena por distancia)
}
