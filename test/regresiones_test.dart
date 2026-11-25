import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:multimarket/ticket/ticket_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> estado() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dos súper pegados: se queda la tienda que ya tenía el producto', () {
    // ~55 m de separación en latitud
    final mas = Store(
      id: 'mas',
      name: 'Más',
      chain: 'mas',
      lat: 36.5000,
      lon: -4.6000,
    );
    final car = Store(
      id: 'car',
      name: 'Carrefour',
      chain: 'carrefour',
      lat: 36.50050,
      lon: -4.6000,
    );
    // estás a 20 m del Carrefour y a ~35 m del Más: el GPS no lo distingue
    final lat = 36.50032;
    expect(tiendaMasCercana(lat, -4.6, [mas, car])?.id, 'car');
    expect(tiendaMasCercana(lat, -4.6, [mas, car], preferida: mas)?.id, 'mas');
    // si la preferida queda lejos de verdad, manda la más cercana
    final lejos = Store(
      id: 'lejos',
      name: 'Otro',
      chain: 'dia',
      lat: 36.51,
      lon: -4.6,
    );
    expect(
      tiendaMasCercana(lat, -4.6, [lejos, car], preferida: lejos)?.id,
      'car',
    );
  });

  test(
    'un precio escrito antes de tener tienda no se pierde al asignarla sin precio conocido',
    () async {
      final s = await estado();
      final it = s.add(const Product(name: 'Tomate frito'));
      s.setPrice(it, 1.20); // sin tienda
      expect(it.price, 1.20);
      final st = s.stores.first;
      s.assign(it, Option(st, null));
      expect(it.storeId, st.id);
      expect(
        it.price,
        1.20,
        reason:
            'la asignación automática llega tarde y no debe borrar tu precio',
      );
      s.dispose();
    },
  );

  test('el mismo ticket aplicado dos veces no duplica el historial', () async {
    final s = await estado();
    final t = parsearTicket([
      'ALDI',
      'LECHE ENTERA 1,05 A',
      'PAN DE MOLDE 1,35 B',
      'A PAGAR 2,40',
    ]);
    final cruces = s.cruzar(t);
    s.aplicarTicket(t, cruces);
    final n = s.compras.length;
    expect(n, 2);
    s.aplicarTicket(t, s.cruzar(t));
    expect(s.compras.length, n);
    expect(s.ultimasFusionadas, 2);
    s.dispose();
  });

  test(
    'sesión de compra: compras seguidas en <20 min mantienen la tienda; pasado ese margen, no',
    () async {
      final s = await estado();
      final st = s.stores.first;
      final ahora = DateTime(2026, 11, 20, 12, 0);
      Compra c(String id, int minutosAntes) => Compra(
        id: id.padRight(15, '0'),
        itemId: id,
        key: id,
        name: id,
        qty: 1,
        storeId: st.id,
        storeName: st.name,
        ms: ahora
            .subtract(Duration(minutes: minutosAntes))
            .millisecondsSinceEpoch,
      );
      s.compras.add(c('uno', 5));
      expect(s.tiendaDeSesion(ahora: ahora)?.id, st.id);
      expect(
        s.tiendaDeSesion(salvo: 'uno', ahora: ahora),
        isNull,
        reason: 'el propio producto no cuenta',
      );
      s.compras
        ..clear()
        ..add(c('viejo', 30));
      expect(s.tiendaDeSesion(ahora: ahora), isNull);
      s.dispose();
    },
  );

  test(
    'al añadir: primero lo que ya compraste (más veces antes), con búsqueda por comienzo de palabra',
    () async {
      final s = await estado();
      Compra c(String id, String nombre, int ms) => Compra(
        id: id.padRight(15, '0'),
        itemId: id,
        key: nombre.toLowerCase(),
        name: nombre,
        qty: 1,
        ms: ms,
      );
      s.compras
        ..add(c('a1', 'Leche de avena', 1000))
        ..add(c('b1', 'Leche entera', 2000))
        ..add(c('b2', 'Leche entera', 3000))
        ..add(c('c1', 'Arroz largo', 4000));
      final r = s.productosPrevios('lec');
      expect(r.map((p) => p.name), ['Leche entera', 'Leche de avena']);
      expect(s.productosPrevios('leche ent').map((p) => p.name), [
        'Leche entera',
      ]);
      expect(s.productosPrevios('xyz'), isEmpty);
      expect(s.productosPrevios('l'), isEmpty, reason: 'una letra no basta');
      s.dispose();
    },
  );
}
