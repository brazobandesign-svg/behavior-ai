import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/messages.dart';

part 'messages_dao.g.dart';

@DriftAccessor(tables: [LocalMessages])
class MessagesDao extends DatabaseAccessor<AppDatabase> with _$MessagesDaoMixin {
  MessagesDao(super.db);

  /// Stream reactivo de mensajes de una conversación, ordenados por fecha ascendente.
  Stream<List<LocalMessage>> watchByConversation(String conversationId) {
    return (select(localMessages)
          ..where((tbl) => tbl.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)]))
        .watch();
  }

  /// Obtiene los mensajes de una conversación en una consulta puntual.
  Future<List<LocalMessage>> getByConversation(String conversationId) {
    return (select(localMessages)
          ..where((tbl) => tbl.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)]))
        .get();
  }

  /// Inserta o actualiza un mensaje local.
  Future<void> upsert(LocalMessagesCompanion entry) {
    return into(localMessages).insertOnConflictUpdate(entry);
  }

  /// Inserta o actualiza un lote de mensajes.
  Future<void> upsertAll(List<LocalMessagesCompanion> entries) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(localMessages, entries);
    });
  }

  /// Actualiza el contenido de un mensaje existente (por ejemplo durante streaming o respuesta final).
  Future<void> updateContent(
    String id,
    String content, {
    bool? isThinking,
    bool? isDegraded,
    String? sourcesJson,
    String? attachmentsJson,
  }) {
    return (update(localMessages)..where((t) => t.id.equals(id))).write(
      LocalMessagesCompanion(
        content: Value(content),
        isThinking: isThinking != null ? Value(isThinking) : const Value.absent(),
        isDegraded: isDegraded != null ? Value(isDegraded) : const Value.absent(),
        sourcesJson: sourcesJson != null ? Value(sourcesJson) : const Value.absent(),
        attachmentsJson: attachmentsJson != null ? Value(attachmentsJson) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Elimina los mensajes de una conversación específica.
  Future<void> deleteByConversation(String conversationId) {
    return (delete(localMessages)..where((t) => t.conversationId.equals(conversationId))).go();
  }

  /// Elimina los mensajes posteriores a una fecha dentro de una conversación (útil al editar/regenerar).
  Future<void> deleteAfter(String conversationId, DateTime date) {
    return (delete(localMessages)
          ..where((t) => t.conversationId.equals(conversationId) & t.createdAt.isBiggerThanValue(date)))
        .go();
  }

  /// Elimina un mensaje por su ID.
  Future<void> deleteById(String id) {
    return (delete(localMessages)..where((t) => t.id.equals(id))).go();
  }

  /// Elimina todos los mensajes locales.
  Future<void> deleteAll() {
    return delete(localMessages).go();
  }

  /// Obtiene mensajes en estado 'queued' ordenados por createdAt ASC.
  Future<List<LocalMessage>> getQueuedMessages() {
    return (select(localMessages)
          ..where((tbl) => tbl.status.equals(LocalMessageStatus.queued.name))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc)]))
        .get();
  }

  /// C10: busca conversaciones cuyo contenido local coincida con la query.
  /// Cubre invitados y mensajes offline que nunca llegaron a Supabase.
  Future<List<String>> searchConversationIds(String query, {int limit = 50}) {
    // Neutralizar comodines LIKE del usuario para que busque texto literal.
    final q = query.replaceAll(RegExp(r'[%_\\]'), '').trim();
    if (q.isEmpty) return Future.value(const <String>[]);
    final convId = localMessages.conversationId;
    final stmt = selectOnly(localMessages)
      ..addColumns([convId])
      ..where(localMessages.content.like('%$q%'))
      ..groupBy([convId])
      ..limit(limit);
    return stmt.get().then((rows) => rows.map((r) => r.read(convId)!).toList());
  }

  /// Actualiza el estado de sincronización de un mensaje.
  Future<void> updateStatus(String id, LocalMessageStatus newStatus) {
    return (update(localMessages)..where((t) => t.id.equals(id))).write(
      LocalMessagesCompanion(
        status: Value(newStatus),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
