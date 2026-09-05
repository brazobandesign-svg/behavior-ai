import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'supabase_service.dart';

/// Encapsula una sesión atómica de generación de streaming LLM (F1).
/// Cada mensaje enviado tiene su propio ciclo de vida, cliente HTTP y UUID,
/// eliminando variables globales estáticas y carreras entre chats concurrentes.
class GenerationSession {
  final String id;
  final String? conversationId;
  final http.Client client;
  final Completer<void> completer;
  bool _isCancelled = false;

  GenerationSession({
    required this.id,
    required this.conversationId,
    http.Client? client,
  })  : client = client ?? http.Client(),
        completer = Completer<void>();

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    try {
      client.close();
    } catch (_) {}
    if (!completer.isCompleted) {
      completer.complete();
    }
  }
}

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

    const prodUrl =
        'https://exodo-api-23368377903.us-east1.run.app/api/chat';

    if (!list.contains(prodUrl)) list.add(prodUrl);

    // SEGURIDAD (auditoría C3): candidatos HTTP locales SOLO en debug.
    // En release el JWT viaja siempre por HTTPS al backend productivo; una IP
    // LAN hostil o un endpoint http muerto jamás recibe el Bearer del usuario.
    if (kDebugMode) {
      list.add('http://127.0.0.1:3000/api/chat');
      list.add('http://192.168.8.223:3000/api/chat');
    }
    return list;
  }

  static String get backendUrl => _workingUrl ?? (_candidateUrls.isNotEmpty ? _candidateUrls.first : 'https://exodo-api-23368377903.us-east1.run.app/api/chat');

  static List<String> get candidateUrls => List.unmodifiable(_candidateUrls);

  static Future<void> setWorkingUrl(String url) async {
    _workingUrl = url;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_backend_url', url);
    } catch (_) {}
  }

  static Future<void> loadSavedWorkingUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('custom_backend_url');
      if (saved == null || saved.isEmpty) return;
      // Validar antes de confiar: un túnel efímero muerto (p. ej.
      // trycloudflare) quedaría como ÚNICO candidato y envenenaría todas
      // las peticiones hasta fallar. Si no responde, se descarta y se
      // limpia la preferencia para auto-sanar el estado persistido.
      final base = saved.endsWith('/api/chat')
          ? saved.substring(0, saved.length - '/api/chat'.length)
          : saved;
      try {
        final resp = await http
            .get(Uri.parse('$base/health'))
            .timeout(const Duration(seconds: 3));
        if (resp.statusCode == 200) {
          _workingUrl = saved.endsWith('/api/chat')
              ? saved
              : '$saved/api/chat';
          return;
        }
      } catch (_) {}
      debugPrint('[ChatService] URL guardada muerta ($base): descartada');
      _workingUrl = null;
      await prefs.remove('custom_backend_url');
    } catch (_) {}
  }

  /// Todos los backends conocidos, con el que funciona (si vive) primero.
  /// La transcripción de voz SIEMPRE itera esta lista completa: nunca
  /// depender de un solo URL evita el fallo total por un candidato muerto.
  static List<String> get allBackendCandidates {
    final list = <String>[];
    final working = _workingUrl;
    if (working != null && working.isNotEmpty) list.add(working);
    for (final c in _candidateUrls) {
      if (!list.contains(c)) list.add(c);
    }
    return list;
  }

  static List<String> get voiceTranscribeUrls {
    final list = <String>[];
    for (final c in allBackendCandidates) {
      final vUrl = c.replaceAll('/api/chat', '/api/voice/transcribe');
      if (!list.contains(vUrl)) list.add(vUrl);
    }
    return list;
  }

  static String generateSessionId() {
    final rnd = math.Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // v4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    return '${bytes.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}-'
        '${bytes.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}-'
        '${bytes.sublist(6, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}-'
        '${bytes.sublist(8, 10).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}-'
        '${bytes.sublist(10, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// [F1] Cancelación delegada: ahora se gestiona atómicamente por sesión vía GenerationSession.
  static void cancelStream() {}

  /// Sonda paralela de candidatos: todos compiten con un GET /health barato y
  /// gana el primero que responda 200. Elimina el coste secuencial (~1.5s por
  /// candidato muerto) antes del POST real, que sigue saliendo UNA sola vez.
  static Future<String?> _probeFastestBackend(
    List<String> urls, {
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    if (urls.isEmpty) return null;
    if (urls.length == 1) return urls.first;
    final completer = Completer<String?>();
    var pending = urls.length;
    for (final url in urls) {
      final base = url.replaceAll('/api/chat', '');
      () async {
        try {
          final resp =
              await http.get(Uri.parse('$base/health')).timeout(timeout);
          if (resp.statusCode == 200 && !completer.isCompleted) {
            completer.complete(url);
            return;
          }
        } catch (_) {}
        pending--;
        if (pending == 0 && !completer.isCompleted) completer.complete(null);
      }();
    }
    return completer.future;
  }


  /// Consulta el estado y consumo de cuota diaria del usuario desde /api/user/usage
  static Future<Map<String, dynamic>?> getUserUsage() async {
    final session = SupabaseService.client.auth.currentSession;
    final jwt = session?.accessToken;

    for (final candidate in _candidateUrls) {
      final base = candidate.replaceAll('/api/chat', '');
      final uri = Uri.parse('$base/api/user/usage');
      try {
        final response = await http.get(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (jwt != null) 'Authorization': 'Bearer $jwt',
          },
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          _workingUrl = candidate;
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Future<void> sendMessageStream({
    required String message,
    String? conversationId,
    List<Map<String, dynamic>>? history,
    String? modelOverride,
    String? taskType, // 'simple' | 'reasoning' | null (auto): switcher Flash/Deep
    String? locale, // idioma de la interfaz -> el modelo responde en él
    List<Attachment>? attachments, // [Punto 40] archivos para multimodal
    GenerationSession? session, // [F1] Sesión atómica de generación
    void Function(Map<String, dynamic> meta)? onMeta,
    void Function(String code)? onNotice, // avisos estructurados del backend
    void Function()? onGeneratingImage, // [UX imagen] backend avisa que empieza el t2i
    required void Function(String chunk) onChunk,
    required void Function(String fullText, List<Source> sources) onComplete,
    required void Function(String error) onError,
  }) async {
    final activeSession = session ??
        GenerationSession(
          id: generateSessionId(),
          conversationId: conversationId,
        );

    final authSession = SupabaseService.client.auth.currentSession;
    final jwt = authSession?.accessToken;

    try {
      if (activeSession.isCancelled) return;

      http.StreamedResponse? response;
      http.Client? client;
      // Última respuesta REAL del servidor (no-200). Si existe, el backend
      // está vivo y respondió un error: el mensaje al usuario debe ser
      // honesto (Cód. X / caída), nunca "Sin conexión" (eso es solo para
      // fallos de red del cliente, donde nada llegó al servidor).
      http.StreamedResponse? lastServerResponse;

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

      // Sonda paralela (una sola vez por arranque): elige el backend vivo
      // más rápido sin encadenar timeouts secuenciales. El POST real sale
      // después, una única vez, contra el ganador.
      if (_workingUrl == null) {
        _workingUrl = await _probeFastestBackend(_candidateUrls);
        if (_workingUrl != null) setWorkingUrl(_workingUrl!);
      }
      if (activeSession.isCancelled) return;

      for (final url in _candidateUrls) {
        if (activeSession.isCancelled) return;
        try {
          final reqClient = activeSession.client;
          final request = http.Request('POST', Uri.parse(url));
          request.headers.addAll({
            'Content-Type': 'application/json',
            if (jwt != null) 'Authorization': 'Bearer $jwt',
          });
          request.body = jsonEncode({
            'message': message,
            // Los null NO viajan: un backend endurecido responde 400 a
            // "conversationId": null / "history": null. Dart serializa nulls
            // explícitos (la web los omite porque JSON.stringify dropea
            // undefined) — misma lección que la tolerancia de null del server.
            'conversationId': ?conversationId,
            if (history != null && history.isNotEmpty) 'history': history,
            'model_override': ?modelOverride,
            if (taskType != null && taskType != 'auto') 'taskType': taskType,
            if (locale != null && locale.isNotEmpty) 'locale': locale,
            if (attachmentsJson != null && attachmentsJson.isNotEmpty)
              'attachments': attachmentsJson, // [Punto 40+42]
          });

          final isWorkingUrl = _workingUrl == url;
          final isLocal = url.contains('localhost') ||
              url.contains('127.0.0.1') ||
              url.contains('10.0.2.2') ||
              url.contains('192.168.');
          final timeoutDuration = isWorkingUrl
              ? const Duration(seconds: 45)
              : (isLocal ? const Duration(milliseconds: 1500) : const Duration(seconds: 45));
          final resp = await reqClient.send(request).timeout(timeoutDuration);
          if (resp.statusCode == 200) {
            client = reqClient;
            response = resp;
            _workingUrl = url;
            setWorkingUrl(url);
            break;
          }
          // 429/403/402 son respuestas DEFINITIVAS del backend (límite diario,
          // plan requerido): no tiene sentido probar más candidatos. Leer el
          // mensaje del servidor y surfacearlo tal cual — antes un 429 caía
          // al error genérico "Sin conexión con el servidor".
          if (resp.statusCode == 429 || resp.statusCode == 403 || resp.statusCode == 402) {
            try {
              final body = await resp.stream.bytesToString();
              final data = jsonDecode(body);
              final serverMsg = (data is Map && data['message'] is String && (data['message'] as String).trim().isNotEmpty)
                  ? data['message'] as String
                  : null;
              if (!activeSession.isCancelled) {
                onError(serverMsg ??
                    (resp.statusCode == 429
                        ? 'Alcanzaste tu límite diario. Tu cuota se renueva mañana.'
                        : 'Tu plan no incluye esta función.'));
              }
              return;
            } catch (_) {
              if (!activeSession.isCancelled) {
                onError(resp.statusCode == 429
                    ? 'Alcanzaste tu límite diario. Tu cuota se renueva mañana.'
                    : 'Tu plan no incluye esta función.');
              }
              return;
            }
          }
          // Cualquier otro 4xx/5xx: drenar el socket y recordar la respuesta
          // REAL del servidor para el mensaje final honesto.
          try {
            await resp.stream.bytesToString().timeout(const Duration(seconds: 2));
          } catch (_) {}
          lastServerResponse = resp;
        } catch (_) {}
      }

      if (response == null || client == null) {
        if (!activeSession.isCancelled) {
          final failed = lastServerResponse;
          String errMsg;
          if (failed == null) {
            // Nada llegó al servidor: fallo de red del cliente.
            errMsg =
                'Sin conexión con el servidor. Verifica tu red e inténtalo de nuevo.';
          } else if (failed.statusCode >= 500) {
            // [Misión down] Nada "reinicia" solo: mensaje honesto de caída.
            errMsg =
                'Exodo no está disponible en este momento. Estamos trabajando para restablecer el servicio. Inténtalo de nuevo en unos minutos.';
          } else if (failed.statusCode == 413) {
            errMsg =
                'El archivo adjunto es demasiado grande. Por favor, intenta con uno más pequeño.';
          } else if (failed.statusCode == 429) {
            // C9: el límite de invitados se aplica en servidor y su cuerpo
            // JSON trae el mensaje real (límite diario alcanzado, etc.).
            errMsg =
                'Alcanzaste el límite diario de mensajes como invitado. Crea una cuenta gratuita para continuar.';
            try {
              final body = await failed.stream.bytesToString();
              final serverMsg = body.contains('"message"')
                  ? (body.split('"message":"').last.split('"').first)
                  : '';
              if (serverMsg.trim().isNotEmpty) errMsg = serverMsg;
            } catch (_) {}
          } else {
            errMsg = 'Hubo un error de conexión (Cód. ${failed.statusCode}).';
          }
          onError(errMsg);
        }
        return;
      }

      String fullText = '';
      List<Source> sources = [];
      bool isCompleted = false;
      bool errorSurfaced = false;

      // C4: watchdog de inactividad — si el servidor no manda NADA en 45s
      // (red muerta en silencio), cortamos en vez de dejar "pensando" eterno.
      final watchedStream = response.stream.timeout(
        const Duration(seconds: 45),
        onTimeout: (sink) =>
            sink.addError(TimeoutException('Sin datos del servidor por 45s')),
      );

      watchedStream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (activeSession.isCancelled) return;
              if (line.startsWith('data: ')) {
                final dataStr = line.substring(6).trim();
                if (dataStr == '[DONE]') return;
                try {
                  final data = jsonDecode(dataStr);
                  final type = data['type'];
                  if (type == 'meta') {
                    if (onMeta != null && data is Map<String, dynamic>) {
                      onMeta(data);
                    }
                  } else if (type == 'notice') {
                    // Aviso estructurado (p. ej. image_login_required)
                    if (onNotice != null && data['code'] is String) {
                      onNotice(data['code'] as String);
                    }
                  } else if (type == 'heartbeat') {
                    // [Punto 41+42] Heartbeat del backend para mantener viva la conexión SSE.
                  } else if (type == 'generating_image') {
                    // [UX #1] El backend avisa que está esperando la imagen de
                    // DashScope (8–12s). La app muestra el placeholder shimmer.
                    onGeneratingImage?.call();
                  } else if (type == 'chunk') {
                    final content = data['content'] as String?;
                    if (content != null && content.isNotEmpty) {
                      fullText += content;
                      onChunk(content);
                    }
                  } else if (type == 'done') {
                    if (isCompleted) return;
                    // C5: si ya se surfaceó un error, ignorar el done para no
                    // crear una burbuja assistant VACÍA después del error.
                    if (errorSurfaced) return;
                    isCompleted = true;
                    final doneContent = data['content'] as String? ??
                        data['message'] as String?;
                    final effectiveText = fullText.isNotEmpty
                        ? fullText
                        : (doneContent ?? '');
                    final rawSources = data['sources'];
                    if (rawSources is List) {
                      sources = rawSources
                          .whereType<Map>()
                          .map(
                            (s) => Source.fromJson(
                              Map<String, dynamic>.from(s),
                            ),
                          )
                          .toList();
                    }
                    _enrichSources(doneContent ?? effectiveText, effectiveText, sources)
                        .then((enriched) {
                          if (!activeSession.isCancelled) {
                            onComplete(effectiveText, enriched);
                          }
                        })
                        .catchError((_) {
                          if (!activeSession.isCancelled) {
                            onComplete(effectiveText, sources);
                          }
                        });
                  } else if (type == 'error') {
                    if (!activeSession.isCancelled) {
                      errorSurfaced = true;
                      onError(data['content'] as String? ?? 'Error en streaming');
                    }
                  }
                } catch (_) {}
              }
            },
            onDone: () {
              if (activeSession.isCancelled || isCompleted || errorSurfaced) {
                return;
              }
              if (fullText.isNotEmpty) {
                isCompleted = true;
                onComplete(fullText, sources);
              } else {
                onError('La conexión se cerró inesperadamente.');
              }
            },
            onError: (e) {
              if (activeSession.isCancelled || errorSurfaced) return;
              if (e is TimeoutException) {
                onError('La conexión se quedó sin respuesta. Inténtalo de nuevo.');
                return;
              }
              // [Misión down] Los errores de red crudos (SocketException en
              // inglés, ClientException...) nunca llegan al usuario tal cual.
              onError(_mapNetworkError(e));
            },
          );
    } catch (e) {
      if (!activeSession.isCancelled) onError(_mapNetworkError(e));
    }
  }

  /// Mapea excepciones de red a mensaje de marca. Todo lo demás pasa tal cual
  /// (ya viene sanitizado del backend o de las ramas de arriba).
  static String _mapNetworkError(Object e) {
    const networkTypes = [
      'SocketException',
      'HandshakeException',
      'TlsException',
      'ClientException',
      'HttpException',
      'Connection closed',
      'Connection reset',
      'Failed host lookup',
      'Network is unreachable',
    ];
    final s = e.toString();
    for (final t in networkTypes) {
      if (s.contains(t)) {
        return 'No pudimos conectar. Reintentar.';
      }
    }
    return s;
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

  /// Genera un título contextual ultra-conciso (2 a 4 palabras) llamando al
  /// endpoint LLM del backend `/api/chat/title` con qwen3.7-flash.
  static Future<String?> generateTitle({
    required String conversationId,
    required String userText,
    required String assistantText,
    String locale = 'es',
  }) async {
    for (final candidate in _candidateUrls) {
      final titleUrl = candidate.endsWith('/api/chat')
          ? '$candidate/title'
          : '${candidate.replaceAll(RegExp(r'/api/chat.*'), '')}/api/chat/title';
      try {
        final session = SupabaseService.client.auth.currentSession;
        final token = session?.accessToken;
        final headers = {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        };
        final body = jsonEncode({
          if (conversationId.isNotEmpty) 'conversationId': conversationId,
          'locale': locale,
          'messages': [
            {'role': 'user', 'content': userText},
            {'role': 'assistant', 'content': assistantText},
          ],
        });

        final resp = await http
            .post(
              Uri.parse(titleUrl),
              headers: headers,
              body: body,
            )
            .timeout(const Duration(seconds: 8));

        if (resp.statusCode == 200) {
          final data = jsonDecode(utf8.decode(resp.bodyBytes));
          if (data is Map && data['title'] is String && (data['title'] as String).trim().isNotEmpty) {
            _workingUrl = candidate;
            return (data['title'] as String).trim();
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ChatService] generateTitle failed on $titleUrl: $e');
        }
      }
    }
    return null;
  }
}

