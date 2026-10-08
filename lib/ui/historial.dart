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
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.replay, size: 16),
                  label: const Text('Repetir', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    if (s.repetirCompra(e.value) == 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Todo eso ya está en tu lista'),
                          behavior: SnackBarBehavior.floating,
                          showCloseIcon: true,
                        ),
                      );
                    }
                  },
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (c.price != null) Text(eur(c.total)),
                        IconButton(
                          tooltip: 'Añadir otra vez a la lista',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_shopping_cart, size: 20),
                          onPressed: () {
                            final it = s.recomprar(c);
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    it == null
                                        ? '«${c.name}» ya está en tu lista'
                                        : 'Añadido: ${c.name}',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                  showCloseIcon: true,
                                  duration: const Duration(seconds: 4),
                                  persist: false,
                                  action: it == null
                                      ? null
                                      : SnackBarAction(
                                          label: 'Deshacer',
                                          onPressed: () => s.remove(it),
                                        ),
                                ),
                              );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
