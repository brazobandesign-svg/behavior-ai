import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'supabase_service.dart';

class ChatService {
  static String? _workingUrl;

  static List<String> get _candidateUrls {
    if (_workingUrl != null) return [_workingUrl!];
    // Prioridad de URLs:
    //   1. BACKEND_URL pasada por --dart-define al compilar (PRODUCCIÓN: https://api.exodo.com).
    //   2. localhost (solo con `adb reverse tcp:3000 tcp:3000` activo en debug).
    //   3. 10.0.2.2 (loopback del emulador Android).
    const env = String.fromEnvironment('BACKEND_URL');
    final list = <String>[];
    if (env.isNotEmpty) list.add(env);
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      list.add('http://localhost:3000/api/chat');  // funciona con `adb reverse tcp:3000 tcp:3000`
      list.add('http://10.0.2.2:3000/api/chat');   // emulador Android Studio
    }
    list.add('http://localhost:3000/api/chat');
    return list;
  }

  static String get backendUrl => _workingUrl ?? _candidateUrls.first;

  static http.Client? _activeClient;
  static bool _isCancelled = false;

  static void cancelStream() {
    _isCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  static Future<void> sendMessageStream({
    required String message,
    String? conversationId,
    List<Map<String, dynamic>>? history,
    String? modelOverride,
    required void Function(String chunk) onChunk,
    required void Function(String fullText, List<Source> sources) onComplete,
    required void Function(String error) onError,
  }) async {
    final session = SupabaseService.client.auth.currentSession;
    final jwt = session?.accessToken;

    try {
      _isCancelled = false;
      _activeClient?.close();

      http.StreamedResponse? response;
      http.Client? client;
      String lastError = 'Error indefinido';

      for (final url in _candidateUrls) {
        if (_isCancelled) return;
        try {
          final reqClient = http.Client();
          final request = http.Request('POST', Uri.parse(url));
          request.headers.addAll({
            'Content-Type': 'application/json',
            if (jwt != null) 'Authorization': 'Bearer $jwt',
          });
          request.body = jsonEncode({
            'message': message,
            'conversationId': conversationId,
            'history': ?history,
            'model_override': ?modelOverride,
          });
          final resp = await reqClient.send(request).timeout(const Duration(seconds: 15));
          client = reqClient;
          _activeClient = client;
          response = resp;
          _workingUrl = url;
          break;
        } catch (e) {
          lastError = e.toString().replaceAll('Exception: ', '');
        }
      }

      if (response == null || client == null) {
        if (!_isCancelled) {
          onError('⚠️ No se pudo conectar al servidor ($lastError). Verifica tu conexión o que el servidor local esté activo.');
        }
        return;
      }

      if (response.statusCode != 200) {
        if (response.statusCode == 429) {
          if (!_isCancelled) {
            onError('⏳ Has excedido el límite de peticiones por minuto. Por favor, espera unos segundos antes de continuar.');
          }
          if (_activeClient == client) _activeClient = null;
          client.close();
          return;
        }
        final body = await response.stream.bytesToString();
        try {
          final err = jsonDecode(body);
          if (!_isCancelled) {
            onError(err['message'] ?? err['detail'] ?? err['error'] ?? 'Error del backend (${response.statusCode})');
          }
        } catch (_) {
          if (!_isCancelled) onError('Error del backend (${response.statusCode})');
        }
        if (_activeClient == client) _activeClient = null;
        client.close();
        return;
      }

      String fullText = '';
      List<Source> sources = [];

      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (_isCancelled) return;
        if (line.startsWith('data: ')) {
          final dataStr = line.substring(6).trim();
          if (dataStr.isEmpty) return;
          try {
            final data = jsonDecode(dataStr);
            final type = data['type'];
            if (type == 'chunk') {
              final content = data['content'] as String? ?? '';
              fullText += content;
              onChunk(content);
            } else if (type == 'done') {
              final content = data['content'] as String? ?? fullText;
              fullText = content;
              final rawSources = data['sources'];
              if (rawSources is List) {
                sources = rawSources.whereType<Map<String, dynamic>>().map((s) => Source.fromJson(s)).toList();
              }
              onComplete(fullText, sources);
            } else if (type == 'error') {
              onError(data['content'] as String? ?? 'Error en streaming');
            }
          } catch (_) {}
        }
      }, onDone: () {
        if (_activeClient == client) _activeClient = null;
        client?.close();
      }, onError: (e) {
        if (_activeClient == client) _activeClient = null;
        client?.close();
        if (!_isCancelled) onError(e.toString());
      });
    } catch (e) {
      if (!_isCancelled) onError(e.toString());
    }
  }
}
