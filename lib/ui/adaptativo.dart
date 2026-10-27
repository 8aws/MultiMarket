import 'package:flutter/widgets.dart';

/// Clases de tamaño de la ventana (ancho disponible), como las clases de tamaño de Apple: nada depende del modelo de dispositivo.
enum ClaseVentana { compacta, media, expandida }

const double anchoMedia = 600;
const double anchoExpandida = 840;

/// A partir de este ancho la pantalla principal se divide en dos paneles (lista + detalle).
/// Se queda un poco por debajo de «expandida» para que quepa la pantalla interior de un plegable.
const double anchoDosPaneles = 700;

ClaseVentana claseVentana(double ancho) => ancho >= anchoExpandida
    ? ClaseVentana.expandida
    : ancho >= anchoMedia
    ? ClaseVentana.media
    : ClaseVentana.compacta;

/// Alto mínimo para dos paneles: un iPhone en horizontal (~390-430 pt de alto) no los usa aunque pase de 700 de ancho.
const double altoDosPaneles = 560;

/// Medidas del iPhone Duo en el simulador (puntos): exterior 466×678; interior vertical 669×951 (un panel)
/// e interior horizontal 951×669 (dos paneles).
bool cabenDosPaneles(Size t) =>
    t.width >= anchoDosPaneles && t.height >= altoDosPaneles;

/// ¿Cabe la pantalla en dos paneles?
bool dosPaneles(BuildContext context) =>
    cabenDosPaneles(MediaQuery.sizeOf(context));

/// Franjas laterales del sistema (cámara, hora y cobertura se mueven a un lateral en el Duo y en iPhone horizontal):
/// se respetan UNA vez para toda la app y se ponen a 0 para los hijos, así ninguna pantalla las duplica ni las olvida.
class MargenesLaterales extends StatelessWidget {
  const MargenesLaterales({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final p = mq.padding;
    if (p.left == 0 && p.right == 0) return child;
    return Padding(
      padding: EdgeInsets.only(left: p.left, right: p.right),
      child: MediaQuery(
        data: mq.copyWith(padding: p.copyWith(left: 0, right: 0)),
        child: child,
      ),
    );
  }
}
