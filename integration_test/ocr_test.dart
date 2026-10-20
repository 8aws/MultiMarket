// Prueba del OCR nativo (Apple Vision) en un simulador o dispositivo iOS:
//   flutter test integration_test/ocr_test.dart -d <id-del-simulador>
// Dibuja un ticket sintético en una imagen, la pasa por el canal nativo y comprueba que el parser lo entiende.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:multimarket/ticket/ticket_lector.dart';
import 'package:multimarket/ticket/ticket_parser.dart';
import 'package:path_provider/path_provider.dart';

Future<String> dibujar(List<String> lineas) async {
  const ancho = 900.0, alto = 70.0;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(
    ui.Rect.fromLTWH(0, 0, ancho, alto * (lineas.length + 1)),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  for (var i = 0; i < lineas.length; i++) {
    final tp = TextPainter(
      text: TextSpan(
        text: lineas[i],
        style: const TextStyle(
          color: ui.Color(0xFF000000),
          fontSize: 34,
          fontFamily: 'Courier',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, ui.Offset(30, alto * (i + 0.5)));
  }
  final img = await rec.endRecording().toImage(
    ancho.toInt(),
    (alto * (lineas.length + 1)).toInt(),
  );
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/ocr_prueba.png');
  await f.writeAsBytes(bytes!.buffer.asUint8List());
  return f.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Apple Vision lee un ticket dibujado y el parser cuadra el total',
    (tester) async {
      final ruta = await tester.runAsync(
        () => dibujar([
          'LIDL SUPERMERCADOS S.A.U.',
          'LECHE ENTERA 1L        1,05 A',
          'PAN DE MOLDE           1,35 B',
          'QUESO FRESCO           2,05 A',
          'TOTAL                  4,45',
          'ENTREGA                4,45',
        ]),
      );
      final tickets = await tester.runAsync(() => leerTickets(ruta!));
      expect(tickets, isNotNull);
      expect(tickets!, isNotEmpty);
      final t = parsearTicket(tickets.first);
      // ignore: avoid_print
      print('LINEAS: ${tickets.first}');
      expect(t.cadena, 'lidl');
      expect(t.lineas.length, 3);
      expect(t.total, 4.45);
      expect(t.cuadra, isTrue);
    },
  );

  testWidgets('imagen muy alta: lectura por tiras sin perder ni duplicar líneas', (
    tester,
  ) async {
    final lineas = <String>['LIDL SUPERMERCADOS S.A.U.'];
    var total = 0.0;
    for (var i = 1; i <= 40; i++) {
      final p = 0.50 + i * 0.37;
      total += p;
      lineas.add(
        'PRODUCTO NUMERO ${i.toString().padLeft(2, '0')}'.padRight(28) +
            '${p.toStringAsFixed(2).replaceAll('.', ',')} A',
      );
    }
    final tot = total.toStringAsFixed(2).replaceAll('.', ',');
    lineas.addAll(['TOTAL'.padRight(28) + tot, 'ENTREGA'.padRight(28) + tot]);
    final ruta = await tester.runAsync(() => dibujar(lineas));
    final tickets = await tester.runAsync(() => leerTickets(ruta!));
    // ignore: avoid_print
    print(
      'COLUMNAS=${tickets!.length} n=${tickets.first.length} primeras=${tickets.first.take(5)} ultimas=${tickets.first.reversed.take(3).toList()}',
    );
    final t = parsearTicket(tickets.first);
    // ignore: avoid_print
    print(
      'TIRAS: lineas=${t.lineas.length} total=${t.total} neta=${t.sumaNeta.toStringAsFixed(2)} cuadra=${t.cuadra}',
    );
    expect(
      t.lineas.length,
      40,
      reason: 'ninguna línea perdida ni repetida en las uniones de las tiras',
    );
    expect(t.cuadra, isTrue);
  });
}
