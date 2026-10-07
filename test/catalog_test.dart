import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:multimarket/sync/pb_api.dart';
import 'package:multimarket/ui/foto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:multimarket/catalog.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/state.dart';

void main() {
  reporteTests();
  fotoTests();
  comparacionTests();
  test('cantidades normalizadas', () {
    expect(parseQuantity('1 l'), (n: 1000.0, u: 'ml'));
    expect(parseQuantity('1,5 L'), (n: 1500.0, u: 'ml'));
    expect(parseQuantity('400 g'), (n: 400.0, u: 'g'));
    expect(parseQuantity('1.5 kg'), (n: 1500.0, u: 'g'));
    expect(parseQuantity('33 cl'), (n: 330.0, u: 'ml'));
    expect(parseQuantity('sin dato'), isNull);
  });

  test('clave genérica: marcas distintas de la misma leche coinciden', () {
    // la misma leche con categorías distintas según la ficha y la marca dentro del nombre
    final a = genericKey(
      categories: ['en:dairies', 'en:cow-milks'],
      quantity: '1 l',
      fallbackName: 'Leche entera',
      brands: 'Hacendado',
    );
    final b = genericKey(
      categories: ['en:dairies', 'en:uht'],
      quantity: '1L',
      fallbackName: 'Leche entera DIA',
      brands: 'Dia',
    );
    expect(a, 'leche-entera|1000ml');
    expect(b, a, reason: 'marca y cantidad no cuentan');
    expect(
      genericKey(quantity: '1,5 L', fallbackName: 'Leche entera'),
      isNot(a),
    );
    expect(genericKey(fallbackName: 'Pan de molde'), 'pan-molde');
    expect(genericKey(categories: ['en:dairies', 'en:milks']), 'milks');
  });

  test('refrigerado: sugerencia a partir de categorías reales', () {
    // leche UHT de Dia (datos reales de Open Food Facts)
    expect(
      suggestCold([
        'en:dairies',
        'en:milks',
        'en:pasteurised-products',
        'en:uht-milks',
      ]),
      isFalse,
    );
    // leche esterilizada de Hacendado
    expect(
      suggestCold(['en:dairies', 'en:milks', 'en:sterilised-milks']),
      isFalse,
    );
    expect(suggestCold(['en:dairies', 'en:yogurts']), isTrue);
    expect(suggestCold(['en:meats', 'en:poultry']), isTrue);
    expect(
      suggestCold(['en:frozen-foods', 'en:ice-creams-and-sorbets']),
      isTrue,
    );
    expect(suggestCold(['en:canned-foods', 'en:fishes']), isFalse);
    expect(suggestCold(['en:beverages']), isFalse);
    expect(suggestCold(null, name: 'Yogur natural'), isTrue);
    expect(
      suggestCold([
        'en:dairies',
        'en:pasteurised-products',
      ], name: 'Leche entera esterilizada'),
      isFalse,
      reason: 'el nombre dice que es esterilizada',
    );
  });

  test('marca blanca por marca o por tienda única', () {
    expect(ownChainFrom('Hacendado'), 'mercadona');
    expect(ownChainFrom('MERCADONA', 'Mercadona'), 'mercadona');
    expect(
      ownChainFrom('Gaza', 'Mercadona'),
      'mercadona',
      reason: 'tienda única conocida',
    );
    expect(ownChainFrom('Gaza', 'Mercadona, Carrefour'), isNull);
    expect(ownChainFrom('Coca-Cola'), isNull);
  });

  test('producto desde un registro de Open Food Facts', () {
    final p = productFromOff({
      'code': '8480017006080',
      'product_name': 'Leche entera de vaca DIA',
      'brands': ['Dia'],
      'quantity': '1L',
      'image_front_small_url': 'https://images.openfoodfacts.org/x.200.jpg',
      'categories_tags': [
        'en:dairies',
        'en:milks',
        'en:uht-milks',
        'en:whole-milks',
      ],
      'stores': 'Dia',
    })!;
    expect(p.barcode, '8480017006080');
    expect(p.cold, isFalse);
    expect(p.ownChain, 'dia');
    expect(p.imageUrl, contains('openfoodfacts'));
    expect(p.genericKey, 'leche-entera-vaca|1000ml');
    expect(
      productFromOff({'code': '1'}),
      isNull,
      reason: 'sin nombre no sirve',
    );
  });

  test(
    'un precio anotado sirve para productos equivalentes de otra marca',
    () async {
      SharedPreferences.setMockInitialValues({});
      final s = AppState(await SharedPreferences.getInstance());
      final cats = ['en:dairies', 'en:whole-milks'];
      final gk = genericKey(categories: cats, quantity: '1 l');
      final hacendado = Product(
        name: 'Leche Hacendado',
        barcode: '111',
        genericKey: gk,
      );
      final gaza = Product(name: 'Leche Gaza', barcode: '222', genericKey: gk);
      final item = s.add(hacendado);
      final dia = s.stores.firstWhere((x) => x.chain == 'dia');
      s.cfg.enabled.add(dia.id);
      item.storeId = dia.id;
      s.setPrice(item, 0.85);
      final o = (await s.options(
        gaza,
      )).firstWhere((x) => x.store.chain == 'dia');
      expect(o.price, 0.85);
      expect(o.quote!.equivalente, isTrue);
      expect(o.quote!.age, contains('similar'));
      s.dispose();
    },
  );
}

void fotoTests() {
  test('limpiarFoto elimina los metadatos (ubicación) y reduce a 1024 px', () {
    final base = img.Image(width: 2000, height: 1000);
    img.fill(base, color: img.ColorRgb8(30, 90, 170));
    base.exif.gpsIfd.gpsLatitude = 40.4168;
    base.exif.gpsIfd.gpsLongitude = -3.7038;
    base.exif.imageIfd.make = 'MiMovil';
    final conExif = Uint8List.fromList(img.encodeJpg(base));
    // la foto original lleva la ubicación dentro
    expect(img.decodeJpg(conExif)!.exif.gpsIfd.hasGPSLatitude, isTrue);
    final limpia = limpiarFoto(conExif)!;
    final r = img.decodeJpg(limpia)!;
    // foto «pelada»: ni un solo marcador de metadatos en el archivo
    final ascii = String.fromCharCodes(limpia);
    expect(ascii.contains('Exif'), isFalse);
    expect(ascii.contains('MiMovil'), isFalse);
    expect(
      ascii.contains('http://ns.adobe.com/xap'),
      isFalse,
      reason: 'sin XMP',
    );
    expect(r.exif.gpsIfd.hasGPSLatitude, isFalse);
    expect(r.exif.gpsIfd.hasGPSLongitude, isFalse);
    expect(r.exif.imageIfd.hasMake, isFalse);
    expect(r.width, 1024);
    expect(r.height, 512);
  });

  test('limpiarFoto rechaza lo que no es una imagen legible', () {
    expect(limpiarFoto(Uint8List.fromList([1, 2, 3])), isNull);
  });
}

void comparacionTests() {
  test('cantidades: packs, centilitros y unidades', () {
    expect(parseQuantity('3 x 125 g'), (n: 375.0, u: 'g'));
    expect(parseQuantity('4×200ml'), (n: 800.0, u: 'ml'));
    expect(parseQuantity('1.170 g (3 x 390 g)'), (n: 1170.0, u: 'g'));
    expect(parseQuantity('6 uds'), (n: 6.0, u: 'ud'));
    expect(parseQuantity('12 unidades'), (n: 12.0, u: 'ud'));
    expect(parseQuantity('33 cl'), (n: 330.0, u: 'ml'));
    expect(parseQuantity('sin tamaño'), isNull);
  });

  test('precio unitario por kg, litro y unidad', () {
    final a = precioUnitario(1.20, '200 g')!;
    expect(a.valor, closeTo(6.0, 1e-9));
    expect(a.etiqueta, '€/kg');
    expect(precioUnitario(2.50, '450 g')!.valor, closeTo(5.5556, 1e-3));
    expect(precioUnitario(0.89, '1 l')!.valor, closeTo(0.89, 1e-9));
    expect(precioUnitario(0.89, '1 l')!.dimension, 'L');
    expect(precioUnitario(3.0, '6 uds')!.valor, closeTo(0.5, 1e-9));
    expect(precioUnitario(null, '1 l'), isNull);
    expect(precioUnitario(1.0, null), isNull);
    expect(precioUnitario(0, '1 l'), isNull);
  });

  test('comparar: el bote grande puede salir más barato por kilo', () {
    final pequeno = LineaComparar(
      producto: const Product(name: 'Bote 200 g', barcode: '1'),
      cantidad: '200 g',
      precio: 1.20,
    );
    final grande = LineaComparar(
      producto: const Product(name: 'Bote 450 g', barcode: '2'),
      cantidad: '450 g',
      precio: 2.50,
    );
    final leche = LineaComparar(
      producto: const Product(name: 'Leche', barcode: '3'),
      cantidad: '1 L',
      precio: 0.89,
    );
    final incompleto = LineaComparar(
      producto: const Product(name: 'Sin precio', barcode: '4'),
      cantidad: '300 g',
    );
    final r = comparar([pequeno, grande, leche, incompleto]);
    expect(r.porDimension['kg']!.map((l) => l.producto.name), [
      'Bote 450 g',
      'Bote 200 g',
    ]);
    expect(r.esMejor(grande), isTrue);
    expect(r.esMejor(pequeno), isFalse);
    expect(
      r.esMejor(leche),
      isFalse,
      reason: 'es la única de su dimensión: no hay con qué compararla',
    );
    expect(r.sobrecoste(pequeno), closeTo(8.0, 0.1));
    expect(r.sobrecoste(grande), closeTo(0.0, 1e-9));
    expect(r.sinDatos, [incompleto]);
    // el litro no se mezcla con el kilo
    expect(r.porDimension.keys, containsAll(['kg', 'L']));
  });
}

void reporteTests() {
  test(
    'id de la foto comunitaria a partir de su URL (solo las de nuestro servidor)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final api = PbApi(
        await SharedPreferences.getInstance(),
        'https://mm.example',
      );
      expect(
        api.fotoIdDeUrl(
          'https://mm.example/api/files/pbc_123/abcdefghijklmno/foto.jpg?thumb=200x200',
        ),
        'abcdefghijklmno',
      );
      expect(
        api.fotoIdDeUrl(
          'https://images.openfoodfacts.org/images/products/848/x.200.jpg',
        ),
        isNull,
      );
      expect(api.fotoIdDeUrl(null), isNull);
    },
  );
}
