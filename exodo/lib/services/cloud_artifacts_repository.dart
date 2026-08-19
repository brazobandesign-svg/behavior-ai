import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'chat_service.dart';
import 'supabase_service.dart';

/// Modelo que representa un artefacto publicado en la nube.
class PublishedArtifactSummary {
  final String id;
  final String slug;
  final String title;
  final String kind;
  final String? language;
  final bool isPublic;
  final int viewsCount;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const PublishedArtifactSummary({
    required this.id,
    required this.slug,
    required this.title,
    required this.kind,
    this.language,
    required this.isPublic,
    required this.viewsCount,
    required this.createdAt,
    this.expiresAt,
  });

  /// URL pública interactiva para compartir
  String get publicUrl {
    final base = ChatService.backendUrl
        .replaceAll('/api/chat', '')
        .replaceAll('/chat', '')
        .replaceAll(RegExp(r'/+$'), '');
    return '$base/api/artifacts/$slug';
  }

  /// URL cruda de metadatos/JSON
  String get rawUrl => '$publicUrl/raw';

  /// Indica si el artefacto tiene fecha de expiración y si ya expiró
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory PublishedArtifactSummary.fromJson(Map<String, dynamic> json) {
    return PublishedArtifactSummary(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? 'Sin título',
      kind: json['kind'] as String? ?? 'code',
      language: json['language'] as String?,
      isPublic: json['is_public'] as bool? ?? true,
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'title': title,
      'kind': kind,
      'language': language,
      'is_public': isPublic,
      'views_count': viewsCount,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
    };
  }
}

/// Repositorio para la gestión de artefactos publicados en Cloud.
class CloudArtifactsRepository {
  CloudArtifactsRepository._();
  static final CloudArtifactsRepository instance = CloudArtifactsRepository._();

  static String get _baseEndpoint {
    final base = ChatService.backendUrl
        .replaceAll('/api/chat', '')
        .replaceAll('/chat', '')
        .replaceAll(RegExp(r'/+$'), '');
    return '$base/api/artifacts';
  }

  /// Obtiene la lista de artefactos publicados por el usuario actual autenticado.
  Future<List<PublishedArtifactSummary>> getMyPublishedArtifacts({
    int limit = 50,
    int offset = 0,
  }) async {
    final jwt = SupabaseService.client.auth.currentSession?.accessToken;
    if (jwt == null) {
      debugPrint('[CloudArtifactsRepository] Usuario no autenticado.');
      return [];
    }

    final uri = Uri.parse('$_baseEndpoint/me?limit=$limit&offset=$offset');
    try {
      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final items = decoded['items'] as List<dynamic>? ?? [];
        return items
            .whereType<Map<String, dynamic>>()
            .map((e) => PublishedArtifactSummary.fromJson(e))
            .toList(growable: false);
      } else {
        debugPrint('[CloudArtifactsRepository] Error al obtener artefactos: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('[CloudArtifactsRepository] Excepción en getMyPublishedArtifacts: $e');
      rethrow;
    }
  }

  /// Elimina un artefacto publicado por su slug (requiere ser el dueño).
  Future<bool> deletePublishedArtifact(String slug) async {
    if (slug.trim().isEmpty) return false;

    final jwt = SupabaseService.client.auth.currentSession?.accessToken;
    if (jwt == null) {
      debugPrint('[CloudArtifactsRepository] Usuario no autenticado.');
      return false;
    }

    final uri = Uri.parse('$_baseEndpoint/$slug');
    try {
      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $jwt',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        debugPrint('[CloudArtifactsRepository] Artefacto $slug eliminado correctamente.');
        return true;
      } else {
        debugPrint('[CloudArtifactsRepository] Error al eliminar $slug: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[CloudArtifactsRepository] Excepción en deletePublishedArtifact: $e');
      return false;
    }
  }
}
