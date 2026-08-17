import 'dart:convert';
import 'package:http/http.dart' as http;
import 'supabase_service.dart';

/// Servicio de Stripe para Éxodo.
/// Crea Checkout Sessions y abre el portal de gestión.
class StripeService {
  /// URL base del backend — reutiliza la misma lógica que ChatService.
  static String get _backendBase {
    const env1 = String.fromEnvironment('BACKEND_URL');
    const env2 = String.fromEnvironment('EXODO_BACKEND_URL');
    for (final env in [env1, env2]) {
      if (env.isNotEmpty) {
        final base = env.endsWith('/api/chat')
            ? env.replaceAll('/api/chat', '')
            : (env.endsWith('/api') ? env.substring(0, env.length - 4) : env);
        return base;
      }
    }
    return 'http://192.168.8.223:3000';
  }

  /// Crea una sesión de Stripe Checkout y abre la URL en el navegador.
  /// Retorna la URL de checkout, o null si hay error.
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
