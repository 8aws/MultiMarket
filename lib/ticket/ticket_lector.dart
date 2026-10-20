// Lee un ticket (foto, imagen o PDF) y devuelve sus líneas de texto.
// Todo ocurre en el dispositivo y los ficheros temporales se borran siempre, hayan salido bien o mal.
// - PDF con texto (apps de Lidl, MÁS…): se lee el texto directamente, sin OCR.
// - Imagen o PDF escaneado: OCR nativo de Apple (Vision), solo iOS.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'ticket_ocr.dart';

/// ¿Se puede leer un fichero en esta plataforma? (en web solo se puede pegar el texto)
bool get lectorDisponible => !kIsWeb;

bool get _hayOcr => !kIsWeb && Platform.isIOS;

const _canalOcr = MethodChannel('es.uverse.multimarket/ocr');

Future<List<List<String>>> leerTickets(String ruta) async {
  final esPdf = ruta.toLowerCase().endsWith('.pdf');
  return esPdf ? _leerPdf(ruta) : _ocr(ruta);
}

/// OCR con Apple Vision (nativo, en el dispositivo). Devuelve un ticket por cada columna de la imagen.
Future<List<List<String>>> _ocr(String ruta) async {
  if (!_hayOcr) {
    throw UnsupportedError('El OCR de imágenes solo está disponible en iOS');
  }
  final r = await _canalOcr.invokeListMethod<Map>('reconocer', ruta) ?? [];
  final fr = [
    for (final m in r)
      FragmentoOcr(
        m['t'] as String,
        (m['x0'] as num).toDouble(),
        (m['y0'] as num).toDouble(),
        (m['x1'] as num).toDouble(),
        (m['y1'] as num).toDouble(),
      ),
  ];
  return [for (final c in separarColumnas(fr)) agruparPorFilas(c)];
}

Future<List<List<String>>> _leerPdf(String ruta) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openFile(ruta);
  final out = <List<String>>[];
  // un PDF con texto es UN ticket aunque tenga varias páginas (una línea puede cortarse entre páginas)
  final textoPaginas = <String>[];
  try {
    for (final p in doc.pages) {
      final t = (await p.loadText())?.fullText ?? '';
      final lineas = t
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty);
      if (lineas.join().length >= 40) {
        textoPaginas.addAll(lineas);
        continue;
      }
      // página escaneada: se dibuja a imagen y se pasa por OCR
      final alto = 2400.0;
      final im = await p.render(
        fullWidth: alto * p.width / p.height,
        fullHeight: alto,
        backgroundColor: 0xffffffff,
      );
      if (im == null) continue;
      final dir = await getTemporaryDirectory();
      final f = File(
        '${dir.path}/ticket_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      try {
        final png = img.encodePng(
          img.Image.fromBytes(
            width: im.width,
            height: im.height,
            bytes: im.pixels.buffer,
            order: img.ChannelOrder.bgra,
            numChannels: 4,
          ),
        );
        await f.writeAsBytes(png);
        out.addAll(await _ocr(f.path));
      } finally {
        im.dispose();
        if (await f.exists()) await f.delete();
      }
    }
  } finally {
    await doc.dispose();
  }
  if (textoPaginas.isNotEmpty) out.insert(0, textoPaginas);
  return out;
}
