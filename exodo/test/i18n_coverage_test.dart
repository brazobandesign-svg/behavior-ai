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
    // 2026-08-28: rebranding de modelos — G1.1/XPi sustituyen a las
    // variantes anteriores (Genesis/Hazak/Ehyeh/Origo) por decisión de producto.
    expect(ht['widget.square_genesis'], contains('G1.1'));
  });

  test('P2 i18n: sin fugas de inglés fuera de _en (Settings modal)', () {
    final fr = translationsFor('fr');
    expect(fr['settings.title'], 'Paramètres');
    expect(fr['settings.profile'], 'Profil');
    final ht = translationsFor('ht');
    expect(ht['settings.title'], 'Paramèt');
  });

  // ────────────────────────────────────────────────────────────────────────────
  // [Punto 7] Paridad de las claves de artefactos (acciones, pestañas, tooltips)
  // Criterio 3: en en/fr/ht las pestañas y botones deben mostrar el idioma.
  // ────────────────────────────────────────────────────────────────────────────
  test('P7 i18n: las 21 claves de artefactos existen y no están vacías en los 14 locales', () {
    const codes = ['es','en','fr','ht','pt','pt_BR','it','de','ru','zh','ja','ar','ko','hi'];
    const keys = [
      'artifacts.action_preview', 'artifacts.action_save',
      'artifacts.action_saving', 'artifacts.action_saved',
      'github.commit_chip',      'artifacts.tab_preview',
      'artifacts.tab_code',      'artifacts.tooltip_export',
      'artifacts.no_preview_desc','artifacts.search_hint',
      'artifacts.table_empty',   'artifacts.export_sheet_title',
      'artifacts.export_sheet_desc','artifacts.export_na',
      'artifacts.error_export',  'artifacts.web_link_failed',
      'artifacts.error_publish', 'artifacts.generating_link',
      'artifacts.original_chat_missing','artifacts.error_share',
      'artifacts.export_desc_web','artifacts.export_desc_pdf',
      'artifacts.export_desc_docx','artifacts.export_desc_xlsx',
      'artifacts.export_desc_html',
    ];
    for (final code in codes) {
      final map = translationsFor(code);
      for (final k in keys) {
        expect(map[k]?.trim(), allOf(isNotNull, isNot(isEmpty)),
            reason: '$code carece de $k');
      }
    }
  });

  test('P7 i18n: valores exactos en, fr, ht (criterio 3 del auditor)', () {
    final en = translationsFor('en');
    expect(en['artifacts.action_preview'], 'Preview');
    expect(en['artifacts.action_save'], 'Save to Records');
    expect(en['artifacts.tab_preview'], 'Preview');
    expect(en['artifacts.tab_code'], 'Code');
    expect(en['artifacts.open_fullscreen'], 'Open');
    expect(en['act.copy'], 'Copy');
    expect(en['github.commit_chip'], 'Commit to GitHub');

    final fr = translationsFor('fr');
    expect(fr['artifacts.tab_preview'], 'Aperçu');
    expect(fr['artifacts.tab_code'], 'Code');
    expect(fr['artifacts.action_preview'], 'Aperçu');
    expect(fr['artifacts.action_save'], 'Enregistrer dans Dossiers');
    expect(fr['github.commit_chip'], 'Commiter sur GitHub');

    final ht = translationsFor('ht');
    expect(ht['artifacts.tab_preview'], 'Previzyon');
    expect(ht['artifacts.tab_code'], 'Kòd');
    expect(ht['artifacts.action_preview'], 'Previzyon');
    expect(ht['artifacts.action_save'], 'Sove nan Fichye');
    expect(ht['github.commit_chip'], 'Mete sou GitHub');
  });

  test('P7 i18n: las claves del P7 se incluyen en el universo ES (no colisionan)', () {
    final es = translationsFor('es');
    expect(es['artifacts.action_preview'], 'Vista previa');
    expect(es['artifacts.tab_preview'], 'Vista previa');
    expect(es['artifacts.tab_code'], 'Código');
    expect(es['artifacts.action_save'], 'Guardar en Expedientes');
  });
}
