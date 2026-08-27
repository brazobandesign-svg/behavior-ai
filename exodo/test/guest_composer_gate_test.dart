// [Punto 6] Guest × Composer: banner de capacidad, chip de modelos y
// UpgradeModal bajo llave.
//
// Criterios del auditor:
//   · Guest: chip con candado 🔒, tap = sólo háptica (hoja NO abre).
//   · Guest: el banner "More capacity with..." no aparece.
//   · Guest: UpgradeModal no abre BAJO NINGUNA circunstancia.
//
// Compuertas replicadas exactamente de producción en pure_logic_helpers.dart.
import 'package:flutter_test/flutter_test.dart';
import 'helpers/pure_logic_helpers.dart';

void main() {
  group('P6-Guest · banner "More capacity with..."', () {
    test('Referencia: autenticado free con perfil y flag activo → visible', () {
      expect(
        bannerCapacityVisible(
          showTab2Banner: true,
          isIncognito: false,
          isPro: false,
          isGuestUser: false,
          hasProfile: true,
        ),
        isTrue,
      );
    });

    test('Invitado NUNCA lo ve, tenga o no perfil', () {
      for (final hasProfile in [true, false]) {
        expect(
          bannerCapacityVisible(
            showTab2Banner: true,
            isIncognito: false,
            isPro: false,
            isGuestUser: true,
            hasProfile: hasProfile,
          ),
          isFalse,
          reason: 'hasProfile=$hasProfile',
        );
      }
    });

    test('Los otros bloqueos históricos siguen operativos (sin regresión)', () {
      const base = (
        showTab2Banner: true,
        isIncognito: false,
        isPro: false,
        isGuestUser: false,
        hasProfile: true,
      );
      expect(bannerCapacityVisible(showTab2Banner: false, isIncognito: base.isIncognito, isPro: base.isPro, isGuestUser: base.isGuestUser, hasProfile: base.hasProfile), isFalse);
      expect(bannerCapacityVisible(showTab2Banner: true, isIncognito: true, isPro: base.isPro, isGuestUser: base.isGuestUser, hasProfile: base.hasProfile), isFalse);
      expect(bannerCapacityVisible(showTab2Banner: true, isIncognito: base.isIncognito, isPro: true, isGuestUser: base.isGuestUser, hasProfile: base.hasProfile), isFalse);
      expect(bannerCapacityVisible(showTab2Banner: true, isIncognito: base.isIncognito, isPro: base.isPro, isGuestUser: base.isGuestUser, hasProfile: false), isFalse);
    });
  });

  group('P6-Guest · chip del selector de modelos (candado 🔒)', () {
    test('Invitado → candado: tap mudo con háptica, sin hoja', () {
      expect(modelChipLocked(isIncognito: false, isGuestUser: true), isTrue);
      expect(modelSheetCanOpen(isIncognito: false, isGuestUser: true), isFalse);
    });

    test('"Idéntico al modo incógnito": mismo veredicto que el invitado', () {
      expect(
        modelChipLocked(isIncognito: true, isGuestUser: false),
        modelChipLocked(isIncognito: false, isGuestUser: true),
      );
      expect(
        modelSheetCanOpen(isIncognito: true, isGuestUser: false),
        modelSheetCanOpen(isIncognito: false, isGuestUser: true),
      );
    });

    test('Autenticado normal → flecha, hoja abrible (sin regresión)', () {
      expect(modelChipLocked(isIncognito: false, isGuestUser: false), isFalse);
      expect(modelSheetCanOpen(isIncognito: false, isGuestUser: false), isTrue);
    });

    test('Matriz completa incógnito × invitado coherente tap↔sheet↔icono', () {
      for (final inc in [true, false]) {
        for (final guest in [true, false]) {
          final locked = modelChipLocked(isIncognito: inc, isGuestUser: guest);
          final sheetOpens =
              modelSheetCanOpen(isIncognito: inc, isGuestUser: guest);
          // Coherencia interna: si hay candado, la hoja nunca abre (y viceversa).
          expect(locked, isNot(sheetOpens),
              reason: 'inc=$inc guest=$guest');
        }
      }
    });
  });

  group('P6-Guest · UpgradeModal bajo ninguna circunstancia', () {
    test('Guard central: invitado → el modal jamás se dibuja', () {
      expect(upgradeModalOpens(isGuestUser: true), isFalse);
    });

    test('Autenticado → modal operativo (sin regresión)', () {
      expect(upgradeModalOpens(isGuestUser: false), isTrue);
    });

    test('Coherencia P4×P6: para invitados modal cerrado Y checkout mute', () {
      for (final isOnline in [true, false]) {
        final opens = upgradeModalOpens(isGuestUser: true);
        final checkoutNoOp =
            purchaseButtonIsNoOp(isGuestUser: true, isOnline: isOnline);
        expect(opens, isFalse);
        expect(checkoutNoOp, isTrue);
        // Aunque un trigger olvidado abriera show(), el guard central es
        // exactamente upgradeModalOpens; y a pesar de todo startCheckout
        // seguiría devolviendo false (doble red de seguridad).
        expect(canStartCheckout(jwt: null, isOnline: isOnline), isFalse);
      }
    });

    test('Coherencia P6: con chip bloqueado, ni composer ni burbuja llegan lejos',
        () {
      // Cadena defensiva para invitado:
      //   chip mudo → _showModelSheet cerrado → tile Pro inalcanzable;
      //   onUpgradeTap guard + UpgradeModal.show guard = doble llave;
      //   message_bubble/drawer quedan neutralizados por el guard central.
      final guestLocked = modelChipLocked(isIncognito: false, isGuestUser: true);
      final sheetClosed =
          !modelSheetCanOpen(isIncognito: false, isGuestUser: true);
      final modalMuted = !upgradeModalOpens(isGuestUser: true);
      expect(guestLocked && sheetClosed && modalMuted, isTrue);
    });
  });
}
