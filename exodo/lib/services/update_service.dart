// ═══════════════════════════════════════════════════════════════════════════════
// UPDATE SERVICE — Auto-actualización de APK fuera de Google Play
// ───────────────────────────────────────────────────────────────────────────────
// Distribución directa por APK: GitHub Releases aloja el .apk gratis y sirve
// descargas rápidas por CDN. Flujo (todo SILENCIOSO hasta el final):
//   1. Al arrancar (máx. una vez cada 12h) se lee version.json del repo.
//   2. Si latest_version_code > versionCode instalado ⇒ se descarga el APK
//      en segundo plano SIN avisar (el usuario sigue usando la app normal).
//   3. Al completar: queda listo para instalar (diálogo en la app y/o
//      notificación del sistema — Android exige confirmar la instalación;
//      ninguna app puede autoinstalarse sin ser tienda del sistema).
//
// version.json (commiteado en la raíz de exodo-app):
//   { "latest_version_code": 2, "latest_version_name": "1.1.0",
//     "download_url": ".../releases/download/v1.1.0/exodo.apk",
//     "changelog": "..." }
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String downloadUrl;
  final String changelog;
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    required this.changelog,
  });
}

/// Parseo en isolate (el JSON puede traer changelogs largos).
UpdateInfo? _parseVersionJson(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final code = decoded['latest_version_code'];
    final url = decoded['download_url'];
    if (code is! int || url is! String || url.isEmpty) return null;
    return UpdateInfo(
      versionCode: code,
      versionName: (decoded['latest_version_name'] as String?) ?? '',
      downloadUrl: url,
      changelog: (decoded['changelog'] as String?) ?? '',
    );
  } catch (_) {
    return null;
  }
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  /// Fuente de verdad del manifiesto de versión (repo público; si el repo se
  /// vuelve privado, mover este archivo al backend o a un gist público).
  static const String versionJsonUrl =
      'https://raw.githubusercontent.com/brazobandesign-svg/behavior-ai/main/exodo-app/version.json';

  static const String _lastCheckKey = 'exodo_update_last_check';
  static const Duration _minCheckInterval = Duration(hours: 12);

  /// APK ya descargado esperando instalación (path no-null ⇒ mostrar CTA).
  final ValueNotifier<String?> readyToInstall = ValueNotifier(null);
  UpdateInfo? _pendingInfo;

  UpdateInfo? get pendingInfo => _pendingInfo;

  /// Chequeo silencioso: errores se tragan siempre — la app jamás arranca
  /// con un diálogo de update roto. Máx. una vez cada 12h.
  Future<void> checkAndDownloadSilently() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _minCheckInterval.inMilliseconds) return;
      await prefs.setInt(_lastCheckKey, now);

      final resp = await http
          .get(Uri.parse(versionJsonUrl))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return;
      final info = await compute(_parseVersionJson, resp.body);
      if (info == null) return;

      final installedCode = await _installedVersionCode();
      if (installedCode == null || info.versionCode <= installedCode) return;

      final path = await _downloadApk(info);
      if (path != null) {
        _pendingInfo = info;
        readyToInstall.value = path;
      }
    } catch (_) {
      // Silencio total: el update nunca interrumpe la experiencia.
    }
  }

  Future<int?> _installedVersionCode() async {
    try {
      return await MethodChannel('exodo/app_info').invokeMethod<int>('versionCode');
    } catch (_) {
      return null;
    }
  }

  /// Descarga el APK a un archivo temporal. Silenciosa; sin barra de
  /// progreso (el APK es ~80MB y el CDN de GitHub es rápido).
  Future<String?> _downloadApk(UpdateInfo info) async {
    try {
      final resp = await http
          .get(Uri.parse(info.downloadUrl))
          .timeout(const Duration(minutes: 10));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return null;
      final dir = await getTemporaryDirectory();
      final name =
          'exodo-update-${info.versionName.isNotEmpty ? info.versionName : info.versionCode}.apk';
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Lanza el instalador nativo de Android (pantalla de confirmación del
  /// sistema — requisito ineludible fuera de Play Store).
  Future<bool> install() async {
    final path = readyToInstall.value;
    if (path == null) return false;
    final result = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  }
}
