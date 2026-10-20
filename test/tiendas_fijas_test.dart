import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Store t(String id, String chain) =>
    Store(id: id, name: chain, chain: chain, lat: 36.5, lon: -4.6, km: 1);

void main() {
  test(
    'la lista creada con ubicación real queda fijada; con la de ejemplo no',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(await SharedPreferences.getInstance());
      expect(s.locApprox, isTrue);
      expect(
        s.listaDeTiendasFijada,
        isFalse,
        reason: 'ubicación aproximada de ejemplo',
      );
      s.locApprox = false;
      s.stores = [t('a', 'lidl')];
      expect(s.listaDeTiendasFijada, isTrue);
      s.dispose();
    },
  );

  test(
    'al actualizar se conservan las tiendas que ya usas aunque no salgan',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(await SharedPreferences.getInstance());
      s.locApprox = false;
      s.stores = [t('a', 'lidl'), t('b', 'dia')];
      s.cfg.enabled = {'a'};
      final it = s.add(const Product(name: 'Leche'));
      it.storeId = 'b';
      s.buscarTiendas = (_, _, _) async => [t('c', 'aldi')];
      await s.refreshStores(relocate: false);
      expect(s.stores.map((x) => x.id), ['c']);
      expect(s.storeById('a'), isNotNull, reason: 'activa: se conserva');
      expect(
        s.storeById('b'),
        isNotNull,
        reason: 'asignada a un producto: se conserva',
      );
      expect(s.storeById('b')!.chain, 'dia');
      s.dispose();
    },
  );

  test('si la búsqueda falla se mantiene la lista guardada', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState(await SharedPreferences.getInstance());
    s.locApprox = false;
    s.stores = [t('a', 'lidl')];
    s.buscarTiendas = (_, _, _) async => throw StateError('sin red');
    await s.refreshStores(relocate: false);
    expect(s.stores.map((x) => x.id), ['a']);
    expect(s.storesError, isNotNull);
    s.dispose();
  });
}
