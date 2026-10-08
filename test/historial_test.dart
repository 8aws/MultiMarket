import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> mk([Map<String, Object> init = const {}]) async {
  SharedPreferences.setMockInitialValues(init);
  return AppState(await SharedPreferences.getInstance());
}

void main() {
  deteccionTiendaTests();
  recompraDesdeHistorialTests();
  recompraImagenTests();
  test('marcar comprado registra la compra; desmarcar la retira', () async {
    final s = await mk();
    final it = s.add(const Product(name: 'Leche', barcode: '8480000106483'));
    s.setCantidad(it, 3);
    s.setPrice(it, 0.85);
    s.toggleDone(it);
    expect(s.compras, hasLength(1));
    final c = s.compras.single;
    expect(c.key, '8480000106483');
    expect(c.qty, 3);
    expect(c.price, 0.85);
    expect(c.total, closeTo(2.55, 1e-9));
    s.toggleDone(it); // desmarcar = error: no cuenta
    expect(s.compras, isEmpty);
    s.dispose();
  });

  test('las compras de cada lista son independientes y se guardan', () async {
    final s = await mk();
    s.toggleDone(s.add(const Product(name: 'Pan')));
    s.crearHogar('Casa');
    expect(s.compras, isEmpty, reason: 'otra lista, otro historial');
    s.toggleDone(s.add(const Product(name: 'Arroz')));
    final s2 = AppState(await SharedPreferences.getInstance());
    expect(s2.compras.map((c) => c.name), ['Arroz']);
    s2.selectHogar(Hogar.privadaId);
    expect(s2.compras.map((c) => c.name), ['Pan']);
    s.dispose();
    s2.dispose();
  });

  test('la cantidad multiplica el importe en totales', () async {
    final s = await mk();
    final it = s.add(const Product(name: 'Yogur'));
    s.setPrice(it, 1.0);
    s.setCantidad(it, 4);
    expect(s.totalPending, closeTo(4.0, 1e-9));
    s.setCantidad(it, 0); // mínimo 1
    expect(it.cantidad, 1);
    s.dispose();
  });
}

void deteccionTiendaTests() {
  test('tienda más cercana dentro del radio; fuera de él, ninguna', () {
    final lidl = Store(
      id: 'a',
      name: 'Lidl',
      chain: 'lidl',
      lat: 40.4200,
      lon: -3.7000,
    );
    final mas = Store(
      id: 'b',
      name: 'Más',
      chain: 'masymas',
      lat: 40.4210,
      lon: -3.7000,
    ); // ~111 m
    // estoy a ~10 m del Lidl
    expect(tiendaMasCercana(40.42009, -3.7000, [mas, lidl])?.name, 'Lidl');
    // a 60 m de ninguna: fuera del radio por defecto de 50 m si lo reduzco
    expect(
      tiendaMasCercana(40.4205, -3.7000, [mas, lidl], maxMetros: 30),
      isNull,
    );
    // lejos de todo
    expect(tiendaMasCercana(41.0, -3.0, [mas, lidl]), isNull);
  });

  test(
    'al marcar comprado en otra tienda se reasigna el producto y su compra, con deshacer',
    () async {
      final s = await mk();
      final it = s.add(const Product(name: 'Leche'));
      final mas = s.stores.firstWhere((x) => x.chain == 'dia');
      final lidl = s.stores.firstWhere((x) => x.chain == 'lidl');
      it.storeId = mas.id;
      s.toggleDone(it); // el GPS real no existe en tests: no cambia nada solo
      expect(s.compras.single.storeId, mas.id);
      Aviso? aviso;
      final sub = s.avisos.listen((a) => aviso = a);
      await s.reasignarSiOtraTienda(it, lidl);
      await Future<void>.delayed(Duration.zero);
      expect(it.storeId, lidl.id);
      expect(s.compras.single.storeId, lidl.id);
      expect(s.compras.single.storeName, lidl.name);
      expect(aviso, isNotNull);
      expect(aviso!.texto, contains('Lidl'));
      aviso!.deshacer!();
      expect(it.storeId, mas.id);
      expect(s.compras.single.storeId, mas.id);
      // misma tienda: no hace nada
      aviso = null;
      await s.reasignarSiOtraTienda(it, mas);
      await Future<void>.delayed(Duration.zero);
      expect(aviso, isNull);
      await sub.cancel();
      s.dispose();
    },
  );
}

void recompraDesdeHistorialTests() {
  test('recomprar desde el historial repone cantidad y no duplica', () async {
    final s = await mk();
    final it = s.add(const Product(name: 'Leche', barcode: '8480000106483'));
    s.setCantidad(it, 3);
    s.toggleDone(it);
    final c = s.compras.single;
    final otra = s.recomprar(c)!;
    expect(otra.done, isFalse);
    expect(otra.cantidad, 3);
    expect(otra.barcode, '8480000106483');
    expect(s.recomprar(c), isNull, reason: 'ya está pendiente');
    expect(s.repetirCompra([c]), 0);
    s.dispose();
  });

  test('repetir una compra añade solo lo que falta', () async {
    final s = await mk();
    final a = s.add(const Product(name: 'Pan'));
    final b = s.add(const Product(name: 'Arroz'));
    s.toggleDone(a);
    s.toggleDone(b);
    s.add(const Product(name: 'Pan')); // ya pendiente
    expect(s.repetirCompra([...s.compras]), 1);
    expect(s.items.where((i) => !i.done).map((i) => i.name).toSet(), {
      'Pan',
      'Arroz',
    });
    s.dispose();
  });
}

void recompraImagenTests() {
  test(
    'al recomprar se recupera la foto enlazada que tenía el producto',
    () async {
      final s = await mk();
      final it = s.add(
        const Product(
          name: 'Leche',
          barcode: '8480000106483',
          imageUrl: 'https://img.example/leche.jpg',
        ),
      );
      s.toggleDone(it);
      s.items.clear(); // la compra ya se limpió de la lista
      final otra = s.recomprar(s.compras.single)!;
      expect(otra.imageUrl, 'https://img.example/leche.jpg');
      s.dispose();
    },
  );
}
