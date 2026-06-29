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
            'history': history,
            'model_override': modelOverride,
          });
          final resp = await reqClient.send(request).timeout(const Duration(milliseconds: 1800));
          client = reqClient;
          _activeClient = client;
          response = resp;
          _workingUrl = url;
          break;
        } catch (_) {}
      }

      if (response == null || client == null || response.statusCode != 200) {
        if (_activeClient == client) _activeClient = null;
        client?.close();
        if (!_isCancelled) {
          await _sendDirectNimStream(
            message: message,
            history: history,
            modelOverride: modelOverride,
            onChunk: onChunk,
            onComplete: onComplete,
            onError: onError,
          );
        }
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
              _enrichSources(message, fullText, sources).then((enriched) {
                onComplete(fullText, enriched);
              });
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

  static Future<void> _sendDirectNimStream({
    required String message,
    List<Map<String, dynamic>>? history,
    String? modelOverride,
    required void Function(String chunk) onChunk,
    required void Function(String fullText, List<Source> sources) onComplete,
    required void Function(String error) onError,
  }) async {
    try {
      String nimModel = 'nvidia/nemotron-3-ultra-550b-a55b';
      String apiKey = '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';

      if (modelOverride == 'nim-deepseek-v4-pro') {
        nimModel = 'meta/llama-3.3-70b-instruct';
        apiKey = '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';
      } else if (modelOverride == 'nim-deepseek-v4-flash') {
        nimModel = 'minimaxai/minimax-m3';
        apiKey = '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';
      } else if (modelOverride == 'nim-minimax-m3') {
        nimModel = 'minimaxai/minimax-m3';
        apiKey = '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';
      }

      final reqClient = http.Client();
      _activeClient = reqClient;
      final request = http.Request('POST', Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      });

      const systemPrompt = "Eres Éxodo by Behavior, un asistente de IA avanzado con contexto dominicano. Sé útil, claro, directo y preciso.";
      final cleanHistory = <Map<String, dynamic>>[];
      if (history != null) {
        for (final h in history) {
          final r = h['role']?.toString() ?? 'user';
          final c = h['content']?.toString() ?? '';
          if (c.trim().isEmpty) continue;
          if (cleanHistory.isNotEmpty && cleanHistory.last['role'] == r && cleanHistory.last['content'] == c) continue;
          cleanHistory.add({'role': r, 'content': c});
        }
        if (cleanHistory.isNotEmpty && cleanHistory.last['role'] == 'user' && cleanHistory.last['content'] == message) {
          cleanHistory.removeLast();
        }
      }

      final messages = [
        {'role': 'system', 'content': systemPrompt},
        ...cleanHistory,
        {'role': 'user', 'content': message},
      ];

      request.body = jsonEncode({
        'model': nimModel,
        'messages': messages,
        'temperature': 0.7,
        'max_tokens': 4096,
        'stream': true,
      });

      final response = await reqClient.send(request).timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        final errBody = await response.stream.bytesToString();
        if (!_isCancelled) onError('Error de API directa (${response.statusCode}): $errBody');
        reqClient.close();
        return;
      }

      String fullText = '';
      bool isCompleted = false;
      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (_isCancelled) return;
        if (line.startsWith('data: ')) {
          final dataStr = line.substring(6).trim();
          if (dataStr == '[DONE]') {
            if (!isCompleted) {
              isCompleted = true;
              _enrichSources(message, fullText, []).then((enriched) {
                onComplete(fullText, enriched);
              });
            }
            return;
          }
          if (dataStr.isEmpty) return;
          try {
            final data = jsonDecode(dataStr);
            final choices = data['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'];
              if (delta != null && delta['content'] != null) {
                final content = delta['content'] as String;
                fullText += content;
                onChunk(content);
              }
            }
          } catch (_) {}
        }
      }, onDone: () {
        if (_activeClient == reqClient) _activeClient = null;
        reqClient.close();
        if (fullText.isNotEmpty && !isCompleted) {
          isCompleted = true;
          _enrichSources(message, fullText, []).then((enriched) {
            onComplete(fullText, enriched);
          });
        }
      }, onError: (e) {
        if (_activeClient == reqClient) _activeClient = null;
        reqClient.close();
        if (fullText.isNotEmpty && !isCompleted) {
          isCompleted = true;
          _enrichSources(message, fullText, []).then((enriched) {
            onComplete(fullText, enriched);
          });
        } else if (!_isCancelled) {
          onError(e.toString());
        }
      });
    } catch (e) {
      if (!_isCancelled) onError('Error de conexión: ${e.toString().replaceAll('Exception: ', '')}');
    }
  }

  static Future<List<Source>> _enrichSources(String userPrompt, String responseText, List<Source> existingSources) async {
    if (existingSources.isNotEmpty) return existingSources;
    
    final List<Source> found = [];
    final Set<String> seenUrls = {};

    // 1. Extraer enlaces markdown [Título](URL)
    final mdRegex = RegExp(r'\[([^\]]+)\]\((https?://[^\s)]+)\)');
    for (final match in mdRegex.allMatches(responseText)) {
      final title = match.group(1)?.trim() ?? '';
      final url = match.group(2)?.trim() ?? '';
      if (url.isNotEmpty && !url.contains('localhost') && seenUrls.add(url)) {
        found.add(Source(title: title.isNotEmpty ? title : Uri.parse(url).host, url: url));
      }
    }

    // 2. Extraer URLs en texto plano https://...
    final urlRegex = RegExp(r'(https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:/[^\s\)\]\>"]*)?)');
    for (final match in urlRegex.allMatches(responseText)) {
      final url = match.group(1)?.trim() ?? '';
      if (url.isNotEmpty && !url.contains('localhost') && seenUrls.add(url)) {
        final host = Uri.tryParse(url)?.host ?? url;
        found.add(Source(title: host.replaceFirst('www.', ''), url: url));
      }
    }

    // 3. Si sigue vacío y no es un saludo básico, buscar en Wikipedia para ofrecer fuentes reales
    final cleanQuery = userPrompt.trim();
    final lower = cleanQuery.toLowerCase();
    final isGreeting = ['hola', 'hey', 'buenos dias', 'buenas', 'gracias', 'que tal', 'hi', 'hello', 'ok', 'vale'].contains(lower);

    if (found.isEmpty && cleanQuery.length >= 4 && !isGreeting) {
      try {
        // Limpiamos palabras comunes de búsqueda para encontrar los artículos precisos
        String searchQuery = cleanQuery.replaceAll(RegExp(r'(?i)(busca en internet|buscar en la web|según la web|segun la web|busca en la web|dime sobre|háblame de|hablame de|qué sabes sobre|que sabes sobre|quién fue|quien fue|historia de|información sobre|informacion sobre)'), '').trim();
        if (searchQuery.isEmpty || searchQuery.length < 3) searchQuery = cleanQuery;

        final lang = cleanQuery.contains(RegExp(r'[áéíóúñ¿¡]', caseSensitive: false)) ? 'es' : 'es';
        final searchUri = Uri.parse('https://$lang.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(searchQuery)}&format=json');
        final resp = await http.get(searchUri).timeout(const Duration(seconds: 3));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final searchResults = data['query']?['search'] as List?;
          if (searchResults != null) {
            for (final item in searchResults.take(4)) {
              final title = item['title']?.toString() ?? '';
              if (title.isNotEmpty) {
                final url = 'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}';
                if (seenUrls.add(url)) {
                  found.add(Source(title: title, url: url));
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    return found;
  }
}
