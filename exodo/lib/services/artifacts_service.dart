import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/artifacts/artifact.dart';
import 'chat_service.dart';
import 'supabase_service.dart';

/// Servicio para interactuar con la API Cloud de Artefactos de Éxodo.
class ArtifactsService {
  ArtifactsService._();
  static final ArtifactsService instance = ArtifactsService._();

  static String _mapKind(ArtifactKind kind) {
    switch (kind) {
      case ArtifactKind.html:
        return 'html';
      case ArtifactKind.svg:
        return 'svg';
      case ArtifactKind.mermaid:
        return 'mermaid';
      case ArtifactKind.react:
        return 'react';
      case ArtifactKind.code:
      case ArtifactKind.table:
      case ArtifactKind.json:
      case ArtifactKind.latex:
      case ArtifactKind.diagram:
      case ArtifactKind.vue:
        return 'code';
    }
  }

  /// Publica un artefacto en el backend de Éxodo y retorna su URL pública para compartir.
  static Future<String?> publishArtifact(Artifact artifact) async {
    try {
      final base = ChatService.backendUrl
          .replaceAll('/api/chat', '')
          .replaceAll('/chat', '')
          .replaceAll(RegExp(r'/+$'), '');

      final uri = Uri.parse('$base/api/artifacts/publish');
      final token = SupabaseService.client.auth.currentSession?.accessToken;

      final body = jsonEncode({
        'title': artifact.title?.trim().isNotEmpty == true
            ? artifact.title!.trim()
            : 'Artefacto Éxodo',
        'kind': _mapKind(artifact.kind),
        'language': artifact.language.isNotEmpty ? artifact.language : null,
        'source_code': artifact.sourceCode,
        'is_public': true,
        'metadata': artifact.meta,
      });

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final url = data['url'] as String?;
        if (url != null && url.isNotEmpty) {
          debugPrint('[ArtifactsService] Artefacto publicado exitosamente: $url');
          return url;
        }
      } else {
        debugPrint('[ArtifactsService] Error publicando artefacto: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('[ArtifactsService] Excepción al publicar artefacto: $e');
    }
    return null;
  }
}
