// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversations_dao.dart';

// ignore_for_file: type=lint
mixin _$ConversationsDaoMixin on DatabaseAccessor<AppDatabase> {
  $LocalConversationsTable get localConversations =>
      attachedDatabase.localConversations;
  ConversationsDaoManager get managers => ConversationsDaoManager(this);
}

class ConversationsDaoManager {
  final _$ConversationsDaoMixin _db;
  ConversationsDaoManager(this._db);
  $$LocalConversationsTableTableManager get localConversations =>
      $$LocalConversationsTableTableManager(
        _db.attachedDatabase,
        _db.localConversations,
      );
}
