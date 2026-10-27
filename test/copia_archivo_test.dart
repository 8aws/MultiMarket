import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'copia en archivo: sale con formato propio y se restaura en otro dispositivo',
    () async {
      SharedPreferences.setMockInitialValues({});
      final a = AppState(await SharedPreferences.getInstance());
      final it = a.add(Product(name: 'Leche entera', cold: true));
      a.setPrice(it, 1.05);
      final bytes = a.copiaEnArchivo();
      final j = jsonDecode(utf8.decode(bytes)) as Map;
      expect(j['multimarket'], 1);
      expect(j['datos'], isA<Map>());

      SharedPreferences.setMockInitialValues({});
      final b = AppState(await SharedPreferences.getInstance());
      expect(b.restaurarDeArchivo(utf8.decode(bytes)), isNull);
      expect(b.allItems.map((i) => i.name), contains('Leche entera'));
      expect(
        b.allItems.firstWhere((i) => i.name == 'Leche entera').price,
        1.05,
      );
    },
  );

  test('copia en archivo: rechaza lo que no es una copia', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState(await SharedPreferences.getInstance());
    expect(s.restaurarDeArchivo('{"hola":1}'), isNotNull);
    expect(s.restaurarDeArchivo('no es json'), isNotNull);
  });
}
