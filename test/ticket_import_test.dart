import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:multimarket/ticket/ticket_match.dart';
import 'package:multimarket/ticket/ticket_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> mk() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await SharedPreferences.getInstance());
}

void main() {
  test(
    'importar un ticket: marca lo seguro, guarda todo y aprende alias',
    () async {
      final s = await mk();
      final leche = s.add(const Product(name: 'Leche entera'));
      final yogur = s.add(const Product(name: 'Yogur natural'));
      final t = parsearTicket(
        File('test/fixtures/tickets/lidl.txt').readAsLinesSync(),
      );
      final tienda = s.stores.firstWhere(
        (x) => x.chain == 'lidl',
        orElse: () => s.stores.first,
      );
      final cruces = s.cruzar(t);
      expect(cruces, hasLength(t.lineas.length));
      final n = s.aplicarTicket(t, cruces, tienda: tienda);
      // cada línea del ticket queda en el historial, la haya en la lista o no
      expect(s.compras, hasLength(t.lineas.length));
      expect(
        s.compras.every((c) => c.ms == t.fecha!.millisecondsSinceEpoch),
        isTrue,
      );
      expect(s.compras.every((c) => c.storeId == tienda.id), isTrue);
      expect(n, cruces.where((c) => c.estado == EstadoCruce.seguro).length);
      for (final i in [leche, yogur]) {
        if (i.done) expect(i.price, isNotNull);
      }
      // lo pagado es el neto: el historial suma el total del ticket
      final suma = s.compras.fold(0.0, (a, c) => a + c.total);
      expect(suma, closeTo(t.sumaNeta, 0.05));
      s.dispose();
    },
  );

  test(
    'un dudoso resuelto por el usuario marca su producto y deja alias',
    () async {
      final s = await mk();
      final t = Ticket(
        lineas: [TicketLinea(nombre: 'YOGUR 4X125G', bruto: 1.2)],
        cadena: 'lidl',
      );
      s.dispose();
      final s2 = await mk();
      final a = s2.add(const Product(name: 'Yogur natural'));
      s2.add(const Product(name: 'Yogur griego'));
      final c2 = s2.cruzar(t);
      expect(c2.single.estado, EstadoCruce.dudoso);
      expect(s2.aplicarTicket(t, c2, elegidos: {0: a.id}), 1);
      expect(a.done, isTrue);
      expect(s2.aliasTicket['lidl|yogur 4x125g'], 'Yogur natural');
      // la próxima vez ya es seguro, aunque la lista tenga ambos otra vez
      final b = s2.add(const Product(name: 'Yogur natural'));
      s2.add(const Product(name: 'Yogur griego'));
      final c3 = s2.cruzar(t);
      expect(c3.single.estado, EstadoCruce.seguro);
      expect(c3.single.itemId, b.id);
      s2.dispose();
    },
  );
}
