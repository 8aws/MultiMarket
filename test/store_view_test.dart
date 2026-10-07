import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/main.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('vista por tienda: orden, cabeceras y terminadas al final', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final s = AppState(await SharedPreferences.getInstance());
    final mer = s.stores.firstWhere((x) => x.chain == 'mercadona');
    final dia = s.stores.firstWhere((x) => x.chain == 'dia');
    final lid = s.stores.firstWhere((x) => x.chain == 'lidl');
    Item mk(
      String n,
      Store? st,
      int urg, {
      bool cold = false,
      bool done = false,
    }) => Item(
      id: n,
      name: n,
      cold: cold,
      urg: urg,
      done: done,
      storeId: st?.id,
      price: 1.0,
    );
    s.items = [
      mk('Arroz', mer, 3),
      mk('Leche', dia, 1, cold: true),
      mk('Pan', null, 2),
      mk('Atún', lid, 2, done: true),
    ];
    s.view = ViewMode.tiendas;

    await tester.pumpWidget(MultiMarketApp(s));
    await tester.pump();

    final order = ['Dia', 'Mercadona', 'Sin asignar', 'Lidl'];
    final ys = [
      for (final n in order) tester.getTopLeft(find.text(n).first).dy,
    ];
    expect(
      ys,
      orderedEquals([...ys]..sort()),
      reason: 'orden: urgente, sin asignar, terminadas',
    );
    expect(
      find.text('todo comprado'),
      findsNothing,
    ); // subtítulo lleva más texto
    expect(find.textContaining('todo comprado'), findsOneWidget);
    expect(find.textContaining('1 por comprar'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
