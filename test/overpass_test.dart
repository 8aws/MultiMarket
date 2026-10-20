import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:multimarket/sources.dart';

const _ok = {
  'elements': [
    {
      'type': 'node',
      'id': 1,
      'lat': 36.5,
      'lon': -4.6,
      'tags': {'name': 'Lidl', 'shop': 'supermarket'},
    },
  ],
};

void main() {
  cacheTests();
  test('si el servidor principal falla, responde el siguiente', () async {
    final llamadas = <String>[];
    final c = MockClient((r) async {
      llamadas.add(r.url.host);
      if (r.url.host == 'a.test') return http.Response('Bad gateway', 502);
      return http.Response(jsonEncode(_ok), 200);
    });
    final j = await consultarOverpass(
      'q',
      cliente: c,
      servidores: ['a.test', 'b.test', 'c.test'],
      escalon: const Duration(milliseconds: 10),
    );
    expect((j['elements'] as List), hasLength(1));
    expect(llamadas.first, 'a.test');
    expect(llamadas, contains('b.test'));
  });

  test(
    'si el primero tarda mucho, gana el segundo sin esperar al primero',
    () async {
      final c = MockClient((r) async {
        if (r.url.host == 'lento.test') {
          await Future<void>.delayed(const Duration(seconds: 5));
          return http.Response(jsonEncode(_ok), 200);
        }
        return http.Response(jsonEncode(_ok), 200);
      });
      final t = Stopwatch()..start();
      await consultarOverpass(
        'q',
        cliente: c,
        servidores: ['lento.test', 'rapido.test'],
        escalon: const Duration(milliseconds: 50),
      );
      expect(t.elapsedMilliseconds, lessThan(2000));
    },
  );

  test(
    'una respuesta 200 con error de ejecución se trata como fallo',
    () async {
      final c = MockClient((r) async {
        if (r.url.host == 'a.test') {
          return http.Response(
            jsonEncode({
              'elements': [],
              'remark': 'runtime error: Query timed out',
            }),
            200,
          );
        }
        return http.Response(jsonEncode(_ok), 200);
      });
      final j = await consultarOverpass(
        'q',
        cliente: c,
        servidores: ['a.test', 'b.test'],
        escalon: const Duration(milliseconds: 10),
      );
      expect((j['elements'] as List), isNotEmpty);
    },
  );

  test('si todos fallan, error claro de servicio ocupado', () async {
    final c = MockClient((r) async => http.Response('x', 504));
    expect(
      consultarOverpass(
        'q',
        cliente: c,
        servidores: ['a.test', 'b.test'],
        escalon: const Duration(milliseconds: 10),
      ),
      throwsA(isA<OverpassOcupado>()),
    );
  });
}

void cacheTests() {
  test('la caché propia entrega las tiendas sin tocar Overpass', () async {
    final c = MockClient((r) async {
      expect(r.url.path, '/api/mm/v1/tiendas');
      return http.Response(
        jsonEncode({
          'incompleto': false,
          'items': [
            {
              't': 'node',
              'id': 7,
              'lat': 36.5,
              'lon': -4.6,
              'name': 'Lidl',
              'brand': 'Lidl',
            },
            {
              't': 'way',
              'id': 9,
              'lat': 36.51,
              'lon': -4.61,
              'name': 'Dia',
              'brand': 'Dia',
            },
          ],
        }),
        200,
      );
    });
    final r = await tiendasDeNuestraCache(
      'https://x.test',
      36.5,
      -4.6,
      5,
      cliente: c,
    );
    expect(r.incompleto, isFalse);
    expect(r.tiendas.map((t) => t.id), ['osm:node/7', 'osm:way/9']);
    expect(r.tiendas.first.km, lessThan(r.tiendas.last.km));
  });
}
