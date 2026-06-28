import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Servicio para interactuar con los Widgets de Pantalla de Inicio nativos (Android).
class WidgetService {
  static final WidgetService instance = WidgetService._();
  WidgetService._();

  static const MethodChannel _channel = MethodChannel('com.behavior.exodo/widgets');

  /// Solicita al sistema operativo (Android 12+) anclar el widget seleccionado al escritorio.
  /// [type] puede ser 'square' o 'horizontal'.
  Future<bool> requestPinWidget({required String type}) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('pinWidget', {'type': type});
      return result ?? false;
    } catch (e) {
      debugPrint('Error solicitando pin de widget: $e');
      return false;
    }
  }

  /// Obtiene la acción inicial si la app fue abierta desde el widget de inicio.
  Future<String?> getInitialAction() async {
    try {
      return await _channel.invokeMethod<String>('getInitialAction');
    } catch (e) {
      debugPrint('Error obteniendo initial action: $e');
      return null;
    }
  }

  /// Escucha acciones cuando la app ya está abierta y el usuario toca el widget.
  void setActionListener(Function(String action) onAction) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onWidgetAction') {
        final String? action = call.arguments as String?;
        if (action != null) {
          onAction(action);
        }
      }
    });
  }
}
