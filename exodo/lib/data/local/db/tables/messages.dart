import 'package:drift/drift.dart';

enum LocalMessageStatus { pending, sent, failed, sending }
enum LocalMessageSyncStatus { local, syncing, synced, conflict }

@DataClassName('LocalMessage')
class LocalMessages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text().customConstraint('NOT NULL REFERENCES local_conversations(id) ON DELETE CASCADE')();
  TextColumn get role => text()(); // "user" | "assistant" | "system"
  TextColumn get content => text()();
  TextColumn get status => textEnum<LocalMessageStatus>().withDefault(Constant(LocalMessageStatus.pending.name))();
  TextColumn get syncStatus => textEnum<LocalMessageSyncStatus>().withDefault(Constant(LocalMessageSyncStatus.local.name))();
  IntColumn get localSeq => integer().withDefault(const Constant(0))();
  TextColumn get remoteId => text().nullable()();
  TextColumn get intentDetected => text().nullable()();
  TextColumn get modelCalled => text().nullable()();
  TextColumn get sourcesJson => text().nullable()();
  TextColumn get attachmentsJson => text().nullable()();
  BoolColumn get isThinking => boolean().withDefault(const Constant(false))();
  BoolColumn get isDegraded => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
