// [Punto 4] Política de SILENCIO en pagos: Guest/offline × Plan Pro.
//
// Criterio del auditor: sin conexión o siendo invitado, presionar el botón de
// pagar el Plan Pro produce CERO pop-ups, SnackBars o diálogos nativos.
//
// Las compuertas aquí son réplicas exactas de producción (convención del repo):
// - StripeService.startCheckoutSession → guard interno JWT + conectividad.
// - UpgradeModal "Adquirir Pro" (model_selector.dart) → guard invitado/offline.
// - DrawerMenu._showBillingModal portal → guard offline.
import 'package:flutter_test/flutter_test.dart';
import 'helpers/pure_logic_helpers.dart';

void main() {
  group('P4-Billing · StripeService.startCheckoutSession (guard silencioso)', () {
    test('Invitado (sin sesión/JWT) y con internet → NO hay checkout', () {
      expect(canStartCheckout(jwt: null, isOnline: true), isFalse);
    });

    test('Autenticado pero SIN conexión → NO hay checkout (retorno limpio)', () {
      expect(canStartCheckout(jwt: 'jwt-valido-123', isOnline: false), isFalse);
    });

    test('Sin sesión Y sin conexión → NO hay checkout (doble falla)', () {
      expect(canStartCheckout(jwt: null, isOnline: false), isFalse);
    });

    test('JWT vacío cuenta como sin sesión → NO hay checkout', () {
      expect(canStartCheckout(jwt: '', isOnline: true), isFalse);
    });

    test('Autenticado Y conectado → único caso en que el checkout procede', () {
      expect(canStartCheckout(jwt: 'jwt-valido-123', isOnline: true), isTrue);
    });
  });

  group('P4-Billing · botón "Adquirir Pro" (UpgradeModal)', () {
    test('Invitado u offline → el botón es no-op silencioso (criterio auditor)', () {
      expect(purchaseButtonIsNoOp(isGuestUser: true, isOnline: true), isTrue);
      expect(purchaseButtonIsNoOp(isGuestUser: true, isOnline: false), isTrue);
      expect(purchaseButtonIsNoOp(isGuestUser: false, isOnline: false), isTrue);
    });

    test('Autenticado y conectado → el botón reacciona normalmente', () {
      expect(purchaseButtonIsNoOp(isGuestUser: false, isOnline: true), isFalse);
    });

    test('Matriz exhaustiva invitado×conexión coincide con el guard del servicio', () {
      // Coherencia UI ↔ servicio: para usuario autenticado con JWT presente,
      // "botón reacciona" ⇔ "el servicio lanzaría checkout".
      for (final isGuest in [true, false]) {
        for (final isOnline in [true, false]) {
          final uiReacts = !purchaseButtonIsNoOp(
            isGuestUser: isGuest,
            isOnline: isOnline,
          );
          final serviceProceeds = canStartCheckout(jwt: 'jwt-x', isOnline: isOnline);
          if (!isGuest) {
            expect(uiReacts, serviceProceeds, reason: 'isGuest=$isGuest online=$isOnline');
          }
        }
      }
    });
  });

  group('P4-Billing · portal de gestión (drawer, cuentas Pro)', () {
    test('Offline → no-op silencioso (antes mostraba SnackBar con el error)', () {
      expect(portalButtonIsNoOp(isOnline: false), isTrue);
    });

    test('Conectado → abre portal con normalidad', () {
      expect(portalButtonIsNoOp(isOnline: true), isFalse);
    });
  });

  group('P4-Billing · regla global: offline SIEMPRE bloquea en silencio', () {
    test('Sin conexión, ningún flujo de pago se ejecuta pase lo que pase', () {
      final authStates = [
        (isGuestUser: true, jwt: null as String?),
        (isGuestUser: true, jwt: 'jwt-anon'),
        (isGuestUser: false, jwt: null as String?),
        (isGuestUser: false, jwt: 'jwt-pro'),
      ];
      for (final a in authStates) {
        expect(canStartCheckout(jwt: a.jwt, isOnline: false), isFalse,
            reason: 'offline debe bloquear siempre (jwt=${a.jwt})');
        expect(portalButtonIsNoOp(isOnline: false), isTrue);
      }
    });
  });
}
