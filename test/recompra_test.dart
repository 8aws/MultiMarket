import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/recompra.dart';

final base = DateTime(2026, 9, 1, 10);

Compra c(String key, int dia, {int qty = 1, String name = 'Leche'}) => Compra(
  id: 'x$dia$key',
  itemId: 'i$dia',
  key: key,
  name: name,
  qty: qty,
  ms: base.add(Duration(days: dia)).millisecondsSinceEpoch,
);

void main() {
  test('con menos de 3 compras no se sugiere nada', () {
    expect(estimarRecompra([c('a', 0), c('a', 7)]), isNull);
    expect(estimarRecompra([c('a', 0)]), isNull);
  });

  test('una compra cada 7 días: se acaba 7 días después de la última', () {
    final e = estimarRecompra([c('a', 0), c('a', 7), c('a', 14)])!;
    expect(e.cadaDias, closeTo(7, 1e-9));
    // última compra: 15 de septiembre → se acaba el 22
    expect(DateTime(e.due.year, e.due.month, e.due.day), DateTime(2026, 9, 22));
  });

  test('la cantidad cuenta: comprar 2 unidades dura el doble', () {
    // 1 ud cada 7 días → ritmo 1/7 por día; la última compra fue de 2 → dura 14 días
    final e = estimarRecompra([c('a', 0), c('a', 7), c('a', 14, qty: 2)])!;
    final ultima = DateTime(2026, 9, 15);
    expect(e.due.difference(ultima).inDays, closeTo(14, 1));
  });

  test('varias compras el mismo día cuentan como una', () {
    expect(estimarRecompra([c('a', 0), c('a', 0), c('a', 7)]), isNull);
  });

  test('sugiere solo cuando ya toca y no si está en la lista', () {
    final compras = [c('a', 0), c('a', 7), c('a', 14)];
    DateTime hoy(int dias) => base.add(Duration(days: dias));
    List<Sugerencia> s(
      int dia, {
      Set<String> lista = const {},
      Map<String, Descarte> d = const {},
    }) => calcularSugerencias(
      compras: compras,
      yaEnLista: lista,
      descartes: d,
      ahora: hoy(dia),
    );
    expect(s(18), isEmpty, reason: 'aún faltan días');
    expect(s(22).single.name, 'Leche');
    expect(s(22, lista: {'a'}), isEmpty, reason: 'ya está en la lista');
    expect(s(22, d: {'a': Descarte(parar: true)}), isEmpty);
    expect(
      s(
        22,
        d: {'a': Descarte(silenciadoHasta: hoy(30).millisecondsSinceEpoch)},
      ),
      isEmpty,
    );
    expect(
      s(
        31,
        d: {'a': Descarte(silenciadoHasta: hoy(30).millisecondsSinceEpoch)},
      ),
      hasLength(1),
      reason: 'pasó el silencio',
    );
  });

  test('máximo de sugerencias y orden por retraso', () {
    final compras = <Compra>[];
    for (var k = 0; k < 8; k++) {
      // cada producto con un ritmo distinto: cuanto mayor k, más retrasado a día 60
      compras.addAll([c('p$k', 0), c('p$k', 5), c('p$k', 10 + k)]);
    }
    final s = calcularSugerencias(
      compras: compras,
      yaEnLista: {},
      descartes: {},
      ahora: base.add(const Duration(days: 60)),
    );
    expect(s, hasLength(5));
    final retrasos = s
        .map((x) => x.diasDeRetraso(base.add(const Duration(days: 60))))
        .toList();
    expect(retrasos, [...retrasos]..sort((a, b) => b.compareTo(a)));
  });
}
