import 'package:flutter/material.dart';

import '../main.dart';
import '../sync/pb_api.dart';
import 'hogares.dart';

/// Miembros y acceso de una lista compartida.
class MiembrosPage extends StatefulWidget {
  const MiembrosPage({super.key, required this.hogarId});
  final String hogarId;
  @override
  State<MiembrosPage> createState() => _MiembrosPageState();
}

class _MiembrosPageState extends State<MiembrosPage> {
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => _cargando = true);
      await AppScope.of(context).sync.sincronizar();
      if (mounted) setState(() => _cargando = false);
    });
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
  );

  Future<bool> _confirmar(
    String titulo,
    String texto,
    String boton, {
    bool peligro = false,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: peligro
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(boton),
          ),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([s, s.sync]),
      builder: (context, _) {
        final h = s.hogares.where((x) => x.id == widget.hogarId).firstOrNull;
        if (h == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const Scaffold(body: SizedBox.shrink());
        }
        final ms = s.sync.miembros[h.id] ?? const <Miembro>[];
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(title: Text('${h.emoji}  ${h.name}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_cargando || s.sync.sincronizando)
                const LinearProgressIndicator(minHeight: 2),
              if (s.sync.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    s.sync.error!,
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),

              // ---------------------------------------------------- invitación
              if (h.esCreador) ...[
                Text(
                  'INVITAR',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.outline,
                    letterSpacing: .4,
                  ),
                ),
                const SizedBox(height: 6),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Código de invitación'),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                h.inviteCode ?? '—',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  fontFamily: 'Menlo',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copiar',
                              icon: const Icon(Icons.copy),
                              onPressed: h.inviteCode == null
                                  ? null
                                  : () => copiarCodigo(context, h.inviteCode!),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Compártelo con quien quieras añadir. Se pega en «Unirme con un código».',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Generar código nuevo'),
                          onPressed: () async {
                            if (!await _confirmar(
                              '¿Generar código nuevo?',
                              'El código anterior dejará de valer. Quien ya está dentro sigue dentro.',
                              'Generar',
                            )) {
                              return;
                            }
                            final e = await s.regenerarInvitacion(h);
                            _msg(e ?? 'Código nuevo generado');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ------------------------------------------------------ miembros
              Text(
                'MIEMBROS (${ms.length})',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.outline,
                  letterSpacing: .4,
                ),
              ),
              const SizedBox(height: 6),
              Card(
                child: Column(
                  children: [
                    if (ms.isEmpty)
                      const ListTile(
                        title: Text(
                          'Sin datos todavía. Comprueba la conexión.',
                        ),
                      ),
                    for (final m in ms)
                      ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            m.alias.isEmpty
                                ? '?'
                                : m.alias.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(
                          m.userId == s.sync.miId ? '${m.alias} (tú)' : m.alias,
                        ),
                        subtitle: Text(m.esCreador ? 'Creador' : 'Miembro'),
                        trailing: h.esCreador && m.userId != s.sync.miId
                            ? PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'revocar') {
                                    if (!await _confirmar(
                                      '¿Quitar a ${m.alias}?',
                                      'Perderá el acceso a la lista y se borrará su copia al sincronizar.',
                                      'Quitar',
                                      peligro: true,
                                    )) {
                                      return;
                                    }
                                    _msg(
                                      await s.revocar(h, m) ??
                                          '${m.alias} ya no tiene acceso',
                                    );
                                  } else {
                                    if (!await _confirmar(
                                      '¿Hacer creador a ${m.alias}?',
                                      'Pasará a poder invitar, quitar miembros y borrar la lista. Tú serás un miembro más.',
                                      'Transferir',
                                    )) {
                                      return;
                                    }
                                    _msg(
                                      await s.transferirA(h, m) ??
                                          'Ahora el creador es ${m.alias}',
                                    );
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'transferir',
                                    child: Text('Hacer creador'),
                                  ),
                                  PopupMenuItem(
                                    value: 'revocar',
                                    child: Text('Quitar acceso'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // -------------------------------------------------------- salir
              OutlinedButton.icon(
                icon: const Icon(Icons.link_off),
                label: const Text('Desvincular de este dispositivo'),
                onPressed: () async {
                  final otros = ms.length > 1;
                  if (h.esCreador && otros) {
                    _msg(
                      'Eres el creador: transfiere la propiedad a otro miembro antes de salir.',
                    );
                    return;
                  }
                  final aviso = h.esCreador
                      ? 'Eres el único miembro: al salir la lista se borrará del servidor.'
                      : 'La lista seguirá existiendo para los demás. Podrás volver con un código.';
                  if (!await _confirmar(
                    '¿Desvincular «${h.name}»?',
                    aviso,
                    'Desvincular',
                  )) {
                    return;
                  }
                  final e = await s.desvincular(h);
                  if (e != null) {
                    _msg(e);
                  } else if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              if (h.esCreador) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  icon: const Icon(Icons.delete_forever),
                  label: const Text('Borrar la lista para todos'),
                  onPressed: () async {
                    if (!await _confirmar(
                      '¿Borrar «${h.name}» para todos?',
                      'Desaparece para todos los miembros y no se puede deshacer.',
                      'Borrar para todos',
                      peligro: true,
                    )) {
                      return;
                    }
                    final e = await s.borrarParaTodos(h);
                    if (e != null) {
                      _msg(e);
                    } else if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
