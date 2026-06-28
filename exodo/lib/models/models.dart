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
      id: json['id'] as String,
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
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String? ?? 'Nueva conversación',
      modelPlan: json['model_plan'] as String? ?? 'genesis',
      isIncognito: json['is_incognito'] as bool? ?? false,
      isStarred: json['is_starred'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'] as String) : null,
    );
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final String role; // 'user' | 'assistant'
  final String content;
  final String? intentDetected;
  final String? modelCalled;
  final List<Source> sources;
  final DateTime createdAt;
  final bool isThinking;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.intentDetected,
    this.modelCalled,
    this.sources = const [],
    required this.createdAt,
    this.isThinking = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawSources = json['sources'];
    final sourcesList = (rawSources is List)
        ? rawSources
            .whereType<Map<String, dynamic>>()
            .map((s) => Source.fromJson(s))
            .toList()
        : <Source>[];
    return ChatMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      intentDetected: json['intent_detected'] as String?,
      modelCalled: json['model_called'] as String?,
      sources: sourcesList,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
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
    modelId: 'nim-nemotron-3-ultra',
    title: 'G1.1',
    subtitle: 'Origo',
    plan: 'genesis',
    description: 'Modelo capaz para tareas diarias.',
    descriptionEn: 'Capable model for everyday tasks.',
  ),
  ExodoModelOption(
    id: 'ehyeh',
    modelId: 'nim-deepseek-v4-pro',
    title: 'XPi',
    subtitle: 'Ehyeh',
    plan: 'hazak',
    description: 'Razonamiento avanzado para tareas exigentes.',
    descriptionEn: 'Advanced reasoning for demanding tasks.',
  ),
];
