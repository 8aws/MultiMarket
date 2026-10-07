// Prueba de sincronización contra el servidor REAL (usa el cliente y el motor de la app).
// No se ejecuta en `flutter test` normal: MM_LIVE=1 flutter test test/sync_live_test.dart
// Crea usuarios temporales y los borra al terminar. Respeta el rate limiting (≤ 1 vez/minuto).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:multimarket/sync/pb_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> dispositivo(String url, String alias) async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState(await SharedPreferences.getInstance());
  s.cfg.serverUrl = url;
  s.cfg.alias = alias;
  return s;
}

Item it(String name, {bool cold = false}) =>
    Item(id: PbApi.randomId(), name: name, cold: cold);

void main() {
  final live = Platform.environment['MM_LIVE'] == '1';
  final url = Platform.environment['MM_URL'] ?? '';

  test(
    'dos dispositivos comparten una lista de extremo a extremo',
    () async {
      final a = await dispositivo(url, 'Ana');
      final b = await dispositivo(url, 'Beto');
      String? hid;
      try {
        // Ana crea la lista y añade un producto
        expect(await a.crearCompartida('Casa', '🏠'), isNull);
        hid = a.hogar.id;
        expect(a.hogar.esCreador, isTrue);
        expect(a.hogar.inviteCode, isNotNull);
        a.items.add(it('Leche', cold: true));
        await a.sync.sincronizar();
        expect(a.sync.error, isNull);

        // Beto se une con el código y recibe el producto
        expect(await b.unirseConCodigo(a.hogar.inviteCode!), isNull);
        await b.sync.sincronizar();
        expect(b.items.map((i) => i.name), ['Leche']);
        expect(b.hogar.esCreador, isFalse);

        // imagen enlazada y clave de equivalencia viajan con el producto
        a.items.first.imageUrl = 'https://images.openfoodfacts.org/x.200.jpg';
        a.items.first.genericKey = 'leche-entera|1000ml';
        await a.sync.sincronizar();
        await b.sync.sincronizar();
        expect(b.items.first.imageUrl, contains('openfoodfacts'));
        expect(b.items.first.genericKey, 'leche-entera|1000ml');

        // La tienda que elige Ana llega a Beto con su nombre, aunque no esté en su zona
        final lejos = Store(
          id: 'osm:node/999',
          name: 'Supermercado Lejano',
          chain: 'lejano',
          lat: 36.7,
          lon: -4.4,
        );
        a.extraStores[lejos.id] = lejos;
        a.items.first.storeId = lejos.id;
        await a.sync.sincronizar();
        expect(a.sync.error, isNull, reason: 'subida de Ana');
        await b.sync.sincronizar();
        expect(b.sync.error, isNull, reason: 'bajada de Beto');
        expect(b.items.first.storeId, lejos.id);
        expect(b.storeById(lejos.id)?.name, 'Supermercado Lejano');

        // Beto marca comprado y añade otro; Ana lo ve
        b.items.first.done = true;
        b.items.add(it('Pan'));
        await b.sync.sincronizar();
        await a.sync.sincronizar();
        expect(a.items.map((i) => i.name).toSet(), {'Leche', 'Pan'});
        expect(a.items.firstWhere((i) => i.name == 'Leche').done, isTrue);
        expect(a.items.firstWhere((i) => i.name == 'Pan').addedBy, b.sync.miId);

        // Ana borra un producto; desaparece en Beto
        a.items.removeWhere((i) => i.name == 'Pan');
        await a.sync.sincronizar();
        await b.sync.sincronizar();
        expect(b.items.map((i) => i.name), ['Leche']);

        // Beto no puede borrar para todos; Ana revoca a Beto y su copia local desaparece
        expect(await b.borrarParaTodos(b.hogar), isNotNull);
        // y aunque el cliente lo intentara, el servidor lo rechaza
        final forzado = await b.sync.api
            .call('DELETE', '/api/collections/hogares/records/$hid')
            .then((_) => 'borrada', onError: (_) => 'rechazado');
        expect(forzado, 'rechazado');
        expect(
          await a.sync.api.hogar(hid),
          isNotNull,
          reason: 'la lista sigue existiendo',
        );
        final m = a.sync.miembros[hid]!.firstWhere(
          (x) => x.userId == b.sync.miId,
        );
        expect(await a.revocar(a.hogar, m), isNull);
        await b.sync.sincronizar();
        expect(b.hogares.any((h) => h.id == hid), isFalse);

        // Ana borra la lista para todos
        expect(await a.borrarParaTodos(a.hogar), isNull);
        expect(a.hogares.any((h) => h.id == hid), isFalse);
        hid = null;
      } finally {
        for (final s in [a, b]) {
          try {
            await s.sync.api.call(
              'DELETE',
              '/api/collections/users/records/${s.sync.api.userId}',
            );
          } catch (_) {}
          s.dispose();
        }
      }
    },
    skip: live ? false : 'define MM_LIVE=1 para probar contra el servidor',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'eliminar cuenta: la lista en la que estabas solo se borra del servidor',
    () async {
      final a = await dispositivo(url, 'Ana');
      String? hid;
      try {
        expect(await a.crearCompartida('Temporal', '🏠'), isNull);
        hid = a.hogar.id;
        a.items.add(it('Leche'));
        await a.sync.sincronizar();
        expect(await a.tieneCuentaEnServidor, isTrue);
        expect(await a.eliminarCuenta(borrarLocal: true), isNull);
        expect(a.hogares.length, 1, reason: 'solo queda la privada');
        expect(await a.tieneCuentaEnServidor, isFalse);
        // la cuenta ya no existe: una nueva sesión (otra cuenta) no ve esa lista
        final b = await dispositivo(url, 'Beto');
        try {
          expect(await b.sync.api.hogar(hid), isNull);
        } finally {
          try {
            await b.sync.api.call(
              'DELETE',
              '/api/collections/users/records/${b.sync.api.userId}',
            );
          } catch (_) {}
          b.dispose();
        }
      } finally {
        a.dispose();
      }
    },
    skip: live ? false : 'define MM_LIVE=1 para probar contra el servidor',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'cantidad e historial de compras viajan por la lista compartida',
    () async {
      final a = await dispositivo(url, 'Ana');
      final b = await dispositivo(url, 'Beto');
      try {
        expect(await a.crearCompartida('Casa', '🏠'), isNull);
        expect(await b.unirseConCodigo(a.hogar.inviteCode!), isNull);
        final leche = a.add(Product(name: 'Leche', barcode: '8480000106483'));
        a.setCantidad(leche, 2);
        a.setPrice(leche, 0.9);
        await a.sync.sincronizar();
        await b.sync.sincronizar();
        expect(b.items.single.cantidad, 2, reason: 'la cantidad se sincroniza');

        a.toggleDone(a.items.single); // Ana compra
        await a.sync.sincronizar();
        await b.sync.sincronizar();
        expect(b.compras, hasLength(1), reason: 'Beto ve la compra de Ana');
        expect(b.compras.single.qty, 2);
        expect(b.compras.single.by, a.sync.miId);

        a.toggleDone(
          a.items.single,
        ); // se arrepiente: se retira también en el servidor
        await a.sync.sincronizar();
        await b.sync.sincronizar();
        expect(a.compras, isEmpty);
        expect(
          b.compras,
          isEmpty,
          reason: 'la compra retirada desaparece también para Beto',
        );
        expect(await a.borrarParaTodos(a.hogar), isNull);
      } finally {
        for (final s in [a, b]) {
          try {
            await s.sync.api.call(
              'DELETE',
              '/api/collections/users/records/${s.sync.api.userId}',
            );
          } catch (_) {}
          s.dispose();
        }
      }
    },
    skip: live ? false : 'define MM_LIVE=1 para probar contra el servidor',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
