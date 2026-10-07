import 'package:flutter/material.dart';

import '../main.dart';
import '../models.dart';
import '../sources.dart';
import '../state.dart';

class OffersPage extends StatelessWidget {
  const OffersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final list = s.offerList;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Text(
              'Anota a mano ofertas temporales y te avisamos antes de que caduquen.',
              style: TextStyle(color: cs.outline),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text(
                    'Sin ofertas activas.\nPulsa «Nueva oferta».',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.outline),
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final o in list)
                      Dismissible(
                        key: ValueKey(o.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => s.removeOffer(o),
                        child: ListTile(
                          title: Text(o.name),
                          subtitle: Text(
                            '${prettyChain(o.chain)} · hasta ${shortDate(o.until)} · '
                            '${o.daysLeft == 0
                                ? 'último día'
                                : o.daysLeft == 1
                                ? 'queda 1 día'
                                : 'quedan ${o.daysLeft} días'}',
                            style: TextStyle(
                              color: o.daysLeft <= 1 ? Colors.deepOrange : null,
                            ),
                          ),
                          trailing: Text(
                            eur(o.price),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => showOfferDialog(context, s),
            icon: const Icon(Icons.local_offer),
            label: const Text('Nueva oferta'),
          ),
        ),
      ],
    );
  }
}

Future<void> showOfferDialog(
  BuildContext context,
  AppState s, {
  String? presetName,
  String? presetChain,
}) async {
  final name = TextEditingController(text: presetName ?? '');
  final price = TextEditingController();
  // solo las cadenas de los súper activos; si no hay ninguno, todas
  final act = s.activeStores.isEmpty ? s.stores : s.activeStores;
  final chains = {for (final st in act) st.chain}.toList()..sort();
  String? chain = presetChain != null && chains.contains(presetChain)
      ? presetChain
      : (chains.isEmpty ? null : chains.first);
  DateTime? until;
  // productos de la lista, para reutilizar su clave (código de barras)
  final fromList = {for (final i in s.items) i.name: s.productOf(i).key};
  // cadena del súper asignado a cada producto de la lista
  final chainOfItem = {
    for (final i in s.items) i.name: s.storeById(i.storeId)?.chain,
  };
  String? key = presetName == null ? null : fromList[presetName];

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Nueva oferta'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                onChanged: (v) {
                  key = fromList[v.trim()];
                  final c = chainOfItem[v.trim()];
                  if (c != null && chains.contains(c)) setS(() => chain = c);
                },
                decoration: const InputDecoration(
                  labelText: 'Producto',
                  border: OutlineInputBorder(),
                ),
              ),
              if (fromList.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final n in fromList.keys.take(6))
                      ActionChip(
                        label: Text(n, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          name.text = n;
                          key = fromList[n];
                          final c = chainOfItem[n];
                          if (c != null && chains.contains(c)) {
                            setS(() => chain = c);
                          }
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(chain),
                initialValue: chain,
                decoration: const InputDecoration(
                  labelText: 'Supermercado',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final c in chains)
                    DropdownMenuItem(value: c, child: Text(prettyChain(c))),
                ],
                onChanged: (v) => setS(() => chain = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Precio de oferta',
                  suffixText: '€',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(
                  until == null
                      ? 'Válida hasta…'
                      : 'Hasta el ${shortDate(until!)} ${until!.year}',
                ),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: until ?? now.add(const Duration(days: 7)),
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (d != null) setS(() => until = d);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final p = double.tryParse(price.text.replaceAll(',', '.'));
              final n = name.text.trim();
              if (n.isEmpty ||
                  chain == null ||
                  p == null ||
                  p <= 0 ||
                  until == null) {
                return;
              }
              s.addOffer(
                Offer(
                  key: key ?? n.toLowerCase(),
                  name: n,
                  chain: chain!,
                  price: p,
                  until: until!,
                ),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

/// Aviso en la lista: ofertas que caducan hoy o mañana.
class ExpiringOffersBanner extends StatelessWidget {
  const ExpiringOffersBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final soon = s.expiringOffers;
    if (soon.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.amber.withValues(alpha: .2),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_offer, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'Ofertas a punto de caducar',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            for (final o in soon)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${o.name} · ${eur(o.price)} en ${prettyChain(o.chain)} · '
                  '${o.daysLeft == 0 ? 'hoy es el último día' : 'hasta mañana'}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
