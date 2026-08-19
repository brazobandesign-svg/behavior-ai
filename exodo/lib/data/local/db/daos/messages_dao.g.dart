// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'messages_dao.dart';

// ignore_for_file: type=lint
mixin _$MessagesDaoMixin on DatabaseAccessor<AppDatabase> {
  $LocalConversationsTable get localConversations =>
      attachedDatabase.localConversations;
  $LocalMessagesTable get localMessages => attachedDatabase.localMessages;
  MessagesDaoManager get managers => MessagesDaoManager(this);
}

class MessagesDaoManager {
  final _$MessagesDaoMixin _db;
  MessagesDaoManager(this._db);
  $$LocalConversationsTableTableManager get localConversations =>
      $$LocalConversationsTableTableManager(
        _db.attachedDatabase,
        _db.localConversations,
      );
  $$LocalMessagesTableTableManager get localMessages =>
      $$LocalMessagesTableTableManager(_db.attachedDatabase, _db.localMessages);
}
