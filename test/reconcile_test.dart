import 'package:flutter_test/flutter_test.dart';
import 'package:multimarket/models.dart';
import 'package:multimarket/sync/reconcile.dart';

Item it(
  String id, {
  String name = 'Leche',
  bool done = false,
  int urg = 2,
  int ms = 0,
}) =>
    Item(id: id, name: name, cold: false, done: done, urg: urg, updatedMs: ms);

void main() {
  test('local nuevo se sube; remoto nuevo se baja', () {
    final p = reconcile(
      local: [it('a')],
      remote: [it('b', name: 'Pan')],
      last: {},
      now: 5,
    );
    expect(p.pushCreate.map((i) => i.id), ['a']);
    expect(p.addLocal.map((i) => i.id), ['b']);
    expect(p.sigs.keys.toSet(), {'a', 'b'});
  });

  test('solo cambia el servidor → se baja; solo cambia local → se sube', () {
    final base = it('a');
    final last = {'a': sigOf(base)};
    var p = reconcile(
      local: [it('a')],
      remote: [it('a', done: true)],
      last: last,
      now: 9,
    );
    expect(p.updateLocal.single.done, isTrue);
    expect(p.pushUpdate, isEmpty);

    p = reconcile(
      local: [it('a', done: true)],
      remote: [it('a')],
      last: last,
      now: 9,
    );
    expect(p.pushUpdate.single.done, isTrue);
    expect(p.pushUpdate.single.updatedMs, 9);
    expect(p.updateLocal, isEmpty);
  });

  test('si cambian los dos gana el cambio local (último en sincronizar)', () {
    final last = {'a': sigOf(it('a'))};
    final p = reconcile(
      local: [it('a', urg: 1)],
      remote: [it('a', done: true)],
      last: last,
      now: 7,
    );
    expect(p.pushUpdate.single.urg, 1);
    expect(p.updateLocal, isEmpty);
  });

  test(
    'borrados: el borrado remoto quita lo local, el local borra lo remoto',
    () {
      final last = {'a': sigOf(it('a')), 'b': sigOf(it('b'))};
      final p = reconcile(
        local: [it('a')],
        remote: [it('b')],
        last: last,
        now: 1,
      );
      expect(p.removeLocal, ['a'], reason: 'a ya no está en el servidor');
      expect(p.pushDelete, ['b'], reason: 'b ya no está en local');
    },
  );

  test('editado en local mientras otro lo borraba: se recrea', () {
    final last = {'a': sigOf(it('a'))};
    final p = reconcile(
      local: [it('a', done: true)],
      remote: [],
      last: last,
      now: 3,
    );
    expect(p.pushCreate.single.id, 'a');
    expect(p.removeLocal, isEmpty);
  });

  test('primera vez que se ven: gana el más reciente', () {
    var p = reconcile(
      local: [it('a', done: true, ms: 10)],
      remote: [it('a', ms: 5)],
      last: {},
      now: 20,
    );
    expect(p.pushUpdate, hasLength(1));
    p = reconcile(
      local: [it('a', done: true, ms: 1)],
      remote: [it('a', ms: 5)],
      last: {},
      now: 20,
    );
    expect(p.updateLocal, hasLength(1));
  });

  test('sin cambios → plan vacío', () {
    final i = it('a');
    final p = reconcile(
      local: [i],
      remote: [it('a')],
      last: {'a': sigOf(i)},
      now: 1,
    );
    expect(p.vacio, isTrue);
  });
}
