import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../theme/exodo_palette.dart';
import 'chat_service.dart';
import 'supabase_service.dart';

/// Servicio de Stripe para Éxodo.
/// Crea Checkout Sessions y abre el portal de gestión.
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

  /// Inicia el flujo de checkout de Stripe en el navegador externo con feedback visual.
  static Future<bool> startCheckoutSession(BuildContext context, {bool isAnnual = false}) async {
    if (_isCheckingOut) return false;
    _isCheckingOut = true;

    try {
      final session = SupabaseService.client.auth.currentSession;
      final jwt = session?.accessToken;

      if (jwt == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Debes iniciar sesión con tu cuenta para adquirir una suscripción.'),
              backgroundColor: ExodoPalette.danger,
            ),
          );
        }
        return false;
      }

      final url = await createCheckoutSession(isAnnual: isAnnual);
      if (url != null && url.isNotEmpty) {
        final uri = Uri.parse(url);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        return launched;
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo generar el enlace de pago de Stripe. Intenta más tarde.'),
              backgroundColor: ExodoPalette.danger,
            ),
          );
        }
        return false;
      }
    } catch (e) {
      if (context.mounted) {
        final cleanMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de suscripción: $cleanMsg'),
            backgroundColor: ExodoPalette.danger,
          ),
        );
      }
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
