import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';
import 'miembros.dart';

const _emojis = ['🏠', '💼', '👵', '🏖️', '👨‍👩‍👧', '🎉'];

/// Botón junto al título: lista activa y acceso al selector.
class HogarChip extends StatelessWidget {
  const HogarChip({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final h = s.hogar;
    return ActionChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.only(right: 4),
      avatar: Text(h.emoji, style: const TextStyle(fontSize: 14)),
      labelStyle: const TextStyle(fontSize: 13),
      label: Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      onPressed: () => showHogarSheet(context),
    );
  }
}

String _estado(AppState s, Hogar h) {
  if (h.esPrivada) return 'Solo tú';
  if (!h.remota) return 'Solo en este dispositivo';
  final n = s.sync.miembros[h.id]?.length;
  final quien = n == null
      ? 'Compartida'
      : (n == 1 ? 'Solo tú por ahora' : 'Con $n personas');
  return h.esCreador ? '$quien · eres el creador' : quien;
}

void _aviso(BuildContext c, String m) => ScaffoldMessenger.of(
  c,
).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

Future<void> showHogarSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          AppScope.of(context),
          AppScope.of(context).sync,
        ]),
        builder: (ctx, _) {
          final s = AppScope.of(context);
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * .8,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mis listas',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                    if (s.sync.hayRemotas)
                      s.sync.sincronizando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              s.sync.error == null
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_off_outlined,
                              size: 20,
                              color: s.sync.error == null
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                  ],
                ),
                if (s.sync.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      s.sync.error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final h in s.hogares)
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: h.id == s.currentId
                            ? Theme.of(ctx).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ListTile(
                      leading: Text(
                        h.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                      title: Text(
                        h.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${_estado(s, h)} · ${s.itemsOf(h.id).where((i) => !i.done).length} pendientes',
                      ),
                      trailing: !h.remota
                          ? (h.id == s.currentId
                                ? const Icon(Icons.check)
                                : null)
                          : IconButton(
                              tooltip: 'Miembros y acceso',
                              icon: const Icon(Icons.group_outlined),
                              onPressed: () {
                                Navigator.pop(ctx);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => MiembrosPage(hogarId: h.id),
                                  ),
                                );
                              },
                            ),
                      onTap: () {
                        s.selectHogar(h.id);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                if (s.puedeCrearHogar) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva lista compartida'),
                    onPressed: () => showCrearCompartida(ctx, s),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('Unirme con un código'),
                    onPressed: () => showUnirse(ctx, s),
                  ),
                ] else
                  Text(
                    'Máximo ${Hogar.maxCompartidos} listas compartidas además de la privada.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Recuperar mis listas'),
                  onPressed: () async {
                    await s.recuperarListas().timeout(
                      const Duration(seconds: 20),
                      onTimeout: () {
                        s.diagnosticoRecuperar = 'El servidor no responde';
                        return 0;
                      },
                    );
                    if (!ctx.mounted) return;
                    // un diálogo: un SnackBar quedaría tapado por esta hoja
                    await showDialog<void>(
                      context: ctx,
                      builder: (d) => AlertDialog(
                        content: Text(s.diagnosticoRecuperar),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(d),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

/// Pide el nombre visible si todavía no hay uno.
Widget _aliasField(TextEditingController c) => TextField(
  controller: c,
  textCapitalization: TextCapitalization.words,
  decoration: const InputDecoration(
    labelText: 'Tu nombre para los demás',
    helperText: 'Lo verán los miembros de la lista',
    border: OutlineInputBorder(),
  ),
);

Future<void> showCrearCompartida(BuildContext context, AppState s) async {
  final name = TextEditingController();
  final alias = TextEditingController(text: s.cfg.alias);
  var emoji = _emojis.first;
  var guardando = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Nueva lista compartida'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre (Casa, Trabajo, Abuelos…)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in _emojis)
                    ChoiceChip(
                      label: Text(e, style: const TextStyle(fontSize: 18)),
                      selected: emoji == e,
                      onSelected: (_) => setS(() => emoji = e),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _aliasField(alias),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: guardando ? null : () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: guardando
                ? null
                : () async {
                    setS(() {
                      guardando = true;
                      error = null;
                    });
                    s.cfg.alias = alias.text.trim();
                    final e = await s.crearCompartida(name.text, emoji);
                    if (e == null) {
                      if (ctx.mounted) Navigator.pop(ctx);
                    } else {
                      setS(() {
                        guardando = false;
                        error = e;
                      });
                    }
                  },
            child: guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Crear'),
          ),
        ],
      ),
    ),
  );
  if (context.mounted && s.hogar.remota) {
    Navigator.of(context).maybePop(); // cierra la hoja
  }
}

Future<void> showUnirse(BuildContext context, AppState s) async {
  final code = TextEditingController();
  final alias = TextEditingController(text: s.cfg.alias);
  var guardando = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Unirme a una lista'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: code,
                autofocus: true,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                decoration: const InputDecoration(
                  labelText: 'Código de invitación',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _aliasField(alias),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: guardando ? null : () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: guardando
                ? null
                : () async {
                    setS(() {
                      guardando = true;
                      error = null;
                    });
                    s.cfg.alias = alias.text.trim();
                    final e = await s.unirseConCodigo(code.text);
                    if (e == null) {
                      if (ctx.mounted) Navigator.pop(ctx);
                    } else {
                      setS(() {
                        guardando = false;
                        error = e;
                      });
                    }
                  },
            child: guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Unirme'),
          ),
        ],
      ),
    ),
  );
  if (context.mounted && s.hogar.remota) Navigator.of(context).maybePop();
}

/// Editar nombre/emoji de una lista local (las compartidas se renombran en el servidor más adelante).
Future<void> showHogarDialog(
  BuildContext context,
  AppState s, {
  Hogar? h,
}) async {
  final name = TextEditingController(text: h?.name ?? '');
  var emoji = h?.emoji ?? _emojis.first;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(h == null ? 'Nueva lista' : 'Editar lista'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final e in _emojis)
                  ChoiceChip(
                    label: Text(e, style: const TextStyle(fontSize: 18)),
                    selected: emoji == e,
                    onSelected: (_) => setS(() => emoji = e),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              h == null
                  ? s.crearHogar(name.text, emoji: emoji)
                  : s.renombrarHogar(h, name.text, emoji);
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

Future<void> confirmarBorrarHogar(
  BuildContext context,
  AppState s,
  Hogar h,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('¿Borrar «${h.name}»?'),
      content: const Text(
        'Se elimina la lista y sus productos de este dispositivo.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  if (ok == true) s.borrarHogar(h);
}

void copiarCodigo(BuildContext context, String code) {
  Clipboard.setData(ClipboardData(text: code));
  _aviso(context, 'Código copiado');
}
