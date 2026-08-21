import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// [Fix LG V60 #2] Servicio de persistencia de adjuntos en el sistema de
/// archivos local. Permite reducir el tamaño de SQLite moviendo los bytes
/// binarios de imágenes a un directorio dedicado dentro de
/// `getApplicationDocumentsDirectory()`, conservando únicamente metadatos
/// (fileName, mimeType) en la columna `attachments_json` de Drift.
///
/// Se mantiene retrocompatibilidad con adjuntos guardados como base64
/// inline: si no hay archivo en disco, el bubble usa `Image.memory`.
class AttachmentStorage {
  AttachmentStorage._();

  static final AttachmentStorage instance = AttachmentStorage._();

  static const String _kAttachmentsDir = 'attachments';
  static const String _kThumbnailsDir = 'attachments/thumbs';

  Directory? _rootDir;
  Directory? _thumbsDir;

  Future<Directory> _ensureRoot() async {
    if (_rootDir != null) return _rootDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_kAttachmentsDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _rootDir = dir;
    return dir;
  }

  Future<Directory> _ensureThumbs() async {
    if (_thumbsDir != null) return _thumbsDir!;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_kThumbnailsDir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _thumbsDir = dir;
    return dir;
  }

  /// Persiste los bytes binarios del adjunto en `attachments/` y devuelve
  /// una ruta absoluta. Es idempotente: si el archivo ya existe en disco
  /// no vuelve a escribirlo.
  Future<String> persistBytes({
    required String messageId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) return '';
    final dir = await _ensureRoot();
    final safeName = _sanitizeFileName(fileName);
    final file = File('${dir.path}/${messageId}_$safeName');
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }

  /// Copia un archivo recién seleccionado desde la caché volátil del
  /// image_picker/file_picker al almacenamiento permanente `attachments/`
  /// y devuelve la ruta absoluta de la copia. Se invoca en el momento de
  /// la selección (no al guardar el mensaje) para que la foto sobreviva
  /// aunque la app se cierre o el OS purgue la caché antes del envío.
  /// Devuelve '' si el origen no existe (p. ej. plataforma web).
  Future<String> persistPickedFile({
    required String sourcePath,
    required String fileName,
  }) async {
    if (sourcePath.isEmpty) return '';
    final src = File(sourcePath);
    if (!await src.exists()) return '';
    final dir = await _ensureRoot();
    var ext = _fileExtension(fileName);
    if (ext.isEmpty) ext = _fileExtension(sourcePath);
    if (ext.isEmpty) ext = '.jpg';
    final file =
        File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}$ext');
    await src.copy(file.path);
    return file.path;
  }

  /// Lee bytes desde disco. Si el archivo no existe (datos antiguos o
  /// respaldo tras desinstalación), devuelve `null` y el caller debe
  /// recurrir al base64 almacenado en SQLite.
  Future<Uint8List?> loadFromPath(String filePath) async {
    if (filePath.isEmpty) return null;
    final file = File(filePath);
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Borra los archivos físicos asociados a un mensaje (limpieza al
  /// eliminar la conversación o el adjunto).
  Future<void> deleteForMessage(String messageId) async {
    try {
      final dir = await _ensureRoot();
      final thumbsDir = await _ensureThumbs();
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains(messageId)) {
          await entity.delete().catchError((_) => entity);
        }
      }
      await for (final entity in thumbsDir.list()) {
        if (entity is File && entity.path.contains(messageId)) {
          await entity.delete().catchError((_) => entity);
        }
      }
    } catch (_) {}
  }

  /// Decodifica bytes desde un JSON-encoded base64 (formato antiguo).
  /// Devuelve `Uint8List(0)` si el string es inválido o vacío.
  static Uint8List decodeBase64(String? encoded) {
    if (encoded == null || encoded.isEmpty) return Uint8List(0);
    try {
      return base64Decode(encoded);
    } catch (_) {
      return Uint8List(0);
    }
  }

  /// Codifica bytes a base64 para almacenamiento en JSON.
  static String encodeBase64(Uint8List bytes) {
    if (bytes.isEmpty) return '';
    return base64Encode(bytes);
  }

  static String _sanitizeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }

  /// Extensión con punto de un nombre de archivo ('.jpg'), o '' si no
  /// tiene. Toma solo el basename para no confundirse con puntos en la ruta.
  static String _fileExtension(String name) {
    final base = name.replaceAll('\\', '/').split('/').last;
    final dot = base.lastIndexOf('.');
    if (dot <= 0) return '';
    return base.substring(dot).toLowerCase();
  }
}
