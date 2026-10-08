import 'dart:math' as math;

const defaultServerUrl = 'https://multimarket.uverse.es';

enum Criterion { precio, distancia, preferencia }

enum ViewMode { compra, tiendas }

enum ColdFilter { todo, frio, seco }

/// Tiempo máximo recomendado fuera de nevera según el transporte.
/// Base: regla general de seguridad alimentaria (máx. 1-2 h; 1 h con calor).
enum Cooler {
  ninguna('Bolsa', 60),
  bolsa('Bolsa isotérmica', 120),
  bolsaPetaca('Bolsa + petaca de frío', 180);

  const Cooler(this.label, this.minutes);
  final String label;
  final int minutes;
}

/// Lista de la compra: la privada (siempre existe) o un hogar compartido.
class Hogar {
  Hogar({
    required this.id,
    required this.name,
    this.emoji = '🏠',
    this.esCreador = true,
    this.remota = false,
    this.inviteCode,
  });
  static const privadaId = 'privada';
  static const maxCompartidos = 3;

  final String id;
  String name;
  String emoji;
  bool get esPrivada => id == privadaId;

  /// Solo el creador puede borrar la lista de origen y gestionar miembros.
  /// El resto solo puede desvincularla de su dispositivo.
  bool esCreador;

  /// true = existe en el servidor (el `id` es el id del servidor) y se sincroniza.
  bool remota;

  /// Código de invitación vigente (solo lo ve el creador).
  String? inviteCode;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'creador': esCreador,
    'remota': remota,
    'code': inviteCode,
  };
  factory Hogar.fromJson(Map<String, dynamic> j) => Hogar(
    id: j['id'],
    name: j['name'],
    emoji: j['emoji'] ?? '🏠',
    esCreador: j['creador'] ?? true,
    remota: j['remota'] ?? false,
    inviteCode: j['code'],
  );
}

const urgencyNames = ['Ya', 'Pronto', 'Sin prisa'];

class Store {
  Store({
    required this.id,
    required this.name,
    required this.chain,
    required this.lat,
    required this.lon,
    this.km = 0,
  });

  final String id;
  final String name;
  final String chain; // normalizada en minúsculas: 'mercadona', 'lidl'...
  final double lat, lon;
  double km;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'chain': chain,
    'lat': lat,
    'lon': lon,
  };

  factory Store.fromJson(Map<String, dynamic> j) => Store(
    id: j['id'],
    name: j['name'],
    chain: j['chain'],
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
  );
}

class Product {
  const Product({
    required this.name,
    this.cold = false,
    this.barcode,
    this.ownChain,
    this.demo = false,
    this.imageUrl,
    this.quantity,
    this.genericKey,
  });

  final String name;
  final bool cold;
  final String? barcode;

  /// Cadena exclusiva (marca blanca) o null si se vende en varias.
  final String? ownChain;
  final bool demo;

  /// Foto de Open Food Facts (se enlaza, no se copia).
  final String? imageUrl;
  final String? quantity;

  /// Clave de equivalencia entre marcas (categoría + cantidad).
  final String? genericKey;

  String get key => barcode ?? name.toLowerCase();

  Product copyWith({
    bool? cold,
    String? ownChain,
    String? imageUrl,
    String? genericKey,
  }) => Product(
    name: name,
    cold: cold ?? this.cold,
    barcode: barcode,
    ownChain: ownChain ?? this.ownChain,
    demo: demo,
    imageUrl: imageUrl ?? this.imageUrl,
    quantity: quantity,
    genericKey: genericKey ?? this.genericKey,
  );

  Product conFrio(bool frio) => copyWith(cold: frio);
  Product conCadena(String chain) => copyWith(ownChain: chain);
}

enum QuoteSource { openPrices, tu, ejemplo }

const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];
String shortDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

class Quote {
  const Quote(
    this.price,
    this.date,
    this.source, {
    this.outOfStock = false,
    this.until,
    this.equivalente = false,
  });
  final double? price;
  final DateTime date;
  final QuoteSource source;
  final bool outOfStock;

  /// Precio de otro producto equivalente (misma categoría y cantidad), no de este mismo.
  final bool equivalente;

  /// Si es una oferta temporal: último día de validez.
  final DateTime? until;

  String get sourceLabel => switch (source) {
    QuoteSource.openPrices => 'Open Prices',
    QuoteSource.tu => 'tú',
    QuoteSource.ejemplo => 'ejemplo',
  };

  String get age {
    if (until != null) return 'oferta hasta ${shortDate(until!)}';
    if (equivalente) return 'similar · $sourceLabel';
    final d = DateTime.now().difference(date).inDays;
    if (source == QuoteSource.ejemplo) return 'ejemplo';
    if (d <= 0) return 'hoy · $sourceLabel';
    if (d < 31) return 'hace $d d · $sourceLabel';
    if (d < 365) return 'hace ${d ~/ 30} m · $sourceLabel';
    return 'hace +1 año · $sourceLabel';
  }
}

/// Oferta temporal anotada a mano: precio válido hasta `until` (inclusive).
class Offer {
  Offer({
    required this.key,
    required this.name,
    required this.chain,
    required this.price,
    required this.until,
  });
  final String
  key; // clave de producto (código de barras o nombre en minúsculas)
  final String name;
  final String chain;
  final double price;
  final DateTime until; // solo cuenta la fecha

  String get id => '$key|$chain';

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  int get daysLeft => _day(until).difference(_day(DateTime.now())).inDays;
  bool get active => daysLeft >= 0;

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'chain': chain,
    'price': price,
    'until': _day(until).toIso8601String(),
  };

  factory Offer.fromJson(Map<String, dynamic> j) => Offer(
    key: j['key'],
    name: j['name'],
    chain: j['chain'],
    price: (j['price'] as num).toDouble(),
    until: DateTime.parse(j['until']),
  );
}

/// Una tienda candidata para un producto, con su precio conocido.
class Option {
  Option(this.store, this.quote);
  final Store store;
  final Quote? quote;
  double? get price => quote?.price;
  bool get out => quote?.outOfStock ?? false;
}

class Item {
  Item({
    required this.id,
    required this.name,
    required this.cold,
    this.urg = 2,
    this.done = false,
    this.storeId,
    this.price,
    this.barcode,
    this.addedBy,
    this.updatedMs = 0,
    this.imageUrl,
    this.genericKey,
    this.localImage,
    this.cantidad = 1,
  });

  String id; // 15 caracteres [a-z0-9] (formato de id de PocketBase)
  String
  name; // editable: el usuario le pone su nombre y tamaño («Leche entera 1 L»)
  bool cold;
  int urg; // 1 ya, 2 pronto, 3 sin prisa
  bool done;
  String? storeId;
  double? price;
  String? barcode;
  String? addedBy; // id de usuario del servidor (listas compartidas)
  int updatedMs; // último cambio local o remoto (ms)
  String? imageUrl; // foto enlazada (Open Food Facts o comunidad)
  String? genericKey; // equivalencia entre marcas
  String? localImage; // foto propia, solo en este dispositivo
  int cantidad; // unidades (1 por defecto); el precio es por unidad

  /// Importe de la línea: precio por unidad × cantidad.
  double get total => (price ?? 0) * cantidad;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'cold': cold,
    'urg': urg,
    'done': done,
    'storeId': storeId,
    'price': price,
    'barcode': barcode,
    'addedBy': addedBy,
    'updatedMs': updatedMs,
    'imageUrl': imageUrl,
    'genericKey': genericKey,
    'localImage': localImage,
    'cantidad': cantidad,
  };

  factory Item.fromJson(Map<String, dynamic> j) => Item(
    id: j['id'],
    name: j['name'],
    cold: j['cold'],
    urg: j['urg'],
    done: j['done'],
    storeId: j['storeId'],
    price: (j['price'] as num?)?.toDouble(),
    barcode: j['barcode'],
    addedBy: j['addedBy'],
    updatedMs: j['updatedMs'] ?? 0,
    imageUrl: j['imageUrl'],
    genericKey: j['genericKey'],
    localImage: j['localImage'],
    cantidad: j['cantidad'] ?? 1,
  );
}

/// Una compra hecha: se guarda cuando marcas un producto como comprado. Es la base de la recompra y las estadísticas.
class Compra {
  Compra({
    required this.id,
    required this.itemId,
    required this.key,
    required this.name,
    required this.qty,
    this.price,
    this.storeId,
    this.storeName,
    required this.ms,
    this.by,
  });

  final String id; // 15 caracteres [a-z0-9]
  final String itemId; // producto de la lista que la originó (para deshacer)
  final String key; // código de barras o nombre normalizado
  final String name;
  final int qty;
  final double? price; // por unidad
  final String? storeId;
  final String? storeName;
  final int ms; // instante (ms desde 1970)
  final String? by; // usuario del servidor, en listas compartidas

  DateTime get fecha => DateTime.fromMillisecondsSinceEpoch(ms);
  double get total => (price ?? 0) * qty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'itemId': itemId,
    'key': key,
    'name': name,
    'qty': qty,
    'price': price,
    'storeId': storeId,
    'storeName': storeName,
    'ms': ms,
    'by': by,
  };

  factory Compra.fromJson(Map<String, dynamic> j) => Compra(
    id: j['id'],
    itemId: j['itemId'] ?? '',
    key: j['key'],
    name: j['name'],
    qty: j['qty'] ?? 1,
    price: (j['price'] as num?)?.toDouble(),
    storeId: j['storeId'],
    storeName: j['storeName'],
    ms: j['ms'],
    by: j['by'],
  );
}

/// Una línea de la comparativa: un producto con su tamaño y precio (ambos editables por el usuario).
class LineaComparar {
  LineaComparar({required this.producto, this.cantidad, this.precio});
  final Product producto;
  String? cantidad; // «450 g», «1 L», «3 x 125 g»…
  double? precio; // del envase

  String get id => producto.key;
}

/// La tienda más cercana (dentro de `maxMetros`) a una posición, o null si ninguna está lo bastante cerca.
Store? tiendaMasCercana(
  double lat,
  double lon,
  Iterable<Store> candidatas, {
  double maxMetros = 150,
}) {
  Store? mejor;
  var dMejor = double.infinity;
  for (final s in candidatas) {
    final d = haversineKm(lat, lon, s.lat, s.lon) * 1000;
    if (d <= maxMetros && d < dMejor) {
      mejor = s;
      dMejor = d;
    }
  }
  return mejor;
}

/// Mensaje al usuario con una acción opcional de deshacer (barra inferior).
class Aviso {
  Aviso(this.texto, {this.deshacer});
  final String texto;
  final void Function()? deshacer;
}

/// Versión de la app (mantener igual que `version` de pubspec.yaml); se añade a los informes de errores.
const versionApp = '1.0.0+1';

class Settings {
  Settings({
    Set<String>? enabled,
    Set<String>? favChains,
    this.radiusKm = 3,
    this.criterion = Criterion.precio,
    this.auto = false,
    this.coldTimer = true,
    this.cooler = Cooler.ninguna,
    this.demoPrices = true,
    this.offerReminderDays = 1,
    this.showCartCard = true,
    this.showColdCard = true,
    this.alias = '',
    this.serverUrl = defaultServerUrl,
    this.showImages = true,
    this.sharePhotos = false,
    this.shareNewProducts = true,
    this.detectarTienda = true,
    this.recompra = true,
    this.enviarErrores = false,
    this.copiaPrivada = false,
  }) : enabled = enabled ?? {},
       favChains = favChains ?? {};

  Set<String> enabled; // ids de tienda activas
  Set<String> favChains;
  double radiusKm;
  Criterion criterion;
  bool auto;
  bool coldTimer;
  Cooler cooler;
  bool demoPrices;
  int offerReminderDays; // 0 = sin aviso
  bool showCartCard; // tarjetas de la lista
  bool showColdCard;
  bool showImages; // miniaturas en la lista
  bool
  sharePhotos; // true = compartir fotos sin preguntar; false = preguntar cada vez
  bool
  enviarErrores; // informes de errores anónimos al servidor (desactivado por defecto)
  bool
  copiaPrivada; // copia de la lista privada en el servidor (opcional, desactivada por defecto)
  bool recompra; // sugerencias «fantasma» de reposición según tu historial
  bool
  detectarTienda; // al marcar comprado, usa la ubicación para saber en qué tienda estás
  bool
  shareNewProducts; // los productos nuevos que creas van a la base general (moderada)
  String alias; // nombre visible para el resto de miembros
  String serverUrl;

  Map<String, dynamic> toJson() => {
    'enabled': enabled.toList(),
    'favChains': favChains.toList(),
    'radiusKm': radiusKm,
    'criterion': criterion.name,
    'auto': auto,
    'coldTimer': coldTimer,
    'cooler': cooler.name,
    'demoPrices': demoPrices,
    'offerReminderDays': offerReminderDays,
    'showCartCard': showCartCard,
    'showColdCard': showColdCard,
    'alias': alias,
    'serverUrl': serverUrl,
    'showImages': showImages,
    'sharePhotos': sharePhotos,
    'shareNewProducts': shareNewProducts,
    'detectarTienda': detectarTienda,
    'recompra': recompra,
    'enviarErrores': enviarErrores,
    'copiaPrivada': copiaPrivada,
  };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
    enabled: {...?(j['enabled'] as List?)?.cast<String>()},
    favChains: {...?(j['favChains'] as List?)?.cast<String>()},
    radiusKm: (j['radiusKm'] as num?)?.toDouble() ?? 3,
    criterion: Criterion.values.byName(j['criterion'] ?? 'precio'),
    auto: j['auto'] ?? false,
    coldTimer: j['coldTimer'] ?? true,
    cooler: Cooler.values.byName(j['cooler'] ?? 'ninguna'),
    demoPrices: j['demoPrices'] ?? true,
    offerReminderDays: j['offerReminderDays'] ?? 1,
    showCartCard: j['showCartCard'] ?? true,
    showColdCard: j['showColdCard'] ?? true,
    alias: j['alias'] ?? '',
    serverUrl: j['serverUrl'] ?? defaultServerUrl,
    showImages: j['showImages'] ?? true,
    sharePhotos: j['sharePhotos'] ?? false,
    shareNewProducts: j['shareNewProducts'] ?? true,
    detectarTienda: j['detectarTienda'] ?? true,
    recompra: j['recompra'] ?? true,
    enviarErrores: j['enviarErrores'] ?? false,
    copiaPrivada: j['copiaPrivada'] ?? false,
  );
}

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

String eur(double n) => '${n.toStringAsFixed(2).replaceAll('.', ',')} €';
