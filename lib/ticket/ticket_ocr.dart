// Reconstruye las FILAS de un ticket a partir de los fragmentos que devuelve el OCR.
// El OCR suele separar «LECHE ENTERA» y «1,05» en dos líneas aunque estén en la misma fila del papel;
// el parser necesita el precio en la misma línea que el nombre, así que se agrupa por posición vertical.

class FragmentoOcr {
  const FragmentoOcr(
    this.texto,
    this.izq,
    this.arriba,
    this.derecha,
    this.abajo,
  );
  final String texto;
  final double izq, arriba, derecha, abajo;
  double get centroY => (arriba + abajo) / 2;
  double get alto => abajo - arriba;
}

List<String> agruparPorFilas(List<FragmentoOcr> fr) {
  if (fr.isEmpty) return const [];
  final ord = [...fr]..sort((a, b) => a.centroY.compareTo(b.centroY));
  final filas = <List<FragmentoOcr>>[];
  for (final f in ord) {
    // pertenece a la fila si su centro cae dentro de la franja vertical de la fila (con margen)
    final fila = filas.isEmpty ? null : filas.last;
    if (fila != null) {
      final cy = fila.fold(0.0, (t, x) => t + x.centroY) / fila.length;
      final alto = fila.fold(0.0, (t, x) => t + x.alto) / fila.length;
      // dos textos que ocupan el mismo tramo horizontal no son la misma fila (foto torcida: dos nombres seguidos)
      final solapa = fila.any((g) => f.izq < g.derecha && g.izq < f.derecha);
      if ((f.centroY - cy).abs() <= alto * .5 && !solapa) {
        fila.add(f);
        continue;
      }
    }
    filas.add([f]);
  }
  return [
    for (final fila in filas)
      (fila..sort((a, b) => a.izq.compareTo(b.izq)))
          .map((f) => f.texto.trim())
          .where((t) => t.isNotEmpty)
          .join(' '),
  ].where((l) => l.isNotEmpty).toList();
}

/// Separa varios tickets puestos lado a lado en la misma hoja: busca una banda vertical vacía que cruce
/// toda la altura. Para no partir un ticket por error exige un hueco ancho y que cada lado tenga contenido.
List<List<FragmentoOcr>> separarColumnas(List<FragmentoOcr> fr) {
  if (fr.length < 8) return [fr];
  final ord = [...fr]..sort((a, b) => a.izq.compareTo(b.izq));
  final ancho =
      fr.map((f) => f.derecha).reduce((a, b) => a > b ? a : b) -
      fr.map((f) => f.izq).reduce((a, b) => a < b ? a : b);
  final grupos = <List<FragmentoOcr>>[
    [ord.first],
  ];
  var fin = ord.first.derecha;
  for (final f in ord.skip(1)) {
    if (f.izq - fin >= ancho * .08) {
      grupos.add([f]);
    } else {
      grupos.last.add(f);
    }
    if (f.derecha > fin) fin = f.derecha;
  }
  final minimo = fr.length * .25;
  final validos = grupos.where((g) => g.length >= minimo).toList();
  if (validos.length < 2) return [fr];
  // Un ticket de verdad tiene texto Y precios; una «columna de nombres» y una «columna de precios» del mismo ticket
  // no son dos tickets. Además ambos deben ocupar casi toda la altura.
  bool pareceTicket(List<FragmentoOcr> g) {
    final precios = g
        .where((f) => RegExp(r'\d+[.,]\d{2}').hasMatch(f.texto))
        .length;
    final textos = g
        .where((f) => RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ]{3,}').hasMatch(f.texto))
        .length;
    return precios >= 3 && textos >= 3;
  }

  final alturaTotal =
      fr.map((f) => f.abajo).reduce((a, b) => a > b ? a : b) -
      fr.map((f) => f.arriba).reduce((a, b) => a < b ? a : b);
  double altura(List<FragmentoOcr> g) =>
      g.map((f) => f.abajo).reduce((a, b) => a > b ? a : b) -
      g.map((f) => f.arriba).reduce((a, b) => a < b ? a : b);
  if (!validos.every((g) => pareceTicket(g) && altura(g) >= alturaTotal * .6)) {
    return [fr];
  }
  // los fragmentos sueltos de grupos pequeños se reparten al grupo válido más cercano
  for (final g in grupos.where((g) => g.length < minimo)) {
    for (final f in g) {
      validos.reduce((a, b) => _dist(a, f) <= _dist(b, f) ? a : b).add(f);
    }
  }
  return validos;
}

double _dist(List<FragmentoOcr> g, FragmentoOcr f) {
  final i = g.map((x) => x.izq).reduce((a, b) => a < b ? a : b);
  final d = g.map((x) => x.derecha).reduce((a, b) => a > b ? a : b);
  return f.izq < i ? i - f.izq : (f.izq > d ? f.izq - d : 0);
}
