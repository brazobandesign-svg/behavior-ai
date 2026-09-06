import 'package:flutter_test/flutter_test.dart';
import 'package:exodo/services/guided_card.dart';

void main() {
  group('parseGuidedCard', () {
    test('parsea bloque completo con fence, recommend y labels', () {
      const content = '```exodo-options\n{"question":"¿Para quién es el regalo?","options":["Pareja","Amigo/a","Familiar","Compañero"],"recommend":0,"labels":{"recommended":"Exodo recomienda","other":"Otra opción","other_hint":"escribe tu propia respuesta","back":"Atrás"}}\n```';
      final card = parseGuidedCard(content);
      expect(card, isNotNull);
      expect(card!.question, '¿Para quién es el regalo?');
      expect(card.options.length, 4);
      expect(card.recommend, 0);
      expect(card.labels['recommended'], 'Exodo recomienda');
      expect(card.labels['other'], 'Otra opción');
      expect(card.labels['back'], 'Atrás');
    });

    test('parsea bloque SIN fence de cierre (modelos que olvidan el cierre)', () {
      const content = '```exodo-options\n{"question":"¿Para quién es el regalo?","options":["Pareja","Amigo/a","Familiar","Compañero"],"recommend":0}';
      final card = parseGuidedCard(content);
      expect(card, isNotNull);
      expect(card!.recommend, 0);
    });

    test('parsea con texto chunked y saltos de línea del stream', () {
      const content = '```\n```exodo-options\n{"question":"¿Q","options":[]}';
      expect(parseGuidedCard(content), isNull);
    });

    test('null con JSON incompleto (streaming a medias)', () {
      const content = '```exodo-options\n{"question":"¿Para quién';
      expect(parseGuidedCard(content), isNull);
    });

    test('null sin bloque', () {
      expect(parseGuidedCard('Hola, ¿qué tal?'), isNull);
    });

    test('isOptionsOnlyMessage: true para bloque puro, false con intro', () {
      expect(
        isOptionsOnlyMessage('```exodo-options\n{"question":"Q","options":["A","B"],"recommend":0}\n```'),
        isTrue,
      );
      expect(
        isOptionsOnlyMessage('Claro, primero:\n```exodo-options\n{"question":"Q","options":["A","B"]}\n```'),
        isFalse,
      );
    });
  });
}
