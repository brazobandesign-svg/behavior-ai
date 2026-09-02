import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Servicio de almacenamiento en disco persistente para imágenes generadas y de red.
///
/// Resuelve:
/// 1. Cero parpadeo o pantallas en blanco al salir y entrar al chat (la imagen se
///    lee directamente de almacenamiento local en 0ms).
/// 2. Persistencia permanente aunque la URL firmada de DashScope (OSS) expire.
/// 3. Soporte offline total para imágenes ya descargadas.
class ImageCacheService {
  static final Map<String, File> _memoryIndex = {};
  static Directory? _cacheDir;
  static final Map<String, Future<File?>> _inFlightDownloads = {};

  /// Inicializa o recupera el directorio de almacenamiento local de imágenes.
  static Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}/exodo_image_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Convierte una URL en un nombre de archivo único, seguro y determinista.
  static String _urlToFilename(String url) {
    final uri = Uri.tryParse(url);
    final segments = uri?.pathSegments ?? [];
    String rawName = segments.isNotEmpty ? segments.last : 'image.png';
    if (!rawName.contains('.')) rawName = '$rawName.png';
    // Sanitizar caracteres especiales
    final cleanName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');

    // FNV-1a 64-bit hash del string completo de la URL
    int hash = 0xcbf29ce484222325;
    for (int i = 0; i < url.length; i++) {
      hash ^= url.codeUnitAt(i);
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final hexHash = hash.toRadixString(16).padLeft(16, '0');
    // Longitud máxima de seguridad para filesystem
    final trimmedName = cleanName.length > 32 ? cleanName.substring(0, 32) : cleanName;
    return '${hexHash}_$trimmedName';
  }

  /// Retorna síncronamente el archivo local si ya está en caché en memoria o verificado.
  static File? getCachedFileFast(String url) {
    if (_memoryIndex.containsKey(url)) {
      final file = _memoryIndex[url]!;
      if (file.existsSync() && file.lengthSync() > 0) {
        return file;
      }
      _memoryIndex.remove(url);
    }
    if (_cacheDir != null) {
      final filename = _urlToFilename(url);
      final file = File('${_cacheDir!.path}/$filename');
      if (file.existsSync() && file.lengthSync() > 0) {
        _memoryIndex[url] = file;
        return file;
      }
    }
    return null;
  }

  /// Busca el archivo en disco o lo descarga en background guardándolo de forma permanente.
  static Future<File?> getOrDownloadImage(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    if (url.isEmpty || !url.startsWith('http')) return null;

    // 1. Verificación rápida en memoria/disco
    final existing = getCachedFileFast(url);
    if (existing != null) return existing;

    final dir = await _getCacheDirectory();
    final filename = _urlToFilename(url);
    final destinationFile = File('${dir.path}/$filename');

    if (await destinationFile.exists() && (await destinationFile.length()) > 0) {
      _memoryIndex[url] = destinationFile;
      return destinationFile;
    }

    // 2. Si ya hay una descarga en progreso para esta URL, unirse a ella
    if (_inFlightDownloads.containsKey(url)) {
      return await _inFlightDownloads[url]!;
    }

    // 3. Descargar y guardar atómicamente
    final future = _downloadInternal(url, destinationFile, onProgress);
    _inFlightDownloads[url] = future;
    try {
      final result = await future;
      return result;
    } finally {
      _inFlightDownloads.remove(url);
    }
  }

  static Future<File?> _downloadInternal(
    String url,
    File destinationFile,
    void Function(double progress)? onProgress,
  ) async {
    final tempFile = File('${destinationFile.path}.tmp');
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        debugPrint('[ImageCacheService] Error HTTP ${streamedResponse.statusCode} al descargar $url');
        return null;
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = tempFile.openWrite();

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(receivedBytes / totalBytes);
        }
      }

      await sink.flush();
      await sink.close();

      if (await tempFile.exists() && (await tempFile.length()) > 0) {
        if (await destinationFile.exists()) {
          await destinationFile.delete();
        }
        await tempFile.rename(destinationFile.path);
        _memoryIndex[url] = destinationFile;
        return destinationFile;
      }
      return null;
    } catch (e) {
      debugPrint('[ImageCacheService] Falló descarga de imagen: $e');
      if (await tempFile.exists()) {
        try { await tempFile.delete(); } catch (_) {}
      }
      return null;
    }
  }
}
