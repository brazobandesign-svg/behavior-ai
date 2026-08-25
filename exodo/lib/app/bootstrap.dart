import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../services/supabase_service.dart';

/// Bootstrap de inicio instantáneo (Fast-Start 0s).
/// Proporciona los datos del último estado cacheado en SharedPreferences
/// en el milisegundo 0 para pintar la UI sin bloquear con llamadas de red.
class Bootstrap {
  final bool hasAuthToken;
  final UserProfile? cachedProfile;
  final String? selectedModelId;
  final String? lastConversationId;
  final List<Conversation> cachedConversations;
  final List<ChatMessage> cachedLastMessages;
  final String? cachedTheme;
  final int? cachedTokensUsed;

  const Bootstrap({
    required this.hasAuthToken,
    this.cachedProfile,
    this.selectedModelId,
    this.lastConversationId,
    this.cachedConversations = const [],
    this.cachedLastMessages = const [],
    this.cachedTheme,
    this.cachedTokensUsed,
  });

  /// Lectura sincrónica de SharedPreferences antes del primer frame en main().
  /// NO toca red ni espera a Supabase.initialize().
  ///
  /// AISLAMIENTO POR CUENTA: el snapshot se pinta sólo si fue guardado por la
  /// MISMA sesión activa (uid detectado en los tokens sb-*). Si la última
  /// cuenta del dispositivo es otra, se descarta perfil/conversaciones/mensajes
  /// para no filtrar datos entre cuentas en el frame 0.
  static Future<Bootstrap> readSync() async {
    final prefs = await SharedPreferences.getInstance();

    String? activeUid;
    for (final k in prefs.getKeys()) {
      if (!k.startsWith('sb-') || !k.contains('auth-token')) continue;
      try {
        final raw = prefs.getString(k);
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final user = decoded['user'];
          if (user is Map<String, dynamic> && user['id'] is String) {
            activeUid = user['id'] as String;
            break;
          }
          final session = decoded['currentSession'];
          if (session is Map<String, dynamic>) {
            final su = session['user'];
            if (su is Map<String, dynamic> && su['id'] is String) {
              activeUid = su['id'] as String;
              break;
            }
          }
        }
      } catch (_) {}
    }

    final snapshotUid = prefs.getString('exodo_snapshot_uid');
    final sameAccount =
        (activeUid == null && snapshotUid == null) ||
        (activeUid != null && snapshotUid == activeUid);
    // Sin coincidencia de cuenta: cachés de usuario vacías (tema/modelo se
    // conservan: son preferencias de dispositivo, no datos personales).
    final userCacheValid = sameAccount;

    final hasAuthToken = activeUid != null;

    // Cachés de usuario: sólo si el snapshot pertenece a la cuenta activa.
    final profileJson = userCacheValid
        ? prefs.getString('exodo_cached_profile')
        : null;
    UserProfile? cachedProfile;
    if (profileJson != null) {
      try {
        final decoded = jsonDecode(profileJson);
        if (decoded is Map<String, dynamic>) {
          cachedProfile = UserProfile.fromJson(decoded);
        }
      } catch (_) {}
    }

    final conversationsJson = userCacheValid
        ? prefs.getString('exodo_cached_conversations')
        : null;
    List<Conversation> cachedConversations = const [];
    if (conversationsJson != null) {
      try {
        final decoded = jsonDecode(conversationsJson);
        if (decoded is List) {
          cachedConversations = decoded
              .whereType<Map>()
              .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }

    final lastMessagesJson = userCacheValid
        ? prefs.getString('exodo_cached_last_messages')
        : null;
    List<ChatMessage> cachedLastMessages = const [];
    if (lastMessagesJson != null) {
      try {
        final decoded = jsonDecode(lastMessagesJson);
        if (decoded is List) {
          cachedLastMessages = decoded
              .whereType<Map>()
              .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }

    return Bootstrap(
      hasAuthToken: hasAuthToken,
      cachedProfile: cachedProfile,
      selectedModelId: prefs.getString('exodo_selected_model'),
      lastConversationId: userCacheValid
          ? prefs.getString('exodo_last_conversation_id')
          : null,
      cachedConversations: cachedConversations,
      cachedLastMessages: cachedLastMessages,
      cachedTheme: prefs.getString('exodo_theme'),
      cachedTokensUsed: userCacheValid ? prefs.getInt('exodo_tokens_used') : null,
    );
  }

  /// Guarda snapshot compacto en SharedPreferences para acelerar el próximo arranque.
  static Future<void> saveSnapshot({
    UserProfile? profile,
    String? selectedModelId,
    String? lastConversationId,
    List<Conversation>? conversations,
    List<ChatMessage>? lastMessages,
    String? theme,
    int? tokensUsed,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Marcar de qué cuenta es este snapshot (aislamiento entre cuentas).
      final uid = SupabaseService.client.auth.currentUser?.id;
      if (uid != null && uid.isNotEmpty) {
        prefs.setString('exodo_snapshot_uid', uid);
      }
      if (profile != null) {
        prefs.setString('exodo_cached_profile', jsonEncode(profile.toJson()));
      }
      if (selectedModelId != null) {
        prefs.setString('exodo_selected_model', selectedModelId);
      }
      if (lastConversationId != null) {
        prefs.setString('exodo_last_conversation_id', lastConversationId);
      }
      if (conversations != null) {
        final sample = conversations.take(20).map((c) => c.toJson()).toList();
        prefs.setString('exodo_cached_conversations', jsonEncode(sample));
      }
      if (lastMessages != null) {
        final sample = lastMessages.take(30).map((m) => m.toJson()).toList();
        prefs.setString('exodo_cached_last_messages', jsonEncode(sample));
      }
      if (theme != null) {
        prefs.setString('exodo_theme', theme);
      }
      if (tokensUsed != null) {
        prefs.setInt('exodo_tokens_used', tokensUsed);
      }
    } catch (_) {}
  }
}
