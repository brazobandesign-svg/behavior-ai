import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'chat_service.dart';
import 'connectivity_service.dart';
import 'supabase_service.dart';
import 'web_billing_adapter.dart';

/// Servicio de Stripe para Éxodo.
/// Crea Checkout Sessions y abre el portal de gestión.
///
/// [Punto 4] POLÍTICA DE SILENCIO EN PAGOS: ningún método de este servicio
/// muestra SnackBars ni diálogos nativos. Sin sesión iniciada (invitado) o
/// sin conexión el flujo simplemente NO OCURRE (retorno limpio `false`),
/// y la UI queda muda; puede añadir háptica suave si el botón se presiona.
class StripeService {
  static bool _isCheckingOut = false;

  static List<String> get _checkoutUrls {
    final list = <String>[];
    for (final c in ChatService.candidateUrls) {
      final sUrl = c.replaceAll('/api/chat', '/api/stripe/checkout');
      if (!list.contains(sUrl)) list.add(sUrl);
    }
    return list;
  }

  static List<String> get _portalUrls {
    final list = <String>[];
    for (final c in ChatService.candidateUrls) {
      final sUrl = c.replaceAll('/api/chat', '/api/stripe/portal');
      if (!list.contains(sUrl)) list.add(sUrl);
    }
    return list;
  }

  /// Crea una sesión de Stripe Checkout y retorna la URL generada.
  /// [isAnnual] determina si se crea una suscripción anual (true) o mensual (false).
  static Future<String?> createCheckoutSession({bool isAnnual = false}) async {
    final session = SupabaseService.client.auth.currentSession;
    final jwt = session?.accessToken;

    if (jwt == null) {
      throw Exception('Debes iniciar sesión para suscribirte');
    }

    Exception? lastError;
    for (final candidateUrl in _checkoutUrls) {
      try {
        final response = await http.post(
          Uri.parse(candidateUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({
            'isAnnual': isAnnual,
            'origin': 'exodo://checkout',
          }),
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['url'] as String?;
        } else {
          final data = jsonDecode(response.body);
          throw Exception(data['error'] ?? data['message'] ?? 'Error al crear sesión de pago');
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }

    throw lastError ?? Exception('No se pudo conectar con el servidor de pagos');
  }

  /// Inicia el flujo de checkout de Stripe en el navegador externo.
  ///
  /// [Punto 4] Si no hay sesión (invitado) o no hay conexión, retorna `false`
  /// de inmediato y EN SILENCIO: cero pop-ups, cero SnackBars. Los fallos de
  /// red/backend también se tragan aquí — para el usuario el botón es un
  /// no-op. La háptica suave (si se desea) vive en la capa UI, no aquí.
  static Future<bool> startCheckoutSession({bool isAnnual = false}) async {
    if (_isCheckingOut) return false;

    final session = SupabaseService.client.auth.currentSession;
    final jwt = session?.accessToken;

    // Guest / sin sesión / sin conexión → retorno limpio y silencioso.
    if (jwt == null || jwt.isEmpty || !ConnectivityService().isOnline) {
      return false;
    }

    _isCheckingOut = true;
    try {
      final url = await createCheckoutSession(isAnnual: isAnnual);
      if (url != null && url.isNotEmpty) {
        if (kIsWeb) {
          // Web: delegar al adaptador de navegador. Misma pestaña (`_self`) para
          // que Stripe retorne sobre la SPA con ?session_id=...&status=success.
          // El consumo de parámetros pendientes corre fire-and-forget: refresca
          // el perfil en silencio si el usuario volvió a esta página tras pagar.
          unawaited(WebBillingAdapter.processReturnParameters());
          return await WebBillingAdapter.openCheckoutInSameTab(url);
        }
        final uri = Uri.parse(url);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        return launched;
      }
      // El backend no devolvió URL → silencio total.
      return false;
    } catch (_) {
      // Fallo de red/backend → silencio total (criterio auditor: cero pop-ups).
      return false;
    } finally {
      _isCheckingOut = false;
    }
  }

  /// Abre el portal de gestión de Stripe (cancelar, cambiar método de pago).
  static Future<String?> createPortalSession() async {
    final session = SupabaseService.client.auth.currentSession;
    final jwt = session?.accessToken;

    if (jwt == null) {
      throw Exception('Debes iniciar sesión');
    }

    Exception? lastError;
    for (final candidateUrl in _portalUrls) {
      try {
        final response = await http.post(
          Uri.parse(candidateUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['url'] as String?;
        } else {
          final data = jsonDecode(response.body);
          throw Exception(data['error'] ?? data['message'] ?? 'Error al abrir portal');
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }

    throw lastError ?? Exception('No se pudo conectar con el portal de pagos');
  }
}
