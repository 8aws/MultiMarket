// Cruce de las líneas de un ticket con la lista de la compra. Función pura.
//
// Los tickets abrevian y truncan («LECHE ENT. HACENDADO 1L»), así que se compara por palabras:
// una palabra de la lista «está» en el ticket si coincide o es prefijo de alguna (≥3 letras).
// - alias: lo que el usuario ya confirmó en esa cadena (nombre del ticket normalizado → id de item). Gana siempre.
// - seguro: todas las palabras del producto aparecen y no hay otro candidato casi igual → se aplica solo.
// - dudoso: aparecen al menos la mitad, o hay empate → se pregunta.
// - nuevo: nada parecido → solo entra en el catálogo/historial.

import 'ticket_parser.dart';

enum EstadoCruce { seguro, dudoso, nuevo }

class Candidato {
  Candidato(this.id, this.nombre);
  final String id;
  final String nombre;
}

class Cruce {
  Cruce(
    this.linea,
    this.estado, {
    this.itemId,
    this.puntos = 0,
    this.alternativas = const [],
  });
  final TicketLinea linea;
  final EstadoCruce estado;
  final String? itemId; // propuesto (seguro) o mejor candidato (dudoso)
  final double puntos;
  final List<String> alternativas; // otros ids posibles
}

String normalizarNombre(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[áàä]'), 'a')
    .replaceAll(RegExp(r'[éèë]'), 'e')
    .replaceAll(RegExp(r'[íìï]'), 'i')
    .replaceAll(RegExp(r'[óòö]'), 'o')
    .replaceAll(RegExp(r'[úùü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim();

const _vacias = {'de', 'del', 'la', 'el', 'y', 'con', 'sin', 'en', 'al'};

List<String> _palabras(String s) => normalizarNombre(s)
    .split(' ')
    .where(
      (t) =>
          t.length > 1 &&
          !_vacias.contains(t) &&
          !RegExp(
            r'^\d+[a-z]{0,2}$',
          ).hasMatch(t), // tamaños («1l», «500g») no identifican
    )
    .toList();

/// Cuánto «está» una palabra del producto en la línea del ticket: 1 si aparece entera, 0,95 si el ticket la trunca
/// (prefijo de ≥3 letras: «ENT.» por «entera»).
double _peso(String w, List<String> t) {
  var mejor = 0.0;
  for (final x in t) {
    if (w == x) return 1;
    final c = w.length <= x.length ? w : x, l = w.length <= x.length ? x : w;
    if (c.length >= 3 && l.startsWith(c)) {
      if (mejor < .95) mejor = .95;
    }
  }
  return mejor;
}

/// Fracción (0–1) de palabras del producto de la lista que aparecen en la línea del ticket.
double cobertura(String producto, String lineaTicket) {
  final p = _palabras(producto);
  if (p.isEmpty) return 0;
  final t = _palabras(lineaTicket);
  return p.fold(0.0, (a, w) => a + _peso(w, t)) / p.length;
}

/// ¿Hay al menos una palabra que coincide entera o con un prefijo de ≥4 letras? Un prefijo de 3 letras solo ayuda
/// a completar un producto ya reconocido: «CEBOLLA EN POLVO CAR» (Carmencita) no es «carnes» por empezar por «car».
bool _hayCoincidenciaFirme(String producto, String lineaTicket) {
  final t = _palabras(lineaTicket);
  return _palabras(producto).any(
    (w) => t.any(
      (x) =>
          w == x ||
          (w.length <= x.length ? w : x).length >= 4 &&
              (w.length <= x.length ? x : w).startsWith(
                w.length <= x.length ? w : x,
              ),
    ),
  );
}

List<Cruce> cruzarTicket(
  Ticket ticket,
  List<Candidato> lista, {
  Map<String, String> alias = const {},
}) {
  final usados = <String>{};
  final res = List<Cruce?>.filled(ticket.lineas.length, null);
  // 1º alias confirmados
  for (var i = 0; i < ticket.lineas.length; i++) {
    final id = alias[normalizarNombre(ticket.lineas[i].nombre)];
    if (id != null && lista.any((c) => c.id == id) && !usados.contains(id)) {
      usados.add(id);
      res[i] = Cruce(
        ticket.lineas[i],
        EstadoCruce.seguro,
        itemId: id,
        puntos: 1,
      );
    }
  }
  // 2º por palabras, primero las parejas más claras
  final pares = <(int, Candidato, double)>[];
  for (var i = 0; i < ticket.lineas.length; i++) {
    if (res[i] != null) continue;
    for (final c in lista) {
      if (usados.contains(c.id)) continue;
      final cob = cobertura(c.nombre, ticket.lineas[i].nombre);
      if (cob >= .5 &&
          _hayCoincidenciaFirme(c.nombre, ticket.lineas[i].nombre)) {
        pares.add((i, c, cob));
      }
    }
  }
  pares.sort((a, b) => b.$3.compareTo(a.$3));
  for (final p in pares) {
    if (res[p.$1] != null || usados.contains(p.$2.id)) continue;
    final rivales = pares
        .where(
          (q) =>
              q.$1 == p.$1 &&
              q.$2.id != p.$2.id &&
              !usados.contains(q.$2.id) &&
              q.$3 >= p.$3 - .01,
        )
        .toList();
    final seguro = p.$3 >= .95 && rivales.isEmpty;
    if (seguro) usados.add(p.$2.id);
    res[p.$1] = Cruce(
      ticket.lineas[p.$1],
      seguro ? EstadoCruce.seguro : EstadoCruce.dudoso,
      itemId: p.$2.id,
      puntos: p.$3,
      alternativas: [for (final q in rivales) q.$2.id],
    );
  }
  return [
    for (var i = 0; i < res.length; i++)
      res[i] ?? Cruce(ticket.lineas[i], EstadoCruce.nuevo),
  ];
}
