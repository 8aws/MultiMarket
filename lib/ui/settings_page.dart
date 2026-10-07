import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models.dart';
import '../sources.dart';
import '../state.dart';
import 'hogares.dart';
import 'miembros.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final c = s.cfg;
    final cs = Theme.of(context).colorScheme;
    Widget h(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Text(
        t.toUpperCase(),
        style: TextStyle(fontSize: 12, color: cs.outline, letterSpacing: .4),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ------------------------------------------------ listas
        h('Mis listas'),
        Card(
          child: Column(
            children: [
              for (final g in s.hogares)
                ListTile(
                  leading: Text(g.emoji, style: const TextStyle(fontSize: 22)),
                  title: Text(g.name),
                  subtitle: Text(
                    g.esPrivada
                        ? 'Privada, solo en tu dispositivo'
                        : g.remota
                        ? (g.esCreador
                              ? 'Compartida · eres el creador'
                              : 'Compartida')
                        : 'Solo en este dispositivo',
                  ),
                  trailing: g.esPrivada
                      ? null
                      : g.remota
                      ? const Icon(Icons.chevron_right)
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () =>
                                  showHogarDialog(context, s, h: g),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () =>
                                  confirmarBorrarHogar(context, s, g),
                            ),
                          ],
                        ),
                  onTap: g.remota
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MiembrosPage(hogarId: g.id),
                          ),
                        )
                      : null,
                ),
              if (s.puedeCrearHogar) ...[
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Nueva lista compartida'),
                  onTap: () => showCrearCompartida(context, s),
                ),
                ListTile(
                  leading: const Icon(Icons.vpn_key_outlined),
                  title: const Text('Unirme con un código'),
                  onTap: () => showUnirse(context, s),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            'Hasta ${Hogar.maxCompartidos} listas compartidas (casa, trabajo, abuelos…). Sin lista compartida, todo es privado.',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),

        // ------------------------------------------------ cuenta
        h('Cuenta y sincronización'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Tu nombre'),
                subtitle: Text(
                  c.alias.isEmpty
                      ? 'Sin nombre (lo piden al compartir)'
                      : c.alias,
                ),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () async {
                  final ctl = TextEditingController(text: c.alias);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Tu nombre'),
                      content: TextField(
                        controller: ctl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
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
                  if (ok == true) {
                    c.alias = ctl.text.trim();
                    s.changed();
                  }
                },
              ),
              ListTile(
                title: const Text('Servidor'),
                subtitle: Text(c.serverUrl),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () async {
                  final ctl = TextEditingController(text: c.serverUrl);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Servidor PocketBase'),
                      content: TextField(
                        controller: ctl,
                        autofocus: true,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar'),
                        ),
                        TextButton(
                          onPressed: () {
                            ctl.text = defaultServerUrl;
                            Navigator.pop(ctx, true);
                          },
                          child: const Text('Restaurar'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Guardar'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true && ctl.text.trim().startsWith('http')) {
                    c.serverUrl = ctl.text.trim().replaceAll(
                      RegExp(r'/+$'),
                      '',
                    );
                    s.changed();
                  }
                },
              ),
              if (s.sync.hayRemotas)
                ListTile(
                  leading: Icon(
                    s.sync.error == null
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: s.sync.error == null ? Colors.green : Colors.orange,
                  ),
                  title: Text(s.sync.error ?? 'Sincronizado'),
                  subtitle: s.sync.ultimaSync == null
                      ? null
                      : Text(
                          'Última vez: ${s.sync.ultimaSync!.hour.toString().padLeft(2, '0')}:${s.sync.ultimaSync!.minute.toString().padLeft(2, '0')}',
                        ),
                  trailing: IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: s.sync.sincronizar,
                  ),
                ),
            ],
          ),
        ),

        // ------------------------------------------------ supermercados
        h('Mis supermercados'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  s.locApprox ? Icons.location_searching : Icons.my_location,
                ),
                title: Text(
                  s.locApprox
                      ? 'Ubicación aproximada (Madrid)'
                      : 'Usando tu ubicación',
                ),
                subtitle: Text(
                  s.storesError ??
                      '${s.stores.where((x) => x.km <= c.radiusKm).length} supermercados en OpenStreetMap · radio ${c.radiusKm.toStringAsFixed(0)} km',
                ),
                trailing: s.loadingStores
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: 'Buscar cerca de mí',
                        icon: const Icon(Icons.refresh),
                        onPressed: () => s.refreshStores(),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('Radio'),
                    Expanded(
                      child: Slider(
                        min: 1,
                        max: 10,
                        divisions: 9,
                        value: c.radiusKm.clamp(1, 10),
                        label: '${c.radiusKm.toStringAsFixed(0)} km',
                        onChanged: (v) {
                          c.radiusKm = v;
                          s.refresh();
                        },
                        onChangeEnd: (_) {
                          // al ampliar hay que descargar más; al reducir basta con filtrar
                          c.radiusKm > s.fetchedRadiusKm
                              ? s.refreshStores(relocate: false)
                              : s.changed();
                        },
                      ),
                    ),
                    Text('${c.radiusKm.toStringAsFixed(0)} km'),
                  ],
                ),
              ),
              const Divider(height: 1),
              Builder(
                builder: (context) {
                  // solo las del radio elegido; ventana con scroll de ~8 filas
                  final near = s.stores
                      .where((st) => st.km <= c.radiusKm)
                      .toList();
                  const rowH = 76.0, maxRows = 6;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            near.length > maxRows
                                ? '${near.length} supermercados · la lista tiene su propio scroll; desliza por el margen derecho para mover la pantalla'
                                : '${near.length} ${near.length == 1 ? 'supermercado' : 'supermercados'}',
                            style: TextStyle(fontSize: 12, color: cs.outline),
                          ),
                        ),
                      ),
                      // margen a la derecha: deslizar ahí mueve la pantalla, no la ventana
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 36, 8),
                        child: Container(
                          height: (near.length.clamp(1, maxRows)) * rowH,
                          decoration: BoxDecoration(
                            border: Border.all(color: cs.outlineVariant),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: near.isEmpty
                              ? Center(
                                  child: Text(
                                    'Ninguno en este radio',
                                    style: TextStyle(color: cs.outline),
                                  ),
                                )
                              : Scrollbar(
                                  thumbVisibility: near.length > maxRows,
                                  child: ListView.builder(
                                    itemCount: near.length,
                                    itemExtent: rowH,
                                    itemBuilder: (context, i) {
                                      final st = near[i];
                                      return ListTile(
                                        dense: true,
                                        title: Text(
                                          shortStoreName(st.name),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          st.name.toLowerCase().contains(
                                                st.chain,
                                              )
                                              ? '${st.km.toStringAsFixed(1)} km'
                                              : '${prettyChain(st.chain)} · ${st.km.toStringAsFixed(1)} km',
                                        ),
                                        leading: IconButton(
                                          icon: Icon(
                                            c.favChains.contains(st.chain)
                                                ? Icons.star
                                                : Icons.star_border,
                                            color:
                                                c.favChains.contains(st.chain)
                                                ? Colors.amber
                                                : cs.outline,
                                          ),
                                          onPressed: () {
                                            c.favChains.contains(st.chain)
                                                ? c.favChains.remove(st.chain)
                                                : c.favChains.add(st.chain);
                                            s.changed();
                                          },
                                        ),
                                        trailing: Switch(
                                          value: c.enabled.contains(st.id),
                                          onChanged: (v) {
                                            v
                                                ? c.enabled.add(st.id)
                                                : c.enabled.remove(st.id);
                                            s.changed();
                                          },
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            '★ marca cadenas favoritas. Los productos de marca blanca se asignan siempre a su cadena.',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),

        // ------------------------------------------------ imágenes
        h('Imágenes'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Miniaturas en la lista'),
                subtitle: const Text(
                  'Foto del producto junto al nombre (de Open Food Facts, la comunidad o tuya)',
                ),
                value: c.showImages,
                onChanged: (v) {
                  c.showImages = v;
                  s.changed();
                },
              ),
              SwitchListTile(
                title: const Text('Compartir mis fotos sin preguntar'),
                subtitle: const Text(
                  'Si lo apagas, se te pregunta cada vez. Las fotos compartidas serán públicas, '
                  'sin restricciones ni licencias derivadas, y se revisan antes de publicarse. '
                  'Una vez aprobadas son permanentes.',
                ),
                value: c.sharePhotos,
                onChanged: (v) {
                  c.sharePhotos = v;
                  s.changed();
                },
              ),
              SwitchListTile(
                title: const Text('Compartir productos nuevos'),
                subtitle: const Text(
                  'Los productos que creas (que no están en Open Food Facts) se proponen a la base común: '
                  'serán públicos para todos tras una revisión.',
                ),
                value: c.shareNewProducts,
                onChanged: (v) {
                  c.shareNewProducts = v;
                  s.changed();
                },
              ),
              const ListTile(
                dense: true,
                title: Text(
                  'Las imágenes de productos vienen de Open Food Facts (CC-BY-SA) y se enlazan, no se copian.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),

        // ------------------------------------------------ tarjetas
        h('Tarjetas de la lista'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Mostrar tarjeta de la cesta'),
                subtitle: const Text(
                  'Cesta con total, progreso y desglose por tienda',
                ),
                value: c.showCartCard,
                onChanged: (v) {
                  c.showCartCard = v;
                  s.changed();
                },
              ),
              SwitchListTile(
                title: const Text('Mostrar tarjeta del frío'),
                subtitle: const Text(
                  'Solo oculta la tarjeta; los avisos siguen si el temporizador está activo',
                ),
                value: c.showColdCard,
                onChanged: (v) {
                  c.showColdCard = v;
                  s.changed();
                },
              ),
            ],
          ),
        ),

        // ------------------------------------------------ selección
        h('Selección de súper'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Priorizar por'),
                trailing: DropdownButton<Criterion>(
                  value: c.criterion,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final k in Criterion.values)
                      DropdownMenuItem(value: k, child: Text(k.name)),
                  ],
                  onChanged: (v) {
                    c.criterion = v!;
                    s.changed();
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('Sugerencias de recompra'),
                subtitle: const Text(
                  'Aparecen al 50 % en la lista los productos que, según tu historial, toca reponer. Necesita al menos 3 compras de cada uno',
                ),
                value: c.recompra,
                onChanged: (v) {
                  c.recompra = v;
                  s.changed();
                },
              ),
              if (c.recompra && s.descartes.isNotEmpty)
                ListTile(
                  title: const Text('Restablecer sugerencias silenciadas'),
                  subtitle: Text(
                    '${s.descartes.length} producto${s.descartes.length == 1 ? '' : 's'} descartado${s.descartes.length == 1 ? '' : 's'} en esta lista',
                  ),
                  trailing: const Icon(Icons.restart_alt),
                  onTap: s.restablecerSugerencias,
                ),
              SwitchListTile(
                title: const Text('Detectar la tienda al comprar'),
                subtitle: const Text(
                  'Al marcar un producto como comprado, usa tu ubicación (si ya diste permiso) para saber en qué tienda estás y reasignarlo si es otra',
                ),
                value: c.detectarTienda,
                onChanged: (v) {
                  c.detectarTienda = v;
                  s.changed();
                },
              ),
              SwitchListTile(
                title: const Text('Asignar automáticamente'),
                subtitle: const Text('Si no, te muestra los precios y eliges'),
                value: c.auto,
                onChanged: (v) {
                  c.auto = v;
                  s.changed();
                },
              ),
              SwitchListTile(
                title: const Text('Usar precios de ejemplo'),
                subtitle: const Text(
                  'Los datos abiertos de España aún son escasos. Los de ejemplo se marcan como tal.',
                ),
                value: c.demoPrices,
                onChanged: (v) {
                  c.demoPrices = v;
                  s.changed();
                },
              ),
            ],
          ),
        ),

        // ------------------------------------------------ frío
        h('Productos fríos'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Temporizador de frío'),
                subtitle: const Text(
                  'Empieza al marcar como comprado el primer producto refrigerado y avisa a los 20 min, a 10 min del límite y al agotarse.',
                ),
                value: c.coldTimer,
                onChanged: (v) {
                  c.coldTimer = v;
                  if (!v) s.stopCold();
                  s.applyColdSettings();
                },
              ),
              if (c.coldTimer)
                ListTile(
                  title: const Text('Cómo los transportas'),
                  subtitle: Text(
                    'Tiempo máximo hasta la nevera: ${c.cooler.minutes} min',
                  ),
                  trailing: DropdownButton<Cooler>(
                    value: c.cooler,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final k in Cooler.values)
                        DropdownMenuItem(value: k, child: Text(k.label)),
                    ],
                    onChanged: (v) {
                      c.cooler = v!;
                      s.applyColdSettings();
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            'Referencia general de seguridad alimentaria: no más de 1-2 h fuera de frío (1 h con calor). '
            'Con bolsa isotérmica o petaca se amplía, pero es una estimación orientativa.',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),

        // ------------------------------------------------ ofertas
        h('Ofertas'),
        Card(
          child: ListTile(
            title: const Text('Avisarme antes de que caduquen'),
            subtitle: const Text('Notificación a las 10:00'),
            trailing: DropdownButton<int>(
              value: c.offerReminderDays,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Nunca')),
                DropdownMenuItem(value: 1, child: Text('1 día antes')),
                DropdownMenuItem(value: 2, child: Text('2 días antes')),
                DropdownMenuItem(value: 3, child: Text('3 días antes')),
              ],
              onChanged: (v) {
                c.offerReminderDays = v!;
                s.applyOfferSettings();
              },
            ),
          ),
        ),

        // ------------------------------------------------ privacidad
        h('Privacidad'),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Política de privacidad'),
                trailing: const Icon(Icons.open_in_new, size: 16),
                onTap: () => launchUrl(
                  Uri.parse('${c.serverUrl}/privacidad/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Privacy policy (English)'),
                trailing: const Icon(Icons.open_in_new, size: 16),
                onTap: () => launchUrl(
                  Uri.parse('${c.serverUrl}/privacy/'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: Colors.red,
                ),
                title: const Text(
                  'Eliminar mi cuenta y mis datos',
                  style: TextStyle(color: Colors.red),
                ),
                subtitle: const Text(
                  'Borra tu cuenta del servidor y, si quieres, todo lo de este dispositivo',
                ),
                onTap: () => confirmarEliminarCuenta(context, s),
              ),
            ],
          ),
        ),

        // ------------------------------------------------ acerca de
        h('Datos abiertos y licencias'),
        Card(
          child: Column(
            children: [
              _link(
                context,
                'Tiendas: © colaboradores de OpenStreetMap (ODbL)',
                'https://www.openstreetmap.org/copyright',
              ),
              _link(
                context,
                'Productos: Open Food Facts (ODbL)',
                'https://world.openfoodfacts.org',
              ),
              _link(
                context,
                'Precios: Open Prices (ODbL)',
                'https://prices.openfoodfacts.org',
              ),
              const ListTile(
                dense: true,
                title: Text(
                  'MultiMarket es software libre bajo licencia MIT. Sin scraping de tiendas.',
                ),
              ),
            ],
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('¿Borrar la lista y los precios anotados?'),
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
              if (ok == true) {
                s.items.clear();
                s.stopCold();
              }
            },
            child: const Text('Vaciar lista'),
          ),
        ),
      ],
    );
  }

  Widget _link(BuildContext c, String t, String url) => ListTile(
    dense: true,
    title: Text(t),
    trailing: const Icon(Icons.open_in_new, size: 16),
    onTap: () =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
  );
}

/// Diálogo para eliminar la cuenta (derecho de supresión) con la opción de borrar también lo local.
Future<void> confirmarEliminarCuenta(BuildContext context, AppState s) async {
  final conCuenta = await s.tieneCuentaEnServidor;
  if (!context.mounted) return;
  var borrarLocal = true;
  var trabajando = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Eliminar mi cuenta y mis datos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conCuenta
                    ? 'Se borrará tu cuenta del servidor y dejarás de pertenecer a tus listas compartidas.\n\n'
                          '• Las listas que creaste pasan al siguiente miembro, o se borran si eras el único.\n'
                          '• Tus fotos y productos aún pendientes de revisión se eliminan.\n'
                          '• Lo que ya se aprobó y es público permanece, sin vínculo contigo.'
                    : 'No tienes cuenta en el servidor (solo la creas si usas listas compartidas, compartes fotos o propones productos). '
                          'Aquí solo puedes borrar los datos de este dispositivo.',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: borrarLocal,
                onChanged: trabajando
                    ? null
                    : (v) => setS(() => borrarLocal = v ?? false),
                title: const Text(
                  'Borrar también los datos de este dispositivo',
                ),
                subtitle: const Text(
                  'Tu lista privada, precios, fotos, ajustes e historial. No se puede deshacer.',
                ),
              ),
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
            onPressed: trabajando ? null : () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: trabajando || (!conCuenta && !borrarLocal)
                ? null
                : () async {
                    setS(() {
                      trabajando = true;
                      error = null;
                    });
                    final e = await s.eliminarCuenta(borrarLocal: borrarLocal);
                    if (e == null) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Listo: tus datos se han eliminado'),
                          ),
                        );
                      }
                    } else {
                      setS(() {
                        trabajando = false;
                        error = e;
                      });
                    }
                  },
            child: trabajando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Eliminar'),
          ),
        ],
      ),
    ),
  );
}
