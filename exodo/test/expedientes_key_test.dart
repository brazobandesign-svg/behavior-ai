import 'package:flutter_test/flutter_test.dart';
import 'helpers/pure_logic_helpers.dart';

void main() {
  group('expedientesPrefsKey (llave por uid)', () {
    test('la llave cambia con el uid', () {
      final keyA = expedientesPrefsKey(uid: 'uid-aaaa-1111');
      final keyB = expedientesPrefsKey(uid: 'uid-bbbb-2222');
      expect(keyA, isNot(equals(keyB)));
    });

    test('incluye el uid en la llave', () {
      expect(
        expedientesPrefsKey(uid: 'abc-123'),
        'exodo_local_expedientes_abc-123',
      );
    });

    test('uid null o vacío cae a scope anon', () {
      expect(expedientesPrefsKey(), 'exodo_local_expedientes_anon');
      expect(expedientesPrefsKey(uid: null), 'exodo_local_expedientes_anon');
      expect(expedientesPrefsKey(uid: ''), 'exodo_local_expedientes_anon');
    });

    test('dos usuarios nunca comparten caché (aislamiento por cuenta)', () {
      final users = List.generate(10, (i) => 'user-$i');
      final keys = users.map((u) => expedientesPrefsKey(uid: u)).toSet();
      expect(keys.length, users.length, reason: 'cada uid debe producir llave única');
    });
  });
}
