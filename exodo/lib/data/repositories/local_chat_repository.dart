import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../local/db/app_database.dart';
import '../local/db/tables/messages.dart'; // Import LocalMessageStatus enum
import '../../models/models.dart';
import 'attachment_storage.dart';

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
        updatedAt: Value(conv.updatedAt ?? DateTime.now()),
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
      updatedAt: Value(c.updatedAt ?? c.createdAt),
    )).toList();
    await db.conversationsDao.upsertAll(companions);
  }

  Future<void> renameConversation(String id, String newTitle) async {
    await db.conversationsDao.updateTitle(id, newTitle);
  }

  Future<void> updateConversationTitle(String id, String newTitle) async {
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
    final domain = list.map(_toDomainMessage).toList();
    if (kDebugMode) {
      final withAtts = domain.where((m) => m.attachments.isNotEmpty).length;
      debugPrint(
        '[LocalChatRepo] getMessages convId=$conversationId returned ${domain.length} msgs ($withAtts with attachments)',
      );
    }
    return domain;
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

    // [Fix LG V60 #2] Persistencia robusta de adjuntos:
    // 1) Si el adjunto trae bytes en memoria, los volcamos a disco en
    //    `attachments/<msgId>_<fileName>` para no inflar SQLite.
    // 2) Serializamos el adjunto a JSON conservando metadatos + base64
    //    como respaldo (así sesiones antiguas o re-instalaciones siguen
    //    mostrando la imagen aunque el archivo físico se haya perdido).
    List<Map<String, dynamic>> attachmentPayloads = [];
    if (msg.attachments.isNotEmpty) {
      for (final a in msg.attachments) {
        var stored = a;
        // Si el composer ya persistió el archivo al momento de la selección
        // (ruta permanente en `attachments/`) y sigue en disco, se conserva
        // tal cual: re-escribirlo generaría una segunda copia idéntica y
        // dejaría la original huérfana sin que ningún cleanup la borre.
        final hasValidPath = a.filePath.isNotEmpty && File(a.filePath).existsSync();
        if (!hasValidPath && a.bytes.isNotEmpty) {
          try {
            final path = await AttachmentStorage.instance.persistBytes(
              messageId: msg.id,
              fileName: a.fileName,
              bytes: a.bytes,
            );
            if (path.isNotEmpty) {
              stored = Attachment(
                filePath: path,
                fileName: a.fileName,
                bytes: a.bytes,
                mimeType: a.mimeType,
              );
            }
          } catch (_) {
            // Si falla el volcado a disco, conservamos el adjunto tal cual
            // (con sus bytes en memoria) para que al menos funcione en
            // la sesión actual.
          }
        }
        attachmentPayloads.add(stored.toJson());
      }
    }
    final attachmentsJson = attachmentPayloads.isNotEmpty
        ? jsonEncode(attachmentPayloads)
        : null;

    if (kDebugMode) {
      debugPrint(
        '[LocalChatRepo] saveMessage id=${msg.id} convId=${msg.conversationId} role=${msg.role} atts=${msg.attachments.length} attachments_json=$attachmentsJson',
      );
    }

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

  /// Reemplaza todo el historial local de una conversación por [messages]
  /// (resultado de la sincronización con la nube, ya fusionado con los
  /// adjuntos locales). A diferencia de [saveMessages], borra primero las
  /// filas existentes: al diferir los ids (local `user-*`/`asst-*` vs UUID
  /// de la nube), el upsert simple acumulaba duplicados por mensaje.
  /// Conserva las filas con status 'queued' del outbox offline (aún no
  /// enviadas a la nube) restaurando su estado tras el reemplazo.
  Future<void> replaceMessages(String conversationId, List<ChatMessage> messages) async {
    if (kDebugMode) {
      final attCount = messages.where((m) => m.attachments.isNotEmpty).length;
      debugPrint(
        '[LocalChatRepo] replaceMessages convId=$conversationId totalMsgs=${messages.length} msgsWithAttachments=$attCount',
      );
    }
    // Qwen 1.1: Envolver en transaccion atomica de base de datos Drift para evitar borrado accidental si falla la insercion
    await db.transaction(() async {
      final queuedRows = await db.messagesDao.getQueuedMessages();
      final keptQueued = queuedRows
          .where((q) => q.conversationId == conversationId)
          .map(_toDomainMessage)
          .where((q) => !messages.any((m) => m.id == q.id))
          .toList();
      await db.messagesDao.deleteByConversation(conversationId);
      final all = [...messages, ...keptQueued];
      if (all.isNotEmpty) {
        await saveMessages(conversationId, all);
      }
      // saveMessages no persiste el status (usa el default 'pending');
      // restaurar 'queued' para que el flush offline vuelva a encontrarlos.
      for (final q in keptQueued) {
        await db.messagesDao.updateStatus(q.id, LocalMessageStatus.queued);
      }
    });
  }

  Future<void> deleteMessageById(String id) async {
    await db.messagesDao.deleteById(id);
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
  // OUTBOX QUEUE (Offline-first)
  // ---------------------------------------------------------------------------

  /// Obtiene mensajes pendientes de envío (status = 'queued') ordenados por createdAt ASC.
  Future<List<ChatMessage>> getQueuedMessages() async {
    final list = await db.messagesDao.getQueuedMessages();
    return list.map(_toDomainMessage).toList();
  }

  /// C10: IDs de conversaciones con contenido local que coincide con la query.
  Future<List<String>> searchConversationIds(String query, {int limit = 50}) {
    return db.messagesDao.searchConversationIds(query, limit: limit);
  }

  /// Actualiza el estado de sincronización de un mensaje.
  Future<void> updateMessageStatus(String messageId, LocalMessageStatus newStatus) async {
    await db.messagesDao.updateStatus(messageId, newStatus);
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
      updatedAt: local.updatedAt,
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

    // [Fix LG V60 #2] Hidratación de adjuntos desde historial:
    // 1) Si el JSON trae `filePath` apuntando a un archivo físico, la
    //    burbuja usará `Image.file(File(att.filePath))` para renderizar
    //    (más rápido y libera memoria).
    // 2) Si no hay filePath válido, recurrimos al `bytes` (base64)
    //    embebido en el JSON y la burbuja usará `Image.memory`.
    // 3) Si ambos están vacíos, conservamos el adjunto con `fileName`
    //    para que el render muestre la fila de archivo.
    List<Attachment> attachments = [];
    if (local.attachmentsJson != null && local.attachmentsJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(local.attachmentsJson!);
        if (decoded is List) {
          attachments = decoded
              .whereType<Map>()
              .map((raw) => Attachment.fromJson(Map<String, dynamic>.from(raw)))
              .toList();
        }
      } catch (_) {
        // Falla silenciosa: si el JSON está corrupto, la burbuja mostrará
        // el nombre del adjunto sin miniatura.
      }
    }

    if (kDebugMode && attachments.isNotEmpty) {
      debugPrint(
        '[LocalChatRepo] _toDomainMessage id=${local.id} convId=${local.conversationId} attsCount=${attachments.length} paths=${attachments.map((a) => a.filePath).toList()}',
      );
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
