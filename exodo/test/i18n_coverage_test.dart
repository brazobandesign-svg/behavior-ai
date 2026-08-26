import 'package:flutter_test/flutter_test.dart';
import 'package:exodo/l10n/app_translations.dart';

void main() {
  test('P3 i18n: todos los locales cubren las 198 claves del universo ES', () {
    const codes = ['en', 'fr', 'ht', 'pt', 'pt_BR', 'it', 'de', 'ru', 'zh', 'ja', 'ar', 'ko', 'hi', 'es'];
    final base = translationsFor('es');
    expect(base.length, greaterThanOrEqualTo(198));

    for (final code in codes) {
      final map = translationsFor(code);
      final missing = base.keys.where((k) => !map.containsKey(k) || map[k]!.trim().isEmpty).toList();
      expect(
        missing,
        isEmpty,
        reason: 'Locale "$code" tiene claves vacías o faltantes: ${missing.take(10).join(', ')}',
      );
    }
  });

  test('P3 i18n: pt_BR ya no es un stub (cubre todo vía _pt + parche)', () {
    final br = translationsFor('pt_BR');
    expect(br.length, greaterThanOrEqualTo(198));
    expect(br['artifacts.title'], isNot(equals('artifacts.title')));
  });
}
