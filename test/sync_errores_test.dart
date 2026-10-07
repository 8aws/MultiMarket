import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/main.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:multimarket/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> conCompartidaSinServidor() async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState(await SharedPreferences.getInstance());
  s.cfg.serverUrl =
      'http://127.0.0.1:1'; // nada escucha: error de conexión inmediato
  final h = Hogar(id: 'abcdefghijklmno', name: 'Casa', remota: true);
  s.hogares.add(h);
  s.selectHogar(h.id);
  s.add(const Product(name: 'Leche'));
  return s;
}

void main() {
  test('esperas de reintento crecientes con tope', () {
    final e = [
      for (var i = 1; i <= 7; i++) SyncService.esperaReintento(i).inSeconds,
    ];
    expect(e, [5, 15, 45, 120, 300, 300, 300]);
  });

  test(
    'sin conexión: error visible, cambios pendientes y reintento programado',
    () async {
      final s = await conCompartidaSinServidor();
      expect(s.sync.cambiosPendientes, 1);
      await s.sync.sincronizar();
      expect(
        s.sync.error,
        anyOf(contains('Sin conexión'), contains('error')),
        reason: 'en los tests de Flutter el cliente HTTP responde siempre 400',
      );
      expect(s.sync.fallos, 1);
      expect(s.sync.proximoReintento, isNotNull);
      expect(s.sync.cambiosPendientes, 1, reason: 'nada se ha subido');
      await s.sync.sincronizar();
      expect(s.sync.fallos, 2);
      s.dispose();
    },
  );

  testWidgets('el aviso aparece en la lista con botón Reintentar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final s = await conCompartidaSinServidor();
    await tester.runAsync(() => s.sync.sincronizar());
    await tester.pumpWidget(MultiMarketApp(s));
    await tester.pump();
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.textContaining('cambio por subir'), findsOneWidget);
    expect(find.textContaining('1 cambio por subir'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
