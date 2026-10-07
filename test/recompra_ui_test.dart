import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/main.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/recompra.dart';
import 'package:multimarket/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> conHistorialSemanal() async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState(await SharedPreferences.getInstance());
  final ahora = DateTime.now();
  // leche cada 7 días: hace 28, 21 y 14 días → debería haberse acabado hace una semana
  for (final dias in [28, 21, 14]) {
    s.compras.add(
      Compra(
        id: 'c$dias',
        itemId: 'i$dias',
        key: 'leche entera 1l',
        name: 'Leche entera 1L',
        qty: 1,
        price: 0.85,
        ms: ahora.subtract(Duration(days: dias)).millisecondsSinceEpoch,
      ),
    );
  }
  return s;
}

void main() {
  test(
    'el historial genera la sugerencia y desaparece si ya está en la lista',
    () async {
      final s = await conHistorialSemanal();
      expect(s.sugerencias.map((g) => g.name), ['Leche entera 1L']);
      s.add(const Product(name: 'Leche entera 1L'));
      expect(s.sugerencias, isEmpty, reason: 'ya está pendiente en la lista');
      s.dispose();
    },
  );

  test('desactivar en Ajustes apaga las sugerencias', () async {
    final s = await conHistorialSemanal();
    s.cfg.recompra = false;
    expect(s.sugerencias, isEmpty);
    s.dispose();
  });

  test(
    'descartar silencia unos días y a la tercera pide decidir; parar la apaga',
    () async {
      final s = await conHistorialSemanal();
      final g = s.sugerencias.single;
      expect(s.descartarSugerencia(g), isFalse);
      expect(s.sugerencias, isEmpty, reason: 'silenciada unos días');
      s.descartes[g.key]!.silenciadoHasta = 0; // pasan los días
      expect(s.descartarSugerencia(s.sugerencias.single), isFalse);
      s.descartes[g.key]!.silenciadoHasta = 0;
      expect(
        s.descartarSugerencia(s.sugerencias.single),
        isTrue,
        reason: '3.º descarte seguido: preguntar',
      );
      s.resolverRecurrente(g.key, DecisionRecompra.parar);
      s.descartes[g.key]!.silenciadoHasta = 0;
      expect(s.sugerencias, isEmpty);
      s.restablecerSugerencias();
      expect(s.sugerencias, hasLength(1));
      s.dispose();
    },
  );

  test('estacional la silencia tres meses', () async {
    final s = await conHistorialSemanal();
    final g = s.sugerencias.single;
    s.resolverRecurrente(g.key, DecisionRecompra.estacional);
    expect(s.sugerencias, isEmpty);
    final hasta = DateTime.fromMillisecondsSinceEpoch(
      s.descartes[g.key]!.silenciadoHasta,
    );
    expect(hasta.difference(DateTime.now()).inDays, closeTo(90, 1));
    s.dispose();
  });

  testWidgets(
    'fantasma al 50 %: tocar la fila la añade; tocar el círculo la descarta',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final s = await conHistorialSemanal();
      await tester.pumpWidget(MultiMarketApp(s));
      await tester.pumpAndSettle();
      expect(find.text('POR SI TE QUEDAS SIN ELLO'), findsOneWidget);
      final op = tester.widget<Opacity>(
        find
            .ancestor(
              of: find.text('Leche entera 1L'),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(op.opacity, .5);
      expect(s.items, isEmpty);

      // círculo: descartar sin añadir
      await tester.tap(find.byTooltip('No hace falta ahora'));
      await tester.pumpAndSettle();
      expect(s.items, isEmpty);
      expect(find.text('POR SI TE QUEDAS SIN ELLO'), findsNothing);

      // tras pasar el silencio, tocar la fila la convierte en producto real
      s.descartes.values.first.silenciadoHasta = 0;
      s.refresh();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leche entera 1L'));
      await tester.pumpAndSettle();
      expect(s.items.single.name, 'Leche entera 1L');
      expect(s.items.single.done, isFalse);
      expect(
        find.text('POR SI TE QUEDAS SIN ELLO'),
        findsNothing,
        reason: 'ya no es fantasma',
      );

      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );

  testWidgets('tras 3 descartes seguidos aparece la pregunta', (tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final s = await conHistorialSemanal();
    await tester.pumpWidget(MultiMarketApp(s));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('No hace falta ahora'));
      await tester.pumpAndSettle();
      if (i < 2) {
        s.descartes.values.first.silenciadoHasta = 0;
        s.refresh();
        await tester.pumpAndSettle();
      }
    }
    expect(find.text('Es estacional (3 meses)'), findsOneWidget);
    expect(find.text('Dejar de recordármelo'), findsOneWidget);
    await tester.tap(find.text('Dejar de recordármelo'));
    await tester.pumpAndSettle();
    expect(s.descartes.values.first.parar, isTrue);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
