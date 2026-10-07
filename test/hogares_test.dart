import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> mk([Map<String, Object> init = const {}]) async {
  SharedPreferences.setMockInitialValues(init);
  return AppState(await SharedPreferences.getInstance());
}

Item it(String n) => Item(id: n, name: n, cold: false);

void main() {
  borradoLocalTests();
  precioFrioTests();
  exclusivosTests();
  test('listas aisladas, límite de 3 y borrado', () async {
    final s = await mk();
    s.items.add(it('privado'));
    final casa = s.crearHogar('Casa')!;
    expect(s.currentId, casa.id);
    expect(s.items, isEmpty, reason: 'la lista nueva empieza vacía');
    s.items.add(it('leche'));
    s.crearHogar('Trabajo');
    s.crearHogar('Abuelos');
    expect(s.puedeCrearHogar, isFalse);
    expect(s.crearHogar('Cuarta'), isNull);
    expect(s.hogares.length, 4);

    s.selectHogar(Hogar.privadaId);
    expect(s.items.map((i) => i.name), ['privado']);
    s.selectHogar(casa.id);
    expect(s.items.map((i) => i.name), ['leche']);

    s.borrarHogar(casa);
    expect(s.currentId, Hogar.privadaId);
    expect(s.hogares.any((h) => h.id == casa.id), isFalse);
    s.borrarHogar(s.hogares.first); // la privada no se borra
    expect(s.hogares.first.esPrivada, isTrue);
    s.dispose();
  });

  test('persistencia y migración de la lista antigua a la privada', () async {
    final antigua = jsonEncode([it('arroz').toJson()]);
    final s = await mk({'items': antigua});
    expect(s.items.map((i) => i.name), ['arroz']);
    s.crearHogar('Casa');
    s.items.add(it('pan'));
    s.changed();
    final s2 = AppState(await SharedPreferences.getInstance());
    expect(s2.hogar.name, 'Casa');
    expect(s2.items.map((i) => i.name), ['pan']);
    s2.selectHogar(Hogar.privadaId);
    expect(s2.items.map((i) => i.name), ['arroz']);
    s.dispose();
    s2.dispose();
  });
}

void exclusivosTests() {
  test(
    'producto marcado como exclusivo se asigna siempre a esa cadena',
    () async {
      final s = await mk();
      final p = const Product(name: 'Pan del horno');
      final item = s.add(p);
      final lidl = s.stores.firstWhere((x) => x.chain == 'lidl');
      s.cfg.enabled.add(lidl.id);
      item.storeId = lidl.id;
      s.setExclusivo(item, true);
      final p2 = s.conExclusivo(p);
      expect(p2.ownChain, 'lidl');
      final opts = await s.options(p2);
      expect(opts.map((o) => o.store.chain).toSet(), {'lidl'});
      s.setExclusivo(item, false);
      expect(s.conExclusivo(p).ownChain, isNull);
      // la regla persiste
      s.setExclusivo(item, true);
      final s2 = AppState(await SharedPreferences.getInstance());
      expect(s2.exclusivos.values, ['lidl']);
      s.dispose();
      s2.dispose();
    },
  );
}

void precioFrioTests() {
  test('precio habitual se recuerda; oferta sin fecha no lo toca', () async {
    final s = await mk();
    final p = const Product(name: 'Detergente');
    final item = s.add(p);
    final dia = s.stores.firstWhere((x) => x.chain == 'dia');
    s.cfg.enabled.add(dia.id);
    item.storeId = dia.id;
    s.setPrice(item, 5.50);
    expect(item.price, 5.50);
    s.setPrice(item, 3.99, oferta: true); // oferta puntual
    expect(item.price, 3.99);
    final o = (await s.options(p)).firstWhere((x) => x.store.chain == 'dia');
    expect(
      o.price,
      5.50,
      reason: 'el precio habitual no cambia con una oferta sin fecha',
    );
    s.setPrice(item, 5.20); // corrección del habitual
    expect(
      (await s.options(p)).firstWhere((x) => x.store.chain == 'dia').price,
      5.20,
    );
    s.setPrice(item, null);
    expect(item.price, isNull);
    s.dispose();
  });

  test('oferta con fecha se guarda como oferta temporal', () async {
    final s = await mk();
    final item = s.add(const Product(name: 'Yogur'));
    final dia = s.stores.firstWhere((x) => x.chain == 'dia');
    item.storeId = dia.id;
    s.setPrice(
      item,
      0.99,
      oferta: true,
      hasta: DateTime.now().add(const Duration(days: 3)),
    );
    expect(s.offerList.single.price, 0.99);
    s.dispose();
  });

  test(
    'refrigerado corregido se recuerda para ese producto y no para otro',
    () async {
      final s = await mk();
      final uht = s.add(const Product(name: 'Leche UHT', cold: true));
      s.setCold(uht, false);
      expect(uht.cold, isFalse);
      expect(
        s.conFrio(const Product(name: 'Leche UHT', cold: true)).cold,
        isFalse,
      );
      expect(
        s.conFrio(const Product(name: 'Leche fresca', cold: true)).cold,
        isTrue,
      );
      final s2 = AppState(await SharedPreferences.getInstance());
      expect(s2.frioManual['leche uht'], isFalse);
      s.setUrgency(uht, 1);
      expect(uht.urg, 1);
      s.dispose();
      s2.dispose();
    },
  );
}

void borradoLocalTests() {
  test('eliminar cuenta sin cuenta de servidor: borra todo lo local', () async {
    final s = await mk();
    s.add(const Product(name: 'Leche', cold: true));
    s.crearHogar('Casa'); // lista local (no remota)
    s.cfg.alias = 'Ana';
    s.exclusivos['k'] = 'dia';
    expect(await s.tieneCuentaEnServidor, isFalse);
    final e = await s.eliminarCuenta(borrarLocal: true);
    expect(e, isNull);
    expect(s.items, isEmpty);
    expect(s.hogares.length, 1);
    expect(s.hogares.first.esPrivada, isTrue);
    expect(s.cfg.alias, '');
    expect(s.exclusivos, isEmpty);
    s.dispose();
  });
}
