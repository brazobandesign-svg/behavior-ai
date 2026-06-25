import 'dart:convert';
import 'package:http/http.dart' as http;
import 'supabase_service.dart';

class ChatResponse {
  final String responseText;
  final String intent;
  final String? imageUrl;
  final int tokensUsed;
  final int tokensLimit;

  ChatResponse({
    required this.responseText,
    required this.intent,
    this.imageUrl,
    required this.tokensUsed,
    required this.tokensLimit,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final tokens = json['tokens'] as Map<String, dynamic>? ?? {};
    return ChatResponse(
      responseText: json['response'] as String? ?? '',
      intent: json['intent'] as String? ?? 'SIMPLE',
      imageUrl: json['image_url'] as String?,
      tokensUsed: tokens['used'] as int? ?? 0,
      tokensLimit: tokens['limit'] as int? ?? 15000,
    );
  }
}

class ChatService {
  // Para emulador Android es 10.0.2.2, para Windows o Web es localhost
  static const String backendUrl = 'http://localhost:3000/api/chat';

  static Future<ChatResponse> sendMessage({
    required String message,
    String? conversationId,
  }) async {
    final session = SupabaseService.client.auth.currentSession;
    final jwt = session?.accessToken;

    final response = await http.post(
      Uri.parse(backendUrl),
      headers: {
        'Content-Type': 'application/json',
        if (jwt != null) 'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({
        'message': message,
        if (conversationId != null) 'conversationId': conversationId,
      }),
    );

    if (response.statusCode == 200) {
      return ChatResponse.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } else {
      final err = jsonDecode(utf8.decode(response.bodyBytes));
      throw Exception(err['error'] ?? 'Error del backend (${response.statusCode})');
    }
  }
}
