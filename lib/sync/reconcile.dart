import 'dart:convert';

import '../models.dart';

/// Firma de los campos que se sincronizan (excluye `updatedMs`).
String sigOf(Item i) => jsonEncode([
  i.name,
  i.cold,
  i.urg,
  i.done,
  i.storeId,
  i.price,
  i.barcode,
  i.imageUrl,
  i.genericKey,
  i.cantidad,
]);

class Plan {
  final addLocal = <Item>[]; // nuevos desde el servidor
  final updateLocal = <Item>[]; // el servidor manda
  final removeLocal = <String>[]; // borrados en el servidor
  final pushCreate = <Item>[];
  final pushUpdate = <Item>[];
  final pushDelete = <String>[]; // borrados en local
  final sigs = <String, String>{}; // firmas acordadas tras aplicar el plan

  bool get vacio =>
      addLocal.isEmpty &&
      updateLocal.isEmpty &&
      removeLocal.isEmpty &&
      pushCreate.isEmpty &&
      pushUpdate.isEmpty &&
      pushDelete.isEmpty;
}

/// Compara copia local, copia remota y la última firma sincronizada (`last`).
/// Gana el último cambio de cada producto; si solo cambió un lado, se propaga ese.
Plan reconcile({
  required List<Item> local,
  required List<Item> remote,
  required Map<String, String> last,
  int now = 0,
}) {
  final p = Plan();
  final rem = {for (final r in remote) r.id: r};
  final loc = {for (final l in local) l.id: l};

  for (final l in local) {
    final r = rem[l.id];
    final ls = sigOf(l), lastSig = last[l.id];
    if (r == null) {
      if (lastSig == null || ls != lastSig) {
        // nuevo en local, o editado en local mientras otro lo borraba: se (re)crea
        l.updatedMs = now;
        p.pushCreate.add(l);
        p.sigs[l.id] = ls;
      } else {
        p.removeLocal.add(l.id); // existía sincronizado y alguien lo borró
      }
      continue;
    }
    final rs = sigOf(r);
    if (ls == rs) {
      p.sigs[l.id] = ls;
    } else if (lastSig == null) {
      // primera vez que se ven los dos: el más reciente gana
      if (l.updatedMs > r.updatedMs) {
        l.updatedMs = now;
        p.pushUpdate.add(l);
        p.sigs[l.id] = ls;
      } else {
        p.updateLocal.add(r);
        p.sigs[l.id] = rs;
      }
    } else if (ls == lastSig) {
      p.updateLocal.add(r); // solo cambió el servidor
      p.sigs[l.id] = rs;
    } else if (rs == lastSig) {
      l.updatedMs = now; // solo cambió local
      p.pushUpdate.add(l);
      p.sigs[l.id] = ls;
    } else {
      // cambiaron ambos: gana el cambio local (el más reciente en el momento de sincronizar)
      l.updatedMs = now;
      p.pushUpdate.add(l);
      p.sigs[l.id] = ls;
    }
  }

  for (final r in remote) {
    if (loc.containsKey(r.id)) continue;
    if (last.containsKey(r.id)) {
      p.pushDelete.add(r.id); // existía sincronizado y se borró en local
    } else {
      p.addLocal.add(r);
      p.sigs[r.id] = sigOf(r);
    }
  }
  return p;
}
