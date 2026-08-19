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
  /// URL base del backend — reutiliza la misma lógica que ChatService.
  static String get _backendBase {
    return ChatService.backendUrl
        .replaceAll('/api/chat', '')
        .replaceAll('/chat', '')
        .replaceAll(RegExp(r'/+$'), '');
  }

  /// Crea una sesión de Stripe Checkout y retorna la URL generada.
  static Future<String?> createCheckoutSession() async {
    final session = SupabaseService.client.auth.currentSession;
    final jwt = session?.accessToken;

    if (jwt == null) {
      throw Exception('Debes iniciar sesión para suscribirte');
    }

    final response = await http.post(
      Uri.parse('$_backendBase/api/stripe/checkout'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({
        'origin': 'exodo://checkout',
      }),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['url'] as String?;
    } else {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Error al crear sesión de pago');
    }
  }

  /// Inicia el flujo de checkout de Stripe en el navegador externo con feedback visual.
  static Future<bool> startCheckoutSession(BuildContext context) async {
    try {
      final session = SupabaseService.client.auth.currentSession;
      final jwt = session?.accessToken;

      if (jwt == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Debes iniciar sesión con tu cuenta para adquirir una suscripción.'),
              backgroundColor: ExodoPalette.danger,
            ),
          );
        }
        return false;
      }

      final url = await createCheckoutSession();
      if (url != null && url.isNotEmpty) {
        final uri = Uri.parse(url);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        return launched;
      } else {
        if (context.mounted) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de suscripción: $cleanMsg'),
            backgroundColor: ExodoPalette.danger,
          ),
        );
      }
      return false;
    }
  }

  /// Abre el portal de gestión de Stripe (cancelar, cambiar método de pago).
  static Future<String?> createPortalSession() async {
    final session = SupabaseService.client.auth.currentSession;
    final jwt = session?.accessToken;

    if (jwt == null) {
      throw Exception('Debes iniciar sesión');
    }

    final response = await http.post(
      Uri.parse('$_backendBase/api/stripe/portal'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['url'] as String?;
    } else {
      final data = jsonDecode(response.body);
      throw Exception(data['error'] ?? 'Error al abrir portal');
    }
  }
}
