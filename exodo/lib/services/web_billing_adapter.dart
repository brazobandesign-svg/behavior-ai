import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'supabase_service.dart';

/// Resultado de procesar los parámetros de retorno tras volver de Stripe.
class WebBillingReturn {
  /// Estado clasificado del retorno.
  final WebBillingReturnKind kind;

  /// ID de la Checkout Session (`?session_id=...`). Null si Stripe no lo envió.
  final String? sessionId;

  /// URI exacta de la que se leyeron los parámetros (solo diagnóstico).
  final Uri sourceUri;

  /// Plan vigente en Supabase tras el refresco de perfil (si se llegó a consultar).
  /// Mutable: se completa durante el proceso de retorno (resultado parcial útil).
  String? profilePlan;

  WebBillingReturn({
    required this.kind,
    required this.sourceUri,
    this.sessionId,
    this.profilePlan,
  });

  bool get isSuccess => kind == WebBillingReturnKind.success;
  bool get isCanceled => kind == WebBillingReturnKind.canceled;
}

enum WebBillingReturnKind { success, canceled }

/// Adaptador de facturación para navegadores (Flutter Web).
///
/// En web la app es una SPA: abrir Stripe en una pestaña nueva fragmenta la
/// sesión (el token queda en localStorage de la primera pestaña y la segunda
/// arranca sin login). La navegación correcta es en la MISMA pestaña — el
/// equivalente a `window.location.href = url` — de modo que Stripe redirija
/// de vuelta sobre la propia SPA con `?session_id=...&status=success`.
///
/// Responsabilidades exclusivas de web (`kIsWeb == true`):
///   • `openCheckoutInSameTab`: navega al Checkout en `_self` vía url_launcher
///     (`webOnlyWindowName: '_self'`), que internamente asigna la URL a la
///     ventana actual: sin ventanas emergentes ni bloqueos de pop-up.
///   • `processReturnParameters`: al aterrizar de vuelta, inspecciona
///     `Uri.base`, clasifica éxito/cancelación y refresca el perfil desde
///     Supabase. Usa reintentos cortos porque el webhook de Stripe tarda unos
///     segundos en escribir `profiles.plan = 'hazak'` mientras el navegador ya
///     regresó. Idempotente por `session_id` dentro de la vida de la página.
///
/// POLÍTICA DE SILENCIO EN PAGOS [Punto 4]: ningún método muestra SnackBars,
/// diálogos ni logs de error hacia la UI; todo fallo se traga silenciosamente.
///
/// Cableado opcional para el dueño del arranque/pantallas (una línea):
///   WebBillingAdapter.onProcessed = (r) => r.isSuccess ? ... : null;
///
/// En móvil (`!kIsWeb`) StripeService NO delega aquí: el flujo existente con
/// navegador externo permanece 100% inalterado.
class WebBillingAdapter {
  WebBillingAdapter._();

  /// `true` solo cuando corre como SPA en navegador.
  static bool get isActive => kIsWeb;

  /// Hook opcional para quien integre UI/estado (p.ej. AppState):
  /// se invoca una vez por retorno clasificado, después del refresco de perfil.
  static void Function(WebBillingReturn info)? onProcessed;

  /// session_id ya procesados en esta vida de página (idempotencia barata:
  /// un reload limpia el set, pero eso solo produce un fetch extra inofensivo).
  static final Set<String> _processedSessionIds = <String>{};

  /// Abre [url] (Stripe Checkout) en la MISMA pestaña del navegador.
  ///
  /// Equivalente web a `window.location.href = url`. Si por robustez se invoca
  /// fuera de web, cae con gracia al comportamiento móvil original (navegador
  /// externo) para no romper nada.
  static Future<bool> openCheckoutInSameTab(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('https') && !uri.isScheme('http'))) {
      return false;
    }
    try {
      if (!kIsWeb) {
        // Fallback defensivo: igual al camino histórico de móvil.
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return await launchUrl(uri, webOnlyWindowName: '_self');
    } catch (_) {
      // Navegación fallida → silencio total; la UI decide qué mostrar (nada).
      return false;
    }
  }

  /// Procesa los parámetros de retorno presentes en la URL actual del
  /// navegador (`?session_id=...&status=success` o `/success` / `/canceled`).
  ///
  /// - Solo actúa en web (`kIsWeb`); en otras plataformas retorna null.
  /// - Si no hay parámetros de retorno, retorna null inmediatamente (no-op).
  /// - Con éxito: consulta el perfil a Supabase reintentando brevemente hasta
  ///   que el webhook publique el plan, y notifica vía `onProcessed`.
  /// - Con cancelación: solo clasifica y notifica; no hay red que esperar.
  static Future<WebBillingReturn?> processReturnParameters({
    int maxProfileAttempts = 4,
  }) async {
    if (!kIsWeb) return null;

    final returnInfo = classifyReturnUrl(Uri.base);
    if (returnInfo == null) return null;

    // Idempotencia: si esta sesión de checkout ya fue consumida en esta carga,
    // salir sin repetir trabajo. Con cancelaciones no hay sesión asociada.
    final sid = returnInfo.sessionId;
    if (sid != null && sid.isNotEmpty) {
      if (_processedSessionIds.contains(sid)) return null;
      _processedSessionIds.add(sid);
    }

    // Éxito: dar al webhook de Stripe una ventana corta para escribir el plan.
    // Silencioso siempre: getProfile() tiene fallback resiliente propio.
    if (returnInfo.isSuccess) {
      for (var attempt = 0; attempt < maxProfileAttempts; attempt++) {
        try {
          final profile = await SupabaseService.getProfile();
          if (profile != null && profile.plan.isNotEmpty) {
            returnInfo.profilePlan = profile.plan;
            if (profile.plan == 'hazak') break; // Webhook confirmado.
          }
        } catch (_) {
          // Red/RLS caída temporalmente → reintentar en silencio.
        }
        if (attempt + 1 >= maxProfileAttempts) break;
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    }

    final cb = onProcessed;
    if (cb != null) {
      try {
        cb(returnInfo);
      } catch (e) {
        debugPrint('[WebBillingAdapter] onProcessed listener lanzó error (silenciado): $e');
      }
    }
    return returnInfo;
  }

  /// Clasifica [uri] como retorno de Stripe o null si es una URL cualquiera
  /// de la app sin señal de checkout.
  ///
  /// Señales tolerantes:
  ///   • success: `session_id` presente, `status=success|complete|completed`
  ///     o ruta terminando en `/success`.
  ///   • canceled: `status=canceled|cancelled|cancel` o ruta `/canceled`.
  static WebBillingReturn? classifyReturnUrl(Uri uri) {
    final params = uri.queryParameters;
    final sid = params['session_id']?.trim() ?? '';
    final status = (params['status'] ?? '').trim().toLowerCase();
    final path = uri.path.toLowerCase();

    final isSuccess =
        sid.isNotEmpty || status == 'success' || status == 'complete' || status == 'completed' || path.endsWith('/success');
    final isCanceled = status == 'canceled' || status == 'cancelled' || status == 'cancel' || path.endsWith('/canceled');

    if (isSuccess) {
      // session_id vacío + status exitoso sigue siendo éxito legítimo, aunque
      // hoy el backend siempre envía el id ({CHECKOUT_SESSION_ID}).
      return WebBillingReturn(
        kind: WebBillingReturnKind.success,
        sessionId: sid.isNotEmpty ? sid : null,
        sourceUri: uri,
      );
    }
    if (isCanceled) {
      return WebBillingReturn(
        kind: WebBillingReturnKind.canceled,
        sessionId: sid.isNotEmpty ? sid : null,
        sourceUri: uri,
      );
    }
    return null;
  }
}
