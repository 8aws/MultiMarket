import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/ticket/ticket_match.dart';
import 'package:multimarket/ticket/ticket_parser.dart';

Ticket t(List<String> nombres) =>
    Ticket(lineas: [for (final n in nombres) TicketLinea(nombre: n, bruto: 1)]);

void main() {
  final lista = [
    Candidato('a', 'Leche entera 1 L'),
    Candidato('b', 'Pan de molde'),
    Candidato('c', 'Yogur natural'),
    Candidato('d', 'Yogur griego'),
  ];

  test('abreviaturas y prefijos se reconocen solos', () {
    final r = cruzarTicket(t(['LECHE ENT. HACENDADO 1L', 'PAN MOLDE']), lista);
    expect(r[0].estado, EstadoCruce.seguro);
    expect(r[0].itemId, 'a');
    expect(r[1].itemId, 'b');
  });

  test('lo que no está en la lista es nuevo', () {
    final r = cruzarTicket(t(['CHOCOLATE NEGRO 85%']), lista);
    expect(r.single.estado, EstadoCruce.nuevo);
  });

  test('ambiguo o a medias se pregunta', () {
    final r = cruzarTicket(t(['YOGUR 4X125G', 'LECHE']), lista);
    expect(r[0].estado, EstadoCruce.dudoso);
    expect(r[0].alternativas, isNotEmpty);
    expect(
      r[1].estado,
      EstadoCruce.dudoso,
      reason: 'solo 1 de 3 palabras (entera/1/l no están)',
    );
  });

  test('un alias confirmado gana y cada producto se usa una vez', () {
    final r = cruzarTicket(
      t(['LCH ENT HAC', 'LECHE ENTERA 1L']),
      lista,
      alias: {'lch ent hac': 'a'},
    );
    expect(r[0].itemId, 'a');
    expect(r[0].estado, EstadoCruce.seguro);
    expect(
      r[1].estado,
      EstadoCruce.nuevo,
      reason: 'la leche de la lista ya está emparejada',
    );
  });
}
