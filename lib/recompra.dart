// Recompra: sugiere reponer un producto cuando, según tu propio historial, probablemente se haya acabado.
// Funciones puras (sin estado ni red) para poder probarlas.
import 'models.dart';

/// Un producto que probablemente toca reponer.
class Sugerencia {
  Sugerencia({
    required this.key,
    required this.name,
    required this.due,
    required this.cadaDias,
    required this.ultima,
    this.storeId,
    this.price,
  });
  final String key;
  final String name;
  final DateTime due; // cuándo se estima que se acaba
  final double cadaDias; // cada cuántos días suele reponerse
  final DateTime ultima; // última compra
  final String? storeId;
  final double? price;

  /// Cuánto se ha pasado de la fecha prevista, en días (≥ 0 = ya toca).
  int diasDeRetraso(DateTime ahora) => ahora.difference(due).inDays;
}

/// Lo que el usuario ha decidido sobre un producto sugerido.
class Descarte {
  Descarte({this.veces = 0, this.silenciadoHasta = 0, this.parar = false});
  int veces; // descartes seguidos (se reinicia al comprarlo o añadirlo)
  int silenciadoHasta; // ms: no sugerir antes de esta fecha
  bool parar; // «deja de recordármelo»

  Map<String, dynamic> toJson() => {
    'v': veces,
    's': silenciadoHasta,
    'p': parar,
  };
  factory Descarte.fromJson(Map<String, dynamic> j) => Descarte(
    veces: j['v'] ?? 0,
    silenciadoHasta: j['s'] ?? 0,
    parar: j['p'] ?? false,
  );
}

/// Mínimo de compras (en días distintos) para empezar a sugerir: con menos no hay ritmo fiable.
const minComprasRecompra = 3;

DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

/// Estima cuándo se acaba lo último que compraste de un producto.
/// Ritmo de consumo = unidades compradas ANTES de la última compra / días hasta la última compra
/// (la última aún no se ha consumido). Duración de la última = sus unidades / ritmo.
({DateTime due, double cadaDias})? estimarRecompra(List<Compra> compras) {
  // un evento por día (varias compras el mismo día suman)
  final porDia = <DateTime, int>{};
  for (final c in compras) {
    porDia.update(_dia(c.fecha), (q) => q + c.qty, ifAbsent: () => c.qty);
  }
  if (porDia.length < minComprasRecompra) return null;
  final dias = porDia.keys.toList()..sort();
  final primero = dias.first, ultimo = dias.last;
  final span = ultimo.difference(primero).inDays;
  if (span < 2) return null; // todas casi seguidas: no dice nada del ritmo
  final unidadesAntes = dias
      .take(dias.length - 1)
      .fold(0, (t, d) => t + porDia[d]!);
  final ritmo = unidadesAntes / span; // unidades por día
  if (ritmo <= 0) return null;
  final dur = (porDia[ultimo]! / ritmo).clamp(2.0, 180.0);
  return (
    due: ultimo.add(Duration(hours: (dur * 24).round())),
    cadaDias: span / (dias.length - 1),
  );
}

/// Sugerencias para hoy: lo que ya toca reponer, sin lo que ya está en la lista, silenciado o apagado.
List<Sugerencia> calcularSugerencias({
  required List<Compra> compras,
  required Set<String> yaEnLista,
  required Map<String, Descarte> descartes,
  required DateTime ahora,
  int maximo = 5,
}) {
  final porProducto = <String, List<Compra>>{};
  for (final c in compras) {
    porProducto.putIfAbsent(c.key, () => []).add(c);
  }
  final out = <Sugerencia>[];
  porProducto.forEach((key, lista) {
    if (yaEnLista.contains(key)) return;
    final d = descartes[key];
    if (d != null &&
        (d.parar || ahora.millisecondsSinceEpoch < d.silenciadoHasta)) {
      return;
    }
    final e = estimarRecompra(lista);
    if (e == null || ahora.isBefore(e.due)) return;
    lista.sort((a, b) => a.ms.compareTo(b.ms));
    final ult = lista.last;
    out.add(
      Sugerencia(
        key: key,
        name: ult.name,
        due: e.due,
        cadaDias: e.cadaDias,
        ultima: ult.fecha,
        storeId: ult.storeId,
        price: ult.price,
      ),
    );
  });
  // primero lo más pasado de fecha
  out.sort((a, b) => b.diasDeRetraso(ahora).compareTo(a.diasDeRetraso(ahora)));
  return out.take(maximo).toList();
}

/// Qué quiere el usuario cuando descarta varias veces la misma sugerencia.
enum DecisionRecompra { estacional, parar, seguir }
