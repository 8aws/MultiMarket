import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/sources.dart';

void main() {
  nombresTests();
  offersTests();
  test('cadena normalizada desde marca OSM', () {
    expect(chainOf('Carrefour Express'), 'carrefour');
    expect(chainOf('Dia %'), 'dia');
    expect(chainOf('Mediterráneo'), isNull);
    expect(ownChainFromBrands('Hacendado'), 'mercadona');
  });

  test('distancia haversine ~ Madrid-Sol a Atocha', () {
    final d = haversineKm(40.4168, -3.7038, 40.4065, -3.6892);
    expect(d, inInclusiveRange(1.4, 1.9));
  });

  test('ventana de frío según bolsa', () {
    expect(Cooler.ninguna.minutes, 60);
    expect(Cooler.bolsaPetaca.minutes, greaterThan(Cooler.bolsa.minutes));
  });
}

void offersTests() {
  test('oferta: días restantes y caducidad', () {
    final hoy = DateTime.now();
    final a = Offer(
      key: 'k',
      name: 'Detergente',
      chain: 'dia',
      price: 9.99,
      until: hoy,
    );
    final b = Offer(
      key: 'k',
      name: 'Detergente',
      chain: 'dia',
      price: 9.99,
      until: hoy.add(const Duration(days: 3)),
    );
    final c = Offer(
      key: 'k',
      name: 'Detergente',
      chain: 'dia',
      price: 9.99,
      until: hoy.subtract(const Duration(days: 1)),
    );
    expect(a.daysLeft, 0);
    expect(a.active, isTrue);
    expect(b.daysLeft, 3);
    expect(c.active, isFalse);
    expect(Offer.fromJson(b.toJson()).price, 9.99);
  });
}

void nombresTests() {
  test('abrevia prefijos genéricos sin tocar el nombre propio', () {
    expect(
      shortStoreName('Supermercado Lo Compro Todo'),
      'Súper Lo Compro Todo',
    );
    expect(shortStoreName('Hipermercados Don Pepe'), 'Hiper Don Pepe');
    expect(shortStoreName('Mercadona'), 'Mercadona');
  });
}
