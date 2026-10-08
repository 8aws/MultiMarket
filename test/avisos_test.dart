import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';
import 'package:shared_preferences/shared_preferences.dart';

String ahora([int minutosAtras = 0]) => DateTime.now()
    .toUtc()
    .subtract(Duration(minutes: minutosAtras))
    .toIso8601String()
    .replaceFirst('T', ' ');

void main() {
  sancionesTests();
  erroresTests();
  test(
    'un aviso de otro miembro se muestra; los míos, ajenos o viejos no',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(await SharedPreferences.getInstance());
      s.hogares.add(Hogar(id: 'h1', name: 'Casa', remota: true));
      final vistos = <String>[];
      s.avisos.listen((a) => vistos.add(a.texto));

      s.avisoRemoto({
        'id': 'a1',
        'hogar': 'h1',
        'user': 'otro',
        'texto': 'Ana va a comprar en Lidl',
        'created': ahora(),
      });
      s.avisoRemoto({
        'id': 'a2',
        'hogar': 'h1',
        'user': 'otro',
        'texto': 'viejo',
        'created': ahora(30),
      });
      s.avisoRemoto({
        'id': 'a3',
        'hogar': 'otra-lista',
        'user': 'otro',
        'texto': 'ajeno',
        'created': ahora(),
      });
      s.avisoRemoto({
        'id': 'a4',
        'hogar': 'h1',
        'user': s.sync.miId,
        'texto': 'mío',
        'created': ahora(),
      });
      await Future<void>.delayed(Duration.zero);

      expect(vistos, ['Ana va a comprar en Lidl']);
      s.dispose();
    },
  );

  test('«voy yo» en una lista privada no hace nada', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState(await SharedPreferences.getInstance());
    expect(await s.voyYo(), 'Solo en listas compartidas');
    s.dispose();
  });
}

void sancionesTests() {
  test(
    'una sanción temporal bloquea hasta su fecha; la indefinida, siempre',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(await SharedPreferences.getInstance());
      expect(s.puedeCompartir, isTrue);
      expect(s.textoSancion, isNull);
      s.sancionHasta = DateTime.now().add(const Duration(days: 7));
      expect(s.puedeCompartir, isFalse);
      expect(s.textoSancion, contains('hasta el'));
      s.sancionHasta = DateTime.now().subtract(const Duration(days: 1));
      expect(s.puedeCompartir, isTrue, reason: 'la sanción caducó');
      s.sancionIndef = true;
      expect(s.puedeCompartir, isFalse);
      expect(s.textoSancion, contains('no puede compartir contenido nuevo'));
      s.dispose();
    },
  );
}

void erroresTests() {
  test(
    'los errores solo se encolan si el usuario activó los informes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(await SharedPreferences.getInstance());
      expect(s.cfg.enviarErrores, isFalse, reason: 'desactivado por defecto');
      s.registrarError(
        StateError('x'),
        StackTrace.current,
      ); // no hace nada ni lanza
      s.dispose();
    },
  );
}
