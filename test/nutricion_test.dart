import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:multimarket/nutricion.dart';
import 'package:multimarket/sources.dart';

const _off = {
  'quantity': '400 g',
  'serving_size': '30 g',
  'nutriscore_grade': 'c',
  'nova_group': 4,
  'nutriments': {
    'energy-kcal_100g': 484,
    'fat_100g': 25.0,
    'saturated-fat_100g': 9.5,
    'carbohydrates_100g': 58.0,
    'sugars_100g': 31.0,
    'fiber_100g': 3.5,
    'proteins_100g': 6.0,
    'salt_100g': 0.42,
  },
};

void main() {
  test('se leen los valores por 100 g, el Nutri-Score y NOVA', () {
    final n = Nutricion.fromOff(_off);
    expect(n.kcal, 484);
    expect(n.saturadas, 9.5);
    expect(n.azucares, 31.0);
    expect(n.nutriscore, 'c');
    expect(n.nova, 4);
    expect(n.unidad, 'g');
    expect(n.envase, 400);
    expect(n.racion, '30 g');
    expect(n.hayDatos, isTrue);
  });

  test('por envase = valor por 100 g × contenido / 100', () {
    final n = Nutricion.fromOff(_off);
    final e = n.para(n.envase!);
    expect(e.kcal, closeTo(1936, 1e-9));
    expect(e.grasas, closeTo(100, 1e-9));
    expect(e.sal, closeTo(1.68, 1e-9));
  });

  test('si solo hay kJ se convierte a kcal; bebidas en ml', () {
    final n = Nutricion.fromOff({
      'quantity': '1 L',
      'nutriments': {'energy-kj_100g': 418.4, 'sugars_100g': '4,7'},
    });
    expect(n.kcal, closeTo(100, 1e-9));
    expect(n.azucares, 4.7, reason: 'coma decimal en texto');
    expect(n.unidad, 'ml');
    expect(n.envase, 1000);
  });

  test(
    'un grado de Nutri-Score que no es a–e se ignora y sin datos no hay tabla',
    () {
      final n = Nutricion.fromOff({
        'nutriscore_grade': 'unknown',
        'nutriments': {},
      });
      expect(n.nutriscore, isNull);
      expect(n.hayDatos, isFalse);
    },
  );

  test('ida y vuelta por JSON', () {
    final n = Nutricion.fromOff(_off);
    final m = Nutricion.fromJson(
      jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>,
    );
    expect(m.kcal, n.kcal);
    expect(m.nutriscore, 'c');
    expect(m.envase, 400);
  });

  test(
    'nutricionPorCodigo: producto con datos, sin datos y desconocido',
    () async {
      final c = MockClient((r) async {
        if (r.url.path.contains('111')) {
          return http.Response(jsonEncode({'status': 1, 'product': _off}), 200);
        }
        if (r.url.path.contains('222')) {
          return http.Response(
            jsonEncode({
              'status': 1,
              'product': {'nutriments': {}},
            }),
            200,
          );
        }
        return http.Response(jsonEncode({'status': 0}), 200);
      });
      expect(
        (await nutricionPorCodigo('1111111111111', cliente: c))?.kcal,
        484,
      );
      expect(await nutricionPorCodigo('2222222222222', cliente: c), isNull);
      expect(await nutricionPorCodigo('3333333333333', cliente: c), isNull);
    },
  );
}
