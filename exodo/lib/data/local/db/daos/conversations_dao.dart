import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/conversations.dart';

part 'conversations_dao.g.dart';

@DriftAccessor(tables: [LocalConversations])
class ConversationsDao extends DatabaseAccessor<AppDatabase> with _$ConversationsDaoMixin {
  ConversationsDao(super.db);

  /// Stream reactivo de todas las conversaciones ordenadas por fecha descendente.
  Stream<List<LocalConversation>> watchAll({String? userId}) {
    final query = select(localConversations);
    if (userId != null && userId.isNotEmpty) {
      query.where((tbl) => tbl.userId.equals(userId));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.watch();
  }

  /// Obtiene todas las conversaciones del usuario en una consulta puntual.
  Future<List<LocalConversation>> getAll({String? userId}) {
    final query = select(localConversations);
    if (userId != null && userId.isNotEmpty) {
      query.where((tbl) => tbl.userId.equals(userId));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.updatedAt, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
    return query.get();
  }

  /// Stream de una sola conversación por ID.
  Stream<LocalConversation?> watchById(String id) {
    return (select(localConversations)..where((tbl) => tbl.id.equals(id)))
        .watchSingleOrNull();
  }

  /// Obtiene una sola conversación por ID.
  Future<LocalConversation?> getById(String id) {
    return (select(localConversations)..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
  }

  /// Inserta o actualiza una conversación local.
  Future<void> upsert(LocalConversationsCompanion entry) {
    return into(localConversations).insertOnConflictUpdate(entry);
  }

  /// Inserta o actualiza un lote de conversaciones (sync batch).
  Future<void> upsertAll(List<LocalConversationsCompanion> entries) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(localConversations, entries);
    });
  }

  /// Actualiza el título de una conversación.
  Future<void> updateTitle(String id, String newTitle) {
    return (update(localConversations)..where((t) => t.id.equals(id))).write(
      LocalConversationsCompanion(
        title: Value(newTitle),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Actualiza el estado de favorita de una conversación.
  Future<void> toggleStarred(String id, bool isStarred) {
    return (update(localConversations)..where((t) => t.id.equals(id))).write(
      LocalConversationsCompanion(
        isStarred: Value(isStarred),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Elimina una conversación por ID (cascada a sus mensajes).
  Future<void> deleteById(String id) {
    return (delete(localConversations)..where((t) => t.id.equals(id))).go();
  }

  /// Elimina todas las conversaciones de un usuario específico.
  Future<void> deleteAllForUser(String userId) {
    return (delete(localConversations)..where((t) => t.userId.equals(userId))).go();
  }

  /// Elimina todas las conversaciones locales.
  Future<void> deleteAll() {
    return delete(localConversations).go();
  }
}
