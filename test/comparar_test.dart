import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/main.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:multimarket/ui/comparar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'comparar: el grande sale mejor por kilo y se pueden completar los datos que faltan',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final s = AppState(await SharedPreferences.getInstance());
      s.anadirAComparar(
        const Product(name: 'Crema 200 g', barcode: '1'),
        cantidad: '200 g',
        precio: 1.20,
      );
      s.anadirAComparar(
        const Product(name: 'Crema 450 g', barcode: '2'),
        cantidad: '450 g',
        precio: 2.50,
      );
      s.anadirAComparar(const Product(name: 'Crema otra marca', barcode: '3'));
      await tester.pumpWidget(
        AppScope(
          state: s,
          child: const MaterialApp(home: CompararPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('POR KILO'), findsOneWidget);
      expect(find.text('Mejor'), findsOneWidget);
      expect(
        find.textContaining('5,56'),
        findsOneWidget,
        reason: '2,50 € / 0,45 kg',
      );
      expect(
        find.textContaining('6,00'),
        findsOneWidget,
        reason: '1,20 € / 0,2 kg',
      );
      expect(find.text('FALTAN DATOS'), findsOneWidget);
      expect(find.text('Sin tamaño o precio'), findsOneWidget);

      // el usuario completa los datos de la tercera: 300 g a 1,50 € = 5,00 €/kg → pasa a ser la mejor
      final campos = find.byType(TextField);
      final i = tester
          .widgetList<TextField>(campos)
          .toList()
          .indexWhere(
            (t) =>
                t.decoration?.labelText == 'Tamaño' &&
                t.controller!.text.isEmpty,
          );
      expect(i, greaterThanOrEqualTo(0));
      await tester.enterText(campos.at(i), '300 g');
      await tester.enterText(campos.at(i + 1), '1,50');
      await tester.pumpAndSettle();
      expect(find.text('FALTAN DATOS'), findsNothing);
      expect(find.textContaining('5,00'), findsOneWidget);
      expect(find.text('Mejor'), findsOneWidget);
      expect(s.comparacion.first.producto.name, 'Crema 200 g');

      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
}
