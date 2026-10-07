import 'ticket/ticket_match.dart';
import 'ticket/ticket_parser.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'notifier.dart';
import 'recompra.dart';
import 'sources.dart';
import 'sync/pb_api.dart';
import 'sync/sync_service.dart';

class AppState extends ChangeNotifier {
  AppState(this._prefs) {
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    sync.addListener(refresh); // estado de la sincronización → repintar
    sync.iniciar();
    unawaited(recuperarListas());
  }

  final SharedPreferences _prefs;
  SharedPreferences get prefs => _prefs;
  late final SyncService sync = SyncService(this);
  late final Timer _ticker;

  // listas: la privada + hasta 3 hogares compartidos
  List<Hogar> hogares = [
    Hogar(id: Hogar.privadaId, name: 'Mi lista', emoji: '🔒'),
  ];
  String currentId = Hogar.privadaId;
  final Map<String, List<Item>> _lists = {};
  final Map<String, Map<String, Offer>> _offers = {};

  /// Historial de compras por lista (la privada o cada hogar compartido).
  final Map<String, List<Compra>> _compras = {};

  /// Decisiones sobre las sugerencias de recompra, por lista y producto.
  final Map<String, Map<String, Descarte>> _descartes = {};
  Map<String, Descarte> get descartes => _descartes[currentId] ??= {};
  List<Compra> get compras => _compras[currentId] ??= [];
  List<Compra> comprasDe(String hogarId) => _compras[hogarId] ??= [];

  Hogar get hogar =>
      hogares.firstWhere((h) => h.id == currentId, orElse: () => hogares.first);
  List<Item> get items => _lists[currentId] ??= [];
  set items(List<Item> v) => _lists[currentId] = v;
  Map<String, Offer> get offers => _offers[currentId] ??= {};
  List<Item> itemsOf(String id) => _lists[id] ?? const [];
  Iterable<Item> get allItems => _lists.values.expand((l) => l);
  Settings cfg = Settings();
  List<Store> stores = [];
  double lat = 40.4168, lon = -3.7038; // Madrid por defecto
  bool locApprox = true;
  String? storesError;
  bool loadingStores = false;
  double fetchedRadiusKm = 0; // radio de la última descarga de tiendas

  /// Tiendas conocidas solo por las listas compartidas (otro miembro las eligió y no están en mi zona).
  final Map<String, Store> extraStores = {};

  /// Tiendas cuyos datos vienen del propietario de una lista: si coinciden con otra de mi zona, mandan estas.
  final Set<String> tiendasDelPropietario = {};

  ViewMode view = ViewMode.compra;
  ColdFilter filter = ColdFilter.todo;
  int tab = 0;
  bool cartOpen = false; // tarjetas plegables de la lista
  bool coldOpen = false;

  /// Precios que el usuario ha anotado al comprar: 'productKey|cadena'.
  final Map<String, Quote> _local = {};

  /// Lo que el usuario ya confirmó en cada cadena: «cadena|nombre del ticket normalizado» → nombre del producto de la lista.
  final Map<String, String> aliasTicket = {};
  final Map<String, Map<String, Quote>> _opCache = {};

  /// Productos que el usuario ha marcado como exclusivos de una cadena: clave de producto → cadena.
  final Map<String, String> exclusivos = {};

  /// Productos cuyo estado refrigerado ha corregido el usuario: clave de producto → es frío.
  final Map<String, bool> frioManual = {};

  /// Equivalentes de Open Prices ya consultados: clave genérica → precios por cadena.
  final Map<String, Map<String, Quote>> _eqCache = {};

  /// Productos nuevos ya propuestos a la base general (para no repetir).
  final Set<String> proponidos = {};

  /// Fotos propias (solo en este dispositivo): clave de producto → ruta del archivo.
  final Map<String, String> fotosLocales = {};

  /// Ofertas temporales anotadas a mano: 'productKey|cadena'.

  // ----- temporizador de frío
  DateTime? coldStart;
  final ValueNotifier<int> coldElapsed = ValueNotifier(0); // segundos
  final _avisos = StreamController<Aviso>.broadcast();
  Stream<Aviso> get avisos => _avisos.stream;
  final _alerts = StreamController<String>.broadcast();
  Stream<String> get alerts => _alerts.stream;
  final Set<String> _fired = {};

  int get coldWindowSec => cfg.cooler.minutes * 60;
  bool get coldRunning => coldStart != null && cfg.coldTimer;

  // ------------------------------------------------------------ persistencia
  void _load() {
    try {
      final s = _prefs.getString('cfg');
      if (s != null) cfg = Settings.fromJson(jsonDecode(s));
      final hs = _prefs.getString('hogares');
      if (hs != null) {
        final l = [for (final j in jsonDecode(hs) as List) Hogar.fromJson(j)];
        if (l.any((h) => h.esPrivada)) hogares = l;
      }
      currentId = _prefs.getString('currentId') ?? Hogar.privadaId;
      if (!hogares.any((h) => h.id == currentId)) currentId = Hogar.privadaId;
      for (final h in hogares) {
        // migración: antes la lista y las ofertas no tenían hogar
        final old = h.esPrivada ? _prefs.getString('items') : null;
        final raw = _prefs.getString('items:${h.id}') ?? old ?? '[]';
        _lists[h.id] = [
          for (final j in jsonDecode(raw) as List) Item.fromJson(j),
        ];
        final oraw =
            _prefs.getString('offers:${h.id}') ??
            (h.esPrivada ? _prefs.getString('offers') : null) ??
            '[]';
        _offers[h.id] = {};
        for (final j in jsonDecode(oraw) as List) {
          final o = Offer.fromJson(j);
          _offers[h.id]![o.id] = o;
        }
      }
      stores = [
        for (final j
            in (jsonDecode(_prefs.getString('stores') ?? '[]') as List))
          Store.fromJson(j),
      ];
      for (final j
          in (jsonDecode(_prefs.getString('extraStores') ?? '[]') as List)) {
        final st = Store.fromJson(j);
        extraStores[st.id] = st;
      }
      tiendasDelPropietario.addAll(
        (jsonDecode(_prefs.getString('tiendasProp') ?? '[]') as List)
            .cast<String>(),
      );
      lat = _prefs.getDouble('lat') ?? lat;
      lon = _prefs.getDouble('lon') ?? lon;
      locApprox = _prefs.getBool('locApprox') ?? true;
      exclusivos.addAll(
        (jsonDecode(_prefs.getString('exclusivos') ?? '{}') as Map)
            .cast<String, String>(),
      );
      frioManual.addAll(
        (jsonDecode(_prefs.getString('frioManual') ?? '{}') as Map)
            .cast<String, bool>(),
      );
      fotosLocales.addAll(
        (jsonDecode(_prefs.getString('fotosLocales') ?? '{}') as Map)
            .cast<String, String>(),
      );
      proponidos.addAll(
        (jsonDecode(_prefs.getString('proponidos') ?? '[]') as List)
            .cast<String>(),
      );
      for (final h in hogares) {
        final raw = _prefs.getString('compras:${h.id}');
        _compras[h.id] = raw == null
            ? []
            : [for (final j in jsonDecode(raw) as List) Compra.fromJson(j)];
      }
      for (final h in hogares) {
        final raw = _prefs.getString('recompra:${h.id}');
        _descartes[h.id] = raw == null
            ? {}
            : {
                for (final e
                    in (jsonDecode(raw) as Map<String, dynamic>).entries)
                  e.key: Descarte.fromJson(e.value as Map<String, dynamic>),
              };
      }
      aliasTicket.addAll(
        (jsonDecode(_prefs.getString('aliasTicket') ?? '{}') as Map)
            .cast<String, String>(),
      );
      final cs = _prefs.getString('coldStart');
      if (cs != null) coldStart = DateTime.tryParse(cs);
      final loc =
          jsonDecode(_prefs.getString('local') ?? '{}') as Map<String, dynamic>;
      loc.forEach(
        (k, v) => _local[k] = Quote(
          (v['p'] as num).toDouble(),
          DateTime.parse(v['d']),
          QuoteSource.tu,
          outOfStock: v['o'] ?? false,
        ),
      );
    } catch (_) {
      // datos corruptos: se empieza de cero
    }
    if (stores.isNotEmpty) {
      _recomputeKm(); // las distancias no se guardan: se recalculan
    }
    if (stores.isEmpty) {
      stores = demoStores();
      _recomputeKm();
      cfg.enabled = stores.take(3).map((s) => s.id).toSet();
    }
    for (final m in _offers.values) {
      m.removeWhere((_, o) => !o.active);
    }
    if (coldStart != null) {
      _tick(silent: true);
      _scheduleCold();
    }
    _scheduleOffers();
  }

  void _save() {
    _prefs.setString('cfg', jsonEncode(cfg.toJson()));
    _prefs.setString('exclusivos', jsonEncode(exclusivos));
    _prefs.setString('frioManual', jsonEncode(frioManual));
    _prefs.setString('proponidos', jsonEncode(proponidos.toList()));
    _prefs.setString('aliasTicket', jsonEncode(aliasTicket));
    for (final h in hogares) {
      _prefs.setString(
        'recompra:${h.id}',
        jsonEncode(
          (_descartes[h.id] ?? {}).map((k, d) => MapEntry(k, d.toJson())),
        ),
      );
    }
    for (final h in hogares) {
      _prefs.setString(
        'compras:${h.id}',
        jsonEncode((_compras[h.id] ?? []).map((c) => c.toJson()).toList()),
      );
    }
    _prefs.setString('fotosLocales', jsonEncode(fotosLocales));
    _prefs.setString(
      'hogares',
      jsonEncode(hogares.map((h) => h.toJson()).toList()),
    );
    _prefs.setString('currentId', currentId);
    for (final h in hogares) {
      _prefs.setString(
        'items:${h.id}',
        jsonEncode((_lists[h.id] ?? []).map((i) => i.toJson()).toList()),
      );
      _prefs.setString(
        'offers:${h.id}',
        jsonEncode(
          (_offers[h.id] ?? {}).values.map((o) => o.toJson()).toList(),
        ),
      );
    }
    _prefs.setString(
      'stores',
      jsonEncode(stores.map((s) => s.toJson()).toList()),
    );
    _prefs.setString(
      'extraStores',
      jsonEncode(extraStores.values.map((s) => s.toJson()).toList()),
    );
    _prefs.setString('tiendasProp', jsonEncode(tiendasDelPropietario.toList()));
    _prefs.setDouble('lat', lat);
    _prefs.setDouble('lon', lon);
    _prefs.setBool('locApprox', locApprox);
    if (coldStart == null) {
      _prefs.remove('coldStart');
    } else {
      _prefs.setString('coldStart', coldStart!.toIso8601String());
    }
    _prefs.setString(
      'local',
      jsonEncode(
        _local.map(
          (k, q) => MapEntry(k, {
            'p': q.price,
            'd': q.date.toIso8601String(),
            'o': q.outOfStock,
          }),
        ),
      ),
    );
  }

  void refresh() => notifyListeners();

  // ------------------------------------------------------------------ hogares
  int get compartidos => hogares.where((h) => !h.esPrivada).length;
  bool get puedeCrearHogar => compartidos < Hogar.maxCompartidos;

  void selectHogar(String id) {
    if (id == currentId || !hogares.any((h) => h.id == id)) return;
    currentId = id;
    changed();
  }

  Hogar? crearHogar(String name, {String emoji = '🏠'}) {
    name = name.trim();
    if (name.isEmpty || !puedeCrearHogar) return null;
    final h = Hogar(
      id: 'h${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      emoji: emoji,
    );
    hogares.add(h);
    _lists[h.id] = [];
    _offers[h.id] = {};
    currentId = h.id;
    changed();
    return h;
  }

  void renombrarHogar(Hogar h, String name, String emoji) {
    if (name.trim().isEmpty) return;
    h.name = name.trim();
    h.emoji = emoji;
    changed();
  }

  // ------------------------------------------------- listas compartidas (servidor)
  /// Devuelve un mensaje de error, o null si todo fue bien.
  Future<String?> crearCompartida(String name, String emoji) async {
    if (name.trim().isEmpty) return 'Pon un nombre';
    if (!puedeCrearHogar) {
      return 'Máximo ${Hogar.maxCompartidos} listas compartidas';
    }
    try {
      final api = sync.api;
      await api.ensureAuth(alias: cfg.alias);
      final r = await api.crearHogar(name.trim(), emoji);
      final h = Hogar(
        id: r['id'],
        name: name.trim(),
        emoji: emoji,
        esCreador: true,
        remota: true,
        inviteCode: r['invite_code'],
      );
      hogares.add(h);
      _lists[h.id] = [];
      _offers[h.id] = {};
      currentId = h.id;
      changed();
      sync.remotaNueva();
      return null;
    } on PbException catch (e) {
      return e.message;
    }
  }

  /// Si esta cuenta de dispositivo (guardada en el llavero) ya es miembro de listas del servidor que no están en
  /// este dispositivo (reinstalación, datos borrados), las vuelve a añadir. Devuelve cuántas recuperó.
  String diagnosticoRecuperar = '';

  Future<int> recuperarListas() async {
    try {
      if (!await sync.api.tieneCuenta) {
        diagnosticoRecuperar =
            'Este dispositivo no tiene cuenta en el servidor (el llavero está vacío): no hay listas que recuperar';
        return 0;
      }
      await sync.api.ensureAuth(alias: cfg.alias);
      var n = 0;
      final remotas = await sync.api.misHogares();
      for (final r in remotas) {
        final id = r['id'] as String;
        if (hogares.any((h) => h.id == id) || !puedeCrearHogar) continue;
        final mia = r['owner'] == sync.miId;
        hogares.add(
          Hogar(
            id: id,
            name: (r['name'] as String?) ?? 'Lista',
            emoji: (r['emoji'] as String?) ?? '🏠',
            esCreador: mia,
            remota: true,
            inviteCode: mia ? r['invite_code'] as String? : null,
          ),
        );
        _lists[id] = [];
        _offers[id] = {};
        n++;
      }
      diagnosticoRecuperar = n > 0
          ? 'Recuperadas $n lista(s)'
          : 'Tu cuenta es miembro de ${remotas.length} lista(s) en el servidor; todas están ya en este dispositivo'
                '${puedeCrearHogar ? '' : ' (o se alcanzó el máximo)'}';
      if (n > 0) {
        changed();
        sync.remotaNueva();
      }
      return n;
    } catch (e) {
      diagnosticoRecuperar = 'No se pudo consultar el servidor: $e';
      return 0; // se reintenta la próxima vez que arranque
    }
  }

  Future<String?> unirseConCodigo(String code) async {
    if (code.trim().length < 6) return 'Código no válido';
    if (!puedeCrearHogar) {
      return 'Máximo ${Hogar.maxCompartidos} listas compartidas';
    }
    try {
      final api = sync.api;
      await api.ensureAuth(alias: cfg.alias);
      final r = await api.unirse(code, cfg.alias);
      final id = r['id'] as String;
      if (!hogares.any((h) => h.id == id)) {
        hogares.add(
          Hogar(
            id: id,
            name: r['name'] ?? 'Lista',
            emoji: (r['emoji'] as String?) ?? '🏠',
            esCreador: false,
            remota: true,
          ),
        );
        _lists[id] = [];
        _offers[id] = {};
      }
      currentId = id;
      changed();
      sync.remotaNueva();
      return null;
    } on PbException catch (e) {
      return e.message;
    }
  }

  // ----------------------------------------------------------- privacidad
  Future<bool> get tieneCuentaEnServidor => sync.api.tieneCuenta;

  /// Elimina la cuenta del servidor (si existe) y, opcionalmente, todos los datos de este dispositivo.
  /// Devuelve un mensaje de error, o null si todo fue bien. Si el servidor no responde no se borra nada local.
  Future<String?> eliminarCuenta({required bool borrarLocal}) async {
    try {
      if (await sync.api.tieneCuenta) {
        await sync.api.eliminarCuenta();
      }
    } on PbException catch (e) {
      // 404/401: la cuenta ya no existe en el servidor; se sigue con la limpieza local
      if (e.status != 404 && e.status != 401 && e.status != 400) {
        return e.noConnection
            ? 'Sin conexión: no se pudo borrar tu cuenta del servidor. Inténtalo de nuevo con conexión.'
            : e.message;
      }
      await sync.api.olvidarCuenta();
    }
    // las listas compartidas dejan de estar en este dispositivo
    for (final h in hogares.where((h) => h.remota).toList()) {
      _quitarLocal(h);
    }
    if (borrarLocal) {
      await _borrarDatosLocales();
    } else {
      changed();
    }
    return null;
  }

  Future<void> _borrarDatosLocales() async {
    if (!kIsWeb) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final fotos = Directory('${dir.path}/fotos');
        if (await fotos.exists()) await fotos.delete(recursive: true);
      } catch (_) {}
    }
    await Notifier.cancelAll();
    await _prefs.clear();
    _lists.clear();
    _offers.clear();
    _compras.clear();
    _descartes.clear();
    hogares = [Hogar(id: Hogar.privadaId, name: 'Mi lista', emoji: '🔒')];
    currentId = Hogar.privadaId;
    cfg = Settings();
    stores = [];
    extraStores.clear();
    tiendasDelPropietario.clear();
    _local.clear();
    _opCache.clear();
    _eqCache.clear();
    exclusivos.clear();
    frioManual.clear();
    fotosLocales.clear();
    proponidos.clear();
    coldStart = null;
    coldElapsed.value = 0;
    lat = 40.4168;
    lon = -3.7038;
    locApprox = true;
    tab = 0;
    _load();
    notifyListeners();
  }

  /// Quita la lista de este dispositivo. La lista de origen sigue para los demás
  /// (el creador debe transferir antes la propiedad si hay más miembros).
  Future<String?> desvincular(Hogar h) async {
    if (!h.remota) {
      borrarHogar(h);
      return null;
    }
    try {
      final ms = await sync.api.miembros(h.id);
      final mio = ms.where((m) => m.userId == sync.miId).toList();
      if (mio.isNotEmpty) await sync.api.quitarMiembro(mio.first.recordId);
    } on PbException catch (e) {
      if (e.status != 404 && e.status != 403) return e.message;
    }
    _quitarLocal(h);
    changed();
    return null;
  }

  /// Solo el creador: elimina la lista de origen para todos.
  Future<String?> borrarParaTodos(Hogar h) async {
    if (!h.esCreador) return 'Solo el creador puede borrar la lista para todos';
    try {
      await sync.api.borrarHogar(h.id);
    } on PbException catch (e) {
      // 404 = ya no existe (borrada por otro): se limpia la copia local igualmente
      if (e.status != 404) return e.message;
    }
    _quitarLocal(h);
    changed();
    return null;
  }

  Future<String?> regenerarInvitacion(Hogar h) async {
    try {
      h.inviteCode = await sync.api.regenerarInvitacion(h.id);
      changed();
      return null;
    } on PbException catch (e) {
      return e.message;
    }
  }

  Future<String?> revocar(Hogar h, Miembro m) async {
    try {
      await sync.api.quitarMiembro(m.recordId);
      await sync.sincronizar();
      return null;
    } on PbException catch (e) {
      return e.message;
    }
  }

  Future<String?> transferirA(Hogar h, Miembro m) async {
    try {
      await sync.api.transferir(h.id, m.userId);
      await sync.sincronizar();
      return null;
    } on PbException catch (e) {
      return e.message;
    }
  }

  /// Borra un hogar compartido y su lista. La privada no se puede borrar.
  void borrarHogar(Hogar h) {
    if (h.esPrivada) return;
    for (final o in (_offers[h.id] ?? {}).values) {
      Notifier.cancel(_nid('${h.id}|${o.id}', 1000));
    }
    hogares.remove(h);
    _lists.remove(h.id);
    _offers.remove(h.id);
    _compras.remove(h.id);
    _descartes.remove(h.id);
    if (currentId == h.id) currentId = Hogar.privadaId;
    if (!allItems.any((i) => i.done && i.cold)) stopCold();
    changed();
  }

  void toggleCart() {
    cartOpen = !cartOpen;
    notifyListeners();
  }

  void toggleCold() {
    coldOpen = !coldOpen;
    notifyListeners();
  }

  /// Total comprado agrupado por establecimiento (solo si hay algo comprado).
  List<({String name, double total, int count})> get boughtByStore {
    final m = <String, ({double total, int count})>{};
    for (final i in items.where((i) => i.done)) {
      final n = storeById(i.storeId)?.name ?? 'Sin asignar';
      final cur = m[n] ?? (total: 0.0, count: 0);
      m[n] = (total: cur.total + i.total, count: cur.count + 1);
    }
    return [
      for (final e in m.entries)
        (name: e.key, total: e.value.total, count: e.value.count),
    ];
  }

  void changed() {
    _save();
    notifyListeners();
    sync.programar();
  }

  /// La sincronización modificó la lista: guardar y repintar sin volver a programar otra.
  void cambioSincronizado() {
    _save();
    notifyListeners();
  }

  /// El creador te ha quitado de la lista (o la ha borrado): se elimina la copia local.
  void hogarRevocado(Hogar h) {
    final nombre = h.name;
    _quitarLocal(h);
    _alerts.add('Ya no tienes acceso a «$nombre»');
    changed();
  }

  void _quitarLocal(Hogar h) {
    for (final o in (_offers[h.id] ?? {}).values) {
      Notifier.cancel(_nid('${h.id}|${o.id}', 1000));
    }
    hogares.remove(h);
    _lists.remove(h.id);
    _offers.remove(h.id);
    _compras.remove(h.id);
    sync.olvidar(h.id);
    if (currentId == h.id) currentId = Hogar.privadaId;
  }

  // ------------------------------------------------------------- tiendas / GPS
  void _recomputeKm() {
    for (final s in stores) {
      s.km = haversineKm(lat, lon, s.lat, s.lon);
    }
    stores.sort((a, b) => a.km.compareTo(b.km));
    for (final s in extraStores.values) {
      s.km = haversineKm(lat, lon, s.lat, s.lon);
    }
  }

  Future<void> refreshStores({bool relocate = true}) async {
    loadingStores = true;
    storesError = null;
    notifyListeners();
    try {
      if (relocate) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse) {
          final p = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
            ),
          ).timeout(const Duration(seconds: 10));
          lat = p.latitude;
          lon = p.longitude;
          locApprox = false;
        }
      }
      final found = await nearbyStores(lat, lon, cfg.radiusKm.clamp(1, 10));
      fetchedRadiusKm = cfg.radiusKm;
      if (found.isNotEmpty) {
        stores = found;
        // conserva las activas que sigan existiendo; si no hay ninguna, activa las 3 más cercanas
        cfg.enabled.removeWhere((id) => !stores.any((s) => s.id == id));
        if (cfg.enabled.isEmpty) {
          cfg.enabled = stores.take(3).map((s) => s.id).toSet();
        }
      } else {
        storesError = 'No hay supermercados en OpenStreetMap en ese radio.';
      }
    } catch (e) {
      storesError =
          'No se pudo actualizar (¿sin conexión o sin permiso de ubicación?).';
    }
    loadingStores = false;
    changed();
  }

  List<Store> get activeStores => stores
      .where((s) => cfg.enabled.contains(s.id) && s.km <= cfg.radiusKm)
      .toList();

  Store? storeById(String? id) {
    if (id == null) return null;
    if (tiendasDelPropietario.contains(id) && extraStores[id] != null) {
      return extraStores[id]; // en colisión manda lo que dice el propietario de la lista
    }
    for (final s in stores) {
      if (s.id == id) return s;
    }
    return extraStores[id];
  }

  /// Guarda una tienda que llega por una lista compartida y que no está en mi zona.
  void recordarTienda(Store st, {bool delPropietario = false}) {
    if (!delPropietario && storeById(st.id) != null) return;
    st.km = haversineKm(lat, lon, st.lat, st.lon);
    extraStores[st.id] = st;
    if (delPropietario) tiendasDelPropietario.add(st.id);
  }

  // ------------------------------------------------------------------ precios
  Future<Map<String, Quote>> _quotes(Product p) async {
    final out = <String, Quote>{};
    if (cfg.demoPrices) {
      for (final s in stores) {
        final q = demoQuote(p, s.chain);
        if (q != null) out[s.chain] = q;
      }
    }
    if (p.barcode != null) {
      try {
        final op = _opCache[p.barcode!] ??= await openPrices(p.barcode!);
        out.addAll(op); // datos reales pisan a los de ejemplo
      } catch (_) {}
    }
    // precios de productos equivalentes en Open Prices (solo donde falta el del producto exacto)
    if (p.genericKey != null) {
      try {
        final eq = _eqCache[p.genericKey!] ??= await equivalentOpenPrices(
          p,
        ).timeout(const Duration(seconds: 6), onTimeout: () => {});
        eq.forEach((chain, q) => out.putIfAbsent(chain, () => q));
      } catch (_) {}
    }
    for (final s in stores) {
      final l = _local['${p.key}|${s.chain}'];
      if (l != null &&
          (out[s.chain] == null || l.date.isAfter(out[s.chain]!.date))) {
        out[s.chain] = l;
      }
      // sin precio de este producto: el de uno equivalente (misma categoría y cantidad)
      if (out[s.chain] == null && p.genericKey != null) {
        final g = _local['g:${p.genericKey}|${s.chain}'];
        if (g != null) {
          out[s.chain] = Quote(
            g.price,
            g.date,
            g.source,
            outOfStock: g.outOfStock,
            equivalente: true,
          );
        }
      }
      final o = offers['${p.key}|${s.chain}'];
      if (o != null && o.active) {
        out[s.chain] = Quote(
          o.price,
          DateTime.now(),
          QuoteSource.tu,
          until: o.until,
        );
      }
    }
    return out;
  }

  /// Tiendas candidatas ordenadas según el criterio del usuario.
  Future<List<Option>> options(Product p) async {
    final q = await _quotes(p);
    var st = activeStores;
    if (p.ownChain != null) {
      st = st.where((s) => s.chain == p.ownChain).toList();
    }
    final list = [for (final s in st) Option(s, q[s.chain])];
    final withPrice = list.where((o) => o.price != null).toList();
    // sin ningún precio conocido: se listan igualmente para poder elegir
    final base = p.ownChain != null || withPrice.isEmpty ? list : withPrice;
    num fav(Option o) => cfg.favChains.contains(o.store.chain) ? 0 : 1;
    num pr(Option o) => o.price ?? 9999;
    final keys = switch (cfg.criterion) {
      Criterion.precio => (Option o) => [o.out ? 1 : 0, pr(o), o.store.km],
      Criterion.distancia => (Option o) => [o.out ? 1 : 0, o.store.km, pr(o)],
      Criterion.preferencia => (Option o) => [
        o.out ? 1 : 0,
        fav(o),
        pr(o),
        o.store.km,
      ],
    };
    base.sort((a, b) {
      final x = keys(a), y = keys(b);
      for (var i = 0; i < x.length; i++) {
        final c = x[i].compareTo(y[i]);
        if (c != 0) return c;
      }
      return 0;
    });
    return base;
  }

  // -------------------------------------------------------------------- lista
  Item add(Product p) {
    final it = Item(
      id: PbApi.randomId(),
      name: p.name,
      cold: p.cold,
      barcode: p.barcode,
      imageUrl: p.imageUrl,
      genericKey: p.genericKey,
      localImage: fotosLocales[p.key],
    );
    items.add(it);
    changed();
    if (it.imageUrl == null && it.localImage == null) buscarFotoComunidad(it);
    return it;
  }

  void assign(Item it, Option? o) {
    it.storeId = o?.store.id;
    it.price = o?.price;
    changed();
  }

  Product productOf(Item it) {
    final demo = demoCatalog.where((p) => p.name == it.name);
    final p = demo.isNotEmpty
        ? demo.first
        : Product(
            name: it.name,
            cold: it.cold,
            barcode: it.barcode,
            imageUrl: it.imageUrl,
            genericKey: it.genericKey,
          );
    return conFrio(conExclusivo(p));
  }

  /// Aplica la corrección manual de «refrigerado» si el usuario la hizo para este producto.
  Product conFrio(Product p) {
    final f = frioManual[p.key];
    return f == null || f == p.cold ? p : p.conFrio(f);
  }

  /// Aplica la regla «exclusivo de…» que haya marcado el usuario (no pisa la marca blanca ya conocida).
  Product conExclusivo(Product p) {
    final c = exclusivos[p.key];
    return p.ownChain == null && c != null ? p.conCadena(c) : p;
  }

  // ------------------------------------------------------------ comparativa
  /// Productos que estás comparando ahora (se vacía al cerrar la app; es una herramienta del momento).
  final List<LineaComparar> comparacion = [];

  /// Añade un producto a la comparativa (si ya estaba, completa lo que le faltaba).
  void anadirAComparar(Product p, {String? cantidad, double? precio}) {
    final i = comparacion.indexWhere((l) => l.id == p.key);
    if (i >= 0) {
      final l = comparacion[i];
      l.cantidad ??= cantidad ?? p.quantity;
      l.precio ??= precio;
    } else {
      comparacion.add(
        LineaComparar(
          producto: p,
          cantidad: cantidad ?? p.quantity,
          precio: precio,
        ),
      );
    }
    notifyListeners();
  }

  void quitarDeComparar(LineaComparar l) {
    comparacion.remove(l);
    notifyListeners();
  }

  void limpiarComparacion() {
    comparacion.clear();
    notifyListeners();
  }

  // ------------------------------------------------------- modo compra (escáner)
  /// Producto por código de barras: Open Food Facts y, si no está, la base común (aprobados).
  Future<Product?> buscarProductoPorCodigo(String code) async {
    try {
      final p = await productByBarcode(code);
      if (p != null) return conFrio(conExclusivo(p));
    } catch (_) {}
    final c = await sync.api.buscarProductos(code);
    return c.isEmpty ? null : conFrio(conExclusivo(c.first));
  }

  /// Productos PENDIENTES de la lista activa con exactamente ese código de barras.
  List<Item> pendientesConCodigo(String code) =>
      items.where((i) => !i.done && i.barcode == code).toList();

  /// Productos pendientes equivalentes (misma clave genérica: mismo nombre y tamaño, otra marca), sin contar los exactos.
  List<Item> equivalentesPendientes(Product p) {
    final gk = p.genericKey;
    if (gk == null) return [];
    return items
        .where(
          (i) =>
              !i.done &&
              i.barcode != p.barcode &&
              (i.genericKey ?? productOf(i).genericKey) == gk,
        )
        .toList();
  }

  /// Precio conocido del producto en una tienda (de Open Prices, tuyo, oferta…), o null.
  Future<Quote?> precioConocido(Product p, Store st) async {
    try {
      final o = (await options(p)).where((x) => x.store.chain == st.chain);
      return o.isEmpty ? null : o.first.quote;
    } catch (_) {
      return null;
    }
  }

  /// Cambia el producto de una línea de la lista por otro equivalente (el que has encontrado en la tienda).
  void sustituirItem(Item it, Product p) {
    it.name = p.name;
    it.barcode = p.barcode;
    it.imageUrl = p.imageUrl;
    it.genericKey = p.genericKey;
    it.cold = conFrio(p).cold;
    it.localImage = fotosLocales[p.key];
    changed();
  }

  /// Anota el precio visto en la tienda para un producto (sin que esté en la lista).
  void anotarPrecio(Product p, Store st, double price) {
    final q = Quote(price, DateTime.now(), QuoteSource.tu);
    _local['${p.key}|${st.chain}'] = q;
    if (p.genericKey != null) _local['g:${p.genericKey}|${st.chain}'] = q;
    changed();
  }

  /// Marca (o desmarca) el producto del item como exclusivo de la cadena de su tienda asignada.
  void setExclusivo(Item it, bool on) {
    final st = storeById(it.storeId);
    final key = productOf(it).key;
    if (on && st != null) {
      exclusivos[key] = st.chain;
    } else {
      exclusivos.remove(key);
    }
    changed();
  }

  /// Cadena exclusiva activa para el item, si la hay (marca blanca o regla del usuario).
  String? exclusivoDe(Item it) => productOf(it).ownChain;

  /// Tienda donde está el usuario ahora (por ubicación), o null. Solo usa el permiso si YA está concedido:
  /// nunca lo pide al marcar una compra. Reutiliza la última posición durante 90 s.
  ({double lat, double lon, DateTime t})? _pos;

  Future<Store?> tiendaActual() async {
    if (!cfg.detectarTienda) return null;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.whileInUse &&
          perm != LocationPermission.always) {
        return null;
      }
      if (_pos == null || DateTime.now().difference(_pos!.t).inSeconds > 90) {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 5));
        _pos = (lat: p.latitude, lon: p.longitude, t: DateTime.now());
      }
      return tiendaMasCercana(_pos!.lat, _pos!.lon, [
        ...stores,
        ...extraStores.values,
      ]);
    } catch (_) {
      return null;
    }
  }

  /// Si la ubicación dice que estás en otra tienda de la que tenía asignada el producto, lo reasigna
  /// (y su compra) y avisa con la opción de deshacer.
  Future<void> reasignarSiOtraTienda(Item it, Store? donde) async {
    if (donde == null || !it.done || donde.id == it.storeId) return;
    final antes = it.storeId;
    final nombreAntes = storeById(antes)?.name;
    _cambiarTiendaCompra(it, donde.id, donde.name);
    it.storeId = donde.id;
    changed();
    _avisos.add(
      Aviso(
        'Comprado en ${donde.name} (detectado por ubicación)'
        '${nombreAntes == null ? '' : ' · antes: $nombreAntes'}',
        deshacer: () {
          it.storeId = antes;
          _cambiarTiendaCompra(it, antes, nombreAntes);
          changed();
        },
      ),
    );
  }

  void _cambiarTiendaCompra(Item it, String? id, String? nombre) {
    final i = compras.lastIndexWhere((c) => c.itemId == it.id);
    if (i < 0) return;
    final c = compras[i];
    compras[i] = Compra(
      id: c.id,
      itemId: c.itemId,
      key: c.key,
      name: c.name,
      qty: c.qty,
      price: c.price,
      storeId: id,
      storeName: nombre,
      ms: c.ms,
      by: c.by,
    );
  }

  // ------------------------------------------------------------- tickets
  /// Súper del ticket: el indicado, o el activo de la cadena impresa en la cabecera.
  Store? tiendaDeTicket(Ticket t) {
    final c = t.cadena;
    if (c == null) return null;
    final act = activeStores.where((s) => s.chain == c);
    if (act.isNotEmpty) return act.first;
    final todas = stores.where((s) => s.chain == c);
    return todas.isEmpty ? null : todas.first;
  }

  /// Cruza el ticket con los productos pendientes de la lista (usa los alias ya confirmados en esa cadena).
  List<Cruce> cruzar(Ticket t) {
    final pend = items.where((i) => !i.done).toList();
    final pre = '${t.cadena ?? ''}|';
    final alias = <String, String>{};
    for (final e in aliasTicket.entries) {
      if (!e.key.startsWith(pre)) continue;
      final it = pend.where((i) => i.name == e.value);
      if (it.isNotEmpty) alias[e.key.substring(pre.length)] = it.first.id;
    }
    return cruzarTicket(t, [
      for (final i in pend) Candidato(i.id, i.name),
    ], alias: alias);
  }

  /// Aplica el ticket: los cruces «seguros» y los dudosos que el usuario resolvió (`elegidos`: línea → id de item)
  /// marcan su producto como comprado; TODAS las líneas pasan al historial y a los precios propios.
  /// Los dudosos sin resolver y los nuevos solo se guardan como compras sueltas. Devuelve cuántos de la lista se marcaron.
  int aplicarTicket(
    Ticket t,
    List<Cruce> cruces, {
    Map<int, String> elegidos = const {},
    Store? tienda,
  }) {
    final st = tienda ?? tiendaDeTicket(t);
    final ms = (t.fecha ?? DateTime.now()).millisecondsSinceEpoch;
    var marcados = 0;
    for (var i = 0; i < cruces.length; i++) {
      final c = cruces[i], l = c.linea;
      final id = c.estado == EstadoCruce.seguro ? c.itemId : elegidos[i];
      final it = id == null ? null : items.where((x) => x.id == id).firstOrNull;
      final unidades = l.porPeso ? 1 : (l.cantidad ?? 1).round().clamp(1, 999);
      final pagado =
          l.neto /
          unidades; // por unidad (o el importe de la pieza si va por peso)
      final nombre = it?.name ?? l.nombre;
      final key = it == null ? nombre.toLowerCase() : productOf(it).key;
      if (it != null) {
        it.done = true;
        it.cantidad = unidades;
        it.price = pagado;
        if (st != null) it.storeId = st.id;
        aliasTicket['${t.cadena ?? ''}|${normalizarNombre(l.nombre)}'] =
            it.name;
      }
      // precio de estantería (sin promos personales) como precio conocido de la cadena
      if (st != null) {
        final unit = l.porPeso ? l.bruto : l.bruto / unidades;
        _local['$key|${st.chain}'] = Quote(
          unit,
          DateTime.fromMillisecondsSinceEpoch(ms),
          QuoteSource.tu,
        );
      }
      compras.add(
        Compra(
          id: PbApi.randomId(),
          itemId: it?.id ?? 'ticket',
          key: key,
          name: nombre,
          qty: unidades,
          price: pagado,
          storeId: st?.id,
          storeName: st?.name,
          ms: ms,
          by: sync.miId,
        ),
      );
      if (it != null) marcados++;
    }
    changed();
    return marcados;
  }

  void toggleDone(Item it) {
    it.done = !it.done;
    if (it.done) {
      _registrarCompra(it);
      // en segundo plano: no retrasa la marca
      tiendaActual().then((st) => reasignarSiOtraTienda(it, st));
    } else {
      _deshacerCompra(it);
    }
    if (it.done && it.cold && cfg.coldTimer && coldStart == null) {
      coldStart = DateTime.now();
      _fired.clear();
      coldElapsed.value = 0;
      _scheduleCold();
    }
    if (!it.done && !allItems.any((i) => i.done && i.cold)) stopCold();
    changed();
  }

  /// Guarda en el historial que se ha comprado este producto (con su precio, tienda y cantidad de ese momento).
  void _registrarCompra(Item it) {
    final p = productOf(it);
    final st = storeById(it.storeId);
    compras.add(
      Compra(
        id: PbApi.randomId(),
        itemId: it.id,
        key: p.key,
        name: it.name,
        qty: it.cantidad,
        price: it.price,
        storeId: it.storeId,
        storeName: st?.name,
        ms: DateTime.now().millisecondsSinceEpoch,
        by: sync.miId,
      ),
    );
  }

  /// Desmarcar un producto retira su compra más reciente (era un error o se arrepintió).
  void _deshacerCompra(Item it) {
    final i = compras.lastIndexWhere((c) => c.itemId == it.id);
    if (i < 0) return;
    final c = compras.removeAt(i);
    sync.compraRetirada(currentId, c.id);
  }

  // ----------------------------------------------------------- recompra
  /// Productos que según tu historial toca reponer (vacío si está desactivado).
  List<Sugerencia> get sugerencias {
    if (!cfg.recompra) return const [];
    return calcularSugerencias(
      compras: compras,
      yaEnLista: {
        for (final i in items.where((i) => !i.done)) productOf(i).key,
      },
      descartes: descartes,
      ahora: DateTime.now(),
    );
  }

  /// Convierte una sugerencia en un producto real de la lista.
  Item anadirSugerencia(Sugerencia sg) {
    final esCodigo = RegExp(r'^\d{8,14}$').hasMatch(sg.key);
    final it = add(
      Product(
        name: sg.name,
        barcode: esCodigo ? sg.key : null,
        cold: frioManual[sg.key] ?? looksCold(sg.name),
      ),
    );
    if (sg.storeId != null && storeById(sg.storeId) != null) {
      it.storeId = sg.storeId;
      it.price = sg.price;
    }
    descartes[sg.key]?.veces = 0;
    changed();
    return it;
  }

  /// El usuario toca el círculo de una sugerencia: se quita sin contar como compra. Devuelve true si ya
  /// la ha descartado varias veces seguidas y conviene preguntarle qué quiere.
  bool descartarSugerencia(Sugerencia sg) {
    final d = descartes.putIfAbsent(sg.key, () => Descarte());
    d.veces++;
    // no vuelve a molestar al menos hasta pasada media vida del producto
    final dias = (sg.cadaDias / 2).clamp(2, 60).round();
    d.silenciadoHasta = DateTime.now()
        .add(Duration(days: dias))
        .millisecondsSinceEpoch;
    changed();
    return d.veces >= 3;
  }

  void resolverRecurrente(String key, DecisionRecompra decision) {
    final d = descartes.putIfAbsent(key, () => Descarte());
    d.veces = 0;
    switch (decision) {
      case DecisionRecompra.estacional:
        d.silenciadoHasta = DateTime.now()
            .add(const Duration(days: 90))
            .millisecondsSinceEpoch;
      case DecisionRecompra.parar:
        d.parar = true;
      case DecisionRecompra.seguir:
        d.silenciadoHasta = 0;
    }
    changed();
  }

  /// Vuelve a sugerir todo lo que se había silenciado o apagado en esta lista.
  void restablecerSugerencias() {
    descartes.clear();
    changed();
  }

  void setCantidad(Item it, int n) {
    it.cantidad = n.clamp(1, 999);
    changed();
  }

  /// Si el producto no tiene foto, busca una aprobada en la base colaborativa (sin sesión).
  Future<void> buscarFotoComunidad(Item it) async {
    try {
      final url = await sync.api.fotoComunidad(productOf(it).key);
      if (url != null && it.imageUrl == null && items.contains(it)) {
        it.imageUrl = url;
        changed();
      }
    } catch (_) {}
  }

  /// Foto propia de un producto (solo en este dispositivo). `path` null = quitarla.
  void setFotoLocal(Item it, String? path) {
    final key = productOf(it).key;
    if (path == null) {
      fotosLocales.remove(key);
    } else {
      fotosLocales[key] = path;
    }
    for (final other in allItems.where((x) => productOf(x).key == key)) {
      other.localImage = path;
    }
    changed();
  }

  /// Propone un producto NUEVO a la base general (queda pendiente de moderación).
  /// Falla en silencio si no hay conexión: el producto sigue en la lista del usuario.
  Future<void> proponerProducto(Product p) async {
    if (!cfg.shareNewProducts || proponidos.contains(p.key)) return;
    try {
      await sync.api.proponerProducto(p);
      proponidos.add(p.key);
      changed();
    } on PbException catch (e) {
      // 400 = ya existe o límite: no se reintenta
      if (e.status == 400) {
        proponidos.add(p.key);
        changed();
      }
    }
  }

  /// Cambia el nombre (y tamaño) con el que ves un producto. El código de barras, si lo hay, sigue siendo su identificador.
  void setNombre(Item it, String nombre) {
    final n = nombre.trim();
    if (n.isEmpty || n == it.name) return;
    it.name = n;
    changed();
  }

  void setUrgency(Item it, int urg) {
    it.urg = urg.clamp(1, 3);
    changed();
  }

  /// Corrige si un producto es refrigerado. Se recuerda para ese producto (código de barras o nombre):
  /// la leche UHT y la fresca son productos distintos si tienen distinto nombre o código.
  void setCold(Item it, bool cold) {
    it.cold = cold;
    frioManual[productOf(it).key] = cold;
    changed();
  }

  /// Fija el precio de un item.
  /// - Habitual: se recuerda para comparar la próxima vez.
  /// - Oferta: solo vale para este item (y, si hay fecha límite, se guarda como oferta temporal);
  ///   no cambia el precio habitual.
  void setPrice(
    Item it,
    double? price, {
    bool oferta = false,
    DateTime? hasta,
  }) {
    if (price == null || price <= 0) {
      it.price = null;
      changed();
      return;
    }
    final st = storeById(it.storeId);
    if (oferta) {
      it.price = price;
      if (hasta != null && st != null) {
        addOffer(
          Offer(
            key: productOf(it).key,
            name: it.name,
            chain: st.chain,
            price: price,
            until: hasta,
          ),
        );
        return;
      }
      changed();
    } else {
      recordPrice(it, price);
      if (st == null) {
        it.price = price;
        changed();
      }
    }
  }

  void remove(Item it) {
    items.remove(it);
    changed();
  }

  void clearDone() {
    items.removeWhere((i) => i.done);
    changed();
  }

  /// El usuario anota lo que ha pagado: alimenta la capa local de precios.
  void recordPrice(Item it, double price) {
    final s = storeById(it.storeId);
    if (s == null) return;
    final p = productOf(it);
    final q = Quote(price, DateTime.now(), QuoteSource.tu);
    _local['${p.key}|${s.chain}'] = q;
    if (p.genericKey != null) _local['g:${p.genericKey}|${s.chain}'] = q;
    it.price = price;
    changed();
  }

  void markOutOfStock(Item it) {
    final s = storeById(it.storeId);
    if (s == null) return;
    _local['${productOf(it).key}|${s.chain}'] = Quote(
      null,
      DateTime.now(),
      QuoteSource.tu,
      outOfStock: true,
    );
    changed();
  }

  // ------------------------------------------------------------------ ofertas
  int _nid(String s, int base) {
    var h = 0x811c9dc5; // FNV-1a
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x3fffffff;
    }
    return base + h % 100000;
  }

  DateTime? _offerAlertAt(Offer o) {
    final d = cfg.offerReminderDays;
    if (d <= 0 || !o.active) return null;
    final until = DateTime(o.until.year, o.until.month, o.until.day);
    final now = DateTime.now();
    var at = DateTime(until.year, until.month, until.day - d, 10);
    if (!at.isAfter(now)) at = DateTime(now.year, now.month, now.day, 10);
    if (!at.isAfter(now)) {
      at = now.add(const Duration(minutes: 1)); // ya pasadas las 10:00
    }
    return at;
  }

  void _scheduleOffer(Offer o, [String? home]) {
    final at = _offerAlertAt(o);
    final id = _nid('${home ?? currentId}|${o.id}', 1000);
    Notifier.cancel(id);
    if (at == null) return;
    final left = o.daysLeft;
    Notifier.schedule(
      id,
      'Oferta a punto de caducar',
      '${o.name} a ${eur(o.price)} en ${prettyChain(o.chain)}: '
          '${left <= 0 ? 'último día' : 'hasta el ${shortDate(o.until)}'}.',
      at,
    );
  }

  void _scheduleOffers() {
    _offers.forEach((home, m) {
      for (final o in m.values) {
        _scheduleOffer(o, home);
      }
    });
  }

  void applyOfferSettings() {
    _scheduleOffers();
    changed();
  }

  void addOffer(Offer o) {
    offers[o.id] = o;
    for (final it in items) {
      final st = storeById(it.storeId);
      if (!it.done &&
          st != null &&
          st.chain == o.chain &&
          productOf(it).key == o.key) {
        it.price = o.price;
      }
    }
    _scheduleOffer(o);
    changed();
  }

  void removeOffer(Offer o) {
    offers.remove(o.id);
    Notifier.cancel(_nid('$currentId|${o.id}', 1000));
    changed();
  }

  List<Offer> get offerList {
    final l = offers.values.where((o) => o.active).toList()
      ..sort((a, b) => a.until.compareTo(b.until));
    return l;
  }

  /// Ofertas que caducan dentro del margen de aviso (mínimo 1 día).
  List<Offer> get expiringOffers {
    final d = cfg.offerReminderDays < 1 ? 1 : cfg.offerReminderDays;
    return offerList.where((o) => o.daysLeft <= d).toList();
  }

  List<Item> get visible {
    final l = items
        .where(
          (i) => switch (filter) {
            ColdFilter.todo => true,
            ColdFilter.frio => i.cold,
            ColdFilter.seco => !i.cold,
          },
        )
        .toList();
    l.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (a.urg != b.urg) return a.urg - b.urg;
      return a.name.compareTo(b.name);
    });
    return l;
  }

  double get totalPending =>
      items.where((i) => !i.done).fold(0.0, (t, i) => t + i.total);
  double get totalBought =>
      items.where((i) => i.done).fold(0.0, (t, i) => t + i.total);

  // -------------------------------------------------------- frío en tránsito
  static const _coldIds = [1, 2, 3];

  void _scheduleCold() {
    for (final id in _coldIds) {
      Notifier.cancel(id);
    }
    if (coldStart == null || !cfg.coldTimer) return;
    final start = coldStart!, win = coldWindowSec;
    Notifier.schedule(
      1,
      'Fríos fuera de la nevera',
      'Llevan 20 min. Te quedan ${(win / 60).round() - 20} min para llegar a casa.',
      start.add(const Duration(minutes: 20)),
    );
    Notifier.schedule(
      2,
      'Quedan 10 minutos',
      'Refrigera los productos fríos ya.',
      start.add(Duration(seconds: win - 600)),
    );
    Notifier.schedule(
      3,
      'Tiempo agotado',
      'Revisa los fríos antes de consumirlos.',
      start.add(Duration(seconds: win)),
    );
  }

  /// Cambió la bolsa o el interruptor: recalcula los avisos en marcha.
  void applyColdSettings() {
    _fired.clear();
    _scheduleCold();
    changed();
  }

  void stopCold() {
    coldStart = null;
    _scheduleCold();
    coldElapsed.value = 0;
    _fired.clear();
    changed();
  }

  void _tick({bool silent = false}) {
    if (coldStart == null) return;
    if (!cfg.coldTimer) return;
    final el = DateTime.now().difference(coldStart!).inSeconds;
    coldElapsed.value = el;
    final win = coldWindowSec;
    final marks = <String, int>{
      'inicio': 20 * 60,
      'ultimos': win - 10 * 60,
      'fin': win,
    };
    marks.forEach((k, at) {
      if (at > 0 && el >= at && _fired.add(k)) {
        if (silent) return; // al reabrir la app no se repiten avisos pasados
        final left = ((win - el) / 60).ceil();
        _alerts.add(switch (k) {
          'inicio' =>
            'Los fríos llevan 20 min fuera de la nevera. Te quedan ${left > 0 ? left : 0} min para llegar a casa.',
          'ultimos' => '¡Quedan 10 min! Refrigera los productos fríos ya.',
          _ =>
            'Se ha agotado el tiempo: revisa los fríos antes de consumirlos.',
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    sync.dispose();
    _alerts.close();
    super.dispose();
  }
}
