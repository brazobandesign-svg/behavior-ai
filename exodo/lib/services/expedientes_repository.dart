import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
///
/// Apunta al backend `/api/expedientes`:
///   - GET    /api/expedientes       -> listado (filtro ?category, paginación)
///   - POST   /api/expedientes       -> crea/guarda un registro
///   - GET    /api/expedientes/:id   -> detalle + content_payload
///   - DELETE /api/expedientes/:id   -> elimina un registro propio
class ExpedientesRepository {
  ExpedientesRepository._();
  static final ExpedientesRepository instance = ExpedientesRepository._();

  static String get _baseEndpoint {
    final base = ChatService.backendUrl
        .replaceAll('/api/chat', '')
        .replaceAll('/chat', '')
        .replaceAll(RegExp(r'/+$'), '');
    return '$base/api/expedientes';
  }

  /// Token JWT de Supabase; null si no hay sesión activa.
  static String? get _jwt =>
      SupabaseService.client.auth.currentSession?.accessToken;

  static Map<String, String> get _headers => {
    'Authorization': 'Bearer ${_jwt ?? ''}',
    'Content-Type': 'application/json',
  };

  /// Lista los expedientes del usuario autenticado.
  ///
  /// [category] opcional: 'documento' | 'tabla' | 'interactivo'.
  Future<List<Expediente>> listExpedientes({
    String? category,
    int limit = 50,
    int offset = 0,
  }) async {
    if (_jwt == null) {
      debugPrint('[ExpedientesRepository] Usuario no autenticado.');
      return [];
    }

    final uri = Uri.parse(
      '$_baseEndpoint?limit=$limit&offset=$offset'
      '${category != null && category.isNotEmpty ? '&category=$category' : ''}',
    );
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final items = decoded['items'] as List<dynamic>? ?? [];
        return items
            .whereType<Map<String, dynamic>>()
            .map((e) => Expediente.fromJson(e))
            .toList(growable: false);
      } else {
        debugPrint(
          '[ExpedientesRepository] Error al listar expedientes: '
          '${response.statusCode} - ${response.body}',
        );
        return [];
      }
    } catch (e) {
      debugPrint('[ExpedientesRepository] Excepción en listExpedientes: $e');
      rethrow;
    }
  }

  /// Crea/guarda un expediente. Devuelve el registro creado, o null si falla.
  Future<Expediente?> createExpediente({
    required String title,
    required String category,
    required String fileFormat,
    required String contentPayload,
    String? chatId,
    Map<String, dynamic> metadata = const {},
  }) async {
    if (_jwt == null) {
      debugPrint('[ExpedientesRepository] Usuario no autenticado.');
      return null;
    }

    final uri = Uri.parse(_baseEndpoint);
    try {
      final response = await http
          .post(
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
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 201) {
        return Expediente.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } else {
        debugPrint(
          '[ExpedientesRepository] Error al crear expediente: '
          '${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[ExpedientesRepository] Excepción en createExpediente: $e');
      return null;
    }
  }

  /// Obtiene el detalle (incluido `content_payload`) de un expediente propio.
  Future<Expediente?> getExpediente(String id) async {
    if (id.trim().isEmpty) return null;
    if (_jwt == null) {
      debugPrint('[ExpedientesRepository] Usuario no autenticado.');
      return null;
    }

    final uri = Uri.parse('$_baseEndpoint/$id');
    try {
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        return Expediente.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      } else {
        debugPrint(
          '[ExpedientesRepository] Error al obtener expediente $id: '
          '${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[ExpedientesRepository] Excepción en getExpediente: $e');
      return null;
    }
  }

  /// Elimina un expediente propio por id.
  Future<bool> deleteExpediente(String id) async {
    if (id.trim().isEmpty) return false;
    if (_jwt == null) {
      debugPrint('[ExpedientesRepository] Usuario no autenticado.');
      return false;
    }

    final uri = Uri.parse('$_baseEndpoint/$id');
    try {
      final response = await http
          .delete(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        debugPrint('[ExpedientesRepository] Expediente $id eliminado.');
        return true;
      } else {
        debugPrint(
          '[ExpedientesRepository] Error al eliminar $id: '
          '${response.statusCode} - ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint('[ExpedientesRepository] Excepción en deleteExpediente: $e');
      return false;
    }
  }
}
