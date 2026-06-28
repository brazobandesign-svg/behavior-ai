import 'package:flutter_tts/flutter_tts.dart';

/// Servicio centralizado de Text-To-Speech.
///
/// - Singleton para que solo exista UNA instancia de [FlutterTts] en la app
///   (algunos motores nativos se confunden con múltiples instancias).
/// - Mapea el código de locale de la app (es, en, fr, pt, it, de) al locale
///   BCP-47 que el motor TTS del sistema espera.
/// - Maneja el ciclo de vida: si el usuario llama [speak] mientras hay otra
///   reproducción en curso, primero hace stop para no encadenar audios.
///
/// Nota: este servicio NO es responsable de mostrar SnackBars; eso vive en
/// el caller (chat_screen.dart) para mantener separación UI / lógica.
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  /// Idioma actual configurado en el motor TTS (BCP-47), o null si no se
  /// inicializó todavía.
  String? _currentLanguage;

  String? get currentLanguage => _currentLanguage;

  /// Inicializa el motor y registra handlers de progreso / error.
  /// Es idempotente: llamarlo varias veces no duplica handlers.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _tts.setSharedInstance(true);
      await _tts.awaitSpeakCompletion(true);

      _tts.setStartHandler(() {
        _isSpeaking = true;
      });
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
      });
      _tts.setErrorHandler((msg) {
        _isSpeaking = false;
        // Error real lo verá el caller vía SnackBar; aquí solo reseteamos estado.
        // ignore: avoid_print
        print('[TtsService] error: $msg');
      });
      _tts.setCancelHandler(() {
        _isSpeaking = false;
      });

      _initialized = true;
    } catch (e) {
      _initialized = false;
      rethrow;
    }
  }

  /// Mapea el código corto de la app (es, en, fr, pt, it, de) al locale
  /// BCP-47 que el motor TTS del sistema acepta.
  ///
  /// Si el sistema no tiene una voz para el locale solicitado, el motor
  /// cae a su voz por defecto (típicamente en-US). Esto es comportamiento
  /// esperado; no lanzamos error.
  static String _localeForApp(String appLocale) {
    switch (appLocale) {
      case 'es':
        return 'es-DO'; // español dominicano, mismo que STT
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

  /// Reproduce [text] con el motor TTS del sistema.
  ///
  /// - Si ya hay algo en curso, lo detiene primero.
  /// - [appLocale] es el código corto de la app (es, en, fr, …).
  /// - Devuelve `true` si la reproducción arrancó OK, `false` si falló
  ///   (en cuyo caso el caller debería mostrar un SnackBar).
  Future<bool> speak(String text, {required String appLocale}) async {
    if (text.trim().isEmpty) return false;

    try {
      await _ensureInitialized();

      final locale = _localeForApp(appLocale);
      if (_currentLanguage != locale) {
        await _tts.setLanguage(locale);
        _currentLanguage = locale;
      }

      // Defaults: voz natural, volumen al máximo, pitch neutro.
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.5); // 0.0 (lento) → 1.0 (rápido)

      if (_isSpeaking) {
        await _tts.stop();
        _isSpeaking = false;
      }

      final result = await _tts.speak(text);
      // flutter_tts devuelve 1 en Android si arrancó OK, 0 si no.
      return result == 1;
    } catch (e) {
      _isSpeaking = false;
      // ignore: avoid_print
      print('[TtsService] speak() falló: $e');
      return false;
    }
  }

  /// Detiene cualquier reproducción en curso. No lanza errores.
  Future<void> stop() async {
    if (!_initialized) return;
    try {
      await _tts.stop();
      _isSpeaking = false;
    } catch (_) {
      // ignorar — stop es best-effort
    }
  }
}
