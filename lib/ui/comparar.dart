import 'package:flutter/material.dart';

import '../catalog.dart';
import '../main.dart';
import '../models.dart';
import '../state.dart';
import 'foto.dart';
import 'home.dart' show showNuevoProducto;
import 'scanner.dart';

/// Compara productos por precio/kg, precio/L o precio/unidad. Tamaño y precio son editables:
/// si falta algo se muestra el campo vacío, sin obligar a rellenarlo.
class CompararPage extends StatelessWidget {
  const CompararPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparar productos'),
        actions: [
          if (s.comparacion.isNotEmpty)
            TextButton(
              onPressed: s.limpiarComparacion,
              child: const Text('Vaciar'),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final r = comparar(s.comparacion);
          final cs = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: [
              if (s.comparacion.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text(
                    'Añade productos con el escáner o desde tu lista para ver cuál sale más barato por kilo, litro o unidad.\n\n'
                    'Puedes comparar envases distintos de un mismo producto (200 g frente a 450 g) o marcas equivalentes.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.outline),
                  ),
                ),
              for (final dim in ['kg', 'L', 'ud'])
                if (r.porDimension[dim] != null) ...[
                  _titulo(
                    context,
                    switch (dim) {
                      'kg' => 'Por kilo',
                      'L' => 'Por litro',
                      _ => 'Por unidad',
                    },
                    r.porDimension[dim]!.length < 2
                        ? 'Añade otro para poder comparar'
                        : null,
                  ),
                  for (final l in r.porDimension[dim]!)
                    _FilaComparar(key: ValueKey(l.id), linea: l, resultado: r),
                ],
              if (r.sinDatos.isNotEmpty) ...[
                _titulo(
                  context,
                  'Faltan datos',
                  'Opcional: rellena tamaño y precio si quieres compararlo',
                ),
                for (final l in r.sinDatos)
                  _FilaComparar(key: ValueKey(l.id), linea: l, resultado: r),
              ],
            ],
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'cmp-escanear',
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear otro'),
            onPressed: () => _escanear(context, s),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'cmp-lista',
            icon: const Icon(Icons.checklist),
            label: const Text('De mi lista'),
            onPressed: () => _desdeLista(context, s),
          ),
        ],
      ),
    );
  }

  Widget _titulo(BuildContext context, String t, String? sub) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            letterSpacing: .4,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        if (sub != null)
          Text(sub, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  Future<void> _escanear(BuildContext context, AppState s) async {
    if (!escanerDisponible) return;
    final code = await escanearCodigo(context);
    if (code == null || !context.mounted) return;
    var p = await s.buscarProductoPorCodigo(code);
    if (!context.mounted) return;
    p ??= await showNuevoProducto(
      context,
      codigo: code,
      compartir: s.cfg.shareNewProducts,
    );
    if (p == null) return;
    final st = await s.tiendaActual();
    final q = st == null ? null : await s.precioConocido(p, st);
    s.anadirAComparar(p, precio: q?.price);
  }

  Future<void> _desdeLista(BuildContext context, AppState s) async {
    final it = await showModalBottomSheet<Item>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .7,
          ),
          child: s.items.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Tu lista está vacía'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Elige un producto de tu lista',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (final i in s.items)
                      ListTile(
                        title: Text(i.name),
                        subtitle: i.price == null ? null : Text(eur(i.price!)),
                        onTap: () => Navigator.pop(ctx, i),
                      ),
                  ],
                ),
        ),
      ),
    );
    if (it == null) return;
    s.anadirAComparar(
      s.productOf(it),
      cantidad: extraerTamano(it.name),
      precio: it.price,
    );
  }
}

class _FilaComparar extends StatefulWidget {
  const _FilaComparar({
    super.key,
    required this.linea,
    required this.resultado,
  });
  final LineaComparar linea;
  final ResultadoComparacion resultado;
  @override
  State<_FilaComparar> createState() => _FilaCompararState();
}

class _FilaCompararState extends State<_FilaComparar> {
  late final _tam = TextEditingController(text: widget.linea.cantidad ?? '');
  late final _precio = TextEditingController(
    text: widget.linea.precio == null
        ? ''
        : widget.linea.precio!.toStringAsFixed(2).replaceAll('.', ','),
  );

  @override
  void dispose() {
    _tam.dispose();
    _precio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final l = widget.linea;
    final r = widget.resultado;
    final u = precioUnitario(l.precio, l.cantidad);
    final mejor = r.esMejor(l);
    final extra = r.sobrecoste(l);
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: mejor ? Colors.green : Colors.transparent,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (l.producto.imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ProductThumb(
                      imageUrl: l.producto.imageUrl,
                      size: 40,
                    ),
                  ),
                Expanded(
                  child: Text(
                    l.producto.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: () => s.quitarDeComparar(l),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tam,
                    decoration: const InputDecoration(
                      labelText: 'Tamaño',
                      hintText: '450 g · 1 L · 6 uds',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      l.cantidad = v.trim().isEmpty ? null : v.trim();
                      s.refresh();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _precio,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Precio',
                      suffixText: '€',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      l.precio = double.tryParse(v.replaceAll(',', '.'));
                      s.refresh();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (u != null)
                  Text(
                    '${eur(u.valor)} ${u.etiqueta.substring(1)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  Text(
                    'Sin tamaño o precio',
                    style: TextStyle(color: cs.outline),
                  ),
                const SizedBox(width: 10),
                if (mejor)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Mejor',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  )
                else if (extra != null && extra > 0.5)
                  Text(
                    '+${extra.toStringAsFixed(0)} %',
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void abrirComparar(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => const CompararPage()));
