import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Servicio centralizado de versión de la aplicación.
///
/// Lee dinámicamente el `versionName` y `versionCode` del paquete nativo
/// instalado a través del canal de plataforma `exodo/app_info`. Si no está
/// disponible (desarrollo web, desktop o fallback), utiliza las constantes
/// de compilación alineadas con pubspec.yaml (1.2.5+10).
class AppVersion {
  AppVersion._();

  static const String fallbackVersionName = '1.2.6';
  static const int fallbackVersionCode = 11;

  static String _versionName = fallbackVersionName;
  static int _versionCode = fallbackVersionCode;
  static bool _initialized = false;

  static String get versionName => _versionName;
  static int get versionCode => _versionCode;

  /// Formato de versión legible para el usuario: "v1.2.5 (10)"
  static String get display => 'v$_versionName ($_versionCode)';

  /// Etiqueta para el badge en el menú al presionar el logo: "v1.2.5 (10)"
  static String get badgeDisplay => 'v$_versionName ($_versionCode)';

  /// Inicializa la lectura asíncrona desde el sistema operativo.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      const channel = MethodChannel('exodo/app_info');
      final code = await channel.invokeMethod<int>('versionCode');
      final name = await channel.invokeMethod<String>('versionName');
      if (code != null && code > 0) _versionCode = code;
      if (name != null && name.trim().isNotEmpty) _versionName = name.trim();
      _initialized = true;
    } catch (e) {
      debugPrint('[AppVersion] Fallback a versión estática: $e');
    }
  }
}
