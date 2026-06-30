import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Servicio para interactuar con el Widget de Pantalla de Inicio nativo estilo Grok (Android).
class WidgetService {
  static final WidgetService instance = WidgetService._();
  WidgetService._();

  static const MethodChannel _channel = MethodChannel('com.behavior.exodo/widgets');

  /// Solicita al sistema operativo anclar el widget al escritorio.
  Future<bool> requestPinWidget({String type = 'grok'}) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('pinWidget', {'type': type});
      return result ?? false;
    } catch (e) {
      debugPrint('Error solicitando pin de widget: $e');
      return false;
    }
  }

  /// Obtiene el mensaje introducido por el usuario desde el overlay flotante del widget si abrió la app.
  Future<String?> getInitialPrompt() async {
    try {
      return await _channel.invokeMethod<String>('getInitialPrompt');
    } catch (e) {
      debugPrint('Error obteniendo initial prompt: $e');
      return null;
    }
  }

  /// Escucha mensajes cuando la app ya está abierta en segundo plano y el usuario envía un prompt desde el widget.
  void setPromptListener(Function(String prompt) onPrompt) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWidgetPrompt') {
        final String? prompt = call.arguments as String?;
        if (prompt != null && prompt.isNotEmpty) {
          onPrompt(prompt);
        }
      }
    });
  }
}
