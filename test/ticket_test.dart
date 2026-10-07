import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/ticket/ticket_parser.dart';

List<String> leer(String nombre) =>
    File('test/fixtures/tickets/$nombre.txt').readAsLinesSync();

void main() {
  group('tickets sintéticos con la estructura de cada cadena', () {
    test(
      'Lidl: descuentos por línea, peso DESPUÉS del producto y «unitario x cantidad»',
      () {
        final t = parsearTicket(leer('lidl'));
        expect(t.cadena, 'lidl');
        expect(t.lineas, hasLength(5));
        expect(t.total, 13.10);
        expect(
          t.cuadra,
          isTrue,
          reason: 'bruto ${t.sumaBruta} neto ${t.sumaNeta}',
        );
        final manzana = t.lineas.firstWhere(
          (l) => l.nombre.startsWith('MANZANA'),
        );
        expect(manzana.porPeso, isTrue);
        expect(manzana.cantidad, 0.925);
        expect(manzana.unitario, 2.50);
        expect(manzana.descuento, -0.12);
        final cereales = t.lineas.firstWhere(
          (l) => l.nombre.startsWith('CEREALES'),
        );
        expect(cereales.cantidad, 3);
        expect(cereales.unitario, 2.20);
        expect(cereales.bruto, 6.60);
        final queso = t.lineas.firstWhere((l) => l.nombre.startsWith('QUESO'));
        expect(
          queso.descuento,
          closeTo(-0.55, 1e-9),
          reason: '«Desc.» y «PROMO» se suman a la misma línea',
        );
        expect(t.fecha, DateTime(2026, 10, 12));
      },
    );

    test(
      'MÁS: cantidad × unitario = importe, códigos internos y descuento GLOBAL al final',
      () {
        final t = parsearTicket(leer('mas'));
        expect(t.cadena, 'mas');
        expect(t.lineas, hasLength(4));
        expect(t.descuentoGlobal, -1.50);
        expect(t.total, 18.25);
        expect(t.sumaBruta, closeTo(19.75, 1e-9));
        expect(t.cuadra, isTrue);
        final cafe = t.lineas.firstWhere((l) => l.nombre.startsWith('CAFE'));
        expect(cafe.codigo, '11111');
        expect(cafe.cantidad, 2);
        expect(cafe.unitario, 4.10);
        expect(
          cafe.nombre,
          'CAFE MOLIDO NATURAL',
          reason: 'el código interno no forma parte del nombre',
        );
      },
    );

    test(
      'Aldi: el peso va ANTES del producto (se asocia por aritmética, no por orden)',
      () {
        final t = parsearTicket(leer('aldi'));
        expect(
          t.cadena,
          'aldi',
          reason: 'la cabecera «A L D I» lleva las letras separadas',
        );
        expect(t.lineas, hasLength(4));
        final pollo = t.lineas.firstWhere((l) => l.nombre.startsWith('POLLO'));
        expect(pollo.porPeso, isTrue);
        expect(pollo.cantidad, 0.512);
        final pan = t.lineas.firstWhere((l) => l.nombre.startsWith('PAN'));
        expect(
          pan.porPeso,
          isFalse,
          reason: 'el peso es del producto SIGUIENTE (5,11), no del anterior',
        );
        expect(
          t.lineas.firstWhere((l) => l.nombre.startsWith('SALMON')).descuento,
          -0.70,
        );
        expect(t.total, 10.08);
        expect(t.cuadra, isTrue);
      },
    );
  });

  group('errores típicos del OCR', () {
    test('O por 0 dentro de un número y euro mal leído no impiden cuadrar', () {
      final t = parsearTicket([
        'ALDI',
        'LECHE ENTERA 1L 0,9O £ 3', // «0,9O»: la O es un cero
        'PAN DE MOLDE 1,2O 3', // sin símbolo de euro
        'A PAGAR 2,10 €',
      ]);
      expect(t.lineas.map((l) => l.bruto), [0.90, 1.20]);
      expect(t.cuadra, isTrue);
    });

    test('un precio mal leído NO cuadra, y se sabe cuánto falta', () {
      final t = parsearTicket(
        [
          'LIDL',
          'LECHE 1,00 A',
          'PAN 1,50 A',
          'Total 2,50',
        ].map((l) => l == 'PAN 1,50 A' ? 'PAN 1,58 A' : l).toList(),
      ); // el OCR leyó 1,58
      expect(t.cuadra, isFalse);
      expect(t.diferencia, closeTo(-0.08, 1e-9));
    });

    test('cantidad × precio que no cuadra marca la línea como dudosa', () {
      final t = parsearTicket([
        'SUPERMERCADOS MAS',
        'AGUA MINERAL 6x 0.30 2.90 B', // 6 × 0,30 = 1,80, no 2,90
        'TOTAL A PAGAR 2.90',
      ]);
      expect(t.lineas.single.dudosa, isTrue);
      expect(t.lineas.single.nota, contains('no coincide'));
    });

    test('lo que no es un producto (cabeceras, tarjeta, IVA) no se cuela', () {
      final t = parsearTicket([
        'ALDI',
        'Calle Ejemplo 5, 28000 Ciudad',
        'Horario de apertura:',
        'LECHE 1,00 € 3',
        'A PAGAR 1,00 €',
        'Pago con tarjeta 1,00 €',
        'IVA 10,00% 0,09 0,91 1,00',
        'Total ahorrado: 0,00 €',
      ]);
      expect(t.lineas.map((l) => l.nombre), ['LECHE']);
    });
  });

  // Tickets reales: no están en el repositorio (llevan datos personales). Para probarlos en local:
  //   MM_TICKETS=/ruta/a/carpeta flutter test test/ticket_test.dart
  // La carpeta tiene un .txt por ticket (el texto tal cual lo devuelve el OCR o el PDF).
  group('tickets reales (solo en local)', () {
    final ruta = Platform.environment['MM_TICKETS'];
    final dir = ruta == null ? null : Directory(ruta);
    final hay = dir != null && dir.existsSync();
    test('cada ticket real cuadra con su total impreso', () {
      final ficheros = dir!.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.txt'),
      );
      expect(ficheros, isNotEmpty);
      for (final f in ficheros) {
        final t = parsearTicket(f.readAsLinesSync());
        expect(t.lineas, isNotEmpty, reason: f.path);
        expect(
          t.cuadra,
          isTrue,
          reason: '${f.path}: diferencia ${t.diferencia}',
        );
      }
    }, skip: hay ? false : 'define MM_TICKETS para probar tickets reales');
  });
}
