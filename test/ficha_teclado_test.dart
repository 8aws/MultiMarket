import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(AppState, Item)> preparar() async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState(await SharedPreferences.getInstance());
  s.stores = [
    Store(
      id: 'a',
      name: 'Carrefour',
      chain: 'carrefour',
      lat: 36.5,
      lon: -4.6,
      km: 1,
    ),
  ];
  s.locApprox = false;
  s.cfg.enabled = {'a'};
  // producto de la comunidad (con código de barras y foto enlazada), asignado a un súper
  final it = s.add(
    const Product(
      name: 'Aceite de oliva 1L',
      barcode: '8412345678905',
      imageUrl: 'https://img.example/aceite.jpg',
    ),
  );
  it.storeId = 'a';
  return (s, it);
}

void main() {
  test('precio habitual: se guarda y se recuerda para la cadena', () async {
    final (s, it) = await preparar();
    s.setPrice(it, 3.39);
    expect(it.price, 3.39);
    s.dispose();
  });

  test(
    'precio de oferta con fecha: crea la oferta y deja el precio habitual',
    () async {
      final (s, it) = await preparar();
      s.setPrice(
        it,
        3.39,
        oferta: true,
        hasta: DateTime.now().add(const Duration(days: 6)),
      );
      expect(it.price, 3.39);
      expect(
        s.offers.values.where((o) => o.price == 3.39 && o.chain == 'carrefour'),
        hasLength(1),
      );
      s.dispose();
    },
  );

  test('quitar el precio (vacío) no falla', () async {
    final (s, it) = await preparar();
    s.setPrice(it, 3.39);
    s.setPrice(it, null);
    expect(it.price, isNull);
    s.dispose();
  });
}
