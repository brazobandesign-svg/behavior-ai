import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'chat_service.dart';

/// Servicio centralizado de Text-To-Speech con soporte para CosyVoice y motor nativo.
class TtsService {
  TtsService._() {
    _audioPlayer.onPlayerComplete.listen((_) {
      _setSpeaking(false);
    });
    _audioPlayer.onPlayerStateChanged.listen((state) {
      _setSpeaking(state == PlayerState.playing);
    });
  }

  static final TtsService instance = TtsService._();

  FlutterTts? _ttsInstance;
  FlutterTts get _tts => _ttsInstance ??= FlutterTts();
  bool _initialized = false;
  bool _isSpeaking = false;

  final AudioPlayer _audioPlayer = AudioPlayer();

  /// Notificador reactivo para widgets de UI que necesitan reaccionar en tiempo real
  final ValueNotifier<bool> isSpeakingNotifier = ValueNotifier<bool>(false);

  bool get isSpeaking => _isSpeaking;

  void _setSpeaking(bool val) {
    _isSpeaking = val;
    if (isSpeakingNotifier.value != val) {
      isSpeakingNotifier.value = val;
    }
  }

  String? _currentLanguage;
  String? get currentLanguage => _currentLanguage;

  // Voz natural de CosyVoice (nombre real de voz, NO el nombre del modelo).
  static const String _kCosyvoiceVoice = 'longwan';
  static const Duration _kCandidateTimeout = Duration(seconds: 3);

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _tts.setSharedInstance(true);
      await _tts.awaitSpeakCompletion(true);

      _tts.setStartHandler(() {
        _setSpeaking(true);
      });
      _tts.setCompletionHandler(() {
        _setSpeaking(false);
      });
      _tts.setErrorHandler((msg) {
        _setSpeaking(false);
        debugPrint('[TtsService] error: $msg');
      });
      _tts.setCancelHandler(() {
        _setSpeaking(false);
      });

      _initialized = true;
    } catch (e) {
      _initialized = false;
      rethrow;
    }
  }

  static String _localeForApp(String appLocale) {
    switch (appLocale) {
      case 'es':
        return 'es-DO';
      case 'en':
        return 'en-US';
      case 'fr':
        return 'fr-FR';
      case 'pt':
        return 'pt-BR';
      case 'it':
        return 'it-IT';
      case 'de':
        return 'de-DE';
      default:
        return 'en-US';
    }
  }

  /// Elimina símbolos de Markdown para que el TTS no lea asteriscos,
  /// almohadillas, corchetes, paréntesis, URLs ni bloques de código.
  static String _sanitizeForSpeech(String input) {
    var text = input;
    // URLs sueltas (evita leer "h t t p ..." en voz alta)
    text = text.replaceAll(RegExp(r'https?://\S+'), ' ');
    // Símbolos de Markdown, incluidas las comillas de bloques de código
    text = text.replaceAll(RegExp(r'[*#\[\]()_>|`]'), ' ');
    // Colapsar espacios múltiples
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  Future<bool> speak(String text, {required String appLocale}) async {
    if (text.trim().isEmpty) return false;

    try {
      await _ensureInitialized();

      final locale = _localeForApp(appLocale);
      if (_currentLanguage != locale) {
        await _tts.setLanguage(locale);
        _currentLanguage = locale;
      }

      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.5);

      if (_isSpeaking) {
        await stop();
      }

      final result = await _tts.speak(text);
      final ok = result == 1;
      _setSpeaking(ok);
      return ok;
    } catch (e) {
      _setSpeaking(false);
      debugPrint('[TtsService] speak() falló: $e');
      return false;
    }
  }

  Future<void> speakWithBackend(String text) async {
    if (text.trim().isEmpty) return;

    final cleanText = _sanitizeForSpeech(text);
    if (cleanText.isEmpty) return;

    await stop();

    try {
      for (final candidate in ChatService.candidateUrls) {
        final ttsUrl = candidate.replaceAll('/api/chat', '/api/voice/tts');
        debugPrint('[TTS] Intentando TTS en: $ttsUrl');

        final response = await http
            .post(
              Uri.parse(ttsUrl),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({
                'text': cleanText,
                'voice': _kCosyvoiceVoice,
              }),
            )
            .timeout(_kCandidateTimeout);

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          debugPrint('[TTS] Backend respondió OK (${response.bodyBytes.length} bytes)');

          final dir = await getTemporaryDirectory();
          final ext = _audioExtensionForResponse(response);
          final filename = 'exodo_tts_${DateTime.now().millisecondsSinceEpoch}.$ext';
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(response.bodyBytes, flush: true);

          await _audioPlayer.play(DeviceFileSource(file.path));
          _setSpeaking(true);
          return;
        }
      }

      debugPrint('[TTS] Candidatos del backend agotados, fallback a motor nativo');
      await _fallbackToNativeTts(text);
    } catch (e) {
      debugPrint('[TTS] Excepción en speakWithBackend: $e, fallback a nativo');
      await _fallbackToNativeTts(text);
    }
  }

  Future<void> _fallbackToNativeTts(String text) async {
    try {
      await _ensureInitialized();
      if (_currentLanguage == null) {
        await _tts.setLanguage('es-DO');
        _currentLanguage = 'es-DO';
      }
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      // FIX (TTS-speed 2026-08-19): tempo natural 0.48-0.50. El valor previo
      // (0.9) hacía que la voz sonara acelerada/robótica en el LG V60.
      await _tts.setSpeechRate(0.5);
      await _tts.stop();
      await _tts.speak(_sanitizeForSpeech(text));
      _setSpeaking(true);
    } catch (e) {
      _setSpeaking(false);
      debugPrint('[TtsService] fallback flutter_tts falló: $e');
    }
  }

  /// Detiene inmediatamente cualquier reproducción de audio activa.
  Future<void> stop() async {
    _setSpeaking(false);
    try {
      await _audioPlayer.stop();
    } catch (_) {}

    if (_initialized) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
    _setSpeaking(false);
  }

  static String _audioExtensionForResponse(http.Response response) {
    final ct = (response.headers['content-type'] ?? '').toLowerCase();
    if (ct.contains('mpeg') || ct.contains('mp3')) return 'mp3';
    if (ct.contains('wav') || ct.contains('wave')) return 'wav';
    if (ct.contains('ogg')) return 'ogg';
    if (ct.contains('webm')) return 'webm';
    if (ct.contains('aac') || ct.contains('m4a') || ct.contains('mp4')) {
      return 'm4a';
    }

    final body = response.bodyBytes;
    if (body.length >= 12) {
      if (body[0] == 0x52 && body[1] == 0x49 && body[2] == 0x46 && body[3] == 0x46) {
        return 'wav';
      }
      if (body[0] == 0x49 && body[1] == 0x44 && body[2] == 0x33) {
        return 'mp3';
      }
      if ((body[0] == 0xFF) && (body[1] == 0xFB || body[1] == 0xFA || body[1] == 0xF3 || body[1] == 0xF2)) {
        return 'mp3';
      }
    }
    return 'mp3';
  }
}
