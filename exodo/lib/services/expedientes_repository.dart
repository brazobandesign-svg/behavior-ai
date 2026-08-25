import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_service.dart';
import 'supabase_service.dart';

/// Modelo que representa un expediente privado del usuario.
///
/// Equivale a una fila de la tabla `public.expedientes`.
class Expediente {
  final String id;
  final String? chatId;
  final String title;
  final String category; // 'documento' | 'tabla' | 'interactivo'
  final String fileFormat; // 'docx' | 'xlsx' | 'pdf' | 'html' | 'svg' | 'md'
  final String? contentPayload; // sólo presente en el detalle (GET /:id)
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Expediente({
    required this.id,
    this.chatId,
    required this.title,
    required this.category,
    required this.fileFormat,
    this.contentPayload,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory Expediente.fromJson(Map<String, dynamic> json) {
    return Expediente(
      id: json['id'] as String? ?? '',
      chatId: json['chat_id'] as String?,
      title: json['title'] as String? ?? 'Sin título',
      category: json['category'] as String? ?? 'documento',
      fileFormat: json['file_format'] as String? ?? 'md',
      contentPayload: json['content_payload'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'title': title,
      'category': category,
      'file_format': fileFormat,
      'content_payload': contentPayload,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Repositorio para la gestión de expedientes privados (módulo "Expedientes").
/// Clave de caché de expedientes por cuenta — función pura y testeable.
/// [uid] null o vacío → scope 'anon' (mismo formato que usaba el getter).
String expedientesPrefsKeyFor(String? uid) {
  final scope = (uid == null || uid.isEmpty) ? 'anon' : uid;
  return 'exodo_local_expedientes_$scope';
}

/// Combina persistencia local inmediata (SharedPreferences) con sincronización en la nube (Supabase).
///
/// Combina persistencia local inmediata (SharedPreferences) con sincronización en la nube (Supabase).
class ExpedientesRepository {
  ExpedientesRepository._();
  static final ExpedientesRepository instance = ExpedientesRepository._();

  /// CLAVE POR CUENTA: cada usuario autenticado tiene su propio caché local.
  /// La llave global antigua ('exodo_local_expedientes') mezclaba expedientes
  /// de todas las cuentas del dispositivo y se purga una sola vez (ver
  /// _purgeLegacyKeyIfNeeded); la nube es la fuente de verdad por RLS.
  static String get _prefsKey =>
      expedientesPrefsKeyFor(SupabaseService.client.auth.currentUser?.id);

  static const String _legacyPrefsKey = 'exodo_local_expedientes';

  static String get _baseEndpoint {
    final base = ChatService.backendUrl
        .replaceAll('/api/chat', '')
        .replaceAll('/chat', '')
        .replaceAll(RegExp(r'/+$'), '');
    return '$base/api/expedientes';
  }

  static String? get _jwt =>
      SupabaseService.client.auth.currentSession?.accessToken;

  static Map<String, String> get _headers => {
    'Authorization': 'Bearer ${_jwt ?? ''}',
    'Content-Type': 'application/json',
  };

  static String _generateUuid() {
    final rnd = Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // v4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
    return '${bytes.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}-'
        '${bytes.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}-'
        '${bytes.sublist(6, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}-'
        '${bytes.sublist(8, 10).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}-'
        '${bytes.sublist(10, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// Purga UNA sola vez el caché global legacy (mezclaba cuentas).
  /// No se importa a propósito: su contenido puede contener expedientes de
  /// otras cuentas; la nube repobla el caché del usuario actual vía /api.
  Future<void> _purgeLegacyKeyIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_legacyPrefsKey)) {
        await prefs.remove(_legacyPrefsKey);
        debugPrint('[ExpedientesRepository] Caché legacy global purgada.');
      }
    } catch (_) {}
  }

  Future<List<Expediente>> _loadLocal() async {
    try {
      await _purgeLegacyKeyIfNeeded();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => Expediente.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('[ExpedientesRepository] Error cargando expedientes locales: $e');
      return [];
    }
  }

  Future<void> _saveLocal(List<Expediente> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(list.map((e) => e.toJson()).toList());
      await prefs.setString(_prefsKey, raw);
    } catch (e) {
      debugPrint('[ExpedientesRepository] Error guardando expedientes locales: $e');
    }
  }

  /// Lista los expedientes del usuario autenticado.
  Future<List<Expediente>> listExpedientes({
    String? category,
    int limit = 50,
    int offset = 0,
  }) async {
    final localList = await _loadLocal();

    // Intentar sincronizar en segundo plano si hay sesión
    if (_jwt != null) {
      final uri = Uri.parse(
        '$_baseEndpoint?limit=$limit&offset=$offset'
        '${category != null && category.isNotEmpty ? '&category=$category' : ''}',
      );
      try {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final items = decoded['items'] as List<dynamic>? ?? [];
          final cloudItems = items
              .whereType<Map<String, dynamic>>()
              .map((e) => Expediente.fromJson(e))
              .toList();

          // Merge items preserving local payload and metadata
          final map = {for (final e in localList) e.id: e};
          for (final c in cloudItems) {
            final existing = map[c.id];
            map[c.id] = Expediente(
              id: c.id,
              chatId: c.chatId ?? existing?.chatId,
              title: c.title,
              category: c.category,
              fileFormat: c.fileFormat,
              contentPayload: (c.contentPayload != null && c.contentPayload!.isNotEmpty)
                  ? c.contentPayload
                  : existing?.contentPayload,
              metadata: {
                if (existing != null) ...existing.metadata,
                ...c.metadata,
              },
              createdAt: c.createdAt,
              updatedAt: c.updatedAt,
            );
          }
          final merged = map.values.toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          await _saveLocal(merged);

          if (category != null && category.isNotEmpty) {
            return merged.where((e) => e.category == category).toList();
          }
          return merged;
        }
      } catch (e) {
        debugPrint('[ExpedientesRepository] Red inaccesible o migración pendiente: $e');
      }
    }

    localList.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (category != null && category.isNotEmpty) {
      return localList.where((e) => e.category == category).toList();
    }
    return localList;
  }

  /// Crea/guarda un expediente con persistencia local garantizada.
  Future<Expediente?> createExpediente({
    required String title,
    required String category,
    required String fileFormat,
    required String contentPayload,
    String? chatId,
    Map<String, dynamic> metadata = const {},
  }) async {
    final now = DateTime.now();
    final localExpediente = Expediente(
      id: _generateUuid(),
      chatId: chatId,
      title: title,
      category: category,
      fileFormat: fileFormat,
      contentPayload: contentPayload,
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );

    // Guardado local inmediato
    final localList = await _loadLocal();
    localList.insert(0, localExpediente);
    await _saveLocal(localList);
    debugPrint('[ExpedientesRepository] Expediente guardado localmente: ${localExpediente.id}');

    // Sincronización en la nube (background)
    if (_jwt != null) {
      final uri = Uri.parse(_baseEndpoint);
      http.post(
        uri,
        headers: _headers,
        body: jsonEncode({
          'title': title,
          'category': category,
          'file_format': fileFormat,
          'content_payload': contentPayload,
          'chat_id': chatId,
          'metadata': metadata,
        }),
      ).timeout(const Duration(seconds: 10)).then((response) {
        if (response.statusCode == 201) {
          debugPrint('[ExpedientesRepository] Expediente sincronizado en Supabase.');
        }
      }).catchError((e) {
        debugPrint('[ExpedientesRepository] Sync error (esperado si tabla aún no existe): $e');
      });
    }

    return localExpediente;
  }

  /// Obtiene el detalle (incluido `content_payload`) de un expediente propio.
  Future<Expediente?> getExpediente(String id) async {
    if (id.trim().isEmpty) return null;
    final localList = await _loadLocal();
    final found = localList.where((e) => e.id == id).firstOrNull;
    if (found != null && found.contentPayload != null) return found;

    if (_jwt != null) {
      final uri = Uri.parse('$_baseEndpoint/$id');
      try {
        final response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          return Expediente.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>,
          );
        }
      } catch (e) {
        debugPrint('[ExpedientesRepository] Excepción en getExpediente: $e');
      }
    }
    return found;
  }

  /// Elimina un expediente propio por id.
  Future<bool> deleteExpediente(String id) async {
    if (id.trim().isEmpty) return false;
    final localList = await _loadLocal();
    localList.removeWhere((e) => e.id == id);
    await _saveLocal(localList);

    if (_jwt != null) {
      final uri = Uri.parse('$_baseEndpoint/$id');
      http.delete(uri, headers: _headers).catchError((_) => http.Response('', 500));
    }
    return true;
  }
}
