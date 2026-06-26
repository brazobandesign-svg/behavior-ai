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

  Conversation({
    required this.id,
    required this.userId,
    required this.title,
    this.modelPlan = 'genesis',
    this.isIncognito = false,
    this.isStarred = false,
    required this.createdAt,
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
  final DateTime createdAt;
  final bool isThinking;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.intentDetected,
    this.modelCalled,
    required this.createdAt,
    this.isThinking = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      intentDetected: json['intent_detected'] as String?,
      modelCalled: json['model_called'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }
}

class ExodoModelOption {
  final String id;
  final String title; // 'G1.1', 'G1.3', 'XPi', 'J1.9'
  final String subtitle; // 'Origon', 'Lux', 'Ehyeh', 'Hazak'
  final String plan; // 'genesis' | 'hazak'
  final String description;

  const ExodoModelOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.plan,
    required this.description,
  });
}

const List<ExodoModelOption> exodoModels = [
  ExodoModelOption(
    id: 'origo',
    title: 'G1.1',
    subtitle: 'Origo',
    plan: 'genesis',
    description: 'Modelo capaz para tareas diarias.',
  ),
  ExodoModelOption(
    id: 'ehyeh',
    title: 'XPi',
    subtitle: 'Ehyeh',
    plan: 'hazak',
    description: 'Razonamiento avanzado para tareas exigentes.',
  ),
];
