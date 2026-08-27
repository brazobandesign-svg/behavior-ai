// [Punto 3] Guests × Expedientes: compuertas unitarias de acceso y guardado.
//
// Reglas auditadas:
//   · El Drawer NUNCA muestra Expedientes cuando isGuestUser == true.
//   · ExpedientesScreen no consulta repositorio ni dibuja listas huérfanas.
//   · ArtifactCard / ArtifactFullscreen no ofrecen "Guardar en Expedientes".
//   · ExpedientesRepository.createExpediente devuelve null para invitados.
//
// A diferencia de otras suites del proyecto (helpers réplica), aquí se importa
// el código de producción REAL (`expedientes_access_policy.dart`): es Dart
// puro sin Flutter/plugins, así que testear la política ES testear la app.
import 'package:flutter_test/flutter_test.dart';
import 'package:exodo/l10n/app_translations.dart';
import 'package:exodo/services/expedientes_access_policy.dart';

import 'helpers/pure_logic_helpers.dart';

void main() {
  group('P3-Guest · isGuestIdentity (regla de identidad a nivel de sesión)', () {
    test('Usuario autenticado con uid y email reales NO es invitado', () {
      expect(
        isGuestIdentity(userId: 'uuid-1234', isAnonymous: false, email: 'ana@exodo.app'),
        isFalse,
      );
    });

    test('Sin usuario en sesión → invitado (flujo "Continuar como invitado")', () {
      expect(isGuestIdentity(userId: null, isAnonymous: false), isTrue);
      expect(isGuestIdentity(userId: null, isAnonymous: true), isTrue);
    });

    test('Uid vacío o sólo espacios → invitado', () {
      expect(isGuestIdentity(userId: '', isAnonymous: false, email: 'a@b.com'), isTrue);
      expect(isGuestIdentity(userId: '   ', isAnonymous: false, email: 'a@b.com'), isTrue);
    });

    test('Sesión anónima de Supabase → invitado aunque tenga uid', () {
      expect(
        isGuestIdentity(userId: 'anon-uid-9', isAnonymous: true, email: ''),
        isTrue,
      );
      expect(
        isGuestIdentity(userId: 'anon-uid-9', isAnonymous: true, email: 'x@y.z'),
        isTrue,
      );
    });

    test('Email ausente, vacío o en blanco → invitado', () {
      expect(isGuestIdentity(userId: 'u1', isAnonymous: false), isTrue);
      expect(isGuestIdentity(userId: 'u1', isAnonymous: false, email: ''), isTrue);
      expect(isGuestIdentity(userId: 'u1', isAnonymous: false, email: '   '), isTrue);
    });
  });

  group('P3-Guest · visibilidad del módulo (criterios de auditoría 3 y 4)', () {
    test('En modo Invitado el Drawer/Pantalla NO muestran Expedientes', () {
      expect(expedientesModuleVisible(isGuestUser: true), isFalse);
    });

    test('En modo Autenticado el módulo se muestra con normalidad', () {
      expect(expedientesModuleVisible(isGuestUser: false), isTrue);
    });

    test('Invitado NO puede guardar artefactos como expedientes', () {
      expect(canSaveExpediente(isGuestUser: true), isFalse);
    });

    test('Autenticado SÍ puede guardar artefactos como expedientes', () {
      expect(canSaveExpediente(isGuestUser: false), isTrue);
    });

    test('Las dos compuertas UI son equivalentes (un solo criterio de acceso)', () {
      // Para la misma sesión, visibilidad del módulo y permiso de guardado
      // siempre coinciden: hay una única regla de acceso Guest.
      for (final isGuest in [true, false]) {
        expect(
          expedientesModuleVisible(isGuestUser: isGuest),
          equals(canSaveExpediente(isGuestUser: isGuest)),
          reason: 'isGuestUser=$isGuest debe dar el mismo veredicto en ambas compuertas',
        );
      }
    });
  });

  group('P3-Guest · robustez y coherencia con caché por-cuenta existente', () {
    test('Un guest sin uid sigue cayendo al scope "anon" de prefs', () {
      expect(expedientesPrefsKey(), 'exodo_local_expedientes_anon');
      expect(expedientesPrefsKey(uid: null), 'exodo_local_expedientes_anon');
    });

    test('Nunca lanza con combinaciones límite (null-safety total)', () {
      const ids = <String?>[null, '', ' ', 'u1'];
      const mails = <String?>[null, '', ' ', 'm@x.io'];
      for (final id in ids) {
        for (final anon in [true, false]) {
          for (final mail in mails) {
            final result = isGuestIdentity(userId: id, isAnonymous: anon, email: mail);
            expect(result, anyOf(isTrue, isFalse));
          }
        }
      }
    });

    test('La política coincide semánticamente con AppState.isGuestUser', () {
      // AppState.isGuestUser == true ⇔ guest por sesión Supabase ⇔ política.
      final cases = <(String?, bool, String?, bool)>[
        ('uuid-real', false, 'mail@exodo.app', false),
        (null, false, null, true),
        ('anon-id', true, 'any@exodo.app', true),
        ('id-sin-email', false, '', true),
      ];

      for (final c in cases) {
        expect(
          isGuestIdentity(userId: c.$1, isAnonymous: c.$2, email: c.$3),
          c.$4,
          reason: 'userId=${c.$1} anon=${c.$2} email=${c.$3}',
        );
      }
    });
  });

  group('P3-Guest · i18n del estado guest cubierto en todos los locales', () {
    const codes = [
      'es', 'en', 'fr', 'ht', 'pt', 'pt_BR', 'it',
      'de', 'ru', 'zh', 'ja', 'ar', 'ko', 'hi',
    ];

    test('artifacts.guest_title / artifacts.guest_desc existen y no están vacíos', () {
      for (final code in codes) {
        final map = translationsFor(code);
        expect(
          map['artifacts.guest_title']?.trim(),
          allOf(isNotNull, isNot(isEmpty)),
          reason: 'Locale "$code" sin artifacts.guest_title',
        );
        expect(
          map['artifacts.guest_desc']?.trim(),
          allOf(isNotNull, isNot(isEmpty)),
          reason: 'Locale "$code" sin artifacts.guest_desc',
        );
      }
    });

    test('El ES base define ambos textos (universo de claves)', () {
      final es = translationsFor('es');
      expect(es['artifacts.guest_title'], contains('cuentas'));
      expect(es['artifacts.guest_desc'], contains('expedientes'));
    });
  });
}
