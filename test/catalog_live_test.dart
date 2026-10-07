// Contra las APIs reales de Open Food Facts. MM_LIVE=1 flutter test test/catalog_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/sources.dart';
import 'package:multimarket/state.dart';
import 'package:multimarket/sync/pb_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final live = Platform.environment['MM_LIVE'] == '1';

  test(
    'búsqueda de texto devuelve productos españoles con foto y clave genérica',
    () async {
      final r = await searchProducts('leche entera');
      expect(r, isNotEmpty);
      expect(r.any((p) => p.imageUrl != null), isTrue);
      expect(r.any((p) => p.genericKey != null), isTrue);
      expect(r.every((p) => p.name.isNotEmpty), isTrue);
      // ignore: avoid_print
      print(
        r
            .take(4)
            .map(
              (p) =>
                  '${p.name} | ${p.barcode} | ${p.quantity} | frío=${p.cold} | ${p.ownChain} | ${p.genericKey}',
            )
            .join('\n'),
      );
    },
    skip: live ? false : 'MM_LIVE=1',
  );

  test('búsqueda por código de barras', () async {
    final p = await productByBarcode('8480017006080');
    expect(p, isNotNull);
    expect(p!.barcode, '8480017006080');
    expect(p.name.toLowerCase(), contains('leche'));
    expect(p.cold, isFalse, reason: 'es leche UHT');
    expect(await productByBarcode('0000000000000'), isNull);
  }, skip: live ? false : 'MM_LIVE=1');

  test('precios equivalentes de Open Prices (puede no haber datos)', () async {
    final base = (await searchProducts('leche entera')).first;
    final eq = await equivalentOpenPrices(base);
    expect(eq.values.every((q) => q.equivalente && q.price != null), isTrue);
    // ignore: avoid_print
    print('equivalentes: ${eq.map((k, q) => MapEntry(k, q.price))}');
  }, skip: live ? false : 'MM_LIVE=1');

  test('proponer producto nuevo a la base común (una sola vez)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState(await SharedPreferences.getInstance());
    s.cfg.serverUrl = Platform.environment['MM_URL'] ?? '';
    final nombre = 'Producto de prueba ${PbApi.randomId(6)}';
    final p = Product(
      name: '$nombre · Marca',
      cold: true,
      quantity: '500 g',
      genericKey: 'prueba|500g',
    );
    try {
      await s.proponerProducto(p);
      expect(s.proponidos, contains(p.key));
      // segunda vez: no vuelve a llamar
      await s.proponerProducto(p);
      // y mientras esté pendiente no aparece en la búsqueda pública
      expect(await s.sync.api.buscarProductos(nombre), isEmpty);
    } finally {
      try {
        // primero el producto de prueba (solo su autor puede retirarlo) y después la cuenta
        final r = await s.sync.api.call(
          'GET',
          '/api/collections/productos/records',
          query: {'filter': "key='${p.key}'"},
        );
        for (final m in (r['items'] as List)) {
          await s.sync.api.call(
            'DELETE',
            '/api/collections/productos/records/${m['id']}',
          );
        }
        await s.sync.api.call(
          'DELETE',
          '/api/collections/users/records/${s.sync.api.userId}',
        );
      } catch (_) {}
      s.dispose();
    }
  }, skip: live ? false : 'MM_LIVE=1');
}
