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
    if (env.isNotEmpty) {
      // [Punto 41] BACKEND_URL debe incluir /api/chat. Si el usuario pasó solo
      // la raíz (ej: --dart-define=BACKEND_URL=https://xxx.trycloudflare.com),
      // se lo agregamos para que el POST aterrice en el endpoint correcto.
      final url = env.endsWith('/api/chat') ? env : '$env/api/chat';
      list.add(url);
    }
    if (kDebugMode) {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        list.add(
          'http://localhost:3000/api/chat',
        ); // funciona con `adb reverse tcp:3000 tcp:3000`
        list.add('http://10.0.2.2:3000/api/chat'); // emulador Android Studio
      }
      list.add('http://localhost:3000/api/chat');
    }
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
    List<Attachment>? attachments, // [Punto 40] archivos para multimodal
    required void Function(String chunk) onChunk,
    required void Function(String fullText, List<Source> sources) onComplete,
    required void Function(String error) onError,
  }) async {
    final session = SupabaseService.client.auth.currentSession;
    final jwt = session?.accessToken;

    try {
      _isCancelled = false;
      _activeClient?.close();

      // [Punto 40+42] NO saltamos el backend cuando hay adjuntos.
      // Los adjuntos se codifican en base64 y se mandan al backend,
      // que los usa para enriquecer el mensaje antes de clasificar
      // la intención y rutear al especialista correcto.

      http.StreamedResponse? response;
      http.Client? client;

      // [Punto 40+42] Codificar adjuntos como base64 para el backend.
      final attachmentsJson = attachments
          ?.map(
            (a) => {
              'file_name': a.fileName,
              'mime_type': a.mimeType,
              'base64': a.base64,
            },
          )
          .toList();

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
            if (attachmentsJson != null && attachmentsJson.isNotEmpty)
              'attachments': attachmentsJson, // [Punto 40+42]
          });
          final resp = await reqClient
              .send(request)
              .timeout(const Duration(seconds: 12));
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
          onError(
            'Sin conexión con el servidor. Verifica tu red e inténtalo de nuevo.',
          );
        }
        return;
      }

      String fullText = '';
      List<Source> sources = [];

      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (_isCancelled) return;
              if (line.startsWith('data: ')) {
                final dataStr = line.substring(6).trim();
                if (dataStr.isEmpty) return;
                try {
                  final data = jsonDecode(dataStr);
                  final type = data['type'];
                  if (type == 'heartbeat') {
                    // [Punto 41+42] Heartbeat del backend para mantener viva la conexión SSE.
                    // No hacemos nada, solo evitamos que el canal se cierre por idle timeout.
                  } else if (type == 'chunk') {
                    final content = data['content'] as String? ?? '';
                    fullText += content;
                    onChunk(content);
                  } else if (type == 'done') {
                    final content = data['content'] as String? ?? fullText;
                    fullText = content;
                    final rawSources = data['sources'];
                    if (rawSources is List) {
                      sources = rawSources
                          .where((s) => s is Map)
                          .map(
                            (s) => Source.fromJson(
                              Map<String, dynamic>.from(s as Map),
                            ),
                          )
                          .toList();
                    }
                    _enrichSources(message, fullText, sources)
                        .then((enriched) {
                          onComplete(fullText, enriched);
                        })
                        .catchError((_) {
                          // Si enriquecer fuentes falla (red, timeout), entregamos
                          // la respuesta SIN fuentes en lugar de dejar la UI zombie.
                          onComplete(fullText, sources);
                        });
                  } else if (type == 'error') {
                    onError(data['content'] as String? ?? 'Error en streaming');
                  }
                } catch (_) {}
              }
            },
            onDone: () {
              if (_activeClient == client) _activeClient = null;
              client?.close();
              // Si el stream cerró sin enviar 'done', finalizar con lo que hay.
              if (!_isCancelled && fullText.isNotEmpty) {
                onComplete(fullText, sources);
              } else if (!_isCancelled && fullText.isEmpty) {
                // Stream cerró sin enviar nada — notificar error para
                // desbloquear isGenerating en AppState.
                onError('La conexión se cerró inesperadamente.');
              }
            },
            onError: (e) {
              if (_activeClient == client) _activeClient = null;
              client?.close();
              if (!_isCancelled) onError(e.toString());
            },
          );
    } catch (e) {
      if (!_isCancelled) onError(e.toString());
    }
  }

  static Future<List<Source>> _enrichSources(
    String userPrompt,
    String responseText,
    List<Source> existingSources,
  ) async {
    if (existingSources.isNotEmpty) {
      return existingSources.length > 10
          ? existingSources.take(10).toList()
          : existingSources;
    }

    final List<Source> found = [];
    final Set<String> seenUrls = {};

    // 1. Extraer enlaces markdown [Título](URL)
    final mdRegex = RegExp(r'\[([^\]]+)\]\((https?://[^\s)]+)\)');
    for (final match in mdRegex.allMatches(responseText)) {
      final title = match.group(1)?.trim() ?? '';
      final url = match.group(2)?.trim() ?? '';
      if (url.isNotEmpty && !url.contains('localhost') && seenUrls.add(url)) {
        found.add(
          Source(
            title: title.isNotEmpty ? title : Uri.parse(url).host,
            url: url,
          ),
        );
      }
    }

    // 2. Extraer URLs en texto plano https://...
    final urlRegex = RegExp(
      r'(https?://[a-zA-Z0-9\\-\\.]+\\.[a-zA-Z]{2,}(?:/[^\\s\\)\\]\\>"]*)?)',
    );
    for (final match in urlRegex.allMatches(responseText)) {
      final url = match.group(1)?.trim() ?? '';
      if (url.isNotEmpty && !url.contains('localhost') && seenUrls.add(url)) {
        final host = Uri.tryParse(url)?.host ?? url;
        found.add(Source(title: host.replaceFirst('www.', ''), url: url));
      }
    }

    // [Punto 45] NO fabricamos fuentes. Solo mostramos las que el modelo
    // realmente citó en su respuesta. Fabricar links de Wikipedia o de
    // cualquier API de búsqueda a posteriori es deshonesto: el modelo
    // no consultó esas páginas. Si no hay fuentes reales, no las hay.
    // Esto elimina el bug donde todas las respuestas mostraban los mismos
    // links de Wikipedia sin importar el tema preguntado.

    if (found.length > 10) {
      return found.take(10).toList();
    }
    return found;
  }
}
