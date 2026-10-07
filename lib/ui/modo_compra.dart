import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../main.dart';
import '../models.dart';
import '../state.dart';
import 'comparar.dart';
import 'foto.dart';
import 'home.dart' show showNuevoProducto;
import 'scanner.dart';

/// Escáner pensado para usarlo DENTRO de la tienda: lees un código y decides qué hacer con él.
class ModoCompraPage extends StatefulWidget {
  const ModoCompraPage({super.key});
  @override
  State<ModoCompraPage> createState() => _ModoCompraPageState();
}

class _ModoCompraPageState extends State<ModoCompraPage> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  Store? _tienda; // dónde estás (detectada o elegida)
  bool _detectando = true;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final st = await AppScope.of(context).tiendaActual();
      if (mounted) {
        setState(() {
          _tienda = st;
          _detectando = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture c) async {
    if (_ocupado) return;
    final code = c.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => RegExp(r'^\d{8,14}$').hasMatch(v))
        .firstOrNull;
    if (code == null) return;
    _ocupado = true;
    final s = AppScope.of(context);
    final producto = await s.buscarProductoPorCodigo(code);
    if (!mounted) return;
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: ResultadoEscaneo(
          s: s,
          code: code,
          producto: producto,
          tienda: _tienda,
          onSeguir: () => Navigator.pop(ctx, 'seguir'),
          onCerrar: () => Navigator.pop(ctx, 'cerrar'),
        ),
      ),
    );
    if (!mounted) return;
    if (r == 'cerrar') {
      Navigator.of(context).pop();
    } else {
      _ocupado = false; // vuelve a leer
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Modo compra'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '¿En qué tienda estás?',
            onSelected: (id) =>
                setState(() => _tienda = s.storeById(id) ?? _tienda),
            itemBuilder: (_) => [
              for (final st in s.activeStores)
                PopupMenuItem(value: st.id, child: Text(st.name)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.store_outlined, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    _detectando
                        ? 'Buscando…'
                        : (_tienda?.name ?? '¿Dónde estás?'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Linterna',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No se pudo abrir la cámara. Revisa el permiso en Ajustes del sistema.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Text(
              'Escanea un producto',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja con el resultado de un código: ficha, precio de la balda y qué hacer con él.
class ResultadoEscaneo extends StatefulWidget {
  const ResultadoEscaneo({
    super.key,
    required this.s,
    required this.code,
    required this.producto,
    required this.tienda,
    required this.onSeguir,
    required this.onCerrar,
  });
  final AppState s;
  final String code;
  final Product? producto;
  final Store? tienda;
  final VoidCallback onSeguir, onCerrar;

  @override
  State<ResultadoEscaneo> createState() => _ResultadoEscaneoState();
}

class _ResultadoEscaneoState extends State<ResultadoEscaneo> {
  late Product? _p = widget.producto;
  final _precio = TextEditingController();
  int _accion = 0; // 0 comprado ahora · 1 para más adelante
  int _cantidad = 1;
  bool _oferta = false;
  String? _sustituir; // id del item equivalente que se sustituye
  String? _resultado; // mensaje final cuando ya se aplicó
  Quote? _conocido;

  AppState get s => widget.s;
  List<Item> get _exactos => s.pendientesConCodigo(widget.code);
  List<Item> get _equiv =>
      _p == null || _exactos.isNotEmpty ? [] : s.equivalentesPendientes(_p!);

  @override
  void initState() {
    super.initState();
    _inicializar();
    _cargarPrecio();
  }

  void _inicializar() {
    _accion = _exactos.isNotEmpty || _equiv.isNotEmpty ? 0 : 1;
    _sustituir = _equiv.isEmpty ? null : _equiv.first.id;
    if (_exactos.isNotEmpty) _cantidad = _exactos.first.cantidad;
  }

  Future<void> _cargarPrecio() async {
    final p = _p, st = widget.tienda;
    if (p == null || st == null) return;
    final q = await s.precioConocido(p, st);
    if (!mounted || q == null || q.price == null) return;
    setState(() {
      _conocido = q;
      if (_precio.text.isEmpty) {
        _precio.text = q.price!.toStringAsFixed(2).replaceAll('.', ',');
      }
    });
  }

  @override
  void dispose() {
    _precio.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    final p = await showNuevoProducto(
      context,
      codigo: widget.code,
      compartir: s.cfg.shareNewProducts,
    );
    if (p == null || !mounted) return;
    s.proponerProducto(p);
    setState(() {
      _p = p;
      _inicializar();
    });
    _cargarPrecio();
  }

  void _comparar() {
    final p = _p;
    if (p == null) return;
    final precio = double.tryParse(_precio.text.replaceAll(',', '.'));
    s.anadirAComparar(p, cantidad: p.quantity, precio: precio);
    setState(
      () => _resultado =
          '«${p.name}» añadido a la comparación (${s.comparacion.length})',
    );
  }

  void _aplicar() {
    final p = _p;
    if (p == null) return;
    final precio = double.tryParse(_precio.text.replaceAll(',', '.'));
    final st = widget.tienda;
    Item it;
    final exactos = _exactos;
    if (exactos.isNotEmpty) {
      it = exactos.first;
    } else if (_equiv.isNotEmpty && _sustituir != null) {
      it = _equiv.firstWhere((x) => x.id == _sustituir);
      s.sustituirItem(it, p);
    } else {
      it = s.add(p);
    }
    // comprando ahora, la tienda es esta; para más adelante solo si aún no tenía
    if (st != null && (_accion == 0 || it.storeId == null)) {
      it.storeId = st.id;
    }
    if (_cantidad != it.cantidad) s.setCantidad(it, _cantidad);
    if (precio != null && precio > 0) {
      s.setPrice(it, precio, oferta: _oferta);
    }
    if (_accion == 0 && !it.done) s.toggleDone(it);
    final donde = st == null ? '' : ' en ${st.name}';
    setState(() {
      _resultado = _accion == 0
          ? '«${it.name}» marcado como comprado$donde'
          : '«${it.name}» guardado en la lista para más adelante';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_resultado != null) ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 10),
                Expanded(child: Text(_resultado!)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear más'),
                    onPressed: widget.onSeguir,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCerrar,
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            ),
            if (s.comparacion.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.compare_arrows),
                label: Text('Ver comparación (${s.comparacion.length})'),
                onPressed: () => abrirComparar(context),
              ),
          ] else if (p == null) ...[
            Text(
              'Código ${widget.code}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'No lo conozco todavía. Ponle nombre y tamaño y lo añadimos (también a la base común, si lo tienes activado).',
              style: TextStyle(color: cs.outline),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Crear producto'),
                    onPressed: _crear,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: widget.onSeguir,
                  child: const Text('Escanear otro'),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                if (p.imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ProductThumb(imageUrl: p.imageUrl, size: 64),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        [
                          if (p.quantity != null) p.quantity!,
                          'Código ${widget.code}',
                          if (p.cold) '❄️',
                        ].join(' · '),
                        style: TextStyle(color: cs.outline, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_exactos.isNotEmpty)
              _banda(
                Icons.checklist,
                'Está en tu lista: «${_exactos.first.name}»',
                Colors.green,
              )
            else if (_equiv.isNotEmpty)
              _banda(
                Icons.swap_horiz,
                'No es el de tu lista, pero es equivalente a «${_equiv.first.name}»',
                Colors.orange,
              )
            else
              _banda(
                Icons.add_shopping_cart,
                'No está en tu lista',
                cs.outline,
              ),
            if (_equiv.isNotEmpty) ...[
              const SizedBox(height: 4),
              RadioGroup<String?>(
                groupValue: _sustituir,
                onChanged: (v) => setState(() => _sustituir = v),
                child: Column(
                  children: [
                    for (final e in _equiv)
                      RadioListTile<String?>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('Sustituir «${e.name}»'),
                        value: e.id,
                      ),
                    const RadioListTile<String?>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Añadirlo aparte (sin sustituir nada)'),
                      value: null,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: 0,
                  label: Text('Comprado ahora'),
                  icon: Icon(Icons.shopping_cart_checkout),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text('Para más adelante'),
                  icon: Icon(Icons.bookmark_add_outlined),
                ),
              ],
              selected: {_accion},
              onSelectionChanged: (v) => setState(() => _accion = v.first),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _precio,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: widget.tienda == null
                          ? 'Precio visto (por unidad)'
                          : 'Precio en ${widget.tienda!.name}',
                      suffixText: '€',
                      helperText: _conocido == null
                          ? 'Opcional: lo recordaré para comparar'
                          : 'Conocido: ${_conocido!.age}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    Text(
                      'Cantidad',
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                    Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: _cantidad > 1
                              ? () => setState(() => _cantidad--)
                              : null,
                        ),
                        Text(
                          '$_cantidad',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setState(() => _cantidad++),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Es una oferta'),
              subtitle: const Text('No cambia el precio habitual'),
              value: _oferta,
              onChanged: (v) => setState(() => _oferta = v),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _aplicar,
                    child: Text(
                      _accion == 0
                          ? 'Marcar como comprado'
                          : 'Guardar para después',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: widget.onSeguir,
                  child: const Text('Descartar'),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Añadir a comparar'),
                onPressed: _comparar,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _banda(IconData i, String t, Color c) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: c.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(i, color: c, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

/// Abre el modo compra (solo donde hay cámara).
void abrirModoCompra(BuildContext context) {
  if (!escanerDisponible) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('El escáner no está disponible en este dispositivo'),
      ),
    );
    return;
  }
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const ModoCompraPage()));
}
