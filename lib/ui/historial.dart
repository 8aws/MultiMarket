import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';

/// Historial de compras de la lista activa (la privada, o la compartida con sus miembros).
class HistorialPage extends StatelessWidget {
  const HistorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final lista = [...s.compras]..sort((a, b) => b.ms.compareTo(a.ms));
    if (lista.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Aquí aparecerá lo que vayas comprando en «${s.hogar.name}».\n\nSe guarda al marcar un producto como comprado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.outline),
          ),
        ),
      );
    }
    // agrupado por día
    final dias = <DateTime, List<Compra>>{};
    for (final c in lista) {
      final f = c.fecha;
      dias.putIfAbsent(DateTime(f.year, f.month, f.day), () => []).add(c);
    }
    final entradas = dias.entries.toList();
    final total = lista.fold(0.0, (t, c) => t + c.total);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text('${lista.length} compras en «${s.hogar.name}»'),
            trailing: Text(
              eur(total),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        for (final e in entradas) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${e.key.day} ${shortDate(e.key).split(' ').last} ${e.key.year}',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.outline,
                      letterSpacing: .4,
                    ),
                  ),
                ),
                Text(
                  eur(e.value.fold(0.0, (t, c) => t + c.total)),
                  style: TextStyle(fontSize: 12, color: cs.outline),
                ),
              ],
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final c in e.value)
                  ListTile(
                    dense: true,
                    title: Text(c.qty > 1 ? '${c.name}  ×${c.qty}' : c.name),
                    subtitle: Text(
                      [
                        if (c.storeName != null) c.storeName!,
                        if (s.hogar.remota &&
                            c.by != null &&
                            s.sync.aliasDe[c.by] != null)
                          s.sync.aliasDe[c.by] == null
                              ? ''
                              : (c.by == s.sync.miId
                                    ? 'tú'
                                    : s.sync.aliasDe[c.by]!),
                      ].where((x) => x.isNotEmpty).join(' · '),
                    ),
                    trailing: c.price == null ? null : Text(eur(c.total)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
