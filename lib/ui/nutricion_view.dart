import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../nutricion.dart';
import '../state.dart';

const _coloresNutriscore = {
  'a': Color(0xFF038141),
  'b': Color(0xFF85BB2F),
  'c': Color(0xFFFECB02),
  'd': Color(0xFFEE8100),
  'e': Color(0xFFE63E11),
};

const _textoNova = {
  1: 'Sin procesar o mínimamente procesado',
  2: 'Ingredientes culinarios',
  3: 'Alimento procesado',
  4: 'Ultraprocesado',
};

String _num(double? v, {int dec = 1}) {
  if (v == null) return '—';
  final s = v.toStringAsFixed(dec);
  return (s.contains('.') ? s.replaceAll(RegExp(r'\.?0+$'), '') : s).replaceAll(
    '.',
    ',',
  );
}

/// Información nutricional del producto (por 100 g y por envase), con Nutri-Score y NOVA, de Open Food Facts.
class SeccionNutricion extends StatefulWidget {
  const SeccionNutricion({super.key, required this.s, required this.codigo});
  final AppState s;
  final String? codigo;

  @override
  State<SeccionNutricion> createState() => _SeccionNutricionState();
}

class _SeccionNutricionState extends State<SeccionNutricion> {
  late Future<Nutricion?> _f = widget.s.nutricionDe(widget.codigo);

  @override
  void didUpdateWidget(covariant SeccionNutricion old) {
    super.didUpdateWidget(old);
    if (old.codigo != widget.codigo) _f = widget.s.nutricionDe(widget.codigo);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.codigo == null) return const SizedBox.shrink();
    return FutureBuilder<Nutricion?>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final n = snap.data;
        if (n == null) {
          return const SizedBox.shrink(); // sin datos: no se muestra nada
        }
        return _Tabla(n);
      },
    );
  }
}

class _Tabla extends StatelessWidget {
  const _Tabla(this.n);
  final Nutricion n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final u = n.unidad;
    final envase = n.envase == null ? null : n.para(n.envase!);
    final filas = <(String, double? Function(Nutricion), String, int, bool)>[
      ('Energía', (x) => x.kcal, 'kcal', 0, false),
      ('Grasas', (x) => x.grasas, 'g', 1, false),
      ('de las cuales saturadas', (x) => x.saturadas, 'g', 1, true),
      ('Hidratos de carbono', (x) => x.hidratos, 'g', 1, false),
      ('de los cuales azúcares', (x) => x.azucares, 'g', 1, true),
      ('Fibra', (x) => x.fibra, 'g', 1, false),
      ('Proteínas', (x) => x.proteinas, 'g', 1, false),
      ('Sal', (x) => x.sal, 'g', 2, false),
    ].where((f) => f.$2(n) != null).toList();
    TableRow fila(
      String a,
      String b,
      String c, {
      bool cab = false,
      bool sub = false,
    }) {
      final st = TextStyle(
        fontSize: 13,
        fontWeight: cab ? FontWeight.w600 : FontWeight.normal,
        color: sub ? cs.outline : null,
      );
      return TableRow(
        children: [
          Padding(
            padding: EdgeInsets.only(top: 3, bottom: 3, left: sub ? 12 : 0),
            child: Text(a, style: st),
          ),
          Text(b, style: st, textAlign: TextAlign.right),
          if (envase != null) Text(c, style: st, textAlign: TextAlign.right),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Información nutricional',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (n.nutriscore != null)
                Tooltip(
                  message: 'Nutri-Score ${n.nutriscore!.toUpperCase()}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _coloresNutriscore[n.nutriscore],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      n.nutriscore!.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: n.nutriscore == 'c'
                            ? Colors.black
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              if (n.nova != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'NOVA ${n.nova}: ${_textoNova[n.nova] ?? ''}',
                  child: Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      'NOVA ${n.nova}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Table(
            columnWidths: {
              0: const FlexColumnWidth(2.2),
              1: const FlexColumnWidth(1),
              if (envase != null) 2: const FlexColumnWidth(1.2),
            },
            children: [
              fila(
                '',
                'por 100 $u',
                envase == null
                    ? ''
                    : 'por envase (${_num(n.envase, dec: 0)} $u)',
                cab: true,
              ),
              for (final f in filas)
                fila(
                  f.$1,
                  '${_num(f.$2(n), dec: f.$4)} ${f.$3}',
                  envase == null
                      ? ''
                      : '${_num(f.$2(envase), dec: f.$4)} ${f.$3}',
                  sub: f.$5,
                ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => launchUrl(
              Uri.parse('https://world.openfoodfacts.org/'),
              mode: LaunchMode.externalApplication,
            ),
            child: Text(
              'Datos de Open Food Facts (colaborativos, licencia ODbL). Pueden tener errores: consulta siempre la etiqueta del envase.',
              style: TextStyle(fontSize: 11, color: cs.outline),
            ),
          ),
        ],
      ),
    );
  }
}
