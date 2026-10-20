// Lectura de tickets de supermercado a partir de su TEXTO (OCR en el dispositivo o PDF con texto).
// Funciones puras: no hacen red ni dependen de la cámara, para poder probarlas con tickets reales.
//
// Idea: no se «entiende» el ticket, se combinan pistas y se VALIDA con aritmética:
//   1. se localiza el cuerpo (hasta la línea de TOTAL / IVA),
//   2. cada línea se clasifica por su forma (producto con precio, peso, cantidad×unitario, descuento),
//   3. los descuentos y los pesos se asocian al producto cuyo importe cuadra (sin fiarse del orden:
//      Lidl pone el peso DESPUÉS del producto y Aldi ANTES),
//   4. se comprueba que la suma de las líneas coincide con el total impreso. Si no cuadra, se marcan
//      como dudosas las líneas incoherentes en vez de fiarse de ellas.

class TicketLinea {
  TicketLinea({
    required this.nombre,
    required this.bruto,
    this.cantidad,
    this.unitario,
    this.porPeso = false,
    this.iva,
    this.codigo,
  });

  String nombre;
  double
  bruto; // importe de la línea ANTES de descuentos (precio de balda × cantidad)
  double descuento = 0; // suma de descuentos de la línea (negativa o 0)
  double? cantidad; // unidades, o kg si es por peso
  double? unitario; // precio por unidad o por kg
  bool porPeso;
  String? iva; // letra o código de IVA impreso
  String? codigo; // código interno de la tienda, si lo hay
  bool dudosa = false;
  String? nota;

  double get neto => bruto + descuento; // lo realmente pagado por la línea
}

class Ticket {
  Ticket({
    required this.lineas,
    this.cadena,
    this.fecha,
    this.total,
    this.descuentoGlobal = 0,
  });

  final List<TicketLinea> lineas;
  final String? cadena; // 'lidl', 'aldi', 'mas', 'mercadona'…
  final DateTime? fecha;
  final double? total; // total a pagar impreso
  final double
  descuentoGlobal; // descuento que el ticket aplica al final (p. ej. «DESCUENTO -5,22»)

  double get sumaBruta => lineas.fold(0.0, (t, l) => t + l.bruto);
  double get sumaNeta =>
      lineas.fold(0.0, (t, l) => t + l.neto) + descuentoGlobal;

  /// Diferencia entre el total impreso y lo que suman las líneas (null si no hay total). 0 = todo cuadra.
  double? get diferencia => total == null
      ? null
      : double.parse((total! - sumaNeta).toStringAsFixed(2));

  /// ¿Las líneas suman el total impreso? Es la prueba de que no se ha leído mal nada.
  bool get cuadra => total != null && (sumaNeta - total!).abs() <= 0.02;

  List<TicketLinea> get dudosas => lineas.where((l) => l.dudosa).toList();
}

// ------------------------------------------------------------------ números
double? _num(String s) {
  var t = s.replaceAll(RegExp(r'[€£\s]'), '').replaceAll(',', '.');
  // confusiones típicas del OCR dentro de un número
  t = t.replaceAll(RegExp('[Oo]'), '0').replaceAll(RegExp('[lI|]'), '1');
  return double.tryParse(t);
}

const _precio = r'-?\d+[.,]\d{2}';
const _eur = r'(?:€|£|eur|euros)?';

// «0,953 kg x 6,56 EUR/kg»; el OCR suele cortar el «EUR/kg» final, así que es opcional
final _pesoRe = RegExp(
  r'(\d+[.,]\d{2,3})\s*kg\s*[x×*]\s*(' +
      _precio +
      r')\s*' +
      _eur +
      r'(?:\s*/\s*kg)?\s*$',
  caseSensitive: false,
);
// Tabla de El Corte Inglés / Supercor: «NOMBRE  1,10 €  A  [cant]  1,10 €»
final _filaTablaRe = RegExp(
  r'^(.+?)\s+(\d+[.,]\d{2})\s*€\s+(?:([A-Z])\s+)?(?:(\d+)\s+)?(\d+[.,]\d{2})\s*€$',
);
final _filaTablaSinTotalRe = RegExp(
  r'^(.+?)\s+(\d+[.,]\d{2})\s*€\s+([A-Z])(?:\s+(\d+))?$',
);
// importe seguido de basura del OCR («3,12 îŘšîŚł»): el nombre se perdió
final _precioBasuraRe = RegExp(r'^(-?\d+[.,]\d{2})\s*[^\x00-\x7F]{1,8}$');
// «AGUA 36x 0.28 10.08 B»  (MÁS)
final _cantUnitTotalRe = RegExp(
  r'^(.*?)\s+(\d+)\s*[x×]\s+(\d+[.,]\d{2})\s+(' + _precio + r')\s*(\S{1,3})?$',
  caseSensitive: false,
);
// «CHIPS   1,49x   4   5,96 B»  (Lidl: unitario x cantidad)
final _unitXCantRe = RegExp(
  r'^(.*?)\s+(\d+[.,]\d{2})\s*[x×]\s+(\d+)\s+(' + _precio + r')\s*(\S{1,3})?$',
  caseSensitive: false,
);
// «PIZZA JAMÓN Y QUESO   2,39 B» / «BARRA CAMPESINA   0,62 € 2»
final _colaPrecioRe = RegExp(
  r'^(.*?)\s*(' + _precio + r')\s*' + _eur + r'\s*(\S{1,3})?$',
  caseSensitive: false,
);
final _anclaFinRe = RegExp(
  r'^\s*(total\b|\d+\s*art\.?\s*total|socio club|saldo acumulado|ventajas obtenidas|a pagar|suma\b|iva\b|desglose|entrega|subtotal|base\b)',
  caseSensitive: false,
);
// Líneas con importe que NO son productos (saldos, puntos, club, tarjeta, cambio…).
final _noProductoRe = RegExp(
  r'\b(saldo|acumulado|socio|club|puntos|ventajas|cambio|efectivo|tarjeta|visa|mastercard|importe|imp|entregado|devoluci[oó]n|ahorro|iva|cuota|base imponible|suma)\b',
  caseSensitive: false,
);
final _descuentoRe = RegExp(
  r'^\s*(promo|desc\b|desc\.|descuento|dto|oferta|cup[oó]n|ahorro)',
  caseSensitive: false,
);

String? _detectarCadena(List<String> l) {
  var t = l.take(14).join(' ').toLowerCase();
  // logotipos con letras separadas («A L D I»): se juntan para poder reconocer el nombre
  t = '$t ${t.replaceAll(RegExp(r'(?<=\b\w) (?=\w\b)'), '')}';
  const mapa = {
    'lidl': 'lidl',
    'aldi': 'aldi',
    'mercadona': 'mercadona',
    'carrefour': 'carrefour',
    'alcampo': 'alcampo',
    'eroski': 'eroski',
    'consum': 'consum',
    'supermercados mas': 'mas',
    'supermercados más': 'mas',
    'supercor': 'supercor',
    'hipercor': 'hipercor',
    'el corte ingl': 'elcorteingles',
  };
  for (final e in mapa.entries) {
    if (t.contains(e.key)) return e.value;
  }
  if (RegExp(r'\bdia\b').hasMatch(t)) return 'dia';
  return null;
}

DateTime? _detectarFecha(List<String> l) {
  for (final x in l.take(60)) {
    final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(x);
    if (iso != null) {
      final y = int.parse(iso.group(1)!),
          mo = int.parse(iso.group(2)!),
          d = int.parse(iso.group(3)!);
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return DateTime(y, mo, d);
    }
    final m = RegExp(r'(\d{2})[/.-](\d{2})[/.-](\d{2,4})').firstMatch(x);
    if (m != null) {
      final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return DateTime(y, mo, d);
    }
  }
  return null;
}

String _limpiarNombre(String n) {
  var s = n
      .replaceAll(RegExp(r'\(\d{3,}\)'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  s = s.replaceAll(RegExp(r'[.,\s]+$'), '');
  return s;
}

String? _codigoInterno(String n) =>
    RegExp(r'\((\d{3,})\)').firstMatch(n)?.group(1);

enum _Tipo { producto, peso, descuento }

class _Tok {
  _Tok(this.tipo, {this.linea, this.kg, this.unit, this.importe});
  final _Tipo tipo;
  TicketLinea? linea;
  final double? kg, unit, importe;
}

/// Corrige confusiones típicas del OCR DENTRO de los números (O por 0, l/I por 1) sin tocar el texto.
String _arreglarDigitos(String l) => l
    .replaceAllMapped(
      RegExp(r'(?<=[\d.,])[Oo](?=[\d.,])|(?<=\d)[Oo]\b'),
      (_) => '0',
    )
    .replaceAllMapped(
      RegExp(r'(?<=\d[.,])[lI|](?=\d)|(?<=\d)[lI|](?=[.,]\d)'),
      (_) => '1',
    );

/// Interpreta un ticket a partir de sus líneas de texto.
const _nombreVacio = '(sin nombre)';

TicketLinea _sinNombre(double imp, {String? iva}) =>
    TicketLinea(nombre: _nombreVacio, bruto: imp, iva: iva)
      ..dudosa = true
      ..nota = 'No se leyó el nombre: escríbelo o elimina la línea';

final _soloPrecioRe = RegExp(
  r'^-?\d+[.,]\d{2}\s*(?:€|eur)?$',
  caseSensitive: false,
);
final _terminaEnPrecioRe = RegExp(
  r'\d+[.,]\d{2}\s*(?:€|£|eur)?\s*[A-Z]?$',
  caseSensitive: false,
);
// «6 x ( 2,89 ) 17,34» (Carrefour: cantidad × (unitario) y el total)
final _cantParRe = RegExp(
  r'^(\d+)\s*[x×]\s*\(\s*(\d+[.,]\d{2})\s*\)\s*(-?\d+[.,]\d{2})$',
  caseSensitive: false,
);

/// Algunos tickets (Carrefour en PDF) ponen el importe en la línea SIGUIENTE al nombre, y a veces la página
/// corta entre ambos. Se une cada importe suelto al texto que lo precede para que el resto del lector no lo note.
List<String> _unirPrecios(List<String> ls) {
  final out = <String>[];
  for (final l in ls) {
    if (_soloPrecioRe.hasMatch(l) &&
        out.isNotEmpty &&
        !_terminaEnPrecioRe.hasMatch(out.last) &&
        !_soloPrecioRe.hasMatch(out.last)) {
      out[out.length - 1] = '${out.last} $l';
      continue;
    }
    out.add(l);
  }
  // «NOMBRE» + «6 x ( 2,89 ) 17,34»  →  «NOMBRE 6x 2,89 17,34»
  final res = <String>[];
  for (final l in out) {
    final m = _cantParRe.firstMatch(l);
    if (m != null && res.isNotEmpty && !_terminaEnPrecioRe.hasMatch(res.last)) {
      res[res.length - 1] =
          '${res.last} ${m.group(1)}x ${m.group(2)} ${m.group(3)}';
      continue;
    }
    res.add(l);
  }
  return res;
}

Ticket parsearTicket(List<String> crudas) {
  final lineas = _unirPrecios([
    for (final l in crudas)
      if (l.trim().isNotEmpty)
        _arreglarDigitos(l.replaceAll(RegExp(r'[ \t]+'), ' ').trim()),
  ]);
  final cadena = _detectarCadena(lineas);
  final fecha = _detectarFecha(lineas);

  // totales: «TOTAL A PAGAR» / «A PAGAR» mandan; «TOTAL COMPRA» es el bruto; «DESCUENTO» global
  double? totalPagar, totalCompra, totalSub, descGlobal;
  var fin = lineas.length;
  for (var i = 0; i < lineas.length; i++) {
    final l = lineas[i];
    final m = RegExp(
      '^(.*?)[ .]*($_precio)'
      r'\s*(?:€|£|eur)?\s*$',
      caseSensitive: false,
    ).firstMatch(l);
    final nombre = (m?.group(1) ?? '').toLowerCase();
    final v = m == null ? null : _num(m.group(2)!);
    if (v != null) {
      if (RegExp(
        r'^(\d+\s*art\.?\s*)?(total a pagar|a pagar|total pagado|importe total)',
      ).hasMatch(nombre)) {
        totalPagar ??= v;
      } else if (RegExp(
        r'^subtotal$',
      ).hasMatch(nombre.replaceAll(RegExp(r'[ .:]+$'), ''))) {
        totalSub ??= v;
      } else if (RegExp(
        r'^total( compra)?$',
      ).hasMatch(nombre.replaceAll(RegExp(r'[ .:]+$'), ''))) {
        totalCompra ??= v;
      } else if (RegExp(
            r'^descuento( total)?$',
          ).hasMatch(nombre.replaceAll(RegExp(r'[ .]+$'), '')) &&
          v < 0) {
        descGlobal ??= v;
      }
    }
    if (_anclaFinRe.hasMatch(l) && fin == lineas.length) {
      // «Desc.»/«DESCUENTO» no son el final; «TOTAL…», «A PAGAR», «SUMA», «IVA»… sí
      if (!_descuentoRe.hasMatch(l)) fin = i;
    }
  }
  // totales alternativos cuando el OCR perdió la etiqueta: fila «Suma … PVP» del desglose de IVA o «IMP. 107,06»
  double? totalSuma, totalImp;
  for (final l in lineas) {
    final ms = RegExp(
      r'^suma\b.*?(-?\d+[.,]\d{2})\s*(?:€|eur)?$',
      caseSensitive: false,
    ).firstMatch(l);
    if (ms != null) totalSuma ??= _num(ms.group(1)!);
    final mi = RegExp(
      r'^imp\.?\s*:?\s*(-?\d+[.,]\d{2})',
      caseSensitive: false,
    ).firstMatch(l);
    if (mi != null) totalImp ??= _num(mi.group(1)!);
  }
  final total0 = totalPagar ?? totalCompra ?? totalSub;

  // clasificación del cuerpo
  final toks = <_Tok>[];
  for (var i = 0; i < fin; i++) {
    final l = lineas[i];
    final w = _pesoRe.firstMatch(l);
    if (w != null) {
      toks.add(
        _Tok(_Tipo.peso, kg: _num(w.group(1)!), unit: _num(w.group(2)!)),
      );
      continue;
    }
    final tb = _filaTablaRe.firstMatch(l);
    if (tb != null && !_noProductoRe.hasMatch(tb.group(1)!)) {
      final unit = _num(tb.group(2)!)!, tot = _num(tb.group(5)!)!;
      final cant = tb.group(4) != null
          ? double.parse(tb.group(4)!)
          : (unit > 0
                ? (tot / unit).roundToDouble().clamp(1.0, 999.0).toDouble()
                : 1.0);
      toks.add(
        _Tok(
          _Tipo.producto,
          linea: TicketLinea(
            // la letra del impuesto a veces se cuela al final del nombre («… CHOC B»)
            nombre: _limpiarNombre(
              tb.group(1)!.replaceFirst(RegExp(r'\s+[A-Z]$'), ''),
            ),
            bruto: tot,
            cantidad: cant,
            unitario: unit,
            iva: tb.group(3),
          ),
        ),
      );
      continue;
    }
    final ts = _filaTablaSinTotalRe.firstMatch(l);
    if (ts != null && !_noProductoRe.hasMatch(ts.group(1)!)) {
      final unit = _num(ts.group(2)!)!;
      final cant = ts.group(4) != null ? double.parse(ts.group(4)!) : 1.0;
      toks.add(
        _Tok(
          _Tipo.producto,
          linea: TicketLinea(
            nombre: _limpiarNombre(ts.group(1)!),
            bruto: unit * cant,
            cantidad: cant,
            unitario: unit,
            iva: ts.group(3),
          ),
        ),
      );
      continue;
    }
    final bs = _precioBasuraRe.firstMatch(l);
    if (bs != null) {
      final imp = _num(bs.group(1)!)!;
      if (imp > 0) {
        toks.add(_Tok(_Tipo.producto, linea: _sinNombre(imp)));
        continue;
      }
    }
    var m = _cantUnitTotalRe.firstMatch(l);
    if (m != null) {
      final imp = _num(m.group(4)!)!;
      if (imp > 0) {
        final cant = double.parse(m.group(2)!);
        toks.add(
          _Tok(
            _Tipo.producto,
            linea: TicketLinea(
              nombre: _limpiarNombre(m.group(1)!),
              bruto: imp,
              cantidad: cant,
              unitario: _num(m.group(3)!),
              iva: m.group(5),
              codigo: _codigoInterno(m.group(1)!),
            ),
          ),
        );
        continue;
      }
    }
    m = _unitXCantRe.firstMatch(l);
    if (m != null) {
      final imp = _num(m.group(4)!)!;
      if (imp > 0) {
        toks.add(
          _Tok(
            _Tipo.producto,
            linea: TicketLinea(
              nombre: _limpiarNombre(m.group(1)!),
              bruto: imp,
              cantidad: double.parse(m.group(3)!),
              unitario: _num(m.group(2)!),
              iva: m.group(5),
            ),
          ),
        );
        continue;
      }
    }
    m = _colaPrecioRe.firstMatch(l);
    if (m != null) {
      final imp = _num(m.group(2)!);
      if (imp == null) continue;
      final nombre = m.group(1)!.trim();
      if (imp < 0 || _descuentoRe.hasMatch(nombre)) {
        toks.add(_Tok(_Tipo.descuento, importe: imp < 0 ? imp : -imp));
      } else if (RegExp(r'^[\d\s.,€£/-]*$').hasMatch(nombre) &&
          !_descuentoRe.hasMatch(nombre)) {
        // importe sin nombre legible (el OCR perdió el texto): se conserva como línea dudosa para poder cuadrar
        toks.add(_Tok(_Tipo.producto, linea: _sinNombre(imp, iva: m.group(3))));
      } else if (nombre.length >= 2 &&
          !_noProductoRe.hasMatch(nombre) &&
          !RegExp(r'^[\d\s.,€£/-]+$').hasMatch(nombre)) {
        toks.add(
          _Tok(
            _Tipo.producto,
            linea: TicketLinea(
              nombre: _limpiarNombre(nombre),
              bruto: imp,
              iva: m.group(3),
              codigo: _codigoInterno(nombre),
            ),
          ),
        );
      }
    }
  }

  // Total SIN etiqueta: un importe suelto (sin nombre) que iguala lo acumulado es el total; ahí acaba el cuerpo
  double? totalInferido;
  {
    var acum = 0.0;
    for (var i = 0; i < toks.length; i++) {
      final t0 = toks[i];
      if (t0.tipo == _Tipo.producto) {
        final l0 = t0.linea!;
        final conocidos = [?total0, ?totalSuma, ?totalImp];
        if (l0.nombre == _nombreVacio &&
            acum >= 1 &&
            ((l0.bruto - acum).abs() <= 0.06 ||
                conocidos.any((k) => (k - l0.bruto).abs() <= 0.005))) {
          totalInferido = l0.bruto;
          toks.removeRange(i, toks.length);
          break;
        }
        acum += l0.bruto;
      } else if (t0.tipo == _Tipo.descuento) {
        acum += t0.importe!;
      }
    }
  }

  // asociación de pesos y descuentos al producto cuyo importe cuadra / al anterior
  final prods = <int>[
    for (var i = 0; i < toks.length; i++)
      if (toks[i].tipo == _Tipo.producto) i,
  ];
  double globalDesc = descGlobal ?? 0;
  var ultimo = -1; // índice del último producto visto
  final pesosSinAsignar = <int>[];
  for (var i = 0; i < toks.length; i++) {
    final t = toks[i];
    switch (t.tipo) {
      case _Tipo.producto:
        ultimo = i;
      case _Tipo.descuento:
        if (ultimo >= 0) {
          toks[ultimo].linea!.descuento += t.importe!;
        } else {
          globalDesc +=
              t.importe!; // descuento antes de cualquier producto: va al total
        }
      case _Tipo.peso:
        pesosSinAsignar.add(i);
    }
  }
  for (final i in pesosSinAsignar) {
    final t = toks[i];
    final esperado = t.kg! * t.unit!;
    // candidatos: el producto anterior y el siguiente; gana el que cuadra con kg × €/kg
    final anteriores = prods.where((p) => p < i).toList();
    final siguientes = prods.where((p) => p > i).toList();
    TicketLinea? elegido;
    for (final c in [
      if (anteriores.isNotEmpty) toks[anteriores.last].linea!,
      if (siguientes.isNotEmpty) toks[siguientes.first].linea!,
    ]) {
      if (!c.porPeso && (c.bruto - esperado).abs() <= 0.02) {
        elegido = c;
        break;
      }
    }
    if (elegido != null) {
      elegido
        ..porPeso = true
        ..cantidad = t.kg
        ..unitario = t.unit;
    }
  }

  final out = [for (final p in prods) toks[p].linea!];
  // coherencia interna: cantidad × unitario debe dar el importe
  for (final l in out) {
    if (l.cantidad != null && l.unitario != null) {
      if ((l.cantidad! * l.unitario! - l.bruto).abs() > 0.02) {
        l.dudosa = true;
        l.nota = 'cantidad × precio no coincide con el importe';
      }
    }
  }

  final total = total0 ?? totalInferido ?? totalSuma ?? totalImp;
  final t = Ticket(
    lineas: out,
    cadena: cadena,
    fecha: fecha,
    total:
        total != null && totalPagar == null && total0 != null && globalDesc != 0
        ? total + globalDesc
        : total,
    descuentoGlobal: globalDesc,
  );
  return t;
}
