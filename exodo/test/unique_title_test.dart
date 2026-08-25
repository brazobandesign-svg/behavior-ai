import 'package:flutter_test/flutter_test.dart';
import 'helpers/pure_logic_helpers.dart';

void main() {
  group('makeUniqueTitle (deduplicación "Título ·2")', () {
    test('título nuevo se devuelve sin cambios', () {
      expect(makeUniqueTitle('Hola', <String>{}), 'Hola');
      expect(makeUniqueTitle('Hola', {'Otro título'}), 'Hola');
    });

    test('título duplicado recibe sufijo ·2', () {
      expect(makeUniqueTitle('Hola', {'Hola'}), 'Hola ·2');
    });

    test('encadena ·3, ·4... si ya existen', () {
      final existing = {'Hola', 'Hola ·2'};
      expect(makeUniqueTitle('Hola', existing), 'Hola ·3');

      final existing4 = {'Hola', 'Hola ·2', 'Hola ·3', 'Hola ·4'};
      expect(makeUniqueTitle('Hola', existing4), 'Hola ·5');
    });

    test('usa el primer hueco libre en la secuencia', () {
      // Existen Hola y Hola ·3 pero no Hola ·2 -> debe dar Hola ·2.
      final existing = {'Hola', 'Hola ·3'};
      expect(makeUniqueTitle('Hola', existing), 'Hola ·2');
    });

    test('normaliza espacios antes de comparar', () {
      expect(makeUniqueTitle('  Hola  ', {'Hola'}), 'Hola ·2');
      expect(makeUniqueTitle('Hola', {'  Hola '}), 'Hola ·2');
    });

    test('string vacío o solo espacios no se deduplica', () {
      expect(makeUniqueTitle('', {'', ' ·2'}), '');
      expect(makeUniqueTitle('   ', {}), '');
    });

    test('formato del sufijo es exactamente " ·N" (espacio + punto medio)', () {
      final result = makeUniqueTitle('Chat', {'Chat'});
      expect(result.startsWith('Chat ·'), isTrue);
      expect(result.endsWith('2'), isTrue);
      expect(result.length, 'Chat ·2'.length);
    });
  });
}
