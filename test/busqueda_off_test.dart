import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:multimarket/sources.dart';

void main() {
  test(
    'búsqueda en Open Food Facts: filtra por país con el campo actual y reintenta sin él si falla',
    () async {
      final consultas = <String>[];
      final cliente = MockClient((req) async {
        final q = req.url.queryParameters['q']!;
        consultas.add(q);
        if (q.contains('countries')) {
          // el índice cambia de campo: la consulta con país da 400, no una lista vacía
          return http.Response(jsonEncode({'errors': []}), 400);
        }
        return http.Response(
          jsonEncode({
            'hits': [
              {
                'code': '8410877245930',
                'product_name': 'Leche',
                'categories': ['en:milks'],
              },
            ],
          }),
          200,
        );
      });
      final r = await searchProducts('leche', cliente: cliente);
      expect(consultas.first, 'leche countries:"en:spain"');
      expect(consultas, hasLength(2));
      expect(r, isNotEmpty);
      expect(r.first.name, 'Leche');
    },
  );
}
