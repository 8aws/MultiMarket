import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../state.dart';
import 'pb_api.dart';
import '../models.dart';
import 'reconcile.dart';

/// Sincroniza las listas compartidas con PocketBase:
/// local primero, subida/bajada por conciliación y tiempo real (SSE) para avisar de cambios.
class SyncService extends ChangeNotifier {
  SyncService(this.s);
  final AppState s;

  PbApi? _api;
  String _apiUrl = '';
  bool _again = false;
  Timer? _debounce, _poll, _retry;

  /// Fallos seguidos (0 = todo bien). Sube la espera de los reintentos automáticos.
  int fallos = 0;
  DateTime? proximoReintento;

  /// Espera antes del reintento automático tras `fallos` fallos seguidos: 5 s, 15 s, 45 s, 2 min, 5 min.
  static Duration esperaReintento(int fallos) {
    const segundos = [5, 15, 45, 120, 300];
    return Duration(
      seconds: segundos[(fallos - 1).clamp(0, segundos.length - 1)],
    );
  }

  /// Cambios locales que aún no se han subido al servidor (productos nuevos o modificados).
  int get cambiosPendientes {
    var n = 0;
    for (final h in s.hogares.where((h) => h.remota)) {
      final last = _sigs[h.id] ?? const <String, String>{};
      for (final i in s.itemsOf(h.id)) {
        if (last[i.id] != sigOf(i)) n++;
      }
    }
    return n;
  }

  /// Reintenta ya (botón «Reintentar»).
  Future<void> reintentarAhora() {
    _retry?.cancel();
    return sincronizar();
  }

  void _programarReintento() {
    _retry?.cancel();
    final e = esperaReintento(fallos);
    proximoReintento = DateTime.now().add(e);
    _retry = Timer(e, () {
      if (!_stopped) sincronizar();
    });
  }

  final Map<String, Map<String, String>> _sigs = {}; // hogar → item → firma
  final Map<String, List<Miembro>> miembros = {};
  final Map<String, String> aliasDe =
      {}; // userId → alias (para mostrar autoría)

  DateTime? ultimaSync;
  String? error;
  bool sincronizando = false;
  bool _stopped = false;

  PbApi get api {
    if (_api == null || _apiUrl != s.cfg.serverUrl) {
      _api = PbApi(s.prefs, s.cfg.serverUrl);
      _apiUrl = s.cfg.serverUrl;
    }
    return _api!;
  }

  String? get miId => _api?.userId;
  bool get hayRemotas => s.hogares.any((h) => h.remota);

  // ------------------------------------------------------------ persistencia
  void cargar() {
    try {
      final raw =
          jsonDecode(s.prefs.getString('syncSigs') ?? '{}')
              as Map<String, dynamic>;
      raw.forEach((h, m) => _sigs[h] = (m as Map).cast<String, String>());
      _comprasSubidas.addAll(
        (jsonDecode(s.prefs.getString('syncComprasSubidas') ?? '[]') as List)
            .cast<String>(),
      );
      _comprasBorrar.addAll(
        (jsonDecode(s.prefs.getString('syncComprasBorrar') ?? '[]') as List)
            .cast<String>(),
      );
    } catch (_) {}
  }

  void _guardar() {
    s.prefs.setString('syncSigs', jsonEncode(_sigs));
    s.prefs.setString(
      'syncComprasSubidas',
      jsonEncode(_comprasSubidas.toList()),
    );
    s.prefs.setString('syncComprasBorrar', jsonEncode(_comprasBorrar.toList()));
  }

  // ------------------------------------------------------------- historial
  /// Compras ya enviadas al servidor ('hogar|id') y retiradas pendientes de borrar allí.
  final Set<String> _comprasSubidas = {};
  final Set<String> _comprasBorrar = {};

  /// Se llama cuando el usuario desmarca un producto: la compra ya no cuenta, también en el servidor.
  void compraRetirada(String hogarId, String compraId) {
    final h = s.hogares.where((x) => x.id == hogarId).firstOrNull;
    if (h == null || !h.remota) return;
    if (_comprasSubidas.contains('$hogarId|$compraId')) {
      _comprasBorrar.add('$hogarId|$compraId');
    }
  }

  Future<void> _compras(Hogar h, PbApi a) async {
    Future<void> pausa() => Future.delayed(const Duration(milliseconds: 260));
    // 1) retiradas pendientes
    for (final k
        in _comprasBorrar.where((k) => k.startsWith('${h.id}|')).toList()) {
      await a.borrarCompra(k.split('|')[1]);
      _comprasBorrar.remove(k);
      _comprasSubidas.remove(k);
      await pausa();
    }
    final remotas = await a.comprasRemotas(h.id);
    final enServidor = {for (final r in remotas) r['id'] as String};
    final locales = s.comprasDe(h.id);
    // 2) las que subí y ya no están en el servidor: alguien las retiró
    locales.removeWhere(
      (c) =>
          _comprasSubidas.contains('${h.id}|${c.id}') &&
          !enServidor.contains(c.id),
    );
    final idsLocales = {for (final c in locales) c.id};
    // 3) subo las mías nuevas
    for (final c in locales) {
      if (enServidor.contains(c.id)) {
        _comprasSubidas.add('${h.id}|${c.id}');
        continue;
      }
      await a.crearCompra({
        'id': c.id,
        'hogar': h.id,
        'key': c.key,
        'name': c.name,
        'qty': c.qty,
        'price': c.price,
        'store_id': c.storeId ?? '',
        'store_name': c.storeName ?? '',
        'ms': c.ms,
        'item_id': c.itemId,
        'by': a.userId,
      });
      _comprasSubidas.add('${h.id}|${c.id}');
      await pausa();
    }
    // 4) bajo las de los demás
    for (final r in remotas) {
      final id = r['id'] as String;
      if (idsLocales.contains(id)) continue;
      String? v(String k) =>
          (r[k] as String?)?.isEmpty == true ? null : r[k] as String?;
      locales.add(
        Compra(
          id: id,
          itemId: v('item_id') ?? '',
          key: r['key'],
          name: r['name'],
          qty: ((r['qty'] as num?) ?? 1).toInt(),
          price: (r['price'] as num?)?.toDouble(),
          storeId: v('store_id'),
          storeName: v('store_name'),
          ms: (r['ms'] as num).toInt(),
          by: v('by'),
        ),
      );
      _comprasSubidas.add('${h.id}|$id');
    }
    locales.sort((x, y) => x.ms.compareTo(y.ms));
  }

  /// Arranca la sincronización si hay listas compartidas.
  void iniciar() {
    cargar();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => programar());
    if (hayRemotas) {
      programar(ms: 300);
      _escucharTiempoReal();
    }
  }

  /// Pide una sincronización (agrupa llamadas seguidas).
  void programar({int ms = 700}) {
    if (_stopped || !hayRemotas) return;
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: ms), sincronizar);
  }

  Future<void>? _actual;

  /// Sincroniza ahora. Si ya hay una en marcha, espera a que acabe y repite una vez más
  /// (así quien llama siempre ve el resultado de cambios hechos antes de llamar).
  Future<void> sincronizar() {
    if (!hayRemotas) return Future.value();
    if (_actual != null) {
      _again = true;
      return _actual!;
    }
    final f = _ejecutar();
    _actual = f;
    return f.whenComplete(() => _actual = null);
  }

  Future<void> _ejecutar() async {
    do {
      _again = false;
      sincronizando = true;
      notifyListeners();
      try {
        for (final h in List<Hogar>.of(s.hogares.where((h) => h.remota))) {
          await _hogar(h);
        }
        error = null;
        fallos = 0;
        proximoReintento = null;
        _retry?.cancel();
        ultimaSync = DateTime.now();
      } on PbException catch (e) {
        error = e.noConnection
            ? 'Sin conexión con el servidor'
            : 'El servidor respondió con un error: ${e.message}';
        fallos++;
        _programarReintento();
        _again = false; // no insistir en bucle si hay error
      } catch (e) {
        error = 'Error inesperado al sincronizar';
        fallos++;
        _programarReintento();
        _again = false;
      } finally {
        sincronizando = false;
        _guardar();
        notifyListeners();
      }
    } while (_again);
  }

  // ---------------------------------------------------------------- un hogar
  Item _deRemoto(Map<String, dynamic> r) => Item(
    id: r['id'],
    name: r['name'] ?? '',
    cold: r['cold'] == true,
    urg: ((r['urg'] as num?) ?? 2).toInt().clamp(1, 3),
    done: r['done'] == true,
    storeId: (r['store_id'] as String?)?.isEmpty == true ? null : r['store_id'],
    price: ((r['price'] as num?)?.toDouble() ?? 0) > 0
        ? (r['price'] as num).toDouble()
        : null,
    barcode: (r['barcode'] as String?)?.isEmpty == true ? null : r['barcode'],
    addedBy: (r['added_by'] as String?)?.isEmpty == true ? null : r['added_by'],
    updatedMs: ((r['updated_ms'] as num?) ?? 0).toInt(),
    cantidad: ((r['qty'] as num?) ?? 1).toInt().clamp(1, 999),
    imageUrl: (r['image_url'] as String?)?.isEmpty == true
        ? null
        : r['image_url'],
    genericKey: (r['generic_key'] as String?)?.isEmpty == true
        ? null
        : r['generic_key'],
  );

  /// Datos de la tienda del producto, para que otros dispositivos puedan mostrarla.
  Map<String, dynamic> _tiendaRemota(Item i) {
    final st = s.storeById(i.storeId);
    return {
      'store_name': st?.name ?? '',
      'store_chain': st?.chain ?? '',
      'store_lat': st?.lat,
      'store_lon': st?.lon,
    };
  }

  Map<String, dynamic> _aRemoto(String hogarId, Item i) => {
    ..._tiendaRemota(i),
    'hogar': hogarId,
    'name': i.name,
    'barcode': i.barcode ?? '',
    'cold': i.cold,
    'urg': i.urg,
    'done': i.done,
    'store_id': i.storeId ?? '',
    'price': i.price,
    'added_by': i.addedBy,
    'updated_ms': i.updatedMs,
    'qty': i.cantidad,
    'image_url': i.imageUrl ?? '',
    'generic_key': i.genericKey ?? '',
  };

  Future<void> _hogar(Hogar h) async {
    final a = api;
    await a.ensureAuth(alias: s.cfg.alias);
    // ¿sigo teniendo acceso?
    final info = await a.hogar(h.id);
    if (info == null) {
      s.hogarRevocado(h);
      return;
    }
    h.name = info['name'] ?? h.name;
    h.emoji = (info['emoji'] as String?)?.isNotEmpty == true
        ? info['emoji']
        : h.emoji;
    h.esCreador = info['owner'] == a.userId;
    if (h.esCreador) h.inviteCode = info['invite_code'] as String?;

    final local = s.itemsOf(h.id);
    // ids antiguos (formato local) no valen en el servidor
    for (final l in local) {
      if (!PbApi.idValido.hasMatch(l.id)) {
        _sigs[h.id]?.remove(l.id);
        l.id = PbApi.randomId();
      }
      l.addedBy ??= a.userId;
    }
    final raws = await a.items(h.id);
    // tiendas elegidas por otros miembros que no tengo en mi zona
    for (final r in raws) {
      final id = r['store_id'] as String?;
      final name = r['store_name'] as String?;
      if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
      final lat = (r['store_lat'] as num?)?.toDouble();
      final lon = (r['store_lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      s.recordarTienda(
        delPropietario: r['added_by'] == info['owner'],
        Store(
          id: id,
          name: name,
          chain: ((r['store_chain'] as String?) ?? '').isEmpty
              ? name.toLowerCase()
              : r['store_chain'] as String,
          lat: lat,
          lon: lon,
        ),
      );
    }
    final remote = [for (final r in raws) _deRemoto(r)];
    final last = _sigs.putIfAbsent(h.id, () => {});
    final now = DateTime.now().millisecondsSinceEpoch;
    final plan = reconcile(local: local, remote: remote, last: last, now: now);

    // --- bajar
    for (final r in plan.updateLocal) {
      final i = local.indexWhere((x) => x.id == r.id);
      if (i >= 0) {
        r.localImage =
            local[i].localImage; // la foto propia es solo de este dispositivo
        local[i] = r;
      }
    }
    local.addAll(plan.addLocal);
    local.removeWhere((x) => plan.removeLocal.contains(x.id));

    // --- subir (con pausas por el límite de peticiones del servidor)
    Future<void> pausa() => Future.delayed(const Duration(milliseconds: 260));
    for (final l in plan.pushCreate) {
      await a.crearItem({'id': l.id, ..._aRemoto(h.id, l)});
      await pausa();
    }
    for (final l in plan.pushUpdate) {
      await a.editarItem(l.id, _aRemoto(h.id, l)..remove('hogar'));
      await pausa();
    }
    for (final id in plan.pushDelete) {
      await a.borrarItem(id);
      await pausa();
    }
    // productos ya sincronizados antes de existir los datos de tienda: se completan una vez
    final yaSubidos = {
      ...plan.pushCreate.map((x) => x.id),
      ...plan.pushUpdate.map((x) => x.id),
    };
    for (final r in raws) {
      final id = r['id'] as String;
      final item = local.where((x) => x.id == id).firstOrNull;
      if (item == null || yaSubidos.contains(id) || item.storeId == null) {
        continue;
      }
      if (((r['store_name'] as String?) ?? '').isNotEmpty) continue;
      if (s.storeById(item.storeId) == null) continue;
      await a.editarItem(id, _tiendaRemota(item));
      await pausa();
    }

    last
      ..clear()
      ..addAll(plan.sigs);
    try {
      final m = await a.miembros(h.id);
      miembros[h.id] = m;
      for (final x in m) {
        aliasDe[x.userId] = x.alias;
      }
    } on PbException {
      /* se reintenta en la siguiente */
    }
    try {
      await _compras(h, a);
    } on PbException {
      /* el historial se reintenta en la siguiente sincronización */
    }
    s.cambioSincronizado();
  }

  // ------------------------------------------------------- tiempo real (SSE)
  bool _escuchando = false;

  Future<void> _escucharTiempoReal() async {
    if (_escuchando || _stopped) return;
    _escuchando = true;
    var espera = 2;
    while (!_stopped && hayRemotas) {
      try {
        final a = api;
        await a.ensureAuth(alias: s.cfg.alias);
        final req = http.Request('GET', Uri.parse('${a.baseUrl}/api/realtime'))
          ..headers['Accept'] = 'text/event-stream';
        final resp = await a.client
            .send(req)
            .timeout(const Duration(seconds: 20));
        String? clientId;
        String evento = '';
        await for (final linea
            in resp.stream
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (_stopped) break;
          if (linea.startsWith('event:')) {
            evento = linea.substring(6).trim();
          } else if (linea.startsWith('data:')) {
            if (evento == 'PB_CONNECT') {
              clientId =
                  (jsonDecode(linea.substring(5)) as Map)['clientId']
                      as String?;
              if (clientId != null) {
                await a.call(
                  'POST',
                  '/api/realtime',
                  body: {
                    'clientId': clientId,
                    'subscriptions': ['items', 'miembros', 'avisos'],
                  },
                );
                espera = 2;
                programar(ms: 100);
              }
            } else if (evento == 'avisos') {
              try {
                final d = jsonDecode(linea.substring(5)) as Map;
                if (d['action'] == 'create') {
                  s.avisoRemoto((d['record'] as Map).cast<String, dynamic>());
                }
              } catch (_) {}
            } else {
              programar(ms: 250); // algo cambió en el hogar
            }
          }
        }
      } catch (_) {
        // se reintenta abajo
      }
      if (_stopped || !hayRemotas) break;
      await Future.delayed(Duration(seconds: espera));
      espera = (espera * 2).clamp(2, 60);
    }
    _escuchando = false;
  }

  /// Llamar tras crear/unirse a una lista remota.
  void remotaNueva() {
    programar(ms: 100);
    _escucharTiempoReal();
  }

  void olvidar(String hogarId) {
    _comprasSubidas.removeWhere((k) => k.startsWith('$hogarId|'));
    _comprasBorrar.removeWhere((k) => k.startsWith('$hogarId|'));
    _sigs.remove(hogarId);
    miembros.remove(hogarId);
    _guardar();
  }

  @override
  void dispose() {
    _stopped = true;
    _debounce?.cancel();
    _poll?.cancel();
    _retry?.cancel();
    super.dispose();
  }
}
