import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/main.dart';
import 'package:multimarket/state.dart';
import 'package:multimarket/ui/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Ajustes: secciones plegadas por defecto y se abren al tocar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final s = AppState(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      AppScope(
        state: s,
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pump();
    expect(find.text('Mis listas'), findsOneWidget);
    expect(find.text('Privacidad'), findsOneWidget);
    expect(
      find.text('Política de privacidad'),
      findsNothing,
      reason: 'plegada',
    );
    await tester.tap(find.text('Privacidad'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Política de privacidad'), findsOneWidget);
    await tester.tap(find.text('Privacidad'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Política de privacidad'), findsNothing);
    s.dispose();
  });
}
