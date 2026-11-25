// iCloud Drive de la app (contenedor iCloud.es.uverse.multimarket): copia de seguridad y muestras de desarrollo.
// Todo queda en el iCloud de cada usuario; no pasa por nuestro servidor. Solo iOS; en otras plataformas todo da «no disponible».
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EntradaICloud {
  EntradaICloud(this.nombre, this.carpeta, this.modificado);
  final String nombre;
  final bool carpeta;
  final DateTime modificado;
}

class ICloud {
  ICloud._();
  static const _canal = MethodChannel('es.uverse.multimarket/icloud');

  static bool get _soportado => !kIsWeb && Platform.isIOS;

  static Future<bool> disponible() async {
    if (!_soportado) return false;
    try {
      return await _canal.invokeMethod<bool>('disponible') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> escribir(String ruta, List<int> datos) =>
      _canal.invokeMethod('escribir', {
        'ruta': ruta,
        'datos': Uint8List.fromList(datos),
      });

  static Future<Uint8List?> leer(String ruta) =>
      _canal.invokeMethod<Uint8List>('leer', {'ruta': ruta});

  static Future<DateTime?> modificado(String ruta) async {
    if (!_soportado) return null;
    try {
      final m = await _canal.invokeMapMethod<String, dynamic>('info', {
        'ruta': ruta,
      });
      final ms = m?['modificado'] as int?;
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  static Future<List<EntradaICloud>> listar(String ruta) async {
    if (!_soportado) return const [];
    try {
      final l =
          await _canal.invokeListMethod<Map>('listar', {'ruta': ruta}) ?? [];
      return [
        for (final m in l)
          EntradaICloud(
            m['nombre'] as String,
            m['carpeta'] as bool,
            DateTime.fromMillisecondsSinceEpoch(m['modificado'] as int),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> borrar(String ruta) =>
      _canal.invokeMethod('borrar', {'ruta': ruta});
}
