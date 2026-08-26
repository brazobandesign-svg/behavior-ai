import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exodo/l10n/app_translations.dart';
import 'package:exodo/l10n/localizations_fallback.dart';

Locale _toLocale(String code) {
  final parts = code.split('_');
  return parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
}

/// P1 (2026-08-26): regresión del crash "pantalla gris" en Kreyòl.
///
/// Causa raíz: flutter_localizations no soporta el código `ht`; con
/// MaterialApp.locale = Locale('ht') cualquier widget que invoque
/// MaterialLocalizations.of() lanzaba "No MaterialLocalizations found."
/// y ErrorWidget.builder pintaba la pantalla completa de gris.
void main() {
  testWidgets('P1 regresión: todos los locales de kAppLocales resuelven MaterialLocalizations', (tester) async {
    for (final appLocale in kAppLocales) {
      await tester.pumpWidget(
        MaterialApp(
          locale: _toLocale(appLocale.code),
          localizationsDelegates: kExodoLocalizationsDelegates,
          supportedLocales:
              kAppLocales.map((l) => _toLocale(l.code)).toList(growable: false),
          home: Scaffold(
            body: Center(
              child: IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'regresion',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Locale ${appLocale.code}: el árbol no debe lanzar '
            'excepciones de localización',
      );
      expect(find.byType(IconButton), findsOneWidget);
    }
  });

  test('P1 i18n: claves plan/banner presentes y no vacías en todos los locales', () {
    const keys = ['plan.free', 'plan.pro', 'banner.long_conversation', 'banner.new_chat'];
    const codes = ['en', 'fr', 'ht', 'pt', 'pt_BR', 'it', 'de', 'ru', 'zh', 'ja', 'ar', 'ko', 'hi'];

    for (final k in keys) {
      expect(translationsFor('es')[k]?.trim().isNotEmpty, isTrue, reason: 'Falta $k en es');
    }
    for (final code in codes) {
      final map = translationsFor(code);
      for (final k in keys) {
        expect(map[k]?.trim().isNotEmpty, isTrue, reason: 'Falta $k en $code');
      }
    }
  });

  testWidgets('P1 smoke: MaterialApp en ht renderiza sin ErrorWidget', (tester) async {
    final htTitle = translationsFor('ht')['app.title']!;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ht'),
        localizationsDelegates: kExodoLocalizationsDelegates,
        home: Scaffold(body: Center(child: Text(htTitle))),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Content rendering error'), findsNothing);
    expect(find.text(htTitle), findsOneWidget);
  });
}
