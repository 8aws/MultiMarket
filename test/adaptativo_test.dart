import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/main.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:multimarket/ui/adaptativo.dart';
import 'package:multimarket/ui/ficha.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> conProducto() async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState(await SharedPreferences.getInstance());
  s.add(const Product(name: 'Leche entera 1L', cold: true));
  return s;
}

void main() {
  test('clases de tamaño por ancho', () {
    expect(claseVentana(390), ClaseVentana.compacta);
    expect(claseVentana(620), ClaseVentana.media);
    expect(claseVentana(1000), ClaseVentana.expandida);
  });

  test(
    'dos paneles: ancho y alto suficientes (Duo interior horizontal sí, vertical e iPhone horizontal no)',
    () {
      expect(cabenDosPaneles(const Size(951, 669)), isTrue);
      expect(cabenDosPaneles(const Size(669, 951)), isFalse);
      expect(cabenDosPaneles(const Size(932, 430)), isFalse);
      expect(cabenDosPaneles(const Size(1024, 768)), isTrue);
    },
  );

  testWidgets('pantalla ancha: lista y ficha lado a lado, sin hoja modal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = await conProducto();
    await tester.pumpWidget(MultiMarketApp(s));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Elige un producto de la lista para ver y editar su ficha.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Leche entera 1L'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(FichaProducto), findsOneWidget);
    expect(
      find.byType(BottomSheet),
      findsNothing,
      reason: 'la ficha está en el panel, no en una hoja',
    );
    expect(s.seleccionado?.name, 'Leche entera 1L');
    s.dispose();
  });

  testWidgets('pantalla estrecha: la ficha sigue abriéndose en una hoja', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = await conProducto();
    await tester.pumpWidget(MultiMarketApp(s));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Elige un producto de la lista para ver y editar su ficha.'),
      findsNothing,
    );
    await tester.tap(find.text('Leche entera 1L'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(FichaProducto), findsOneWidget);
    s.dispose();
  });
}
