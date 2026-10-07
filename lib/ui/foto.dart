import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';
import '../state.dart';
import '../sync/pb_api.dart';

/// Las fotos propias se guardan en archivos: no están disponibles en web.
bool get fotosPropiasDisponibles => !kIsWeb;

/// Miniatura de un producto: foto propia > foto enlazada (Open Food Facts o comunidad) > nada.
class ProductThumb extends StatelessWidget {
  const ProductThumb({
    super.key,
    this.localImage,
    this.imageUrl,
    this.size = 40,
  });
  final String? localImage;
  final String? imageUrl;
  final double size;

  bool get hay =>
      (localImage != null && !kIsWeb) ||
      (imageUrl != null && imageUrl!.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    if (!hay) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    Widget img;
    if (localImage != null && !kIsWeb) {
      img = Image.file(
        File(localImage!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _vacio(cs),
      );
    } else {
      img = Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _vacio(cs),
        loadingBuilder: (c, child, p) => p == null ? child : _vacio(cs),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: img);
  }

  Widget _vacio(ColorScheme cs) => Container(
    width: size,
    height: size,
    color: cs.surfaceContainerHighest,
    child: Icon(Icons.image_outlined, size: size * .5, color: cs.outline),
  );
}

/// Reconstruye la foto sin metadatos (EXIF: ubicación GPS, fecha, modelo del móvil…) y la reduce a 1024 px.
/// Las fotos de cámara llevan la ubicación dentro: nunca deben guardarse ni publicarse con ella.
Uint8List? limpiarFoto(Uint8List bytes) {
  try {
    final original = img.decodeImage(bytes);
    if (original == null) return null;
    var f = img.bakeOrientation(
      original,
    ); // aplica la rotación antes de descartar el EXIF
    if (f.width > 1024 || f.height > 1024) {
      f = f.width >= f.height
          ? img.copyResize(f, width: 1024)
          : img.copyResize(f, height: 1024);
    }
    f.exif.clear();
    return Uint8List.fromList(img.encodeJpg(f, quality: 82));
  } catch (_) {
    return null; // no se pudo leer: no se guarda ni se sube (podría llevar metadatos sin limpiar)
  }
}

/// Hace o elige una foto, la guarda en el dispositivo y, si el usuario quiere, la ofrece a la base colaborativa.
Future<void> aniadirFoto(
  BuildContext context,
  AppState s,
  Item it, {
  required ImageSource source,
}) async {
  XFile? x;
  try {
    x = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 82,
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo acceder a la cámara o a la galería'),
        ),
      );
    }
    return;
  }
  if (x == null) return;
  final dir = await getApplicationDocumentsDirectory();
  final carpeta = Directory('${dir.path}/fotos');
  if (!await carpeta.exists()) await carpeta.create(recursive: true);
  final key = s.productOf(it).key.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
  final destino =
      '${carpeta.path}/${key}_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final bytes = limpiarFoto(await x.readAsBytes());
  if (bytes == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo procesar la foto')),
      );
    }
    return;
  }
  await File(destino).writeAsBytes(bytes);
  s.setFotoLocal(it, destino);
  if (!context.mounted) return;

  var compartir = s.cfg.sharePhotos;
  if (!compartir) {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Compartir esta foto?'),
        content: const Text(
          'La foto ya está guardada en tu móvil. Si la compartes con la base colaborativa:\n\n'
          '• será de acceso público,\n'
          '• cualquiera podrá usarla sin restricciones ni licencias derivadas,\n'
          '• se revisará antes de publicarse y no podrás editarla,\n'
          '• mientras esté pendiente puedes retirarla, pero una vez aprobada será permanente en la base común.\n\n'
          'Solo se aceptan fotos PURAS del producto: el envase, sin tickets, caras, dedos ni personas al fondo, '
          'y hechas por ti. Si está casi bien, se recorta al revisarla. '
          'Se eliminan todos los metadatos (ubicación, fecha, modelo del móvil) de la foto.\n\n'
          'Puedes elegir no compartirla y seguir viéndola solo tú.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Solo en mi móvil'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Compartir'),
          ),
        ],
      ),
    );
    compartir = r == true;
  }
  if (!compartir) return;
  try {
    final p = s.productOf(it);
    await s.sync.api.subirFoto(
      key: p.key,
      barcode: p.barcode,
      name: it.name,
      bytes: bytes,
      filename: 'foto.jpg',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto enviada. Se publicará cuando se revise.'),
        ),
      );
    }
  } on PbException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo compartir: ${e.message}. Sigue guardada en tu móvil.',
          ),
        ),
      );
    }
  }
}
