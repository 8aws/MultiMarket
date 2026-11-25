// Fotos propias en la copia de iCloud: solo las que NO se han enviado a la base común (esas ya están a salvo allí).
// Cada foto es un fichero en `Copia/Fotos/` y `Copia/fotos.json` guarda qué producto es cada una. Solo iOS.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'icloud.dart';
import 'state.dart';

String _nombre(String key) =>
    '${key.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}.jpg';

/// Sube a iCloud las fotos propias aún no copiadas (y quita las que ya no existen). Devuelve cuántas se copiaron.
Future<int> guardarFotosEnICloud(AppState s) async {
  var nuevas = 0;
  final indice = <String, String>{};
  final hechas = (jsonDecode(s.prefs.getString('fotosICloud') ?? '{}') as Map)
      .cast<String, String>();
  final vigentes = <String, String>{};
  for (final e in s.fotosLocales.entries) {
    if (s.fotosCompartidas.contains(e.key)) continue;
    final f = File(e.value);
    if (!await f.exists()) continue;
    final nombre = _nombre(e.key);
    indice[e.key] = nombre;
    vigentes[e.key] = e.value;
    if (hechas[e.key] == e.value) continue; // ya copiada
    await ICloud.escribir('Copia/Fotos/$nombre', await f.readAsBytes());
    nuevas++;
  }
  // fotos que ya no son propias (se borraron o se compartieron): se quitan de la copia
  for (final k in hechas.keys.where((k) => !indice.containsKey(k))) {
    try {
      await ICloud.borrar('Copia/Fotos/${_nombre(k)}');
    } catch (_) {}
  }
  await ICloud.escribir('Copia/fotos.json', utf8.encode(jsonEncode(indice)));
  await s.prefs.setString('fotosICloud', jsonEncode(vigentes));
  return nuevas;
}

/// Trae de iCloud las fotos propias de la copia (sin pisar las que ya hay). Devuelve cuántas se recuperaron.
Future<int> restaurarFotosDeICloud(AppState s) async {
  final bytes = await ICloud.leer('Copia/fotos.json');
  if (bytes == null) return 0;
  final indice = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, String>();
  final dir = await getApplicationDocumentsDirectory();
  final carpeta = Directory('${dir.path}/fotos');
  if (!await carpeta.exists()) await carpeta.create(recursive: true);
  var n = 0;
  for (final e in indice.entries) {
    if (s.fotosLocales.containsKey(e.key)) continue;
    final b = await ICloud.leer('Copia/Fotos/${e.value}');
    if (b == null) continue;
    final destino = '${carpeta.path}/${e.value}';
    await File(destino).writeAsBytes(b);
    s.restaurarFotoLocal(e.key, destino);
    n++;
  }
  return n;
}
