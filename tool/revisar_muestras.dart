// Revisa las muestras de tickets que la app guarda en TU iCloud Drive (opción de desarrollo) y compara lo que el
// lector entiende hoy con lo que el usuario dejó tras corregir. Uso:
//   dart run tool/revisar_muestras.dart [carpeta]
// Por defecto: ~/Library/Mobile Documents/iCloud~es~uverse~multimarket/Documents/Muestras
import 'dart:convert';
import 'dart:io';

import 'package:multimarket/ticket/ticket_parser.dart';

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñ ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

void main(List<String> args) {
  final raiz = Directory(
    args.isNotEmpty
        ? args.first
        : '${Platform.environment['HOME']}/Library/Mobile Documents/iCloud~es~uverse~multimarket/Documents/Muestras',
  );
  if (!raiz.existsSync()) {
    stderr.writeln('No existe ${raiz.path} (¿iCloud Drive sincronizado en este Mac?)');
    exit(1);
  }
  final carpetas = [
    for (final d in raiz.listSync(recursive: true).whereType<Directory>())
      if (File('${d.path}/lineas.json').existsSync()) d,
  ]..sort((a, b) => a.path.compareTo(b.path));
  var total = 0, cuadran = 0, conCambios = 0;
  for (final c in carpetas) {
    final lineas = (jsonDecode(File('${c.path}/lineas.json').readAsStringSync()) as List)
        .map((t) => (t as List).cast<String>())
        .toList();
    final resFile = File('${c.path}/resultado.json');
    final tickets = resFile.existsSync()
        ? ((jsonDecode(resFile.readAsStringSync()) as Map)['tickets'] as List?) ?? const []
        : const [];
    for (var i = 0; i < lineas.length; i++) {
      total++;
      final t = parsearTicket(lineas[i]);
      if (t.cuadra) cuadran++;
      final marca = t.cuadra ? 'OK  ' : 'FALLA';
      stdout.writeln('$marca ${c.path.split('Muestras/').last} #$i: ${t.cadena ?? '?'} total=${t.total} suma=${t.sumaNeta.toStringAsFixed(2)} líneas=${t.lineas.length}');
      if (i >= tickets.length) continue;
      final finales = ((tickets[i] as Map)['lineas'] as List).cast<Map>();
      final hoy = {for (final l in t.lineas) '${_norm(l.nombre)}|${l.bruto.toStringAsFixed(2)}'};
      final fin = {for (final l in finales) '${_norm('${l['nombre']}')}|${(l['bruto'] as num).toStringAsFixed(2)}'};
      final sobran = hoy.difference(fin), faltan = fin.difference(hoy);
      if (sobran.isNotEmpty || faltan.isNotEmpty) {
        conCambios++;
        for (final s in sobran) {
          stdout.writeln('     lector hoy (no queda al final): $s');
        }
        for (final f in faltan) {
          stdout.writeln('     usuario dejó (lector hoy no lo da): $f');
        }
      }
    }
  }
  stdout.writeln('\n$total tickets · $cuadran cuadran · $conCambios con diferencias respecto a lo que dejó el usuario');
}
