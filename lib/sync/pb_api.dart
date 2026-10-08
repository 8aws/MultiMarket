import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class PbException implements Exception {
  PbException(this.status, this.message);
  final int status;
  final String message;
  bool get noConnection => status == 0;
  @override
  String toString() => message;
}

class Miembro {
  Miembro({
    required this.recordId,
    required this.userId,
    required this.alias,
    required this.rol,
  });
  final String recordId, userId, alias, rol;
  bool get esCreador => rol == 'owner';
}

/// Cliente REST mínimo de PocketBase. La identidad es un usuario "de dispositivo":
/// correo `<aleatorio>@device.invalid` y contraseña aleatoria, guardados en el llavero.
class PbApi {
  PbApi(this._prefs, this.baseUrl, {http.Client? client})
    : _http = client ?? http.Client();

  final SharedPreferences _prefs;
  final http.Client _http;
  String baseUrl;
  String? _token;
  String? userId;

  static const _store = FlutterSecureStorage();
  static final _rnd = Random.secure();
  static String randomId([int n = 15]) {
    const abc = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(n, (_) => abc[_rnd.nextInt(abc.length)]).join();
  }

  static final idValido = RegExp(r'^[a-z0-9]{15}$');

  // ------------------------------------------------------------ credenciales
  Future<String?> _read(String k) async {
    try {
      final v = await _store.read(key: k);
      if (v != null) return v;
    } catch (_) {}
    return _prefs.getString(
      'sec:$k',
    ); // alternativa si el llavero no está disponible
  }

  Future<void> _write(String k, String v) async {
    try {
      await _store.write(key: k, value: v);
      return;
    } catch (_) {}
    await _prefs.setString('sec:$k', v);
  }

  Future<bool> get tieneCuenta async => await _read('mm_email') != null;

  /// Crea (si hace falta) la cuenta del dispositivo e inicia sesión.
  Future<void> ensureAuth({String alias = ''}) async {
    if (_token != null && userId != null) return;
    var email = await _read('mm_email');
    var pass = await _read('mm_pass');
    if (email == null || pass == null) {
      email = '${randomId(12)}@device.invalid';
      pass = randomId(28);
      await _raw(
        'POST',
        '/api/collections/users/records',
        body: {
          'email': email,
          'password': pass,
          'passwordConfirm': pass,
          'alias': alias,
        },
      );
      await _write('mm_email', email);
      await _write('mm_pass', pass);
    }
    final r = await _raw(
      'POST',
      '/api/collections/users/auth-with-password',
      body: {'identity': email, 'password': pass},
    );
    _token = r['token'] as String;
    userId = (r['record'] as Map)['id'] as String;
  }

  /// Borra la cuenta de este dispositivo en el servidor (derecho de supresión). Los datos asociados se
  /// tratan en el servidor: listas traspasadas o borradas, pendientes eliminados.
  Future<void> eliminarCuenta() async {
    await ensureAuth();
    await _raw(
      'DELETE',
      '/api/collections/users/records/$userId',
      token: _token,
    );
    await olvidarCuenta();
  }

  /// Olvida las credenciales de dispositivo guardadas (la próxima vez que haga falta se crea otra cuenta).
  Future<void> olvidarCuenta() async {
    for (final k in ['mm_email', 'mm_pass']) {
      try {
        await _store.delete(key: k);
      } catch (_) {}
      await _prefs.remove('sec:$k');
    }
    _token = null;
    userId = null;
  }

  Future<void> cerrarSesion() async {
    _token = null;
    userId = null;
  }

  // -------------------------------------------------------------------- base
  Future<Map<String, dynamic>> _raw(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    String? token,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = token;
    if (body != null) req.body = jsonEncode(body);
    http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 20)),
      );
    } catch (e) {
      throw PbException(0, 'Sin conexión con el servidor');
    }
    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        final d = jsonDecode(res.body);
        if (d is Map<String, dynamic>) data = d;
      } catch (_) {}
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final msg = (data['message'] as String?) ?? 'Error ${res.statusCode}';
    throw PbException(res.statusCode, msg);
  }

  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    await ensureAuth();
    try {
      return await _raw(method, path, body: body, query: query, token: _token);
    } on PbException catch (e) {
      if (e.status == 401) {
        // sesión caducada: se vuelve a entrar con las credenciales del dispositivo
        _token = null;
        userId = null;
        await ensureAuth();
        return _raw(method, path, body: body, query: query, token: _token);
      }
      rethrow;
    }
  }

  String? get token => _token;
  http.Client get client => _http;

  // ----------------------------------------------------------------- hogares
  Future<Map<String, dynamic>> crearHogar(String name, String emoji) => call(
    'POST',
    '/api/collections/hogares/records',
    body: {'name': name, 'emoji': emoji, 'owner': userId},
  );

  Future<Map<String, dynamic>?> hogar(String id) async {
    try {
      return await call('GET', '/api/collections/hogares/records/$id');
    } on PbException catch (e) {
      if (e.status == 404 || e.status == 403) return null;
      rethrow;
    }
  }

  /// Listas compartidas de las que esta cuenta es miembro (las únicas que el servidor deja ver).
  Future<List<Map<String, dynamic>>> misHogares() async {
    final r = await call(
      'GET',
      '/api/collections/hogares/records',
      query: {'perPage': '50'},
    );
    return [
      for (final x in r['items'] as List) (x as Map).cast<String, dynamic>(),
    ];
  }

  /// Avisa al resto de miembros de la lista («voy yo»).
  Future<void> avisar(String hogarId, String alias, String texto) => call(
    'POST',
    '/api/collections/avisos/records',
    body: {
      'hogar': hogarId,
      'user': userId,
      'alias': alias,
      'tipo': 'voy',
      'texto': texto,
    },
  );

  Future<Map<String, dynamic>> unirse(String code, String alias) => call(
    'POST',
    '/api/mm/join',
    body: {'code': code.trim().toLowerCase(), 'alias': alias},
  );

  Future<String> regenerarInvitacion(String hogarId) async =>
      (await call('POST', '/api/mm/hogares/$hogarId/invitacion'))['invite_code']
          as String;

  Future<void> transferir(String hogarId, String userId) => call(
    'POST',
    '/api/mm/hogares/$hogarId/transferir',
    body: {'user': userId},
  );

  Future<void> borrarHogar(String hogarId) =>
      call('DELETE', '/api/collections/hogares/records/$hogarId');

  Future<List<Miembro>> miembros(String hogarId) async {
    final r = await call(
      'GET',
      '/api/collections/miembros/records',
      query: {'filter': "hogar='$hogarId'", 'perPage': '50'},
    );
    return [
      for (final m in (r['items'] as List))
        Miembro(
          recordId: m['id'],
          userId: m['user'],
          alias: (m['alias'] as String?)?.isNotEmpty == true
              ? m['alias']
              : 'Miembro',
          rol: m['rol'],
        ),
    ];
  }

  /// Salir (o revocar si lo llama el creador sobre otro miembro).
  Future<void> quitarMiembro(String recordId) =>
      call('DELETE', '/api/collections/miembros/records/$recordId');

  // ------------------------------------------------------------------- fotos
  /// Foto aprobada de la comunidad para un producto (público, no necesita sesión).
  Future<String?> fotoComunidad(String key) async {
    try {
      final r = await _raw(
        'GET',
        '/api/collections/fotos/records',
        query: {
          'filter': "key='${key.replaceAll("'", '')}' && status='approved'",
          'perPage': '1',
          'sort': '-created',
        },
      );
      final items = r['items'] as List? ?? [];
      if (items.isEmpty) return null;
      final f = items.first as Map;
      return '$baseUrl/api/files/${f['collectionId']}/${f['id']}/${f['file']}?thumb=200x200';
    } on PbException {
      return null;
    }
  }

  // ----------------------------------------------------------------- reportes
  static final _idFoto = RegExp(r'/api/files/[^/]+/([a-z0-9]{15})/');

  /// Id de la foto comunitaria a partir de su URL (o null si la imagen no es de nuestra base común).
  String? fotoIdDeUrl(String? url) {
    if (url == null || !url.startsWith(baseUrl)) return null;
    return _idFoto.firstMatch(url)?.group(1);
  }

  /// Reporta una foto de la base común (producto equivocado, no es un producto, datos personales…).
  Future<void> reportarFoto(String fotoId, String motivo, String nota) => call(
    'POST',
    '/api/collections/reportes/records',
    body: {'foto': fotoId, 'motivo': motivo, 'nota': nota},
  );

  // ---------------------------------------------------------------- productos
  Product _productoDe(Map m) {
    String? v(String k) =>
        (m[k] as String?)?.isEmpty == true ? null : m[k] as String?;
    final marca = v('brand');
    final nombre = m['name'] as String;
    return Product(
      name: marca != null && !nombre.toLowerCase().contains(marca.toLowerCase())
          ? '$nombre · $marca'
          : nombre,
      barcode: v('barcode'),
      cold: m['cold'] == true,
      ownChain: v('own_chain'),
      imageUrl: v('image_url'),
      quantity: v('quantity'),
      genericKey: v('generic_key'),
    );
  }

  /// Productos aprobados de la base general (público, sin sesión).
  Future<List<Product>> buscarProductos(String q) async {
    final t = q
        .replaceAll("'", '')
        .replaceAll('"', '')
        .replaceAll(r'\', '')
        .trim();
    if (t.length < 2) return [];
    try {
      final r = await _raw(
        'GET',
        '/api/collections/productos/records',
        query: {
          'filter':
              "status='approved' && (name~'$t' || key='${t.toLowerCase()}' || barcode='$t')",
          'perPage': '8',
        },
      );
      return [
        for (final m in (r['items'] as List? ?? [])) _productoDe(m as Map),
      ];
    } on PbException {
      return [];
    }
  }

  /// Propone un producto nuevo a la base general. Queda pendiente de moderación.
  /// Informe de error anónimo (solo si el usuario lo ha activado en Ajustes).
  Future<void> enviarError(Map<String, dynamic> informe) async {
    await ensureAuth();
    await call('POST', '/api/collections/errores/records', body: informe);
  }

  /// Registro de esta cuenta (incluye si tiene una sanción activa para compartir contenido).
  Future<Map<String, dynamic>> miUsuario() async {
    await ensureAuth();
    return call('GET', '/api/collections/users/records/$userId');
  }

  Future<void> proponerProducto(Product p) async {
    final partes = p.name.split(' · ');
    await call(
      'POST',
      '/api/collections/productos/records',
      body: {
        'key': p.key,
        'barcode': p.barcode ?? '',
        'name': partes.first,
        'brand': partes.length > 1 ? partes.sublist(1).join(' · ') : '',
        'quantity': p.quantity ?? '',
        'cold': p.cold,
        'generic_key': p.genericKey ?? '',
        'own_chain': p.ownChain ?? '',
        'image_url': p.imageUrl ?? '',
      },
    );
  }

  /// Sube una foto a la base colaborativa. Queda pendiente de moderación y solo el autor la ve hasta que se apruebe.
  Future<void> subirFoto({
    required String key,
    String? barcode,
    required String name,
    required List<int> bytes,
    required String filename,
  }) async {
    await ensureAuth();
    final req =
        http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/api/collections/fotos/records'),
          )
          ..headers['Authorization'] = _token!
          ..fields['key'] = key
          ..fields['name'] = name
          ..fields['consent'] = 'true'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: filename),
          );
    if (barcode != null) req.fields['barcode'] = barcode;
    http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(const Duration(seconds: 40)),
      );
    } catch (_) {
      throw PbException(0, 'Sin conexión con el servidor');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String msg = 'No se pudo subir la foto';
      try {
        msg = (jsonDecode(res.body) as Map)['message'] as String? ?? msg;
      } catch (_) {}
      throw PbException(res.statusCode, msg);
    }
  }

  // ----------------------------------------------------------------- compras
  Future<List<Map<String, dynamic>>> comprasRemotas(String hogarId) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page < 30; page++) {
      final r = await call(
        'GET',
        '/api/collections/compras/records',
        query: {
          'filter': "hogar='$hogarId'",
          'perPage': '200',
          'page': '$page',
          'sort': 'ms',
        },
      );
      out.addAll([
        for (final x in r['items'] as List) (x as Map).cast<String, dynamic>(),
      ]);
      if (page >= ((r['totalPages'] as num?) ?? 1)) break;
    }
    return out;
  }

  Future<void> crearCompra(Map<String, dynamic> body) =>
      call('POST', '/api/collections/compras/records', body: body);

  Future<void> borrarCompra(String id) async {
    try {
      await call('DELETE', '/api/collections/compras/records/$id');
    } on PbException catch (e) {
      if (e.status != 404) rethrow;
    }
  }

  // ------------------------------------------------------------------- items
  Future<List<Map<String, dynamic>>> items(String hogarId) async {
    final out = <Map<String, dynamic>>[];
    for (var page = 1; page < 20; page++) {
      final r = await call(
        'GET',
        '/api/collections/items/records',
        query: {
          'filter': "hogar='$hogarId'",
          'perPage': '200',
          'page': '$page',
        },
      );
      out.addAll([
        for (final x in r['items'] as List) (x as Map).cast<String, dynamic>(),
      ]);
      if (page >= ((r['totalPages'] as num?) ?? 1)) break;
    }
    return out;
  }

  Future<void> crearItem(Map<String, dynamic> body) =>
      call('POST', '/api/collections/items/records', body: body);
  Future<void> editarItem(String id, Map<String, dynamic> body) =>
      call('PATCH', '/api/collections/items/records/$id', body: body);
  Future<void> borrarItem(String id) async {
    try {
      await call('DELETE', '/api/collections/items/records/$id');
    } on PbException catch (e) {
      if (e.status != 404) rethrow;
    }
  }
}
