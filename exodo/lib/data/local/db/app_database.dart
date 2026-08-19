import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'tables/conversations.dart';
import 'tables/messages.dart';
import 'daos/conversations_dao.dart';
import 'daos/messages_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [LocalConversations, LocalMessages],
  daos: [ConversationsDao, MessagesDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Migraciones futuras de esquema
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'exodo_app_db');
  }

  static AppDatabase? _instance;
  static AppDatabase get instance => _instance ??= AppDatabase();

  static Future<AppDatabase> open() async {
    return instance;
  }
}
