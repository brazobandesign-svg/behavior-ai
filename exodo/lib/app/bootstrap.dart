import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

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
  static Future<Bootstrap> readSync() async {
    final prefs = await SharedPreferences.getInstance();

    final hasAuthToken = prefs.getKeys().any(
      (k) => k.startsWith('sb-') && k.contains('auth-token'),
    );

    final profileJson = prefs.getString('exodo_cached_profile');
    UserProfile? cachedProfile;
    if (profileJson != null) {
      try {
        final decoded = jsonDecode(profileJson);
        if (decoded is Map<String, dynamic>) {
          cachedProfile = UserProfile.fromJson(decoded);
        }
      } catch (_) {}
    }

    final conversationsJson = prefs.getString('exodo_cached_conversations');
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

    final lastMessagesJson = prefs.getString('exodo_cached_last_messages');
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
      lastConversationId: prefs.getString('exodo_last_conversation_id'),
      cachedConversations: cachedConversations,
      cachedLastMessages: cachedLastMessages,
      cachedTheme: prefs.getString('exodo_theme'),
      cachedTokensUsed: prefs.getInt('exodo_tokens_used'),
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
