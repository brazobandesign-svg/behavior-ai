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
    const env1 = String.fromEnvironment('BACKEND_URL');
    const env2 = String.fromEnvironment('EXODO_BACKEND_URL');
    final list = <String>[];
    for (final env in [env1, env2]) {
      if (env.isNotEmpty) {
        final url = env.endsWith('/api/chat') ? env : '$env/api/chat';
        if (!list.contains(url)) list.add(url);
      }
    }
    // Siempre añadir URL de producción en Railway para garantizar conexión ininterrumpida
    const prodUrl = 'https://behavior-ai-production.up.railway.app/api/chat';
    if (!list.contains(prodUrl)) list.add(prodUrl);

    if (kDebugMode) {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        list.add('http://localhost:3000/api/chat');
        list.add('http://10.0.2.2:3000/api/chat');
      }
    }
    return list;
  }

  static String get backendUrl => _workingUrl ?? (_candidateUrls.isNotEmpty ? _candidateUrls.first : 'https://behavior-ai-production.up.railway.app/api/chat');

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
          // [Punto 4 Fix] Timeouts adaptativos: 3s para localhost/loopback para no congelar
          // en móvil, y 45s para URLs remotas/HTTPS permitiendo cold starts de IA sin cortar al usuario.
          final isLocal = url.contains('localhost') || url.contains('10.0.2.2') || url.contains('192.168.');
          final timeoutDuration = isLocal ? const Duration(seconds: 3) : const Duration(seconds: 45);
          final resp = await reqClient
              .send(request)
              .timeout(timeoutDuration);
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
          String errMsg = 'Sin conexión con el servidor. Verifica tu red e inténtalo de nuevo.';
          if (response != null) {
            if (response.statusCode >= 500) {
              errMsg = 'Error en el servidor (Cód. ${response.statusCode}). Intentando reiniciar...';
            } else if (response.statusCode == 413) {
              errMsg = 'El archivo adjunto es demasiado grande. Por favor, intenta con uno más pequeño.';
            } else if (response.statusCode != 200) {
              errMsg = 'Hubo un error de conexión (Cód. ${response.statusCode}).';
            }
          }
          onError(errMsg);
        }
        return;
      }

      String fullText = '';
      List<Source> sources = [];
      bool isCompleted = false;

      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (_isCancelled) return;
              if (line.startsWith('data: ')) {
                final dataStr = line.substring(6).trim();
                if (dataStr == '[DONE]') return;
                try {
                  final data = jsonDecode(dataStr);
                  final type = data['type'];
                  if (type == 'heartbeat') {
                    // [Punto 41+42] Heartbeat del backend para mantener viva la conexión SSE.
                  } else if (type == 'chunk') {
                    final content = data['content'] as String?;
                    if (content != null && content.isNotEmpty) {
                      fullText += content;
                      onChunk(content);
                    }
                  } else if (type == 'done') {
                    if (isCompleted) return;
                    isCompleted = true;
                    final message = data['message'] as String? ?? fullText;
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
              if (!_isCancelled && !isCompleted && fullText.isNotEmpty) {
                isCompleted = true;
                onComplete(fullText, sources);
              } else if (!_isCancelled && !isCompleted && fullText.isEmpty) {
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
