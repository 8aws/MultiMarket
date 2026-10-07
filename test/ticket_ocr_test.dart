import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/ticket/ticket_ocr.dart';

FragmentoOcr f(String t, double x0, double y0, double x1, [double h = 10]) =>
    FragmentoOcr(t, x0, y0, x1, y0 + h);

void main() {
  test('nombre y precio separados por el OCR vuelven a una sola fila', () {
    final r = agruparPorFilas([
      f('1,05', 200, 31, 240),
      f('LECHE ENTERA', 10, 30, 120),
      f('PAN', 10, 52, 40),
      f('0,89', 200, 53, 240),
    ]);
    expect(r, ['LECHE ENTERA 1,05', 'PAN 0,89']);
  });

  test('dos tickets lado a lado se separan y no se mezclan filas', () {
    final fr = [
      for (var i = 0; i < 6; i++) ...[
        f('A$i', 10, 20.0 * i, 80),
        f('${i}0,00', 90, 20.0 * i, 120),
        f('B$i', 220, 20.0 * i + 3, 290),
        f('${i}1,00', 300, 20.0 * i + 3, 330),
      ],
    ];
    final cols = separarColumnas(fr);
    expect(cols, hasLength(2));
    expect(agruparPorFilas(cols[0]).first, 'A0 00,00');
    expect(agruparPorFilas(cols[1]).first, 'B0 01,00');
  });

  test('un solo ticket no se parte', () {
    final fr = [
      for (var i = 0; i < 10; i++) ...[
        f('PRODUCTO $i', 10, 20.0 * i, 150),
        f('1,00', 160, 20.0 * i, 200),
      ],
    ];
    expect(separarColumnas(fr), hasLength(1));
  });
}
