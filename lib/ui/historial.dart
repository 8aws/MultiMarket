import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// Compras de un mismo día y tienda: lo que en papel sería un ticket.
class _Ticket {
  _Ticket(this.dia, this.storeKey, this.storeName);
  final DateTime dia;
  final String storeKey;
  final String? storeName;
  final compras = <Compra>[];
  double get total => compras.fold(0.0, (t, c) => t + c.total);
}

/// Historial de compras de la lista activa (la privada, o la compartida con sus miembros).
/// Se agrupa por año > mes > ticket, todo plegado salvo el mes más reciente con compras
/// (el en curso, o el último que tenga si este aún no tiene).
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
    // ticket = día + tienda; mes = (año, mes)
    final tickets = <String, _Ticket>{};
    for (final c in lista) {
      final f = c.fecha;
      final dia = DateTime(f.year, f.month, f.day);
      final tk =
          '${dia.millisecondsSinceEpoch}|${c.storeId ?? c.storeName ?? ''}';
      tickets
          .putIfAbsent(
            tk,
            () => _Ticket(dia, c.storeId ?? c.storeName ?? '', c.storeName),
          )
          .compras
          .add(c);
    }
    final porMes = <(int, int), List<_Ticket>>{};
    for (final tk in tickets.values) {
      porMes.putIfAbsent((tk.dia.year, tk.dia.month), () => []).add(tk);
    }
    final meses = porMes.keys.toList()
      ..sort(
        (a, b) => a.$1 != b.$1 ? b.$1.compareTo(a.$1) : b.$2.compareTo(a.$2),
      );
    final ahora = DateTime.now();
    final abierto = porMes.containsKey((ahora.year, ahora.month))
        ? (ahora.year, ahora.month)
        : meses.first; // el más reciente con compras
    final anios = <int>{for (final m in meses) m.$1}.toList()
      ..sort((a, b) => b.compareTo(a));
    final total = lista.fold(0.0, (t, c) => t + c.total);

    Widget mes((int, int) m) {
      final tks = porMes[m]!..sort((a, b) => b.dia.compareTo(a.dia));
      final suma = tks.fold(0.0, (t, k) => t + k.total);
      return ExpansionTile(
        key: PageStorageKey('mes${m.$1}-${m.$2}'),
        initiallyExpanded: m == abierto,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(
          '${_meses[m.$2 - 1][0].toUpperCase()}${_meses[m.$2 - 1].substring(1)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${tks.length} ${tks.length == 1 ? 'compra' : 'compras'}',
          style: TextStyle(fontSize: 12, color: cs.outline),
        ),
        trailing: Text(eur(suma), style: const TextStyle(fontSize: 13)),
        children: [for (final tk in tks) _TicketTile(s: s, tk: tk)],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(
              'Compras en «${s.hogar.name}»',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${lista.length} productos'),
            trailing: Text(
              eur(total),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        for (final y in anios)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: PageStorageKey('anio$y'),
              initiallyExpanded: y == abierto.$1,
              title: Text(
                '$y',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: Text(
                eur(
                  [for (final m in meses.where((m) => m.$1 == y)) ...porMes[m]!]
                      .fold(0.0, (t, k) => t + k.total),
                ),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              children: [for (final m in meses.where((m) => m.$1 == y)) mes(m)],
            ),
          ),
      ],
    );
  }
}

/// Un ticket plegado (tienda · día · total); al abrirlo muestra sus líneas.
class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.s, required this.tk});
  final AppState s;
  final _Ticket tk;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExpansionTile(
      key: PageStorageKey('tk${tk.dia.millisecondsSinceEpoch}${tk.storeKey}'),
      tilePadding: const EdgeInsets.only(left: 24, right: 12),
      title: Text(
        tk.storeName ?? 'Sin tienda',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${shortDate(tk.dia)} · ${tk.compras.length} ${tk.compras.length == 1 ? 'producto' : 'productos'}',
        style: TextStyle(fontSize: 12, color: cs.outline),
      ),
      trailing: Text(
        eur(tk.total),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: const Icon(Icons.replay, size: 16),
            label: const Text('Repetir', style: TextStyle(fontSize: 12)),
            onPressed: () {
              if (s.repetirCompra(tk.compras) == 0) {
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
        ),
        for (final c in tk.compras)
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
                      : (c.by == s.sync.miId ? 'tú' : s.sync.aliasDe[c.by]!),
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
    );
  }
}
