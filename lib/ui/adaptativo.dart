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

/// ¿Cabe la pantalla en dos paneles?
bool dosPaneles(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= anchoDosPaneles;
