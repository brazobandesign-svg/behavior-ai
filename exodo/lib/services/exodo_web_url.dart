import 'package:flutter/foundation.dart';

/// URL del portal web de Éxodo (proyecto exodo-web).
///
/// Producción: URL pública oficial accesible por cualquier usuario y tester desde internet.
/// Si se pasa `--dart-define=EXODO_WEB_URL=https://...`, tiene máxima prioridad.
const String _prodEnvUrl = String.fromEnvironment('EXODO_WEB_URL');

/// URL pública oficial en la web (desplegada en Netlify).
/// Sustituye con tu subdominio o dominio configurado en Netlify (ej: https://exodoweb.netlify.app).
const String _defaultPublicUrl = 'https://exodoweb.netlify.app';

/// IP LAN de desarrollo: solo se usa si estás corriendo en modo debug con el dev server
/// de Vite (`npm run dev -- --host`) conectado al mismo Wi-Fi de tu PC.
const String _lanDevUrl = 'http://192.168.8.223:5173';

String get exodoWebUrl {
  if (_prodEnvUrl.isNotEmpty) return _prodEnvUrl;
  // En versión release instalada en teléfonos de usuarios y testers externos,
  // NUNCA usar la IP privada LAN; siempre la URL pública:
  if (kReleaseMode) return _defaultPublicUrl;
  // En modo debug local:
  return _lanDevUrl;
}
