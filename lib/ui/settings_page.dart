import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ------------------------------------------------ listas
        Seccion(
          'Mis listas',
          Icons.list_alt,
          Card(
            child: Column(
              children: [
                for (final g in s.hogares)
                  ListTile(
                    leading: Text(
                      g.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
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
        ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            'Hasta ${Hogar.maxCompartidos} listas compartidas (casa, trabajo, abuelos…). Sin lista compartida, todo es privado.',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),

        // ------------------------------------------------ cuenta
        Seccion(
          'Cuenta y sincronización',
          Icons.sync,
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
                      color: s.sync.error == null
                          ? Colors.green
                          : Colors.orange,
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
        ),

        // ------------------------------------------------ supermercados
        Seccion(
          'Mis supermercados',
          Icons.store_outlined,
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
                          onPressed: () => _pedirActualizarTiendas(context, s),
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
                          onChangeEnd: (_) async {
                            // al ampliar hay que descargar más (cambia la lista: se pregunta); al reducir basta con filtrar
                            if (c.radiusKm > s.fetchedRadiusKm) {
                              final hecho = await _pedirActualizarTiendas(
                                context,
                                s,
                                relocate: false,
                              );
                              if (!hecho && s.fetchedRadiusKm > 0) {
                                c.radiusKm = s.fetchedRadiusKm;
                              }
                              s.changed();
                            } else {
                              s.changed();
                            }
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
        ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            '★ marca cadenas favoritas. Los productos de marca blanca se asignan siempre a su cadena.',
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),

        // ------------------------------------------------ imágenes
        Seccion(
          'Imágenes',
          Icons.image_outlined,
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
        ),

        // ------------------------------------------------ tarjetas
        Seccion(
          'Tarjetas de la lista',
          Icons.dashboard_customize_outlined,
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
        ),

        // ------------------------------------------------ selección
        Seccion(
          'Selección de súper',
          Icons.tune,
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
                  subtitle: const Text(
                    'Si no, te muestra los precios y eliges',
                  ),
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
        ),

        // ------------------------------------------------ frío
        Seccion(
          'Productos fríos',
          Icons.ac_unit,
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
        Seccion(
          'Ofertas',
          Icons.local_offer_outlined,
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
        ),

        // ------------------------------------------------ colores de los precios
        Seccion(
          'Colores de los precios',
          Icons.palette_outlined,
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LeyendaPrecio(
                    color: null,
                    titulo: 'Negro · escrito por ti',
                    texto:
                        'Lo anotaste tú a mano (o por un ticket tuyo): vale lo que tú digas.',
                  ),
                  _LeyendaPrecio(
                    color: Color(0xFF1E8E3E),
                    titulo: 'Verde · fiable',
                    texto:
                        'Viene de un ticket que cuadra con su total y la cifra es coherente, o lo han confirmado varios usuarios con diferencias de ±10 %.',
                  ),
                  _LeyendaPrecio(
                    color: Color(0xFFB26A00),
                    titulo: 'Ámbar · orientativo',
                    texto:
                        'Hay disparidad entre usuarios (más del 10 %), el dato es antiguo (más de 60 días), es de un producto equivalente por nombre o la fuente es colaborativa sin verificar (Open Prices).',
                  ),
                  _LeyendaPrecio(
                    color: Color(0xFFC62828),
                    titulo: 'Rojo · poco fiable',
                    texto:
                        'Solo lo ha visto un usuario en un ticket que no cuadra, la disparidad es muy alta (más del 40 %) o es un precio de ejemplo.',
                  ),
                  SizedBox(height: 4),
                  Text(
                    'El color nunca cambia tus datos: es solo una ayuda para decidir. Pulsa un precio en la lista para cambiarlo.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ------------------------------------------------ privacidad
        Seccion(
          'Privacidad',
          Icons.privacy_tip_outlined,
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Copia de mi lista privada en el servidor'),
                  subtitle: Text(
                    c.copiaPrivada
                        ? 'Si reinstalas la app podrás recuperar tu lista, historial y precios.${s.ultimaCopia == null ? '' : ' Última copia: ${s.ultimaCopia!.day}/${s.ultimaCopia!.month}/${s.ultimaCopia!.year}'}'
                        : 'Opcional. Guarda tu lista privada, historial y precios en tu cuenta anónima del servidor; solo tú puedes verla. Desactivado por defecto',
                  ),
                  value: c.copiaPrivada,
                  onChanged: (v) async {
                    c.copiaPrivada = v;
                    s.changed();
                    if (v) {
                      await s.subirCopia(forzar: true);
                    } else {
                      await s.borrarCopiaServidor();
                    }
                  },
                ),
                if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) ...[
                  SwitchListTile(
                    title: const Text('Copia automática en iCloud'),
                    subtitle: Text(
                      'Guarda tu lista privada, historial y precios en TU iCloud Drive (carpeta MultiMarket). No pasa por nuestro servidor.'
                      '${s.ultimaCopiaICloud == null ? '' : ' Última copia: ${s.ultimaCopiaICloud!.day}/${s.ultimaCopiaICloud!.month}/${s.ultimaCopiaICloud!.year}'}',
                    ),
                    value: c.copiaICloud,
                    onChanged: (v) async {
                      c.copiaICloud = v;
                      s.changed();
                      if (v) {
                        final e = await s.copiarEnICloud();
                        if (e != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e), showCloseIcon: true),
                          );
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.cloud_download_outlined),
                    title: const Text('Restaurar desde iCloud'),
                    subtitle: const Text(
                      'Sustituye tu lista privada, historial y precios por la copia de tu iCloud.',
                    ),
                    onTap: () async {
                      final mensajes = ScaffoldMessenger.of(context);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('¿Restaurar desde iCloud?'),
                          content: const Text(
                            'Tu lista privada, historial y precios actuales se sustituirán por los de la copia.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancelar'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Restaurar'),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      final e = await s.restaurarDeICloud();
                      mensajes.showSnackBar(
                        SnackBar(
                          content: Text(e ?? 'Copia restaurada'),
                          showCloseIcon: true,
                        ),
                      );
                    },
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Guardar una copia en un archivo'),
                  subtitle: const Text(
                    'Lista privada, historial y precios en un archivo que guardas tú (iCloud Drive, Archivos…). No usa el servidor.',
                  ),
                  onTap: () async {
                    final mensajes = ScaffoldMessenger.of(context);
                    final fecha = DateTime.now().toIso8601String().substring(
                      0,
                      10,
                    );
                    try {
                      final r = await FilePicker.saveFile(
                        fileName: 'multimarket-copia-$fecha.json',
                        bytes: Uint8List.fromList(s.copiaEnArchivo()),
                        mimeType: 'application/json',
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (r != null) {
                        mensajes.showSnackBar(
                          const SnackBar(
                            content: Text('Copia guardada'),
                            showCloseIcon: true,
                          ),
                        );
                      }
                    } catch (_) {
                      mensajes.showSnackBar(
                        const SnackBar(
                          content: Text('No se pudo guardar el archivo'),
                          showCloseIcon: true,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: const Text('Restaurar desde un archivo'),
                  subtitle: const Text(
                    'Sustituye tu lista privada, historial y precios por los del archivo.',
                  ),
                  onTap: () async {
                    final mensajes = ScaffoldMessenger.of(context);
                    final f = await FilePicker.pickFile(
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                    );
                    if (f == null || !context.mounted) return;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('¿Restaurar la copia?'),
                        content: const Text(
                          'Tu lista privada, historial y precios actuales se sustituirán por los del archivo.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Restaurar'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    final texto = utf8.decode(await f.readAsBytes());
                    final error = s.restaurarDeArchivo(texto);
                    mensajes.showSnackBar(
                      SnackBar(
                        content: Text(error ?? 'Copia restaurada'),
                        showCloseIcon: true,
                      ),
                    );
                  },
                ),
                SwitchListTile(
                  title: const Text('Enviar informes de errores'),
                  subtitle: const Text(
                    'Anónimos: versión, sistema y traza del fallo, sin el contenido de tus listas. Ayudan a corregir errores. Desactivado por defecto',
                  ),
                  value: c.enviarErrores,
                  onChanged: (v) {
                    c.enviarErrores = v;
                    s.changed();
                  },
                ),
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
        ),

        // ------------------------------------------------ acerca de
        Seccion(
          'Datos abiertos y licencias',
          Icons.info_outline,
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
                ListTile(
                  dense: true,
                  title: Text('Versión $versionApp'),
                  // 7 toques seguidos activan las opciones de desarrollo (muestras de tickets)
                  onTap: () {
                    if (++_toquesVersion >= 7 && !c.modoDesarrollo) {
                      c.modoDesarrollo = true;
                      s.changed();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Opciones de desarrollo activadas'),
                          showCloseIcon: true,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        if (c.modoDesarrollo)
          Seccion(
            'Desarrollo',
            Icons.science_outlined,
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Enviar muestras de mis tickets'),
                    subtitle: const Text(
                      'Guarda en TU iCloud Drive (MultiMarket/Muestras) el texto leído, el resultado corregido y la imagen de cada ticket que importas, '
                      'para revisar y mejorar la lectura. No pasa por nuestro servidor. Desactivado por defecto.',
                    ),
                    value: c.muestrasTickets,
                    onChanged: (v) {
                      c.muestrasTickets = v;
                      s.changed();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Borrado automático de muestras'),
                    subtitle: const Text('Activado por defecto.'),
                    value: c.borradoMuestras,
                    onChanged: (v) {
                      c.borradoMuestras = v;
                      s.changed();
                    },
                  ),
                  ListTile(
                    enabled: c.borradoMuestras,
                    title: const Text('Conservar las muestras'),
                    subtitle: const Text(
                      'Inmediato: se borran al volver a abrir la app.',
                    ),
                    trailing: DropdownButton<int>(
                      value: c.retencionMuestrasDias,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Inmediato')),
                        DropdownMenuItem(value: 7, child: Text('Semanal')),
                        DropdownMenuItem(value: 30, child: Text('Mensual')),
                        DropdownMenuItem(value: 90, child: Text('Trimestral')),
                        DropdownMenuItem(value: 365, child: Text('Anual')),
                      ],
                      onChanged: c.borradoMuestras
                          ? (v) {
                              c.retencionMuestrasDias = v ?? 90;
                              s.changed();
                            }
                          : null,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_sweep_outlined),
                    title: const Text('Borrar ahora todas las muestras'),
                    onTap: () async {
                      await s.purgarMuestras(ahora: true);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Muestras borradas de iCloud'),
                            showCloseIcon: true,
                          ),
                        );
                      }
                    },
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: const Text('Ocultar opciones de desarrollo'),
                    onTap: () {
                      c.modoDesarrollo = false;
                      _toquesVersion = 0;
                      s.changed();
                    },
                  ),
                ],
              ),
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

class _LeyendaPrecio extends StatelessWidget {
  const _LeyendaPrecio({
    required this.color,
    required this.titulo,
    required this.texto,
  });
  final Color? color;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 10),
            child: Text(
              '0,00 €',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(texto, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Actualizar la lista de supermercados cambia las tiendas de tu zona: si ya estaba creada, se pide confirmación.
Future<bool> _pedirActualizarTiendas(
  BuildContext context,
  AppState s, {
  bool relocate = true,
}) async {
  if (s.listaDeTiendasFijada) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Actualizar los supermercados'),
        content: const Text(
          'Esto cambiará tu lista de locales de compra: se volverán a buscar los supermercados de la zona y pueden '
          'aparecer, desaparecer o cambiar tiendas.\n\n'
          'Las tiendas que ya usas en tu lista se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }
  await s.refreshStores(relocate: relocate);
  return true;
}

int _toquesVersion = 0;

/// Secciones de Ajustes plegables: se ve un solo renglón por tema y se abre el que hace falta.
/// Lo abierto se recuerda mientras la app está en marcha.
final Set<String> _seccionesAbiertas = {};

class Seccion extends StatefulWidget {
  const Seccion(this.titulo, this.icono, this.contenido, {super.key});
  final String titulo;
  final IconData icono;
  final Widget contenido;

  @override
  State<Seccion> createState() => _SeccionState();
}

class _SeccionState extends State<Seccion> {
  bool get _abierta => _seccionesAbiertas.contains(widget.titulo);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            _abierta
                ? _seccionesAbiertas.remove(widget.titulo)
                : _seccionesAbiertas.add(widget.titulo);
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
            child: Row(
              children: [
                Icon(widget.icono, size: 22, color: cs.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.titulo,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _abierta ? .5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more, color: cs.outline),
                ),
              ],
            ),
          ),
        ),
        if (_abierta) widget.contenido,
        Divider(height: 1, color: cs.outlineVariant),
      ],
    );
  }
}
