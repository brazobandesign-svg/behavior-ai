import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class SupabaseService {
  static const String supabaseUrl = 'https://zyvaakfsnlqlgrjdigkr.supabase.co';
  // Llave pública (anon) extraída de tu panel. Es segura para estar en el APK porque RLS la protege.
  static const String supabaseAnonKey = 'sb_publishable_2GO00TNSlCHmvN3_pfODTA__kjjj--';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
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
    return await client.auth.signInWithOAuth(OAuthProvider.google);
  }

  // Perfil del usuario
  static Future<UserProfile?> getProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final res = await client.from('profiles').select().eq('id', user.id).maybeSingle();
    if (res == null) return null;
    return UserProfile.fromJson(res);
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

  // Mensajes
  static Future<List<ChatMessage>> getMessages(String convId) async {
    final res = await client
        .from('messages')
        .select()
        .eq('conversation_id', convId)
        .order('created_at', ascending: true);

    return (res as List).map((json) => ChatMessage.fromJson(json)).toList();
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
}
