import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models.dart';
import '../sources.dart';
import '../state.dart';
import 'ficha.dart';
import 'ticket_page.dart';
import '../catalog.dart';
import 'foto.dart';
import 'scanner.dart';
import 'comparar.dart';
import '../recompra.dart';
import 'historial.dart';
import 'modo_compra.dart';
import 'hogares.dart';
import 'offers_page.dart';
import 'settings_page.dart';

const _urgColors = [Color(0xFFFF3B30), Color(0xFFFF9500), Color(0xFF8E8E93)];

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<String>? _sub;
  StreamSubscription<Aviso>? _subAvisos;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final s = AppScope.of(context);
    _subAvisos = s.avisos.listen((a) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              a.texto,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            duration: const Duration(seconds: 5),
            persist: false, // con acción, Flutter lo deja fijo si no se indica
            showCloseIcon: true,
            behavior: SnackBarBehavior.floating,
            action: a.deshacer == null
                ? null
                : SnackBarAction(label: 'Deshacer', onPressed: a.deshacer!),
          ),
        );
    });
    _sub = s.alerts.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('❄️ $msg'),
            duration: const Duration(seconds: 12),
            showCloseIcon: true,
            behavior: SnackBarBehavior.floating,
          ),
        );
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _subAvisos?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    const titulos = ['MultiMarket', 'Ofertas', 'Ajustes', 'Historial'];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (s.tab == 0 &&
              s.hogares.any((h) => h.id == s.currentId && h.remota))
            IconButton(
              tooltip: 'Voy yo a comprar (avisa a la lista)',
              icon: const Icon(Icons.directions_walk),
              onPressed: () async {
                final e = await s.voyYo();
                if (e != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e),
                      behavior: SnackBarBehavior.floating,
                      showCloseIcon: true,
                    ),
                  );
                }
              },
            ),
          if (s.tab == 0)
            IconButton(
              tooltip: 'Modo compra: escanear en la tienda',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => abrirModoCompra(context),
            ),
        ],
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: s.tab == 0
            ? Row(
                children: [
                  Text(
                    titulos[0],
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Flexible(child: HogarChip()),
                  const SizedBox(width: 8),
                ],
              )
            : Text(
                titulos[s.tab.clamp(0, 3)],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        top: false,
        child: switch (s.tab) {
          0 => const ListPage(),
          1 => const OffersPage(),
          3 => const HistorialPage(),
          _ => const SettingsPage(),
        },
      ),
      floatingActionButton: s.tab == 0
          ? FloatingActionButton(
              tooltip: 'Añadir producto',
              onPressed: () => showAddSheet(context),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

// ============================================================== MENÚ LATERAL
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    void ir(int tab) {
      s.tab = tab;
      s.refresh();
      Navigator.pop(context);
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Text(
                'MultiMarket',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ViewMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ViewMode.compra,
                    label: Text('Por compra'),
                  ),
                  ButtonSegment(
                    value: ViewMode.tiendas,
                    label: Text('Por tienda'),
                  ),
                ],
                selected: {s.view},
                onSelectionChanged: (v) {
                  s.view = v.first;
                  s.tab = 0;
                  s.refresh();
                  Navigator.pop(context);
                },
              ),
            ),
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.shopping_cart_outlined),
              title: const Text('Lista'),
              selected: s.tab == 0,
              onTap: () => ir(0),
            ),
            ListTile(
              leading: const Icon(Icons.local_offer_outlined),
              title: const Text('Ofertas'),
              selected: s.tab == 1,
              onTap: () => ir(1),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Modo compra (escáner)'),
              onTap: () {
                Navigator.pop(context);
                abrirModoCompra(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.compare_arrows),
              title: const Text('Comparar productos'),
              onTap: () {
                Navigator.pop(context);
                abrirComparar(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.card_membership),
              title: const Text('Tarjetas de fidelidad (Loywallet)'),
              subtitle: const Text('Abre la app o te lleva a descargarla'),
              onTap: () {
                Navigator.pop(context);
                // Sin esquema propio en Loywallet, la ficha de la App Store muestra «Abrir» si está instalada
                launchUrl(
                  Uri.parse(
                    'https://apps.apple.com/es/app/loywallet/id6761814853',
                  ),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Importar ticket'),
              onTap: () {
                Navigator.pop(context);
                abrirImportarTicket(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Historial de compras'),
              selected: s.tab == 3,
              onTap: () => ir(3),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Ajustes'),
              selected: s.tab == 2,
              onTap: () => ir(2),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================ LISTA
class ListPage extends StatelessWidget {
  const ListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final items = s.visible;
    final cs = Theme.of(context).colorScheme;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 88), // hueco para el «+»
      children: [
        const SyncBanner(),
        if (s.copiaParaRestaurar != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hay una copia de tu lista privada del ${s.copiaParaRestaurar!.day}/${s.copiaParaRestaurar!.month}/${s.copiaParaRestaurar!.year}. ¿Quieres recuperarla?',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () async {
                          final e = await s.restaurarCopia();
                          if (e != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(e),
                                showCloseIcon: true,
                                persist: false,
                              ),
                            );
                          }
                        },
                        child: const Text('Recuperar'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          s.copiaParaRestaurar = null;
                          s.changed();
                        },
                        child: const Text('Ahora no'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (!s.puedeCompartir)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.block, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.textoSancion!,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (s.cfg.showColdCard) const ColdBanner(),
        const ExpiringOffersBanner(),
        if (s.cfg.showCartCard) const CartCard(),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final e in const {
                ColdFilter.todo: 'Todo',
                ColdFilter.frio: '❄️ Solo fríos',
                ColdFilter.seco: '🧺 Sin refrigerar',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: s.filter == e.key,
                    onSelected: (_) {
                      s.filter = e.key;
                      s.refresh();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'Nada por aquí.\nPulsa + para añadir productos',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.outline),
              ),
            ),
          )
        else if (s.view == ViewMode.compra)
          Card(
            margin: const EdgeInsets.only(top: 6),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [for (final i in items) ItemRow(i)]),
          )
        else
          ..._byStore(context, s, items),
        ..._fantasmas(context, s),
        if (s.items.any((i) => i.done))
          Center(
            child: TextButton(
              onPressed: s.clearDone,
              child: Text(
                'Quitar ${s.items.where((i) => i.done).length} comprados',
              ),
            ),
          ),
      ],
    );
  }

  /// Sugerencias de recompra: anotaciones «fantasma» al 50 %. Tocar la fila las añade a la lista;
  /// tocar el círculo las descarta sin contar como compra.
  List<Widget> _fantasmas(BuildContext context, AppState s) {
    final todas = s.sugerencias.where((g) {
      final frio = s.frioManual[g.key] ?? looksCold(g.name);
      return switch (s.filter) {
        ColdFilter.todo => true,
        ColdFilter.frio => frio,
        ColdFilter.seco => !frio,
      };
    }).toList();
    if (todas.isEmpty) return const [];
    final cs = Theme.of(context).colorScheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(
          'POR SI TE QUEDAS SIN ELLO',
          style: TextStyle(fontSize: 12, letterSpacing: .4, color: cs.outline),
        ),
      ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [for (final g in todas) FilaSugerencia(g)]),
      ),
    ];
  }

  List<Widget> _byStore(BuildContext context, AppState s, List<Item> items) {
    final groups = <String?, List<Item>>{};
    for (final i in items) {
      groups.putIfAbsent(i.storeId, () => []).add(i);
    }
    // 1º tiendas con pendientes (lo más urgente antes, luego la más cercana),
    // 2º "sin asignar", 3º tiendas ya terminadas
    int urgOf(List<Item> g) => g
        .where((i) => !i.done)
        .map((i) => i.urg)
        .fold(9, (a, b) => a < b ? a : b);
    bool finished(List<Item> g) => g.every((i) => i.done);
    int rank(MapEntry<String?, List<Item>> e) => finished(e.value)
        ? 2
        : (e.key == null || s.storeById(e.key) == null ? 1 : 0);
    final entries = groups.entries.toList()
      ..sort((a, b) {
        final r = rank(a) - rank(b);
        if (r != 0) return r;
        final u = urgOf(a.value) - urgOf(b.value);
        if (u != 0) return u;
        final ka = s.storeById(a.key)?.km ?? 99,
            kb = s.storeById(b.key)?.km ?? 99;
        return ka.compareTo(kb);
      });
    return [
      for (final e in entries)
        Card(
          margin: const EdgeInsets.only(top: 12),
          clipBehavior: Clip.antiAlias,
          child: Opacity(
            opacity: finished(e.value) ? .6 : 1,
            child: Column(
              children: [
                StoreHeader(store: s.storeById(e.key), items: e.value),
                for (final i in e.value) ItemRow(i, showStore: false),
              ],
            ),
          ),
        ),
    ];
  }
}

// ============================================== AVISO DE SINCRONIZACIÓN
/// Aparece solo si hay listas compartidas y la última sincronización falló.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final sy = s.sync;
    if (!sy.hayRemotas || sy.error == null) return const SizedBox.shrink();
    final n = sy.cambiosPendientes;
    return Card(
      color: Colors.orange.withValues(alpha: .18),
      margin: const EdgeInsets.only(bottom: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_outlined, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sy.error!,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [
                      if (n > 0)
                        '$n ${n == 1 ? 'cambio' : 'cambios'} por subir'
                      else
                        'No hay cambios pendientes',
                      'se reintenta solo',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            sy.sincronizando
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: sy.reintentarAhora,
                    child: const Text('Reintentar'),
                  ),
          ],
        ),
      ),
    );
  }
}

// ======================================================== CESTA / TOTAL
class CartCard extends StatelessWidget {
  const CartCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final fg = cs.onPrimaryContainer;
    final total = s.totalBought + s.totalPending;
    final done = s.items.where((i) => i.done).length;
    final n = s.items.length;
    final unpriced = s.items.where((i) => i.price == null).length;
    final byStore = s.boughtByStore;
    final coldUnits = s.items.where((i) => i.done && i.cold).length;
    return Card(
      color: cs.primaryContainer,
      margin: const EdgeInsets.only(bottom: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: s.toggleCart,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shopping_cart, color: fg, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tu cesta · $done/$n',
                        style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      eur(total),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: fg,
                      ),
                    ),
                    Icon(
                      s.cartOpen ? Icons.expand_less : Icons.expand_more,
                      color: fg,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: n == 0 ? 0 : done / n,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                if (s.cartOpen) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Comprado ${eur(s.totalBought)}',
                        style: TextStyle(color: fg),
                      ),
                      Text(
                        'Pendiente ${eur(s.totalPending)}',
                        style: TextStyle(color: fg),
                      ),
                    ],
                  ),
                  if (unpriced > 0)
                    Text(
                      '$unpriced sin precio',
                      style: TextStyle(
                        fontSize: 12,
                        color: fg.withValues(alpha: .7),
                      ),
                    ),
                  if (byStore.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Comprado por establecimiento',
                      style: TextStyle(
                        fontSize: 12,
                        color: fg.withValues(alpha: .7),
                      ),
                    ),
                    for (final e in byStore)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${e.name} · ${e.count} ${e.count == 1 ? 'producto' : 'productos'}',
                                style: TextStyle(color: fg),
                              ),
                            ),
                            Text(
                              eur(e.total),
                              style: TextStyle(
                                color: fg,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (coldUnits > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '❄️ $coldUnits ${coldUnits == 1 ? 'producto frío' : 'productos fríos'} en la bolsa',
                      style: TextStyle(color: fg),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================================================== TEMPORIZADOR FRÍO
class ColdBanner extends StatelessWidget {
  const ColdBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    if (!s.coldRunning) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: s.coldElapsed,
      builder: (context, el, _) {
        final win = s.coldWindowSec;
        final left = win - el;
        final frac = (el / win).clamp(0.0, 1.0);
        final color = left <= 0
            ? Colors.red
            : left <= 600
            ? Colors.deepOrange
            : frac > .33
            ? Colors.orange
            : Colors.lightBlue;
        String mm(int sec) =>
            '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
        final coldUnits = s.items.where((i) => i.done && i.cold).length;
        return Card(
          color: color.withValues(alpha: .15),
          margin: const EdgeInsets.only(bottom: 4),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color),
          ),
          child: InkWell(
            onTap: s.toggleCold,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.ac_unit, color: color, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            left <= 0
                                ? 'Tiempo agotado: revisa los fríos'
                                : '${el ~/ 60} min fuera · quedan ${(left / 60).ceil()} min',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          mm(el),
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Icon(
                          s.coldOpen ? Icons.expand_less : Icons.expand_more,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: frac,
                      color: color,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    if (s.coldOpen) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Fríos fuera de la nevera · $coldUnits ${coldUnits == 1 ? 'producto' : 'productos'}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${s.cfg.cooler.label} · máx. ${win ~/ 60} min',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: s.stopCold,
                            icon: const Icon(Icons.kitchen, size: 18),
                            label: const Text('Ya en la nevera'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ======================================================== FILA DE ITEM
class ItemRow extends StatelessWidget {
  const ItemRow(this.item, {super.key, this.showStore = true});
  final Item item;
  final bool showStore;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final store = s.storeById(item.storeId);
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => s.remove(item),
      child: ListTile(
        onTap: () => showFicha(
          context,
          s,
          item,
          onCambiarTienda: () => _changeStore(context, s, item),
        ),
        onLongPress: () => showOfferDialog(
          context,
          s,
          presetName: item.name,
          presetChain: store?.chain,
        ),
        leading: IconButton(
          icon: Icon(
            item.done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: item.done ? Colors.green : cs.outline,
            size: 28,
          ),
          onPressed: () async {
            final wasDone = item.done;
            s.toggleDone(item);
            if (!wasDone &&
                item.price == null &&
                store != null &&
                context.mounted) {
              await _askPrice(context, s, item);
            }
          },
        ),
        title: Row(
          children: [
            if (s.cfg.showImages &&
                (item.localImage != null || item.imageUrl != null))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ProductThumb(
                  localImage: item.localImage,
                  imageUrl: item.imageUrl,
                  size: 36,
                  ampliable: true,
                  titulo: item.name,
                ),
              ),
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  decoration: item.done ? TextDecoration.lineThrough : null,
                  color: item.done ? cs.outline : null,
                ),
              ),
            ),
          ],
        ),
        subtitle: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(Icons.circle, size: 9, color: _urgColors[item.urg - 1]),
            PopupMenuButton<int>(
              tooltip: 'Prioridad',
              padding: EdgeInsets.zero,
              onSelected: (u) => s.setUrgency(item, u),
              itemBuilder: (_) => [
                for (var u = 1; u <= 3; u++)
                  PopupMenuItem(
                    value: u,
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 10, color: _urgColors[u - 1]),
                        const SizedBox(width: 8),
                        Text(urgencyNames[u - 1]),
                      ],
                    ),
                  ),
              ],
              child: Text(
                urgencyNames[item.urg - 1],
                style: TextStyle(color: cs.primary, fontSize: 13),
              ),
            ),
            if (item.cantidad > 1)
              Text(
                '×${item.cantidad}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            if (item.cold) const Text('❄️', style: TextStyle(fontSize: 12)),
            if (s.hogar.remota &&
                item.addedBy != null &&
                item.addedBy != s.sync.miId &&
                s.sync.aliasDe[item.addedBy] != null)
              Text(
                '· ${s.sync.aliasDe[item.addedBy]}',
                style: TextStyle(color: cs.outline, fontSize: 12),
              ),
            if (showStore)
              InkWell(
                onTap: () => _changeStore(context, s, item),
                child: Text(
                  store == null ? '· Elegir súper' : '· ${store.name}',
                  style: TextStyle(color: cs.primary, fontSize: 13),
                ),
              ),
          ],
        ),
        trailing: item.price == null
            ? null
            : Text(
                eur(item.total),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
      ),
    );
  }
}

Future<void> _changeStore(BuildContext context, AppState s, Item it) async {
  final p = s.productOf(it);
  final opts = await s.options(p);
  if (!context.mounted) return;
  await showStoreSheet(context, s, it, opts);
}

Future<void> _askPrice(BuildContext context, AppState s, Item it) async {
  final c = TextEditingController();
  var oferta = false;
  final v = await showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text('¿A cuánto ha salido?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(it.name),
            const SizedBox(height: 8),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                suffixText: '€',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Es una oferta'),
              subtitle: Text(
                oferta
                    ? 'No cambia el precio habitual'
                    : 'Se guarda como precio habitual para comparar',
                style: const TextStyle(fontSize: 12),
              ),
              value: oferta,
              onChanged: (v) => setS(() => oferta = v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Omitir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              double.tryParse(c.text.replaceAll(',', '.')),
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  if (v != null && v > 0) s.setPrice(it, v, oferta: oferta);
}

// ================================================== CABECERA DE TIENDA
class StoreHeader extends StatelessWidget {
  const StoreHeader({super.key, required this.store, required this.items});
  final Store? store;
  final List<Item> items;

  @override
  Widget build(BuildContext context) {
    final pending = items.where((i) => !i.done).toList();
    final sub = pending.fold(0.0, (t, i) => t + i.total);
    final done = pending.isEmpty;
    final urg = pending.map((i) => i.urg).fold(9, (a, b) => a < b ? a : b);
    final cold = pending.where((i) => i.cold).length;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
      child: Row(
        children: [
          if (done)
            const Icon(Icons.check_circle, color: Colors.green, size: 18)
          else
            Icon(Icons.circle, size: 10, color: _urgColors[urg - 1]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store == null ? 'Sin asignar' : store!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  [
                    if (store != null) '${store!.km.toStringAsFixed(1)} km',
                    done ? 'todo comprado' : '${pending.length} por comprar',
                    if (cold > 0) '❄️ $cold',
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(eur(sub), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (store != null)
            IconButton(
              tooltip: 'Cómo llegar',
              icon: const Icon(Icons.directions),
              onPressed: () => showNavigateSheet(context, store!),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

Future<void> showNavigateSheet(BuildContext context, Store st) {
  final ll = '${st.lat},${st.lon}';
  final apple =
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
  Future<void> open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  return showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              st.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Abrir ubicación en…'),
          ),
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('Google Maps'),
            onTap: () {
              Navigator.pop(ctx);
              open('https://www.google.com/maps/dir/?api=1&destination=$ll');
            },
          ),
          ListTile(
            leading: const Icon(Icons.navigation),
            title: const Text('Waze'),
            onTap: () {
              Navigator.pop(ctx);
              open('https://waze.com/ul?ll=$ll&navigate=yes');
            },
          ),
          if (apple)
            ListTile(
              leading: const Icon(Icons.apple),
              title: const Text('Apple Maps'),
              onTap: () {
                Navigator.pop(ctx);
                open('https://maps.apple.com/?daddr=$ll');
              },
            ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('OpenStreetMap'),
            onTap: () {
              Navigator.pop(ctx);
              open(
                'https://www.openstreetmap.org/?mlat=${st.lat}&mlon=${st.lon}#map=18/${st.lat}/${st.lon}',
              );
            },
          ),
        ],
      ),
    ),
  );
}

// ============================================ SELECTOR DE SUPERMERCADO
Future<void> showStoreSheet(
  BuildContext context,
  AppState s,
  Item it,
  List<Option> opts,
) {
  final cheapest = opts
      .where((o) => o.price != null && !o.out)
      .map((o) => o.price!)
      .fold<double?>(null, (a, b) => a == null || b < a ? b : a);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * .8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text(it.name, style: Theme.of(ctx).textTheme.titleLarge),
            Text(
              'Criterio: ${s.cfg.criterion.name}',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (opts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No hay supermercados activos para este producto. Actívalos en Ajustes.',
                ),
              ),
            for (var i = 0; i < opts.length; i++)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: i == 0 && !opts[i].out
                        ? Colors.green
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ListTile(
                  enabled: !opts[i].out,
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          opts[i].store.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (i == 0 && !opts[i].out)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'recomendado',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    '${opts[i].store.km.toStringAsFixed(1)} km'
                    '${s.cfg.favChains.contains(opts[i].store.chain) ? ' · ★' : ''}'
                    '${opts[i].out ? ' · sin stock (según usuarios)' : ''}'
                    '${opts[i].quote != null && !opts[i].out ? ' · ${opts[i].quote!.age}' : ''}',
                  ),
                  trailing: Text(
                    opts[i].price == null
                        ? 'sin precio'
                        : '${eur(opts[i].price!)}${opts[i].price == cheapest ? ' 💚' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () {
                    s.assign(it, opts[i]);
                    Navigator.pop(ctx);
                  },
                ),
              ),
            if (it.storeId != null && s.storeById(it.storeId) != null)
              Builder(
                builder: (_) {
                  final st = s.storeById(it.storeId)!;
                  final marcado = s.exclusivos[s.productOf(it).key] != null;
                  final marca =
                      s.productOf(it).ownChain != null &&
                      !marcado; // marca blanca conocida
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Exclusivo de ${prettyChain(st.chain)}'),
                    subtitle: Text(
                      marca
                          ? 'Marca de la cadena: siempre se asigna aquí'
                          : 'La próxima vez que lo añadas irá directo a ${prettyChain(st.chain)}',
                    ),
                    value: marcado || marca,
                    onChanged: marca
                        ? null
                        : (v) {
                            s.setExclusivo(it, v);
                            Navigator.pop(ctx);
                          },
                  );
                },
              ),
            TextButton(
              onPressed: () {
                s.assign(it, null);
                Navigator.pop(ctx);
              },
              child: const Text('Dejar sin asignar'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ============================================================ AÑADIR
/// Hoja con el campo de texto: se abre con el «+», añade y se cierra.
Future<void> showAddSheet(BuildContext context) async {
  final s = AppScope.of(context);
  final r = await showModalBottomSheet<(Item, Product)>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: const AddSheet(),
    ),
  );
  if (r == null || !context.mounted) return;
  final (it, p) = r;
  final opts = await s.options(p);
  if (!context.mounted) return;
  if (p.ownChain != null) {
    if (opts.isNotEmpty) {
      s.assign(it, opts.first);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Solo se vende en ${prettyChain(p.ownChain!)}. Actívala en Ajustes.',
          ),
        ),
      );
    }
    return;
  }
  if (opts.isEmpty) return;
  if (s.cfg.auto) {
    s.assign(it, opts.first);
  } else {
    await showStoreSheet(context, s, it, opts);
  }
}

class AddSheet extends StatefulWidget {
  const AddSheet({super.key});
  @override
  State<AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<AddSheet> {
  final _c = TextEditingController();
  Timer? _debounce;
  List<Product> _online = [];
  Product? _porCodigo;
  bool _buscandoCodigo = false;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  List<Product> _local(AppState s) {
    final q = _c.text.trim().toLowerCase();
    if (q.isEmpty || !s.cfg.demoPrices) return [];
    return demoCatalog
        .where((p) => p.name.toLowerCase().contains(q))
        .take(4)
        .toList();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    setState(() {
      _online = [];
      _porCodigo = null;
    });
    final texto = v.trim();
    if (esCodigoDeBarras.hasMatch(texto)) {
      // un código de barras: se busca ese producto exacto
      setState(() => _buscandoCodigo = true);
      final api = AppScope.of(context).sync.api;
      productByBarcode(texto)
          .then(
            (p) async => p ?? (await api.buscarProductos(texto)).firstOrNull,
          )
          .then((p) {
            if (mounted && _c.text.trim() == texto) {
              setState(() => _porCodigo = p);
            }
          })
          .catchError((_) {})
          .whenComplete(() {
            if (mounted) setState(() => _buscandoCodigo = false);
          });
      return;
    }
    if (texto.length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      setState(() => _searching = true);
      try {
        final api = AppScope.of(context).sync.api;
        final res = await Future.wait([
          searchProducts(v.trim()).catchError((_) => <Product>[]),
          api.buscarProductos(v.trim()),
        ]);
        // los de la comunidad primero (son los que ha aportado la gente de aquí)
        final r = [...res[1], ...res[0]];
        if (mounted && _c.text.trim() == v.trim()) setState(() => _online = r);
      } catch (_) {}
      if (mounted) setState(() => _searching = false);
    });
  }

  /// «+», Enter: nunca usa un código de barras como nombre.
  void _enviar() {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    if (esCodigoDeBarras.hasMatch(t)) {
      if (_porCodigo != null) {
        _add(_porCodigo!);
      } else if (!_buscandoCodigo) {
        _crearNuevo(codigo: t);
      }
      return;
    }
    _add(Product(name: t, cold: looksCold(t)));
  }

  /// Revisar (y poder corregir) nombre y tamaño de un producto encontrado por código.
  Future<void> _revisarEncontrado(Product p) async {
    final partes = p.name.split(' · ');
    final r = await showNuevoProducto(
      context,
      titulo: 'Tu nombre para este producto',
      nombre: partes.first,
      marca: partes.length > 1 ? partes.sublist(1).join(' · ') : '',
      cantidad: p.quantity ?? '',
      codigo: p.barcode,
      frio: p.cold,
      nota:
          'El código de barras se conserva como identificador. Solo cambia cómo lo ves tú.',
    );
    if (r == null || !mounted) return;
    _add(
      Product(
        name: r.name,
        barcode: p.barcode,
        cold: r.cold,
        ownChain: p.ownChain,
        imageUrl: p.imageUrl,
        quantity: r.quantity,
        genericKey: r.genericKey ?? p.genericKey,
      ),
    );
  }

  Future<void> _escanear() async {
    final code = await escanearCodigo(context);
    if (code == null || !mounted) return;
    _c.text = code;
    _c.selection = TextSelection.collapsed(offset: code.length);
    _onChanged(code);
    setState(() {});
  }

  /// Crea un producto que no existe en las bases abiertas. Se añade a tu lista y se propone a la base general.
  Future<void> _crearNuevo({String? codigo}) async {
    final s = AppScope.of(context);
    final texto = _c.text.trim();
    final p = await showNuevoProducto(
      context,
      nombre: esCodigoDeBarras.hasMatch(texto) ? '' : texto,
      codigo: codigo,
      compartir: s.cfg.shareNewProducts,
    );
    if (p == null || !mounted) return;
    s.proponerProducto(p); // en segundo plano; sin conexión no pasa nada
    _add(p);
  }

  /// Añade el producto y cierra la hoja; la elección de súper la hace quien la abrió.
  void _add(Product p) {
    final s = AppScope.of(context);
    p = s.conFrio(s.conExclusivo(p));
    final it = s.add(p);
    Navigator.pop(context, (it, p));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final text = _c.text.trim();
    final sugg = <Product>[
      ..._local(s),
      ..._online.where((o) => !_local(s).any((l) => l.name == o.name)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (v) {
                    _onChanged(v);
                    setState(() {});
                  },
                  onSubmitted: (v) => _enviar(),
                  decoration: InputDecoration(
                    hintText: 'Añadir producto o código…',
                    suffixIcon: escanerDisponible
                        ? IconButton(
                            tooltip: 'Escanear código de barras',
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: _escanear,
                          )
                        : null,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: esCodigoDeBarras.hasMatch(text)
                    ? 'Añadir a mi lista'
                    : 'Añadir solo a mi lista',
                onPressed: text.isEmpty ? null : _enviar,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (text.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (_buscandoCodigo)
                    const LinearProgressIndicator(minHeight: 2),
                  if (_porCodigo != null)
                    ListTile(
                      leading: ProductThumb(imageUrl: _porCodigo!.imageUrl),
                      title: Text(_porCodigo!.name),
                      subtitle: Text(
                        'Código $text${_porCodigo!.quantity == null ? '' : ' · ${_porCodigo!.quantity}'}\n'
                        'Toca para añadir a tu lista · ✏️ para ponerle tu nombre y tamaño',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Editar nombre y tamaño',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _revisarEncontrado(_porCodigo!),
                      ),
                      onTap: () => _add(_porCodigo!),
                    )
                  else if (esCodigoDeBarras.hasMatch(text) && !_buscandoCodigo)
                    ListTile(
                      leading: const Icon(Icons.qr_code_2),
                      title: Text('Código $text no encontrado'),
                      subtitle: Text(
                        s.cfg.shareNewProducts
                            ? 'Ponle nombre y tamaño: se añade a tu lista y a la base común (pública tras revisión)'
                            : 'Ponle nombre y tamaño: se añade solo a tu lista',
                      ),
                      isThreeLine: true,
                      onTap: () => _crearNuevo(codigo: text),
                    ),
                  if (!esCodigoDeBarras.hasMatch(text))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.playlist_add),
                      title: Text('Crear producto nuevo «$text»…'),
                      subtitle: Text(
                        s.cfg.shareNewProducts
                            ? 'Con marca, tamaño y código · va a tu lista y a la base común'
                            : 'Con marca, tamaño y código · solo a tu lista',
                      ),
                      onTap: () => _crearNuevo(),
                    ),
                  if (!esCodigoDeBarras.hasMatch(text))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add_circle_outline),
                      title: Text('Añadir «$text» a mi lista'),
                      subtitle: const Text('Solo en tu lista, no se comparte'),
                      onTap: () =>
                          _add(Product(name: text, cold: looksCold(text))),
                    ),
                  for (final p in sugg)
                    ListTile(
                      dense: true,
                      leading: p.imageUrl == null
                          ? null
                          : ProductThumb(imageUrl: p.imageUrl, size: 36),
                      title: Text(p.name),
                      subtitle: Text(
                        [
                          if (p.quantity != null) p.quantity!,
                          if (p.ownChain != null)
                            'Exclusivo ${prettyChain(p.ownChain!)}',
                        ].join(' · '),
                      ),
                      trailing: p.cold ? const Text('❄️') : null,
                      onTap: () => _add(p),
                    ),
                  if (_searching) const LinearProgressIndicator(minHeight: 2),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Formulario para crear un producto nuevo. Devuelve el producto o null si se cancela.
Future<Product?> showNuevoProducto(
  BuildContext context, {
  String titulo = 'Producto nuevo',
  String nombre = '',
  String marca = '',
  String cantidad = '',
  String? codigo,
  bool? frio,
  String? nota,
  bool compartir = true,
}) {
  final n = TextEditingController(text: nombre);
  final marcaC = TextEditingController(text: marca);
  final cant = TextEditingController(text: cantidad);
  final cod = TextEditingController(text: codigo ?? '');
  var esFrio = frio ?? looksCold(nombre);
  return showDialog<Product>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: n,
                autofocus: nombre.isEmpty,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setS(() => esFrio = looksCold(v) || esFrio),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: marcaC,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Marca (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cant,
                decoration: const InputDecoration(
                  labelText: 'Cantidad (1 L, 400 g…)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cod,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Código de barras (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Refrigerado ❄️'),
                value: esFrio,
                onChanged: (v) => setS(() => esFrio = v),
              ),
              Text(
                nota ??
                    (compartir
                        ? 'Se añade a tu lista y se propone a la base común: será pública para todos tras una revisión. El código de barras es solo el identificador; el nombre y el tamaño los pones tú.'
                        : 'Se añade solo a tu lista (tienes desactivado compartir productos nuevos).'),
                style: const TextStyle(fontSize: 12),
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
              final nombreF = n.text.trim();
              if (nombreF.isEmpty) return;
              final m = marcaC.text.trim();
              final c = cod.text.trim();
              final q = cant.text.trim();
              Navigator.pop(
                ctx,
                Product(
                  name: m.isEmpty ? nombreF : '$nombreF · $m',
                  barcode: esCodigoDeBarras.hasMatch(c) ? c : null,
                  cold: esFrio,
                  quantity: q.isEmpty ? null : q,
                  genericKey: genericKey(
                    fallbackName: nombreF,
                    quantity: q,
                    brands: m,
                  ),
                ),
              );
            },
            child: const Text('Crear y añadir'),
          ),
        ],
      ),
    ),
  );
}

/// Una sugerencia de recompra: se ve al 50 % para que no se confunda con lo que ya está en la lista.
class FilaSugerencia extends StatelessWidget {
  const FilaSugerencia(this.g, {super.key});
  final Sugerencia g;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final dias = DateTime.now().difference(g.ultima).inDays;
    return Opacity(
      opacity: .5,
      child: ListTile(
        onTap: () => s.anadirSugerencia(g),
        leading: IconButton(
          tooltip: 'No hace falta ahora',
          icon: Icon(Icons.radio_button_unchecked, color: cs.outline, size: 28),
          onPressed: () async {
            final preguntar = s.descartarSugerencia(g);
            if (preguntar && context.mounted) {
              await preguntarRecurrente(context, s, g);
            }
          },
        ),
        title: Text(g.name),
        subtitle: Text(
          'Sueles reponerlo cada ${g.cadaDias.round()} días · última compra hace $dias d · toca para añadir',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

/// Tras descartar varias veces seguidas la misma sugerencia: ¿estacional o dejar de recordarlo?
Future<void> preguntarRecurrente(
  BuildContext context,
  AppState s,
  Sugerencia g,
) async {
  final r = await showDialog<DecisionRecompra>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('«${g.name}»'),
      content: const Text(
        'Has descartado esta sugerencia varias veces seguidas. ¿Qué prefieres?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, DecisionRecompra.seguir),
          child: const Text('Seguir recordándomelo'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, DecisionRecompra.estacional),
          child: const Text('Es estacional (3 meses)'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, DecisionRecompra.parar),
          child: const Text('Dejar de recordármelo'),
        ),
      ],
    ),
  );
  if (r != null) s.resolverRecurrente(g.key, r);
}
