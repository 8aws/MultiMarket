import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../main.dart';
import '../models.dart';
import '../sources.dart';
import '../ticket/ticket_lector.dart';
import '../ticket/ticket_match.dart';
import '../ticket/ticket_parser.dart';

void abrirImportarTicket(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => const TicketPage()));

class _Leido {
  _Leido(this.ticket, this.cruces);
  final Ticket ticket;
  final List<Cruce> cruces;
  final Map<int, String> elegidos =
      {}; // línea → id de item (dudosos resueltos)
}

class TicketPage extends StatefulWidget {
  const TicketPage({super.key});

  @override
  State<TicketPage> createState() => _TicketPageState();
}

class _TicketPageState extends State<TicketPage> {
  List<_Leido>? leidos;
  bool trabajando = false;
  String? error;

  Future<void> _procesar(List<List<String>> tickets) async {
    final s = AppScope.of(context);
    final l = <_Leido>[];
    for (final lineas in tickets) {
      final t = parsearTicket(lineas);
      if (t.lineas.isEmpty) continue;
      final c = s.cruzar(t);
      final r = _Leido(t, c);
      // un dudoso con un único candidato claro se deja preseleccionado
      for (var i = 0; i < c.length; i++) {
        if (c[i].estado == EstadoCruce.dudoso && c[i].alternativas.isEmpty) {
          r.elegidos[i] = c[i].itemId!;
        }
      }
      l.add(r);
    }
    setState(() {
      leidos = l;
      error = l.isEmpty ? 'No he encontrado productos en ese ticket' : null;
    });
  }

  Future<void> _leer(String? ruta) async {
    if (ruta == null) return;
    setState(() {
      trabajando = true;
      error = null;
    });
    try {
      await _procesar(await leerTickets(ruta));
    } catch (e) {
      setState(() => error = 'No se pudo leer el ticket ($e)');
    } finally {
      // la imagen no se conserva: se borra la copia temporal en cuanto se ha extraído el texto
      try {
        final f = File(ruta);
        if (await f.exists()) await f.delete();
      } catch (_) {}
      if (mounted) setState(() => trabajando = false);
    }
  }

  Future<void> _camara() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2400,
    );
    await _leer(x?.path);
  }

  Future<void> _archivo() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'heic'],
    );
    await _leer(f?.path);
  }

  Future<void> _pegar() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pegar texto del ticket'),
        content: TextField(
          controller: c,
          maxLines: 12,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leer'),
          ),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await _procesar([c.text.split('\n')]);
    }
  }

  void _aplicar() {
    final s = AppScope.of(context);
    var marcados = 0, lineas = 0;
    for (final r in leidos!) {
      marcados += s.aplicarTicket(r.ticket, r.cruces, elegidos: r.elegidos);
      lineas += r.ticket.lineas.length;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$lineas productos guardados en el historial · $marcados marcados en la lista',
        ),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        duration: const Duration(seconds: 5),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hayOcr = lectorDisponible;
    return Scaffold(
      appBar: AppBar(title: const Text('Importar ticket')),
      bottomNavigationBar: leidos == null || leidos!.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _aplicar,
                  icon: const Icon(Icons.check),
                  label: const Text('Aplicar'),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'La lectura se hace en tu dispositivo y la imagen se borra al terminar. '
            'Los precios se guardan solo en tu base.',
            style: TextStyle(color: cs.outline),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (hayOcr && (Platform.isIOS || Platform.isAndroid))
                OutlinedButton.icon(
                  onPressed: trabajando ? null : _camara,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Hacer foto'),
                ),
              if (hayOcr)
                OutlinedButton.icon(
                  onPressed: trabajando ? null : _archivo,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Imagen o PDF'),
                ),
              OutlinedButton.icon(
                onPressed: trabajando ? null : _pegar,
                icon: const Icon(Icons.paste),
                label: const Text('Pegar texto'),
              ),
            ],
          ),
          if (trabajando)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(error!, style: TextStyle(color: cs.error)),
            ),
          for (final r in leidos ?? const <_Leido>[])
            _TicketCard(r, () => setState(() {})),
        ],
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard(this.r, this.refrescar);
  final _Leido r;
  final VoidCallback refrescar;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final t = r.ticket;
    final dif = t.diferencia;
    final pend = s.items.where((i) => !i.done).toList();
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t.cadena == null ? 'Ticket' : prettyChain(t.cadena!)}'
              '${t.fecha == null ? '' : ' · ${t.fecha!.day}/${t.fecha!.month}/${t.fecha!.year}'}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 4),
            if (t.total == null)
              Text(
                'Sin total impreso: revisa las líneas',
                style: TextStyle(color: cs.tertiary),
              )
            else if (t.cuadra)
              Text(
                '✓ Las líneas suman el total (${eur(t.total!)})',
                style: const TextStyle(color: Colors.green),
              )
            else
              Text(
                '⚠ Las líneas suman ${eur(t.sumaNeta)} y el ticket dice ${eur(t.total!)} '
                '(${dif! > 0 ? 'faltan' : 'sobran'} ${eur(dif.abs())}). Revisa las marcadas.',
                style: TextStyle(color: cs.error),
              ),
            const Divider(),
            for (var i = 0; i < r.cruces.length; i++)
              _Linea(r, i, pend, refrescar),
          ],
        ),
      ),
    );
  }
}

class _Linea extends StatelessWidget {
  const _Linea(this.r, this.i, this.pend, this.refrescar);
  final _Leido r;
  final int i;
  final List<Item> pend;
  final VoidCallback refrescar;

  @override
  Widget build(BuildContext context) {
    final c = r.cruces[i], l = c.linea;
    final cs = Theme.of(context).colorScheme;
    String? nombreItem(String? id) =>
        pend.where((x) => x.id == id).firstOrNull?.name;
    final detalle = l.porPeso
        ? '${l.cantidad} kg'
        : (l.cantidad != null && l.cantidad! > 1
              ? '${l.cantidad!.round()} ud'
              : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (l.dudosa)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.warning_amber, size: 18, color: cs.error),
                ),
              Expanded(
                child: Text(
                  '${l.nombre}${detalle == null ? '' : ' · $detalle'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                eur(l.neto),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (l.nota != null)
            Text(l.nota!, style: TextStyle(fontSize: 12, color: cs.error)),
          if (c.estado == EstadoCruce.seguro)
            Text(
              '✓ ${nombreItem(c.itemId) ?? 'de la lista'}',
              style: const TextStyle(fontSize: 12, color: Colors.green),
            )
          else if (c.estado == EstadoCruce.dudoso)
            DropdownButton<String?>(
              isExpanded: true,
              isDense: true,
              value: r.elegidos[i],
              hint: const Text('¿Es alguno de tu lista?'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Ninguno')),
                for (final it in pend)
                  if (it.id == c.itemId ||
                      c.alternativas.contains(it.id) ||
                      true)
                    DropdownMenuItem(value: it.id, child: Text(it.name)),
              ],
              onChanged: (v) {
                if (v == null) {
                  r.elegidos.remove(i);
                } else {
                  r.elegidos[i] = v;
                }
                refrescar();
              },
            )
          else
            Text(
              'Nuevo: solo al historial',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
        ],
      ),
    );
  }
}
