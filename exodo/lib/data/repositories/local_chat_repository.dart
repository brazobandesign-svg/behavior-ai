import 'dart:convert';
import 'package:drift/drift.dart';
import '../local/db/app_database.dart';
import '../../models/models.dart';

class LocalChatRepository {
  final AppDatabase db;

  LocalChatRepository({AppDatabase? database}) : db = database ?? AppDatabase.instance;

  // ---------------------------------------------------------------------------
  // CONVERSACIONES
  // ---------------------------------------------------------------------------

  Stream<List<Conversation>> watchConversations({String? userId}) {
    return db.conversationsDao.watchAll(userId: userId).map((list) {
      return list.map(_toDomainConversation).toList();
    });
  }

  Future<List<Conversation>> getConversations({String? userId}) async {
    final list = await db.conversationsDao.getAll(userId: userId);
    return list.map(_toDomainConversation).toList();
  }

  Future<Conversation?> getConversationById(String id) async {
    final local = await db.conversationsDao.getById(id);
    if (local == null) return null;
    return _toDomainConversation(local);
  }

  Future<void> saveConversation(Conversation conv) async {
    await db.conversationsDao.upsert(
      LocalConversationsCompanion(
        id: Value(conv.id),
        userId: Value(conv.userId),
        title: Value(conv.title),
        modelPlan: Value(conv.modelPlan),
        isIncognito: Value(conv.isIncognito),
        isStarred: Value(conv.isStarred),
        createdAt: Value(conv.createdAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> saveConversations(List<Conversation> convs) async {
    final companions = convs.map((c) => LocalConversationsCompanion(
      id: Value(c.id),
      userId: Value(c.userId),
      title: Value(c.title),
      modelPlan: Value(c.modelPlan),
      isIncognito: Value(c.isIncognito),
      isStarred: Value(c.isStarred),
      createdAt: Value(c.createdAt),
      updatedAt: Value(DateTime.now()),
    )).toList();
    await db.conversationsDao.upsertAll(companions);
  }

  Future<void> renameConversation(String id, String newTitle) async {
    await db.conversationsDao.updateTitle(id, newTitle);
  }

  Future<void> toggleStarred(String id, bool isStarred) async {
    await db.conversationsDao.toggleStarred(id, isStarred);
  }

  Future<void> deleteConversation(String id) async {
    await db.conversationsDao.deleteById(id);
  }

  Future<void> deleteAllConversationsForUser(String userId) async {
    await db.conversationsDao.deleteAllForUser(userId);
  }

  // ---------------------------------------------------------------------------
  // MENSAJES
  // ---------------------------------------------------------------------------

  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return db.messagesDao.watchByConversation(conversationId).map((list) {
      return list.map(_toDomainMessage).toList();
    });
  }

  Future<List<ChatMessage>> getMessages(String conversationId) async {
    final list = await db.messagesDao.getByConversation(conversationId);
    return list.map(_toDomainMessage).toList();
  }

  Future<void> saveMessage(ChatMessage msg) async {
    // Ensure parent conversation exists in local database to avoid foreign key violation
    final existingConv = await db.conversationsDao.getById(msg.conversationId);
    if (existingConv == null) {
      await db.conversationsDao.upsert(
        LocalConversationsCompanion(
          id: Value(msg.conversationId),
          userId: Value(msg.conversationId == 'guest' ? 'guest' : 'local'),
          title: const Value('Chat'),
          modelPlan: const Value('genesis'),
          isIncognito: const Value(false),
          isStarred: const Value(false),
          createdAt: Value(msg.createdAt),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    final sourcesJson = msg.sources.isNotEmpty
        ? jsonEncode(msg.sources.map((s) => s.toJson()).toList())
        : null;
    final attachmentsJson = msg.attachments.isNotEmpty
        ? jsonEncode(msg.attachments.map((a) => a.toJson()).toList())
        : null;

    await db.messagesDao.upsert(
      LocalMessagesCompanion(
        id: Value(msg.id),
        conversationId: Value(msg.conversationId),
        role: Value(msg.role),
        content: Value(msg.content),
        intentDetected: Value(msg.intentDetected),
        modelCalled: Value(msg.modelCalled),
        sourcesJson: Value(sourcesJson),
        attachmentsJson: Value(attachmentsJson),
        isThinking: Value(msg.isThinking),
        isDegraded: Value(msg.isDegraded),
        createdAt: Value(msg.createdAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> saveMessages(String conversationId, List<ChatMessage> messages) async {
    final companions = messages.map((msg) {
      final sourcesJson = msg.sources.isNotEmpty
          ? jsonEncode(msg.sources.map((s) => s.toJson()).toList())
          : null;
      final attachmentsJson = msg.attachments.isNotEmpty
          ? jsonEncode(msg.attachments.map((a) => a.toJson()).toList())
          : null;
      return LocalMessagesCompanion(
        id: Value(msg.id),
        conversationId: Value(conversationId),
        role: Value(msg.role),
        content: Value(msg.content),
        intentDetected: Value(msg.intentDetected),
        modelCalled: Value(msg.modelCalled),
        sourcesJson: Value(sourcesJson),
        attachmentsJson: Value(attachmentsJson),
        isThinking: Value(msg.isThinking),
        isDegraded: Value(msg.isDegraded),
        createdAt: Value(msg.createdAt),
        updatedAt: Value(DateTime.now()),
      );
    }).toList();
    await db.messagesDao.upsertAll(companions);
  }

  Future<void> updateMessageContent(
    String id,
    String content, {
    bool? isThinking,
    bool? isDegraded,
    List<Source>? sources,
    List<Attachment>? attachments,
  }) async {
    final sourcesJson = sources != null && sources.isNotEmpty
        ? jsonEncode(sources.map((s) => s.toJson()).toList())
        : null;
    final attachmentsJson = attachments != null && attachments.isNotEmpty
        ? jsonEncode(attachments.map((a) => a.toJson()).toList())
        : null;

    await db.messagesDao.updateContent(
      id,
      content,
      isThinking: isThinking,
      isDegraded: isDegraded,
      sourcesJson: sourcesJson,
      attachmentsJson: attachmentsJson,
    );
  }

  Future<void> deleteMessagesForConversation(String conversationId) async {
    await db.messagesDao.deleteByConversation(conversationId);
  }

  Future<void> clearAll() async {
    await db.messagesDao.deleteAll();
    await db.conversationsDao.deleteAll();
  }

  // ---------------------------------------------------------------------------
  // MAPPERS
  // ---------------------------------------------------------------------------

  Conversation _toDomainConversation(LocalConversation local) {
    return Conversation(
      id: local.id,
      userId: local.userId,
      title: local.title,
      modelPlan: local.modelPlan ?? 'genesis',
      isIncognito: local.isIncognito,
      isStarred: local.isStarred,
      createdAt: local.createdAt,
    );
  }

  ChatMessage _toDomainMessage(LocalMessage local) {
    List<Source> sources = [];
    if (local.sourcesJson != null && local.sourcesJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(local.sourcesJson!);
        if (decoded is List) {
          sources = decoded
              .whereType<Map>()
              .map((s) => Source.fromJson(Map<String, dynamic>.from(s)))
              .toList();
        }
      } catch (_) {}
    }

    List<Attachment> attachments = [];
    if (local.attachmentsJson != null && local.attachmentsJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(local.attachmentsJson!);
        if (decoded is List) {
          attachments = decoded
              .whereType<Map>()
              .map((a) => Attachment.fromJson(Map<String, dynamic>.from(a)))
              .toList();
        }
      } catch (_) {}
    }

    return ChatMessage(
      id: local.id,
      conversationId: local.conversationId,
      role: local.role,
      content: local.content,
      intentDetected: local.intentDetected,
      modelCalled: local.modelCalled,
      sources: sources,
      attachments: attachments,
      isThinking: local.isThinking,
      isDegraded: local.isDegraded,
      createdAt: local.createdAt,
    );
  }
}
