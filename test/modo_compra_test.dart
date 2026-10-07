import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/main.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:multimarket/ui/modo_compra.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> mk() async {
  SharedPreferences.setMockInitialValues({});
  return AppState(await SharedPreferences.getInstance());
}

Widget envoltorio(AppState s, Widget hijo) => AppScope(
  state: s,
  child: MaterialApp(home: Scaffold(body: hijo)),
);

void main() {
  const hacendado = Product(
    name: 'Leche entera · Hacendado',
    barcode: '8480000106483',
    genericKey: 'leche-entera|1000ml',
    quantity: '1 l',
  );
  const gaza = Product(
    name: 'Leche entera · Gaza',
    barcode: '8421860100013',
    genericKey: 'leche-entera|1000ml',
    quantity: '1 l',
  );

  test(
    'coincidencias: exacta por código y equivalentes por clave genérica',
    () async {
      final s = await mk();
      final it = s.add(hacendado);
      expect(s.pendientesConCodigo('8480000106483'), [it]);
      expect(s.pendientesConCodigo('8421860100013'), isEmpty);
      expect(s.equivalentesPendientes(gaza), [it]);
      expect(
        s.equivalentesPendientes(hacendado),
        isEmpty,
        reason: 'el exacto no cuenta como equivalente',
      );
      s.toggleDone(it);
      expect(
        s.equivalentesPendientes(gaza),
        isEmpty,
        reason: 'ya comprado: no se ofrece sustituir',
      );
      s.dispose();
    },
  );

  test(
    'sustituir cambia el producto de la línea; anotar precio lo recuerda por cadena',
    () async {
      final s = await mk();
      final it = s.add(hacendado);
      s.sustituirItem(it, gaza);
      expect(it.name, contains('Gaza'));
      expect(it.barcode, '8421860100013');
      final dia = s.stores.firstWhere((x) => x.chain == 'dia');
      s.cfg.enabled.add(dia.id);
      s.anotarPrecio(gaza, dia, 0.79);
      final q = await s.precioConocido(gaza, dia);
      expect(q?.price, 0.79);
      s.dispose();
    },
  );

  testWidgets(
    'equivalente en la lista: sustituir, comprar y ofrecer escanear más o cerrar',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final s = await mk();
      final dia = s.stores.firstWhere((x) => x.chain == 'dia');
      final it = s.add(hacendado);
      var seguir = false, cerrar = false;
      await tester.pumpWidget(
        envoltorio(
          s,
          ResultadoEscaneo(
            s: s,
            code: gaza.barcode!,
            producto: gaza,
            tienda: dia,
            onSeguir: () => seguir = true,
            onCerrar: () => cerrar = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('equivalente'), findsOneWidget);
      expect(find.text('Comprado ahora'), findsOneWidget);
      expect(find.text('Para más adelante'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '0,79');
      await tester.tap(find.text('Marcar como comprado'));
      await tester.pumpAndSettle();
      expect(it.name, contains('Gaza'), reason: 'sustituido');
      expect(it.done, isTrue);
      expect(it.storeId, dia.id);
      expect(it.price, 0.79);
      expect(s.compras.single.name, contains('Gaza'));
      expect(find.text('Escanear más'), findsOneWidget);
      expect(find.text('Cerrar'), findsOneWidget);
      await tester.tap(find.text('Escanear más'));
      expect(seguir, isTrue);
      await tester.tap(find.text('Cerrar'));
      expect(cerrar, isTrue);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );

  testWidgets(
    'producto que no está en la lista: «para más adelante» lo añade pendiente',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final s = await mk();
      await tester.pumpWidget(
        envoltorio(
          s,
          ResultadoEscaneo(
            s: s,
            code: '8410000000001',
            producto: const Product(
              name: 'Galletas · Marca',
              barcode: '8410000000001',
            ),
            tienda: null,
            onSeguir: () {},
            onCerrar: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No está en tu lista'), findsOneWidget);
      await tester.tap(find.text('Guardar para después'));
      await tester.pumpAndSettle();
      expect(s.items.single.name, contains('Galletas'));
      expect(s.items.single.done, isFalse);
      expect(s.compras, isEmpty);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );

  testWidgets('código desconocido: ofrece crear el producto', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final s = await mk();
    await tester.pumpWidget(
      envoltorio(
        s,
        ResultadoEscaneo(
          s: s,
          code: '8499999999999',
          producto: null,
          tienda: null,
          onSeguir: () {},
          onCerrar: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Crear producto'), findsOneWidget);
    expect(find.textContaining('No lo conozco'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
