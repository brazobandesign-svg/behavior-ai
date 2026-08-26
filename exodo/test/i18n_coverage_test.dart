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

  // P2 (2026-08-26): _ht se re-tradujó de francés heredado a Kreyòl real.
  // Guard de regresión: si alguien revierte el diccionario al stub francés,
  // estos asserts fallan antes de llegar al dispositivo.
  test('P2 i18n: _ht en Kreyòl real (sin francés heredado)', () {
    final ht = translationsFor('ht');
    const expected = <String, String>{
      'greeting.morning': 'Bonjou',
      'greeting.afternoon': 'Bonswa',
      'greeting.evening': 'Bonswa',
      'drawer.search_chats': 'Chèche',
      'drawer.starred': 'Mete anlè',
      'drawer.incognito': 'Mòd Enkoyito',
      'drawer.light_mode': 'Mòd Klè',
      'drawer.dark_mode': 'Mòd Nwa',
      'ctx.rename': 'Chanje non',
      'act.copy': 'Kopye',
      'act.like': 'M renmen',
      'common.yes': 'Wi',
      'lang.sheet_title': 'Lang aplikasyon an',
      'starter.1': 'Rezime nouvèl jodi a',
      'starter.4': 'Lide pou yon pwoje inovatè',
      'settings.logout': 'Dekonekte',
    };
    expected.forEach((k, v) {
      expect(ht[k], v, reason: '_ht["$k"] debe ser Kreyòl "$v", no francés heredado');
    });
    // Marcas intocables (regla de nombres propios).
    expect(ht['app.title'], anyOf(contains('Éxodo'), contains('Exodo')));
    expect(ht['widget.square_genesis'], contains('Genesis'));
  });

  test('P2 i18n: sin fugas de inglés fuera de _en (Settings modal)', () {
    final fr = translationsFor('fr');
    expect(fr['settings.title'], 'Paramètres');
    expect(fr['settings.profile'], 'Profil');
    final ht = translationsFor('ht');
    expect(ht['settings.title'], 'Paramèt');
  });
}
