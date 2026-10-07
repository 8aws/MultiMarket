import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import '../models.dart';
import 'foto.dart';
import '../sources.dart';
import '../sync/pb_api.dart';
import '../state.dart';

const _urgColors = [Color(0xFFFF3B30), Color(0xFFFF9500), Color(0xFF8E8E93)];

/// Ficha de un producto de la lista: prioridad, refrigerado, precio y oferta, tienda.
Future<void> showFicha(
  BuildContext context,
  AppState s,
  Item it, {
  required VoidCallback onCambiarTienda,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: _Ficha(s: s, it: it, onCambiarTienda: onCambiarTienda),
      ),
    ),
  );
}

class _Ficha extends StatefulWidget {
  const _Ficha({
    required this.s,
    required this.it,
    required this.onCambiarTienda,
  });
  final AppState s;
  final Item it;
  final VoidCallback onCambiarTienda;
  @override
  State<_Ficha> createState() => _FichaState();
}

class _FichaState extends State<_Ficha> {
  late final TextEditingController _precio;
  bool _oferta = false;
  DateTime? _hasta;

  AppState get s => widget.s;
  Item get it => widget.it;

  @override
  void initState() {
    super.initState();
    _precio = TextEditingController(
      text: it.price == null
          ? ''
          : it.price!.toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _precio.dispose();
    super.dispose();
  }

  void _guardarPrecio() {
    final v = double.tryParse(_precio.text.replaceAll(',', '.'));
    s.setPrice(it, v, oferta: _oferta, hasta: _hasta);
  }

  @override
  Widget build(BuildContext context) {
    final st = s.storeById(it.storeId);
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (it.localImage != null || it.imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ProductThumb(
                      localImage: it.localImage,
                      imageUrl: it.imageUrl,
                      size: 64,
                    ),
                  ),
                Expanded(
                  child: Text(
                    it.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Nombre y tamaño'),
                  onPressed: () async {
                    final c = TextEditingController(text: it.name);
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Nombre y tamaño'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: c,
                              autofocus: true,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: 'Leche entera 1 L',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (it.barcode != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Código de barras ${it.barcode} (identificador, no cambia)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Guardar'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) s.setNombre(it, c.text);
                  },
                ),
              ],
            ),
            if (fotosPropiasDisponibles)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(
                      it.localImage != null || it.imageUrl != null
                          ? 'Cambiar foto'
                          : 'Añadir foto',
                    ),
                    onPressed: () =>
                        aniadirFoto(context, s, it, source: ImageSource.camera),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Galería'),
                    onPressed: () => aniadirFoto(
                      context,
                      s,
                      it,
                      source: ImageSource.gallery,
                    ),
                  ),
                  if (it.localImage != null)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Quitar mi foto'),
                      onPressed: () => s.setFotoLocal(it, null),
                    ),
                  if (it.localImage == null &&
                      s.sync.api.fotoIdDeUrl(it.imageUrl) != null)
                    TextButton.icon(
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Reportar foto'),
                      onPressed: () => reportarFotoDialog(context, s, it),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Text(
              'Prioridad',
              style: TextStyle(color: cs.outline, fontSize: 12),
            ),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                for (var i = 1; i <= 3; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(urgencyNames[i - 1]),
                    icon: Icon(
                      Icons.circle,
                      size: 10,
                      color: _urgColors[i - 1],
                    ),
                  ),
              ],
              selected: {it.urg},
              onSelectionChanged: (v) => s.setUrgency(it, v.first),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Refrigerado ❄️'),
              subtitle: const Text(
                'Se recuerda para este producto. Si hay una versión distinta (por ejemplo leche UHT y leche fresca), '
                'ponle nombre distinto para tratarlas por separado.',
              ),
              value: it.cold,
              onChanged: (v) => s.setCold(it, v),
            ),
            Row(
              children: [
                const Expanded(child: Text('Cantidad (unidades)')),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: it.cantidad > 1
                      ? () => s.setCantidad(it, it.cantidad - 1)
                      : null,
                ),
                Text(
                  '${it.cantidad}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => s.setCantidad(it, it.cantidad + 1),
                ),
              ],
            ),
            const Divider(),
            Text('Precio', style: TextStyle(color: cs.outline, fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _precio,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      suffixText: '€',
                      hintText: 'Sin precio',
                      helperText: st == null
                          ? 'Asigna un súper para recordar el precio'
                          : 'en ${st.name}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _guardarPrecio,
                  child: const Text('Guardar'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Es una oferta'),
              subtitle: Text(
                _oferta
                    ? 'No cambia el precio habitual de este producto'
                    : 'Se recordará como precio habitual (corrige uno erróneo)',
              ),
              value: _oferta,
              onChanged: (v) => setState(() => _oferta = v),
            ),
            if (_oferta)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(
                    _hasta == null
                        ? 'Válida hasta… (opcional, te avisa antes de caducar)'
                        : 'Hasta el ${shortDate(_hasta!)}',
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _hasta ?? now.add(const Duration(days: 7)),
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _hasta = d);
                  },
                ),
              ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.store_outlined),
              title: Text(st == null ? 'Elegir supermercado' : st.name),
              subtitle: st == null ? null : Text(prettyChain(st.chain)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                widget.onCambiarTienda();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Reporta la foto comunitaria del producto: asignada al producto equivocado, no es un producto, etc.
Future<void> reportarFotoDialog(
  BuildContext context,
  AppState s,
  Item it,
) async {
  final fotoId = s.sync.api.fotoIdDeUrl(it.imageUrl);
  if (fotoId == null) return;
  const motivos = {
    'producto-equivocado': 'No es este producto',
    'no-es-un-producto': 'No es una foto de producto',
    'datos-personales': 'Muestra datos o personas',
    'mala-calidad': 'Mala calidad',
    'otro': 'Otro motivo',
  };
  var motivo = 'producto-equivocado';
  final nota = TextEditingController();
  final enviar = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Reportar foto'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                it.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: motivo,
                onChanged: (v) => setS(() => motivo = v ?? motivo),
                child: Column(
                  children: [
                    for (final e in motivos.entries)
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value),
                        value: e.key,
                      ),
                  ],
                ),
              ),
              TextField(
                controller: nota,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    ),
  );
  if (enviar != true) return;
  String mensaje;
  try {
    await s.sync.api.reportarFoto(fotoId, motivo, nota.text.trim());
    mensaje = 'Gracias: la foto se revisará';
  } on PbException catch (e) {
    mensaje = e.status == 400
        ? 'Ya reportaste esta foto'
        : 'No se pudo enviar: ${e.message}';
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(mensaje)));
  }
}
