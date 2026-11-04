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

  test('punto de corte: dos mitades seguidas con el mismo peso', () {
    expect(puntoDeCorte([]), isNull);
    expect(puntoDeCorte([5]), isNull);
    expect(puntoDeCorte([3, 3]), 1);
    expect(puntoDeCorte([6, 2, 2, 2]), 1);
    expect(puntoDeCorte([2, 2, 2, 6]), 3);
    expect(puntoDeCorte([4, 3, 3, 4]), 2);
  });

  testWidgets(
    'horizontal ancho: frío y sin refrigerar en dos columnas; la ficha va en hoja',
    (tester) async {
      tester.view.physicalSize = const Size(951, 669);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final s = AppState(await SharedPreferences.getInstance());
      s.add(const Product(name: 'Leche entera 1L', cold: true));
      s.add(const Product(name: 'Arroz 1kg'));
      await tester.pumpWidget(MultiMarketApp(s));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Sin refrigerar ·'), findsOneWidget);
      expect(find.textContaining('Fríos ·'), findsOneWidget);
      expect(
        find.text('Elige un producto de la lista para ver y editar su ficha.'),
        findsNothing,
        reason: 'el lado derecho está en uso',
      );
      await tester.tap(find.text('Arroz 1kg'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BottomSheet), findsOneWidget);
      s.dispose();
    },
  );

  testWidgets(
    'horizontal ancho con todo seco: no hay nada que repartir y el panel muestra la ficha',
    (tester) async {
      tester.view.physicalSize = const Size(951, 669);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final s = AppState(await SharedPreferences.getInstance());
      s.add(const Product(name: 'Arroz 1kg'));
      await tester.pumpWidget(MultiMarketApp(s));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Elige un producto de la lista para ver y editar su ficha.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Arroz 1kg'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FichaProducto), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      s.dispose();
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
