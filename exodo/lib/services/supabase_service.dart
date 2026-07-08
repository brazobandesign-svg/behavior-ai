import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';


class SupabaseService {
  static const String supabaseUrl = 'https://zyvaakfsnlqlgrjdigkr.supabase.co';
  // Llave pública (anon) extraída de tu panel. Es segura para estar en el APK porque RLS la protege.
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dmFha2ZzbmxxbGdyamRpZ2tyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0MDg2MTQsImV4cCI6MjA5Nzk4NDYxNH0.ZPW16OYo-09YEe-ti2DaRSh8Yh9TZEQL6e_23bvGZGU';

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Supabase.initialize(
      url: supabaseUrl,
      // ignore: deprecated_member_use
      anonKey: supabaseAnonKey,
    );
    _initialized = true;
  }

  static SupabaseClient get client => Supabase.instance.client;
  static User? get currentUser => client.auth.currentUser;

  // Autenticación por email/password
  static Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(email: email, password: password);
  }

  static Future<AuthResponse> signUp(String email, String password, String fullName) async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
    return response;
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  static Future<bool> signInWithGoogle() async {
    return await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'io.supabase.exodo://login-callback',
    );
  }

  static Future<bool> signInWithApple() async {
    return await client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: kIsWeb ? null : 'io.supabase.exodo://login-callback',
    );
  }

  static Future<AuthResponse> signInAnonymously() async {
    return await client.auth.signInAnonymously(
      data: {'full_name': 'Invitado Éxodo'},
    );
  }

  // Perfil del usuario con auto-creación y fallback resiliente
  static Future<UserProfile?> getProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final defaultFullName = user.userMetadata?['full_name']?.toString() ?? user.email?.split('@')[0] ?? 'Usuario Éxodo';
    final metaAvatar = user.userMetadata?['avatar_url']?.toString() ?? user.userMetadata?['picture']?.toString() ?? user.userMetadata?['photo_url']?.toString();

    try {
      final res = await client.from('profiles').select().eq('id', user.id).maybeSingle();
      if (res == null) {
        final newProfile = {
          'id': user.id,
          'full_name': defaultFullName,
          'plan': 'genesis',
          'avatar_url': ?metaAvatar,
        };
        await client.from('profiles').upsert(newProfile);
        return UserProfile.fromJson(newProfile);
      }
      final profile = UserProfile.fromJson(res);
      if ((profile.avatarUrl == null || profile.avatarUrl!.isEmpty) && metaAvatar != null && metaAvatar.isNotEmpty) {
        await client.from('profiles').update({'avatar_url': metaAvatar}).eq('id', user.id);
        return UserProfile(
          id: profile.id,
          fullName: profile.fullName,
          plan: profile.plan,
          avatarUrl: metaAvatar,
          onboarding: profile.onboarding,
        );
      }
      return profile;
    } catch (e) {
      // Fallback si RLS o red falla temporalmente
      return UserProfile(
        id: user.id,
        fullName: defaultFullName,
        plan: 'genesis',
        avatarUrl: metaAvatar,
      );
    }
  }

  static Future<void> saveOnboarding(Map<String, dynamic> onboardingData) async {
    final user = currentUser;
    if (user == null) return;

    await client.from('profiles').update({
      'onboarding': onboardingData,
    }).eq('id', user.id);
  }

  // Conversaciones
  static Future<List<Conversation>> getConversations() async {
    final user = currentUser;
    if (user == null) return [];

    final res = await client
        .from('conversations')
        .select()
        .eq('user_id', user.id)
        .eq('is_incognito', false)
        .order('updated_at', ascending: false);

    return (res as List).map((json) => Conversation.fromJson(json)).toList();
  }

  static Future<Conversation> createConversation(String title, String modelPlan, bool isIncognito) async {
    final user = currentUser;
    if (user == null) throw Exception('No autenticado');

    final res = await client.from('conversations').insert({
      'user_id': user.id,
      'title': title,
      'model_plan': modelPlan,
      'is_incognito': isIncognito,
    }).select().single();

    return Conversation.fromJson(res);
  }

  static Future<void> deleteConversation(String convId) async {
    await client.from('conversations').delete().eq('id', convId);
  }

  // [Punto 39] Borrar TODAS las conversaciones del usuario (historial completo).
  // Se ejecuta desde Settings → Profile → Delete History.
  static Future<void> deleteAllConversations() async {
    final user = currentUser;
    if (user == null) return;
    await client.from('conversations').delete().eq('user_id', user.id);
  }

  // Mensajes
  static Future<List<ChatMessage>> getMessages(String convId) async {
    final res = await client
        .from('messages')
        .select()
        .eq('conversation_id', convId)
        .order('created_at', ascending: true);

    return (res as List).map((json) => ChatMessage.fromJson(json)).toList();
  }

  // [Punto 37 aviso] Feedback directo a Supabase (sin abrir email).
  // Inserta en tabla `feedback` con RLS: el usuario solo puede insertar.
  // Retorna true si éxito, false si error.
  // Nota: no usamos AppI18n aquí (es un singleton con posible race condition
  // al boot). El locale se guarda como 'es' por defecto si falla.
  static Future<bool> submitFeedback({

    required bool isLike,
    required String comment,
    required String messageExcerpt,
    String? conversationId,
  }) async {
    final user = currentUser;
    if (user == null) return false;

    try {
      await client.from('feedback').insert({
        'user_id': user.id,
        'is_like': isLike,
        'comment': comment,
        'message_excerpt': messageExcerpt.length > 500
            ? messageExcerpt.substring(0, 500)
            : messageExcerpt,
        'conversation_id': conversationId,
        'app_locale': 'es',
        'app_version': '1.1.86',
      });
      return true;
    } catch (e) {
      debugPrint('[Feedback] Error al insertar: $e');
      return false;
    }
  }

  // Uso diario de tokens
  static Future<Map<String, dynamic>?> getTodayUsage() async {
    final user = currentUser;
    if (user == null) return null;

    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10); // '2026-06-25'
    final res = await client
        .from('user_usage')
        .select()
        .eq('user_id', user.id)
        .eq('period', today)
        .maybeSingle();

    return res;
  }

  // Renombrar conversación
  static Future<void> updateConversationTitle(String convId, String newTitle) async {
    await client.from('conversations').update({'title': newTitle}).eq('id', convId);
  }

  // Fijar / desfijar conversación
  // [Punto 38] El update devuelve la fila actualizada para confirmar
  // que la columna is_starred existe y se guardó correctamente.
  static Future<void> toggleConversationStarred(String convId, bool isStarred) async {
    await client.from('conversations').update({'is_starred': isStarred}).eq('id', convId).select();
  }

  // Buscar palabra exacta en el contenido de todos los chats
  static Future<List<String>> searchConversationIdsByMessage(String query) async {
    final user = currentUser;
    if (user == null || query.trim().isEmpty) return [];
    try {
      final res = await client
          .from('messages')
          .select('conversation_id')
          .eq('user_id', user.id)
          .ilike('content', '%$query%');
      return (res as List).map((e) => e['conversation_id'].toString()).toSet().toList();
    } catch (_) {
      return [];
    }
  }

  // --- ANTI-ABUSO GUEST IP ---
  static Future<String?> getPublicIp() async {
    try {
      final res = await http.get(Uri.parse('https://api.ipify.org')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200 && res.body.trim().isNotEmpty) {
        return res.body.trim();
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> recordGuestIpMessage() async {
    final ip = await getPublicIp();
    if (ip == null) return false;
    final now = DateTime.now().toUtc();
    try {
      final data = await client.from('guest_ip_limits').select().eq('ip', ip).maybeSingle();
      if (data != null) {
        final resetTime = DateTime.tryParse(data['reset_time'].toString())?.toUtc() ?? now.add(const Duration(hours: 24));
        if (now.isAfter(resetTime)) {
          await client.from('guest_ip_limits').update({
            'messages_sent': 1,
            'reset_time': now.add(const Duration(hours: 24)).toIso8601String(),
          }).eq('ip', ip);
          return false;
        } else {
          final count = (data['messages_sent'] as int? ?? 0) + 1;
          await client.from('guest_ip_limits').update({'messages_sent': count}).eq('ip', ip);
          return count >= 3;
        }
      } else {
        await client.from('guest_ip_limits').insert({
          'ip': ip,
          'messages_sent': 1,
          'reset_time': now.add(const Duration(hours: 24)).toIso8601String(),
        });
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isGuestIpBlocked() async {
    final ip = await getPublicIp();
    if (ip == null) return false;
    final now = DateTime.now().toUtc();
    try {
      final data = await client.from('guest_ip_limits').select().eq('ip', ip).maybeSingle();
      if (data != null) {
        final resetTime = DateTime.tryParse(data['reset_time'].toString())?.toUtc() ?? now;
        if (now.isAfter(resetTime)) return false;
        return (data['messages_sent'] as int? ?? 0) >= 3;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> resetGuestIpForTesting() async {
    final ip = await getPublicIp();
    if (ip != null) {
      try {
        await client.from('guest_ip_limits').update({'messages_sent': 0}).eq('ip', ip);
      } catch (_) {}
    }
  }
}
