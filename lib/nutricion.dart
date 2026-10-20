// Información nutricional de un producto (Open Food Facts). Siempre se guarda POR 100 g / 100 ml y el valor por envase o por
// ración se calcula a partir de ahí. Los datos son colaborativos y pueden tener errores: nunca sustituyen a la etiqueta.
import 'catalog.dart';

class Nutricion {
  const Nutricion({
    this.kcal,
    this.grasas,
    this.saturadas,
    this.hidratos,
    this.azucares,
    this.fibra,
    this.proteinas,
    this.sal,
    this.nutriscore,
    this.nova,
    this.unidad = 'g',
    this.envase,
    this.racion,
  });

  /// Todos por 100 g (o por 100 ml si `unidad` es `ml`).
  final double? kcal,
      grasas,
      saturadas,
      hidratos,
      azucares,
      fibra,
      proteinas,
      sal;

  /// Letra del Nutri-Score en minúscula ('a'..'e') y grupo NOVA (1..4), si Open Food Facts los tiene.
  final String? nutriscore;
  final int? nova;

  /// 'g' o 'ml': la referencia de los valores.
  final String unidad;

  /// Contenido del envase en g o ml (de `quantity`), para calcular «por envase».
  final double? envase;
  final String? racion; // texto de la ración, p. ej. «30 g»

  bool get hayDatos =>
      kcal != null ||
      grasas != null ||
      hidratos != null ||
      proteinas != null ||
      nutriscore != null;

  /// Multiplica los valores por 100 g por `cantidad`/100 (envase o ración).
  Nutricion para(double cantidad) {
    double? f(double? v) => v == null ? null : v * cantidad / 100;
    return Nutricion(
      kcal: f(kcal),
      grasas: f(grasas),
      saturadas: f(saturadas),
      hidratos: f(hidratos),
      azucares: f(azucares),
      fibra: f(fibra),
      proteinas: f(proteinas),
      sal: f(sal),
      unidad: unidad,
    );
  }

  factory Nutricion.fromOff(Map<String, dynamic> p) {
    final n = (p['nutriments'] as Map?)?.cast<String, dynamic>() ?? {};
    double? v(String k) {
      final x = n['${k}_100g'] ?? n[k];
      if (x is num) return x.toDouble();
      return double.tryParse('${x ?? ''}'.replaceAll(',', '.'));
    }

    // energía: kcal si está; si solo hay kJ, se convierte
    var kcal = v('energy-kcal');
    final kj = v('energy-kj') ?? v('energy');
    kcal ??= kj == null ? null : kj / 4.184;
    final q = parseQuantity(p['quantity'] as String?);
    final grado = '${p['nutriscore_grade'] ?? ''}'.toLowerCase();
    final nova = p['nova_group'];
    return Nutricion(
      kcal: kcal,
      grasas: v('fat'),
      saturadas: v('saturated-fat'),
      hidratos: v('carbohydrates'),
      azucares: v('sugars'),
      fibra: v('fiber'),
      proteinas: v('proteins'),
      sal: v('salt'),
      nutriscore: RegExp(r'^[a-e]$').hasMatch(grado) ? grado : null,
      nova: nova is num ? nova.toInt() : int.tryParse('${nova ?? ''}'),
      unidad: q?.u == 'ml' ? 'ml' : 'g',
      envase: q != null && (q.u == 'g' || q.u == 'ml') ? q.n : null,
      racion: (p['serving_size'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'kcal': kcal,
    'grasas': grasas,
    'saturadas': saturadas,
    'hidratos': hidratos,
    'azucares': azucares,
    'fibra': fibra,
    'proteinas': proteinas,
    'sal': sal,
    'nutriscore': nutriscore,
    'nova': nova,
    'unidad': unidad,
    'envase': envase,
    'racion': racion,
  };

  factory Nutricion.fromJson(Map<String, dynamic> j) {
    double? d(String k) => (j[k] as num?)?.toDouble();
    return Nutricion(
      kcal: d('kcal'),
      grasas: d('grasas'),
      saturadas: d('saturadas'),
      hidratos: d('hidratos'),
      azucares: d('azucares'),
      fibra: d('fibra'),
      proteinas: d('proteinas'),
      sal: d('sal'),
      nutriscore: j['nutriscore'] as String?,
      nova: (j['nova'] as num?)?.toInt(),
      unidad: (j['unidad'] as String?) ?? 'g',
      envase: d('envase'),
      racion: j['racion'] as String?,
    );
  }
}
