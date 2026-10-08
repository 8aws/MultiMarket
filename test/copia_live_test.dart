// Copia de la lista privada contra el servidor REAL: MM_LIVE=1 MM_URL=https://tu-servidor flutter test test/copia_live_test.dart
// Crea una cuenta temporal y la borra al terminar (≤ 1 vez/minuto por el límite de altas).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final live = Platform.environment['MM_LIVE'] == '1';
  final url = Platform.environment['MM_URL'] ?? '';

  test(
    'la lista privada se copia al servidor y se recupera tras «reinstalar»',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = AppState(prefs);
      a.cfg.serverUrl = url;
      a.cfg.alias = 'Copia';
      a.cfg.copiaPrivada = true;
      try {
        final leche = a.add(
          const Product(name: 'Leche', barcode: '8480000106483'),
        );
        a.setCantidad(leche, 2);
        a.toggleDone(leche);
        a.add(const Product(name: 'Pan'));
        await a.subirCopia(forzar: true);
        expect(a.ultimaCopia, isNotNull, reason: 'la subida no falló');

        // «reinstalar»: se borran los datos locales de la lista (las credenciales siguen, como en el llavero)
        for (final k in [
          'items:privada',
          'compras:privada',
          'offers:privada',
          'recompra:privada',
        ]) {
          await prefs.remove(k);
        }
        final b = AppState(prefs);
        b.cfg.serverUrl = url;
        expect(b.items, isEmpty);
        expect(b.compras, isEmpty);
        await b.consultarCopia();
        expect(b.copiaParaRestaurar, isNotNull);
        expect(await b.restaurarCopia(), isNull);
        expect(b.items.map((i) => i.name).toSet(), {'Leche', 'Pan'});
        expect(b.compras, hasLength(1));
        expect(b.compras.single.qty, 2);
        expect(b.copiaParaRestaurar, isNull);
        b.dispose();
      } finally {
        await a.eliminarCuenta(borrarLocal: false);
        a.dispose();
      }
    },
    skip: live && url.isNotEmpty ? false : 'MM_LIVE=1 y MM_URL',
  );
}
