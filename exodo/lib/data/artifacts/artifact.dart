enum ArtifactKind {
  // Ejecutables / renderizables
  html,
  svg,
  mermaid,
  react,
  vue,
  latex,
  diagram,

  // Estáticos
  code,
  table,
  json,
}

enum ArtifactStatus { detected, rendering, ready, exported, error }

class Artifact {
  final String id;
  final String messageId;
  final String conversationId;
  final ArtifactKind kind;
  final String language;
  final String sourceCode;
  final String? title;
  final Map<String, dynamic> meta;
  final DateTime detectedAt;
  final DateTime updatedAt;
  final ArtifactStatus status;
  final String? lastError;

  const Artifact({
    required this.id,
    required this.messageId,
    required this.conversationId,
    required this.kind,
    required this.language,
    required this.sourceCode,
    this.title,
    this.meta = const {},
    required this.detectedAt,
    required this.updatedAt,
    this.status = ArtifactStatus.detected,
    this.lastError,
  });

  Artifact copyWith({
    String? sourceCode,
    String? title,
    Map<String, dynamic>? meta,
    ArtifactStatus? status,
    String? lastError,
    DateTime? updatedAt,
  }) {
    return Artifact(
      id: id,
      messageId: messageId,
      conversationId: conversationId,
      kind: kind,
      language: language,
      sourceCode: sourceCode ?? this.sourceCode,
      title: title ?? this.title,
      meta: meta ?? this.meta,
      detectedAt: detectedAt,
      updatedAt: updatedAt ?? DateTime.now(),
      status: status ?? this.status,
      lastError: lastError,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'messageId': messageId,
    'conversationId': conversationId,
    'kind': kind.name,
    'language': language,
    'sourceCode': sourceCode,
    'title': title,
    'meta': meta,
    'detectedAt': detectedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'status': status.name,
    'lastError': lastError,
  };

  factory Artifact.fromJson(Map<String, dynamic> j) => Artifact(
    id: j['id'] as String,
    messageId: j['messageId'] as String,
    conversationId: j['conversationId'] as String,
    kind: ArtifactKind.values.firstWhere((k) => k.name == j['kind']),
    language: j['language'] as String,
    sourceCode: j['sourceCode'] as String,
    title: j['title'] as String?,
    meta: Map<String, dynamic>.from(j['meta'] as Map? ?? {}),
    detectedAt: DateTime.parse(j['detectedAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    status: ArtifactStatus.values.firstWhere((s) => s.name == j['status']),
    lastError: j['lastError'] as String?,
  );

  bool get isExecutable =>
      kind == ArtifactKind.html ||
      kind == ArtifactKind.svg ||
      kind == ArtifactKind.mermaid ||
      kind == ArtifactKind.react ||
      kind == ArtifactKind.vue;

  bool get isTabular => kind == ArtifactKind.table;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Artifact &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          kind == other.kind &&
          sourceCode == other.sourceCode &&
          status == other.status &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      kind.hashCode ^
      sourceCode.hashCode ^
      status.hashCode ^
      updatedAt.hashCode;
}
