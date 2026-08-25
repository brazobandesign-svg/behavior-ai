import 'dart:convert';
import 'dart:typed_data';

class UserProfile {
  final String id;
  final String? fullName;
  final String plan; // 'genesis' | 'hazak'
  final String? avatarUrl;
  final Map<String, dynamic>? onboarding;

  UserProfile({
    required this.id,
    this.fullName,
    this.plan = 'genesis',
    this.avatarUrl,
    this.onboarding,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String? ?? '',
      fullName: json['full_name'] as String?,
      plan: json['plan'] as String? ?? 'genesis',
      avatarUrl: json['avatar_url'] as String?,
      onboarding: json['onboarding'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'full_name': fullName,
    'plan': plan,
    'avatar_url': avatarUrl,
    'onboarding': onboarding,
  };
}

class Conversation {
  final String id;
  final String userId;
  String title;
  final String modelPlan;
  final bool isIncognito;
  bool isStarred;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Conversation({
    required this.id,
    required this.userId,
    required this.title,
    this.modelPlan = 'genesis',
    this.isIncognito = false,
    this.isStarred = false,
    required this.createdAt,
    this.updatedAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Nueva Conversación',
      modelPlan: json['model_plan'] as String? ?? 'genesis',
      isIncognito: json['is_incognito'] as bool? ?? false,
      isStarred: json['is_starred'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }

  Conversation copyWith({
    String? id,
    String? userId,
    String? title,
    String? modelPlan,
    bool? isIncognito,
    bool? isStarred,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      modelPlan: modelPlan ?? this.modelPlan,
      isIncognito: isIncognito ?? this.isIncognito,
      isStarred: isStarred ?? this.isStarred,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'title': title,
    'model_plan': modelPlan,
    'is_incognito': isIncognito,
    'is_starred': isStarred,
    'created_at': createdAt.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String role; // 'user' | 'assistant'
  final String content;
  final String? intentDetected;
  final String? modelCalled;
  final List<Source> sources;
  final List<Attachment> attachments;
  final DateTime createdAt;
  final bool isThinking;
  final bool isDegraded;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.intentDetected,
    this.modelCalled,
    this.sources = const [],
    this.attachments = const [],
    required this.createdAt,
    this.isThinking = false,
    this.isDegraded = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversation_id': conversationId,
    'role': role,
    'content': content,
    if (intentDetected != null) 'intent_detected': intentDetected,
    if (modelCalled != null) 'model_called': modelCalled,
    'sources': sources.map((s) => s.toJson()).toList(),
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
    'is_thinking': isThinking,
    'is_degraded': isDegraded,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    String contentStr = json['content'] as String? ?? '';
    List<Source> sourcesList = [];
    final rawSources = json['sources'];
    if (rawSources is List && rawSources.isNotEmpty) {
      sourcesList = rawSources
          .whereType<Map>()
          .map((s) => Source.fromJson(Map<String, dynamic>.from(s)))
          .toList();
    } else {
      const marker = '<!-- SOURCES: ';
      final idx = contentStr.indexOf(marker);
      if (idx != -1) {
        final endIdx = contentStr.indexOf(' -->', idx);
        if (endIdx != -1) {
          final jsonStr = contentStr.substring(idx + marker.length, endIdx);
          try {
            final decoded = jsonDecode(jsonStr);
            if (decoded is List) {
              sourcesList = decoded
                  .whereType<Map>()
                  .map((s) => Source.fromJson(Map<String, dynamic>.from(s)))
                  .toList();
            }
          } catch (_) {}
          contentStr = contentStr.substring(0, idx).trimRight();
        }
      }
    }
    List<Attachment> attachmentsList = [];
    const attMarker = '<!-- ATTACHMENTS: ';
    final attIdx = contentStr.indexOf(attMarker);
    if (attIdx != -1) {
      final attEndIdx = contentStr.indexOf(' -->', attIdx);
      if (attEndIdx != -1) {
        final jsonStr = contentStr.substring(attIdx + attMarker.length, attEndIdx);
        try {
          final decoded = jsonDecode(jsonStr);
          if (decoded is List) {
            attachmentsList = decoded
                .whereType<Map>()
                .map((s) => Attachment.fromJson(Map<String, dynamic>.from(s)))
                .toList();
          }
        } catch (_) {}
        contentStr = (contentStr.substring(0, attIdx) + contentStr.substring(attEndIdx + 4)).trimRight();
      }
    } else if (json['attachments'] is List && (json['attachments'] as List).isNotEmpty) {
      try {
        attachmentsList = (json['attachments'] as List)
            .whereType<Map>()
            .map((s) => Attachment.fromJson(Map<String, dynamic>.from(s)))
            .toList();
      } catch (_) {}
    }
    return ChatMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      content: contentStr,
      intentDetected: json['intent_detected'] as String?,
      modelCalled: json['model_called'] as String?,
      sources: sourcesList,
      attachments: attachmentsList,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
      isThinking: json['is_thinking'] as bool? ?? false,
      isDegraded: json['is_degraded'] as bool? ?? json['isDegraded'] as bool? ?? false,
    );
  }
}

/// Fuente que Éxodo consultó para generar la respuesta.
class Source {
  final String title;
  final String url;
  final String? favicon; // emoji o iniciales (ej: "Q" para Quora, "ATM" para ATM)

  const Source({
    required this.title,
    required this.url,
    this.favicon,
  });

  factory Source.fromJson(Map<String, dynamic> json) {
    return Source(
      title: json['title'] as String? ?? '',
      url: json['url'] as String? ?? '',
      favicon: json['favicon'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        if (favicon != null) 'favicon': favicon,
      };
}

class ExodoModelOption {
  final String id;
  final String modelId; // NIM model ID for backend routing (e.g. 'nim-nemotron-3-ultra')
  final String title; // 'G1.1', 'G1.3', 'XPi', 'J1.9'
  final String subtitle; // 'Origo', 'Lux', 'Ehyeh', 'Hazak'
  final String plan; // 'genesis' | 'hazak'
  final String description;
  final String descriptionEn;

  const ExodoModelOption({
    required this.id,
    required this.modelId,
    required this.title,
    required this.subtitle,
    required this.plan,
    required this.description,
    required this.descriptionEn,
  });
}

const List<ExodoModelOption> exodoModels = [
  ExodoModelOption(
    id: 'origo',
    modelId: 'gpt-4o-mini',
    title: 'G1.1',
    subtitle: 'Origo',
    plan: 'genesis',
    description: 'Modelo capaz para tareas diarias.',
    descriptionEn: 'Capable model for everyday tasks.',
  ),
  ExodoModelOption(
    id: 'ehyeh',
    modelId: 'deepseek-chat',
    title: 'XPi',
    subtitle: 'Ehyeh',
    plan: 'hazak',
    description: 'Razonamiento avanzado para tareas exigentes.',
    descriptionEn: 'Advanced reasoning for demanding tasks.',
  ),
  ExodoModelOption(
    id: 'kimi',
    modelId: 'kimi-k3',
    title: 'K3',
    subtitle: 'Kimi (1M)',
    plan: 'genesis',
    description: 'Ventana de 1M de tokens para libros y documentos extensos.',
    descriptionEn: '1M tokens context for large documents and books.',
  ),
];

/// [Punto 40] Datos de un archivo adjunto listo para enviar a la API.
/// Guarda la ruta real, los bytes leídos y el MIME type para construir
/// payloads multimodales (imágenes base64) o texto (PDF/txt).
class Attachment {
  final String filePath;
  final String fileName;
  final Uint8List bytes;
  final String mimeType;

  const Attachment({
    required this.filePath,
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'fileName': fileName,
        'mimeType': mimeType,
        'bytes': base64Encode(bytes),
      };

  factory Attachment.fromJson(Map<String, dynamic> json) {
    Uint8List b = Uint8List(0);
    try {
      if (json['bytes'] is String && (json['bytes'] as String).isNotEmpty) {
        b = base64Decode(json['bytes'] as String);
      }
    } catch (_) {}
    return Attachment(
      filePath: json['filePath'] as String? ?? json['file_path'] as String? ?? '',
      fileName: json['fileName'] as String? ?? json['file_name'] as String? ?? 'file',
      bytes: b,
      mimeType: json['mimeType'] as String? ?? json['mime_type'] as String? ?? 'application/octet-stream',
    );
  }

  bool get isImage =>
      mimeType.startsWith('image/') && mimeType != 'image/svg+xml';

  bool get isPdf => mimeType == 'application/pdf';

  bool get isText => mimeType.startsWith('text/') ||
      fileName.endsWith('.md') ||
      fileName.endsWith('.json') ||
      fileName.endsWith('.xml') ||
      fileName.endsWith('.csv');

  String get base64 => base64Encode(bytes);
}
