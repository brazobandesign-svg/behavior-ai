// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalConversationsTable extends LocalConversations
    with TableInfo<$LocalConversationsTable, LocalConversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('Nueva conversación'),
  );
  static const VerificationMeta _modelPlanMeta = const VerificationMeta(
    'modelPlan',
  );
  @override
  late final GeneratedColumn<String> modelPlan = GeneratedColumn<String>(
    'model_plan',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isIncognitoMeta = const VerificationMeta(
    'isIncognito',
  );
  @override
  late final GeneratedColumn<bool> isIncognito = GeneratedColumn<bool>(
    'is_incognito',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_incognito" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isStarredMeta = const VerificationMeta(
    'isStarred',
  );
  @override
  late final GeneratedColumn<bool> isStarred = GeneratedColumn<bool>(
    'is_starred',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_starred" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastMessageAtMeta = const VerificationMeta(
    'lastMessageAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastMessageAt =
      GeneratedColumn<DateTime>(
        'last_message_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  static const VerificationMeta _remoteUpdatedAtMeta = const VerificationMeta(
    'remoteUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> remoteUpdatedAt =
      GeneratedColumn<DateTime>(
        'remote_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    title,
    modelPlan,
    isIncognito,
    isStarred,
    createdAt,
    updatedAt,
    lastMessageAt,
    syncStatus,
    remoteUpdatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalConversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('model_plan')) {
      context.handle(
        _modelPlanMeta,
        modelPlan.isAcceptableOrUnknown(data['model_plan']!, _modelPlanMeta),
      );
    }
    if (data.containsKey('is_incognito')) {
      context.handle(
        _isIncognitoMeta,
        isIncognito.isAcceptableOrUnknown(
          data['is_incognito']!,
          _isIncognitoMeta,
        ),
      );
    }
    if (data.containsKey('is_starred')) {
      context.handle(
        _isStarredMeta,
        isStarred.isAcceptableOrUnknown(data['is_starred']!, _isStarredMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('last_message_at')) {
      context.handle(
        _lastMessageAtMeta,
        lastMessageAt.isAcceptableOrUnknown(
          data['last_message_at']!,
          _lastMessageAtMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('remote_updated_at')) {
      context.handle(
        _remoteUpdatedAtMeta,
        remoteUpdatedAt.isAcceptableOrUnknown(
          data['remote_updated_at']!,
          _remoteUpdatedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalConversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalConversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      modelPlan: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_plan'],
      ),
      isIncognito: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_incognito'],
      )!,
      isStarred: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_starred'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
      lastMessageAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_message_at'],
      ),
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      remoteUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}remote_updated_at'],
      ),
    );
  }

  @override
  $LocalConversationsTable createAlias(String alias) {
    return $LocalConversationsTable(attachedDatabase, alias);
  }
}

class LocalConversation extends DataClass
    implements Insertable<LocalConversation> {
  final String id;
  final String userId;
  final String title;
  final String? modelPlan;
  final bool isIncognito;
  final bool isStarred;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? lastMessageAt;
  final String syncStatus;
  final DateTime? remoteUpdatedAt;
  const LocalConversation({
    required this.id,
    required this.userId,
    required this.title,
    this.modelPlan,
    required this.isIncognito,
    required this.isStarred,
    required this.createdAt,
    this.updatedAt,
    this.lastMessageAt,
    required this.syncStatus,
    this.remoteUpdatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || modelPlan != null) {
      map['model_plan'] = Variable<String>(modelPlan);
    }
    map['is_incognito'] = Variable<bool>(isIncognito);
    map['is_starred'] = Variable<bool>(isStarred);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    if (!nullToAbsent || lastMessageAt != null) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt);
    }
    map['sync_status'] = Variable<String>(syncStatus);
    if (!nullToAbsent || remoteUpdatedAt != null) {
      map['remote_updated_at'] = Variable<DateTime>(remoteUpdatedAt);
    }
    return map;
  }

  LocalConversationsCompanion toCompanion(bool nullToAbsent) {
    return LocalConversationsCompanion(
      id: Value(id),
      userId: Value(userId),
      title: Value(title),
      modelPlan: modelPlan == null && nullToAbsent
          ? const Value.absent()
          : Value(modelPlan),
      isIncognito: Value(isIncognito),
      isStarred: Value(isStarred),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      lastMessageAt: lastMessageAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageAt),
      syncStatus: Value(syncStatus),
      remoteUpdatedAt: remoteUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteUpdatedAt),
    );
  }

  factory LocalConversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalConversation(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      title: serializer.fromJson<String>(json['title']),
      modelPlan: serializer.fromJson<String?>(json['modelPlan']),
      isIncognito: serializer.fromJson<bool>(json['isIncognito']),
      isStarred: serializer.fromJson<bool>(json['isStarred']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      lastMessageAt: serializer.fromJson<DateTime?>(json['lastMessageAt']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      remoteUpdatedAt: serializer.fromJson<DateTime?>(json['remoteUpdatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'title': serializer.toJson<String>(title),
      'modelPlan': serializer.toJson<String?>(modelPlan),
      'isIncognito': serializer.toJson<bool>(isIncognito),
      'isStarred': serializer.toJson<bool>(isStarred),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'lastMessageAt': serializer.toJson<DateTime?>(lastMessageAt),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'remoteUpdatedAt': serializer.toJson<DateTime?>(remoteUpdatedAt),
    };
  }

  LocalConversation copyWith({
    String? id,
    String? userId,
    String? title,
    Value<String?> modelPlan = const Value.absent(),
    bool? isIncognito,
    bool? isStarred,
    DateTime? createdAt,
    Value<DateTime?> updatedAt = const Value.absent(),
    Value<DateTime?> lastMessageAt = const Value.absent(),
    String? syncStatus,
    Value<DateTime?> remoteUpdatedAt = const Value.absent(),
  }) => LocalConversation(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    title: title ?? this.title,
    modelPlan: modelPlan.present ? modelPlan.value : this.modelPlan,
    isIncognito: isIncognito ?? this.isIncognito,
    isStarred: isStarred ?? this.isStarred,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    lastMessageAt: lastMessageAt.present
        ? lastMessageAt.value
        : this.lastMessageAt,
    syncStatus: syncStatus ?? this.syncStatus,
    remoteUpdatedAt: remoteUpdatedAt.present
        ? remoteUpdatedAt.value
        : this.remoteUpdatedAt,
  );
  LocalConversation copyWithCompanion(LocalConversationsCompanion data) {
    return LocalConversation(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      title: data.title.present ? data.title.value : this.title,
      modelPlan: data.modelPlan.present ? data.modelPlan.value : this.modelPlan,
      isIncognito: data.isIncognito.present
          ? data.isIncognito.value
          : this.isIncognito,
      isStarred: data.isStarred.present ? data.isStarred.value : this.isStarred,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      lastMessageAt: data.lastMessageAt.present
          ? data.lastMessageAt.value
          : this.lastMessageAt,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      remoteUpdatedAt: data.remoteUpdatedAt.present
          ? data.remoteUpdatedAt.value
          : this.remoteUpdatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalConversation(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('modelPlan: $modelPlan, ')
          ..write('isIncognito: $isIncognito, ')
          ..write('isStarred: $isStarred, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('remoteUpdatedAt: $remoteUpdatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    title,
    modelPlan,
    isIncognito,
    isStarred,
    createdAt,
    updatedAt,
    lastMessageAt,
    syncStatus,
    remoteUpdatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalConversation &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.title == this.title &&
          other.modelPlan == this.modelPlan &&
          other.isIncognito == this.isIncognito &&
          other.isStarred == this.isStarred &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.lastMessageAt == this.lastMessageAt &&
          other.syncStatus == this.syncStatus &&
          other.remoteUpdatedAt == this.remoteUpdatedAt);
}

class LocalConversationsCompanion extends UpdateCompanion<LocalConversation> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> title;
  final Value<String?> modelPlan;
  final Value<bool> isIncognito;
  final Value<bool> isStarred;
  final Value<DateTime> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<DateTime?> lastMessageAt;
  final Value<String> syncStatus;
  final Value<DateTime?> remoteUpdatedAt;
  final Value<int> rowid;
  const LocalConversationsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.title = const Value.absent(),
    this.modelPlan = const Value.absent(),
    this.isIncognito = const Value.absent(),
    this.isStarred = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.remoteUpdatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalConversationsCompanion.insert({
    required String id,
    required String userId,
    this.title = const Value.absent(),
    this.modelPlan = const Value.absent(),
    this.isIncognito = const Value.absent(),
    this.isStarred = const Value.absent(),
    required DateTime createdAt,
    this.updatedAt = const Value.absent(),
    this.lastMessageAt = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.remoteUpdatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       createdAt = Value(createdAt);
  static Insertable<LocalConversation> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? title,
    Expression<String>? modelPlan,
    Expression<bool>? isIncognito,
    Expression<bool>? isStarred,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? lastMessageAt,
    Expression<String>? syncStatus,
    Expression<DateTime>? remoteUpdatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (title != null) 'title': title,
      if (modelPlan != null) 'model_plan': modelPlan,
      if (isIncognito != null) 'is_incognito': isIncognito,
      if (isStarred != null) 'is_starred': isStarred,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (lastMessageAt != null) 'last_message_at': lastMessageAt,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (remoteUpdatedAt != null) 'remote_updated_at': remoteUpdatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalConversationsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? title,
    Value<String?>? modelPlan,
    Value<bool>? isIncognito,
    Value<bool>? isStarred,
    Value<DateTime>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<DateTime?>? lastMessageAt,
    Value<String>? syncStatus,
    Value<DateTime?>? remoteUpdatedAt,
    Value<int>? rowid,
  }) {
    return LocalConversationsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      modelPlan: modelPlan ?? this.modelPlan,
      isIncognito: isIncognito ?? this.isIncognito,
      isStarred: isStarred ?? this.isStarred,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      syncStatus: syncStatus ?? this.syncStatus,
      remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (modelPlan.present) {
      map['model_plan'] = Variable<String>(modelPlan.value);
    }
    if (isIncognito.present) {
      map['is_incognito'] = Variable<bool>(isIncognito.value);
    }
    if (isStarred.present) {
      map['is_starred'] = Variable<bool>(isStarred.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (lastMessageAt.present) {
      map['last_message_at'] = Variable<DateTime>(lastMessageAt.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (remoteUpdatedAt.present) {
      map['remote_updated_at'] = Variable<DateTime>(remoteUpdatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalConversationsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('title: $title, ')
          ..write('modelPlan: $modelPlan, ')
          ..write('isIncognito: $isIncognito, ')
          ..write('isStarred: $isStarred, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('lastMessageAt: $lastMessageAt, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('remoteUpdatedAt: $remoteUpdatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalMessagesTable extends LocalMessages
    with TableInfo<$LocalMessagesTable, LocalMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    $customConstraints:
        'NOT NULL REFERENCES local_conversations(id) ON DELETE CASCADE',
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<LocalMessageStatus, String>
  status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: Constant(LocalMessageStatus.pending.name),
  ).withConverter<LocalMessageStatus>($LocalMessagesTable.$converterstatus);
  @override
  late final GeneratedColumnWithTypeConverter<LocalMessageSyncStatus, String>
  syncStatus =
      GeneratedColumn<String>(
        'sync_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(LocalMessageSyncStatus.local.name),
      ).withConverter<LocalMessageSyncStatus>(
        $LocalMessagesTable.$convertersyncStatus,
      );
  static const VerificationMeta _localSeqMeta = const VerificationMeta(
    'localSeq',
  );
  @override
  late final GeneratedColumn<int> localSeq = GeneratedColumn<int>(
    'local_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _intentDetectedMeta = const VerificationMeta(
    'intentDetected',
  );
  @override
  late final GeneratedColumn<String> intentDetected = GeneratedColumn<String>(
    'intent_detected',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelCalledMeta = const VerificationMeta(
    'modelCalled',
  );
  @override
  late final GeneratedColumn<String> modelCalled = GeneratedColumn<String>(
    'model_called',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourcesJsonMeta = const VerificationMeta(
    'sourcesJson',
  );
  @override
  late final GeneratedColumn<String> sourcesJson = GeneratedColumn<String>(
    'sources_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isThinkingMeta = const VerificationMeta(
    'isThinking',
  );
  @override
  late final GeneratedColumn<bool> isThinking = GeneratedColumn<bool>(
    'is_thinking',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_thinking" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isDegradedMeta = const VerificationMeta(
    'isDegraded',
  );
  @override
  late final GeneratedColumn<bool> isDegraded = GeneratedColumn<bool>(
    'is_degraded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_degraded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    role,
    content,
    status,
    syncStatus,
    localSeq,
    remoteId,
    intentDetected,
    modelCalled,
    sourcesJson,
    attachmentsJson,
    isThinking,
    isDegraded,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('local_seq')) {
      context.handle(
        _localSeqMeta,
        localSeq.isAcceptableOrUnknown(data['local_seq']!, _localSeqMeta),
      );
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    }
    if (data.containsKey('intent_detected')) {
      context.handle(
        _intentDetectedMeta,
        intentDetected.isAcceptableOrUnknown(
          data['intent_detected']!,
          _intentDetectedMeta,
        ),
      );
    }
    if (data.containsKey('model_called')) {
      context.handle(
        _modelCalledMeta,
        modelCalled.isAcceptableOrUnknown(
          data['model_called']!,
          _modelCalledMeta,
        ),
      );
    }
    if (data.containsKey('sources_json')) {
      context.handle(
        _sourcesJsonMeta,
        sourcesJson.isAcceptableOrUnknown(
          data['sources_json']!,
          _sourcesJsonMeta,
        ),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('is_thinking')) {
      context.handle(
        _isThinkingMeta,
        isThinking.isAcceptableOrUnknown(data['is_thinking']!, _isThinkingMeta),
      );
    }
    if (data.containsKey('is_degraded')) {
      context.handle(
        _isDegradedMeta,
        isDegraded.isAcceptableOrUnknown(data['is_degraded']!, _isDegradedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      status: $LocalMessagesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      syncStatus: $LocalMessagesTable.$convertersyncStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sync_status'],
        )!,
      ),
      localSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_seq'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      ),
      intentDetected: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}intent_detected'],
      ),
      modelCalled: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_called'],
      ),
      sourcesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sources_json'],
      ),
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      ),
      isThinking: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_thinking'],
      )!,
      isDegraded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_degraded'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $LocalMessagesTable createAlias(String alias) {
    return $LocalMessagesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<LocalMessageStatus, String, String>
  $converterstatus = const EnumNameConverter<LocalMessageStatus>(
    LocalMessageStatus.values,
  );
  static JsonTypeConverter2<LocalMessageSyncStatus, String, String>
  $convertersyncStatus = const EnumNameConverter<LocalMessageSyncStatus>(
    LocalMessageSyncStatus.values,
  );
}

class LocalMessage extends DataClass implements Insertable<LocalMessage> {
  final String id;
  final String conversationId;
  final String role;
  final String content;
  final LocalMessageStatus status;
  final LocalMessageSyncStatus syncStatus;
  final int localSeq;
  final String? remoteId;
  final String? intentDetected;
  final String? modelCalled;
  final String? sourcesJson;
  final String? attachmentsJson;
  final bool isThinking;
  final bool isDegraded;
  final DateTime createdAt;
  final DateTime? updatedAt;
  const LocalMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.status,
    required this.syncStatus,
    required this.localSeq,
    this.remoteId,
    this.intentDetected,
    this.modelCalled,
    this.sourcesJson,
    this.attachmentsJson,
    required this.isThinking,
    required this.isDegraded,
    required this.createdAt,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['role'] = Variable<String>(role);
    map['content'] = Variable<String>(content);
    {
      map['status'] = Variable<String>(
        $LocalMessagesTable.$converterstatus.toSql(status),
      );
    }
    {
      map['sync_status'] = Variable<String>(
        $LocalMessagesTable.$convertersyncStatus.toSql(syncStatus),
      );
    }
    map['local_seq'] = Variable<int>(localSeq);
    if (!nullToAbsent || remoteId != null) {
      map['remote_id'] = Variable<String>(remoteId);
    }
    if (!nullToAbsent || intentDetected != null) {
      map['intent_detected'] = Variable<String>(intentDetected);
    }
    if (!nullToAbsent || modelCalled != null) {
      map['model_called'] = Variable<String>(modelCalled);
    }
    if (!nullToAbsent || sourcesJson != null) {
      map['sources_json'] = Variable<String>(sourcesJson);
    }
    if (!nullToAbsent || attachmentsJson != null) {
      map['attachments_json'] = Variable<String>(attachmentsJson);
    }
    map['is_thinking'] = Variable<bool>(isThinking);
    map['is_degraded'] = Variable<bool>(isDegraded);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  LocalMessagesCompanion toCompanion(bool nullToAbsent) {
    return LocalMessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      role: Value(role),
      content: Value(content),
      status: Value(status),
      syncStatus: Value(syncStatus),
      localSeq: Value(localSeq),
      remoteId: remoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteId),
      intentDetected: intentDetected == null && nullToAbsent
          ? const Value.absent()
          : Value(intentDetected),
      modelCalled: modelCalled == null && nullToAbsent
          ? const Value.absent()
          : Value(modelCalled),
      sourcesJson: sourcesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(sourcesJson),
      attachmentsJson: attachmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(attachmentsJson),
      isThinking: Value(isThinking),
      isDegraded: Value(isDegraded),
      createdAt: Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory LocalMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalMessage(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      role: serializer.fromJson<String>(json['role']),
      content: serializer.fromJson<String>(json['content']),
      status: $LocalMessagesTable.$converterstatus.fromJson(
        serializer.fromJson<String>(json['status']),
      ),
      syncStatus: $LocalMessagesTable.$convertersyncStatus.fromJson(
        serializer.fromJson<String>(json['syncStatus']),
      ),
      localSeq: serializer.fromJson<int>(json['localSeq']),
      remoteId: serializer.fromJson<String?>(json['remoteId']),
      intentDetected: serializer.fromJson<String?>(json['intentDetected']),
      modelCalled: serializer.fromJson<String?>(json['modelCalled']),
      sourcesJson: serializer.fromJson<String?>(json['sourcesJson']),
      attachmentsJson: serializer.fromJson<String?>(json['attachmentsJson']),
      isThinking: serializer.fromJson<bool>(json['isThinking']),
      isDegraded: serializer.fromJson<bool>(json['isDegraded']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'role': serializer.toJson<String>(role),
      'content': serializer.toJson<String>(content),
      'status': serializer.toJson<String>(
        $LocalMessagesTable.$converterstatus.toJson(status),
      ),
      'syncStatus': serializer.toJson<String>(
        $LocalMessagesTable.$convertersyncStatus.toJson(syncStatus),
      ),
      'localSeq': serializer.toJson<int>(localSeq),
      'remoteId': serializer.toJson<String?>(remoteId),
      'intentDetected': serializer.toJson<String?>(intentDetected),
      'modelCalled': serializer.toJson<String?>(modelCalled),
      'sourcesJson': serializer.toJson<String?>(sourcesJson),
      'attachmentsJson': serializer.toJson<String?>(attachmentsJson),
      'isThinking': serializer.toJson<bool>(isThinking),
      'isDegraded': serializer.toJson<bool>(isDegraded),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  LocalMessage copyWith({
    String? id,
    String? conversationId,
    String? role,
    String? content,
    LocalMessageStatus? status,
    LocalMessageSyncStatus? syncStatus,
    int? localSeq,
    Value<String?> remoteId = const Value.absent(),
    Value<String?> intentDetected = const Value.absent(),
    Value<String?> modelCalled = const Value.absent(),
    Value<String?> sourcesJson = const Value.absent(),
    Value<String?> attachmentsJson = const Value.absent(),
    bool? isThinking,
    bool? isDegraded,
    DateTime? createdAt,
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => LocalMessage(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    role: role ?? this.role,
    content: content ?? this.content,
    status: status ?? this.status,
    syncStatus: syncStatus ?? this.syncStatus,
    localSeq: localSeq ?? this.localSeq,
    remoteId: remoteId.present ? remoteId.value : this.remoteId,
    intentDetected: intentDetected.present
        ? intentDetected.value
        : this.intentDetected,
    modelCalled: modelCalled.present ? modelCalled.value : this.modelCalled,
    sourcesJson: sourcesJson.present ? sourcesJson.value : this.sourcesJson,
    attachmentsJson: attachmentsJson.present
        ? attachmentsJson.value
        : this.attachmentsJson,
    isThinking: isThinking ?? this.isThinking,
    isDegraded: isDegraded ?? this.isDegraded,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  LocalMessage copyWithCompanion(LocalMessagesCompanion data) {
    return LocalMessage(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      role: data.role.present ? data.role.value : this.role,
      content: data.content.present ? data.content.value : this.content,
      status: data.status.present ? data.status.value : this.status,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      localSeq: data.localSeq.present ? data.localSeq.value : this.localSeq,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      intentDetected: data.intentDetected.present
          ? data.intentDetected.value
          : this.intentDetected,
      modelCalled: data.modelCalled.present
          ? data.modelCalled.value
          : this.modelCalled,
      sourcesJson: data.sourcesJson.present
          ? data.sourcesJson.value
          : this.sourcesJson,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      isThinking: data.isThinking.present
          ? data.isThinking.value
          : this.isThinking,
      isDegraded: data.isDegraded.present
          ? data.isDegraded.value
          : this.isDegraded,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalMessage(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localSeq: $localSeq, ')
          ..write('remoteId: $remoteId, ')
          ..write('intentDetected: $intentDetected, ')
          ..write('modelCalled: $modelCalled, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('isThinking: $isThinking, ')
          ..write('isDegraded: $isDegraded, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    role,
    content,
    status,
    syncStatus,
    localSeq,
    remoteId,
    intentDetected,
    modelCalled,
    sourcesJson,
    attachmentsJson,
    isThinking,
    isDegraded,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalMessage &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.content == this.content &&
          other.status == this.status &&
          other.syncStatus == this.syncStatus &&
          other.localSeq == this.localSeq &&
          other.remoteId == this.remoteId &&
          other.intentDetected == this.intentDetected &&
          other.modelCalled == this.modelCalled &&
          other.sourcesJson == this.sourcesJson &&
          other.attachmentsJson == this.attachmentsJson &&
          other.isThinking == this.isThinking &&
          other.isDegraded == this.isDegraded &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalMessagesCompanion extends UpdateCompanion<LocalMessage> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> role;
  final Value<String> content;
  final Value<LocalMessageStatus> status;
  final Value<LocalMessageSyncStatus> syncStatus;
  final Value<int> localSeq;
  final Value<String?> remoteId;
  final Value<String?> intentDetected;
  final Value<String?> modelCalled;
  final Value<String?> sourcesJson;
  final Value<String?> attachmentsJson;
  final Value<bool> isThinking;
  final Value<bool> isDegraded;
  final Value<DateTime> createdAt;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const LocalMessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.content = const Value.absent(),
    this.status = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.localSeq = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.intentDetected = const Value.absent(),
    this.modelCalled = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.isThinking = const Value.absent(),
    this.isDegraded = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalMessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String role,
    required String content,
    this.status = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.localSeq = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.intentDetected = const Value.absent(),
    this.modelCalled = const Value.absent(),
    this.sourcesJson = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.isThinking = const Value.absent(),
    this.isDegraded = const Value.absent(),
    required DateTime createdAt,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       role = Value(role),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<LocalMessage> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? role,
    Expression<String>? content,
    Expression<String>? status,
    Expression<String>? syncStatus,
    Expression<int>? localSeq,
    Expression<String>? remoteId,
    Expression<String>? intentDetected,
    Expression<String>? modelCalled,
    Expression<String>? sourcesJson,
    Expression<String>? attachmentsJson,
    Expression<bool>? isThinking,
    Expression<bool>? isDegraded,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (content != null) 'content': content,
      if (status != null) 'status': status,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (localSeq != null) 'local_seq': localSeq,
      if (remoteId != null) 'remote_id': remoteId,
      if (intentDetected != null) 'intent_detected': intentDetected,
      if (modelCalled != null) 'model_called': modelCalled,
      if (sourcesJson != null) 'sources_json': sourcesJson,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (isThinking != null) 'is_thinking': isThinking,
      if (isDegraded != null) 'is_degraded': isDegraded,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? role,
    Value<String>? content,
    Value<LocalMessageStatus>? status,
    Value<LocalMessageSyncStatus>? syncStatus,
    Value<int>? localSeq,
    Value<String?>? remoteId,
    Value<String?>? intentDetected,
    Value<String?>? modelCalled,
    Value<String?>? sourcesJson,
    Value<String?>? attachmentsJson,
    Value<bool>? isThinking,
    Value<bool>? isDegraded,
    Value<DateTime>? createdAt,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return LocalMessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      status: status ?? this.status,
      syncStatus: syncStatus ?? this.syncStatus,
      localSeq: localSeq ?? this.localSeq,
      remoteId: remoteId ?? this.remoteId,
      intentDetected: intentDetected ?? this.intentDetected,
      modelCalled: modelCalled ?? this.modelCalled,
      sourcesJson: sourcesJson ?? this.sourcesJson,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      isThinking: isThinking ?? this.isThinking,
      isDegraded: isDegraded ?? this.isDegraded,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $LocalMessagesTable.$converterstatus.toSql(status.value),
      );
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(
        $LocalMessagesTable.$convertersyncStatus.toSql(syncStatus.value),
      );
    }
    if (localSeq.present) {
      map['local_seq'] = Variable<int>(localSeq.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (intentDetected.present) {
      map['intent_detected'] = Variable<String>(intentDetected.value);
    }
    if (modelCalled.present) {
      map['model_called'] = Variable<String>(modelCalled.value);
    }
    if (sourcesJson.present) {
      map['sources_json'] = Variable<String>(sourcesJson.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (isThinking.present) {
      map['is_thinking'] = Variable<bool>(isThinking.value);
    }
    if (isDegraded.present) {
      map['is_degraded'] = Variable<bool>(isDegraded.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalMessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('content: $content, ')
          ..write('status: $status, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('localSeq: $localSeq, ')
          ..write('remoteId: $remoteId, ')
          ..write('intentDetected: $intentDetected, ')
          ..write('modelCalled: $modelCalled, ')
          ..write('sourcesJson: $sourcesJson, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('isThinking: $isThinking, ')
          ..write('isDegraded: $isDegraded, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalConversationsTable localConversations =
      $LocalConversationsTable(this);
  late final $LocalMessagesTable localMessages = $LocalMessagesTable(this);
  late final ConversationsDao conversationsDao = ConversationsDao(
    this as AppDatabase,
  );
  late final MessagesDao messagesDao = MessagesDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localConversations,
    localMessages,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'local_conversations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('local_messages', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$LocalConversationsTableCreateCompanionBuilder =
    LocalConversationsCompanion Function({
      required String id,
      required String userId,
      Value<String> title,
      Value<String?> modelPlan,
      Value<bool> isIncognito,
      Value<bool> isStarred,
      required DateTime createdAt,
      Value<DateTime?> updatedAt,
      Value<DateTime?> lastMessageAt,
      Value<String> syncStatus,
      Value<DateTime?> remoteUpdatedAt,
      Value<int> rowid,
    });
typedef $$LocalConversationsTableUpdateCompanionBuilder =
    LocalConversationsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> title,
      Value<String?> modelPlan,
      Value<bool> isIncognito,
      Value<bool> isStarred,
      Value<DateTime> createdAt,
      Value<DateTime?> updatedAt,
      Value<DateTime?> lastMessageAt,
      Value<String> syncStatus,
      Value<DateTime?> remoteUpdatedAt,
      Value<int> rowid,
    });

final class $$LocalConversationsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $LocalConversationsTable,
          LocalConversation
        > {
  $$LocalConversationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$LocalMessagesTable, List<LocalMessage>>
  _localMessagesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.localMessages,
    aliasName: $_aliasNameGenerator(
      db.localConversations.id,
      db.localMessages.conversationId,
    ),
  );

  $$LocalMessagesTableProcessedTableManager get localMessagesRefs {
    final manager = $$LocalMessagesTableTableManager(
      $_db,
      $_db.localMessages,
    ).filter((f) => f.conversationId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_localMessagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$LocalConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalConversationsTable> {
  $$LocalConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelPlan => $composableBuilder(
    column: $table.modelPlan,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isIncognito => $composableBuilder(
    column: $table.isIncognito,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isStarred => $composableBuilder(
    column: $table.isStarred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get remoteUpdatedAt => $composableBuilder(
    column: $table.remoteUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> localMessagesRefs(
    Expression<bool> Function($$LocalMessagesTableFilterComposer f) f,
  ) {
    final $$LocalMessagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localMessages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalMessagesTableFilterComposer(
            $db: $db,
            $table: $db.localMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalConversationsTable> {
  $$LocalConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelPlan => $composableBuilder(
    column: $table.modelPlan,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isIncognito => $composableBuilder(
    column: $table.isIncognito,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isStarred => $composableBuilder(
    column: $table.isStarred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get remoteUpdatedAt => $composableBuilder(
    column: $table.remoteUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalConversationsTable> {
  $$LocalConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get modelPlan =>
      $composableBuilder(column: $table.modelPlan, builder: (column) => column);

  GeneratedColumn<bool> get isIncognito => $composableBuilder(
    column: $table.isIncognito,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isStarred =>
      $composableBuilder(column: $table.isStarred, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastMessageAt => $composableBuilder(
    column: $table.lastMessageAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get remoteUpdatedAt => $composableBuilder(
    column: $table.remoteUpdatedAt,
    builder: (column) => column,
  );

  Expression<T> localMessagesRefs<T extends Object>(
    Expression<T> Function($$LocalMessagesTableAnnotationComposer a) f,
  ) {
    final $$LocalMessagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.localMessages,
      getReferencedColumn: (t) => t.conversationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalMessagesTableAnnotationComposer(
            $db: $db,
            $table: $db.localMessages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$LocalConversationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalConversationsTable,
          LocalConversation,
          $$LocalConversationsTableFilterComposer,
          $$LocalConversationsTableOrderingComposer,
          $$LocalConversationsTableAnnotationComposer,
          $$LocalConversationsTableCreateCompanionBuilder,
          $$LocalConversationsTableUpdateCompanionBuilder,
          (LocalConversation, $$LocalConversationsTableReferences),
          LocalConversation,
          PrefetchHooks Function({bool localMessagesRefs})
        > {
  $$LocalConversationsTableTableManager(
    _$AppDatabase db,
    $LocalConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalConversationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> modelPlan = const Value.absent(),
                Value<bool> isIncognito = const Value.absent(),
                Value<bool> isStarred = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime?> remoteUpdatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalConversationsCompanion(
                id: id,
                userId: userId,
                title: title,
                modelPlan: modelPlan,
                isIncognito: isIncognito,
                isStarred: isStarred,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastMessageAt: lastMessageAt,
                syncStatus: syncStatus,
                remoteUpdatedAt: remoteUpdatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                Value<String> title = const Value.absent(),
                Value<String?> modelPlan = const Value.absent(),
                Value<bool> isIncognito = const Value.absent(),
                Value<bool> isStarred = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> lastMessageAt = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<DateTime?> remoteUpdatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalConversationsCompanion.insert(
                id: id,
                userId: userId,
                title: title,
                modelPlan: modelPlan,
                isIncognito: isIncognito,
                isStarred: isStarred,
                createdAt: createdAt,
                updatedAt: updatedAt,
                lastMessageAt: lastMessageAt,
                syncStatus: syncStatus,
                remoteUpdatedAt: remoteUpdatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalConversationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localMessagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (localMessagesRefs) db.localMessages,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (localMessagesRefs)
                    await $_getPrefetchedData<
                      LocalConversation,
                      $LocalConversationsTable,
                      LocalMessage
                    >(
                      currentTable: table,
                      referencedTable: $$LocalConversationsTableReferences
                          ._localMessagesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$LocalConversationsTableReferences(
                            db,
                            table,
                            p0,
                          ).localMessagesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.conversationId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$LocalConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalConversationsTable,
      LocalConversation,
      $$LocalConversationsTableFilterComposer,
      $$LocalConversationsTableOrderingComposer,
      $$LocalConversationsTableAnnotationComposer,
      $$LocalConversationsTableCreateCompanionBuilder,
      $$LocalConversationsTableUpdateCompanionBuilder,
      (LocalConversation, $$LocalConversationsTableReferences),
      LocalConversation,
      PrefetchHooks Function({bool localMessagesRefs})
    >;
typedef $$LocalMessagesTableCreateCompanionBuilder =
    LocalMessagesCompanion Function({
      required String id,
      required String conversationId,
      required String role,
      required String content,
      Value<LocalMessageStatus> status,
      Value<LocalMessageSyncStatus> syncStatus,
      Value<int> localSeq,
      Value<String?> remoteId,
      Value<String?> intentDetected,
      Value<String?> modelCalled,
      Value<String?> sourcesJson,
      Value<String?> attachmentsJson,
      Value<bool> isThinking,
      Value<bool> isDegraded,
      required DateTime createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$LocalMessagesTableUpdateCompanionBuilder =
    LocalMessagesCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String> role,
      Value<String> content,
      Value<LocalMessageStatus> status,
      Value<LocalMessageSyncStatus> syncStatus,
      Value<int> localSeq,
      Value<String?> remoteId,
      Value<String?> intentDetected,
      Value<String?> modelCalled,
      Value<String?> sourcesJson,
      Value<String?> attachmentsJson,
      Value<bool> isThinking,
      Value<bool> isDegraded,
      Value<DateTime> createdAt,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

final class $$LocalMessagesTableReferences
    extends BaseReferences<_$AppDatabase, $LocalMessagesTable, LocalMessage> {
  $$LocalMessagesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $LocalConversationsTable _conversationIdTable(_$AppDatabase db) =>
      db.localConversations.createAlias(
        $_aliasNameGenerator(
          db.localMessages.conversationId,
          db.localConversations.id,
        ),
      );

  $$LocalConversationsTableProcessedTableManager get conversationId {
    final $_column = $_itemColumn<String>('conversation_id')!;

    final manager = $$LocalConversationsTableTableManager(
      $_db,
      $_db.localConversations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_conversationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LocalMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<LocalMessageStatus, LocalMessageStatus, String>
  get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<
    LocalMessageSyncStatus,
    LocalMessageSyncStatus,
    String
  >
  get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get intentDetected => $composableBuilder(
    column: $table.intentDetected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelCalled => $composableBuilder(
    column: $table.modelCalled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcesJson => $composableBuilder(
    column: $table.sourcesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isThinking => $composableBuilder(
    column: $table.isThinking,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDegraded => $composableBuilder(
    column: $table.isDegraded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$LocalConversationsTableFilterComposer get conversationId {
    final $$LocalConversationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.localConversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalConversationsTableFilterComposer(
            $db: $db,
            $table: $db.localConversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get localSeq => $composableBuilder(
    column: $table.localSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get intentDetected => $composableBuilder(
    column: $table.intentDetected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelCalled => $composableBuilder(
    column: $table.modelCalled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcesJson => $composableBuilder(
    column: $table.sourcesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isThinking => $composableBuilder(
    column: $table.isThinking,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDegraded => $composableBuilder(
    column: $table.isDegraded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$LocalConversationsTableOrderingComposer get conversationId {
    final $$LocalConversationsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.conversationId,
      referencedTable: $db.localConversations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LocalConversationsTableOrderingComposer(
            $db: $db,
            $table: $db.localConversations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LocalMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalMessagesTable> {
  $$LocalMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LocalMessageStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumnWithTypeConverter<LocalMessageSyncStatus, String>
  get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get localSeq =>
      $composableBuilder(column: $table.localSeq, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get intentDetected => $composableBuilder(
    column: $table.intentDetected,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelCalled => $composableBuilder(
    column: $table.modelCalled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourcesJson => $composableBuilder(
    column: $table.sourcesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isThinking => $composableBuilder(
    column: $table.isThinking,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDegraded => $composableBuilder(
    column: $table.isDegraded,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$LocalConversationsTableAnnotationComposer get conversationId {
    final $$LocalConversationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.conversationId,
          referencedTable: $db.localConversations,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$LocalConversationsTableAnnotationComposer(
                $db: $db,
                $table: $db.localConversations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$LocalMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalMessagesTable,
          LocalMessage,
          $$LocalMessagesTableFilterComposer,
          $$LocalMessagesTableOrderingComposer,
          $$LocalMessagesTableAnnotationComposer,
          $$LocalMessagesTableCreateCompanionBuilder,
          $$LocalMessagesTableUpdateCompanionBuilder,
          (LocalMessage, $$LocalMessagesTableReferences),
          LocalMessage,
          PrefetchHooks Function({bool conversationId})
        > {
  $$LocalMessagesTableTableManager(_$AppDatabase db, $LocalMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<LocalMessageStatus> status = const Value.absent(),
                Value<LocalMessageSyncStatus> syncStatus = const Value.absent(),
                Value<int> localSeq = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<String?> intentDetected = const Value.absent(),
                Value<String?> modelCalled = const Value.absent(),
                Value<String?> sourcesJson = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<bool> isThinking = const Value.absent(),
                Value<bool> isDegraded = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMessagesCompanion(
                id: id,
                conversationId: conversationId,
                role: role,
                content: content,
                status: status,
                syncStatus: syncStatus,
                localSeq: localSeq,
                remoteId: remoteId,
                intentDetected: intentDetected,
                modelCalled: modelCalled,
                sourcesJson: sourcesJson,
                attachmentsJson: attachmentsJson,
                isThinking: isThinking,
                isDegraded: isDegraded,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String role,
                required String content,
                Value<LocalMessageStatus> status = const Value.absent(),
                Value<LocalMessageSyncStatus> syncStatus = const Value.absent(),
                Value<int> localSeq = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<String?> intentDetected = const Value.absent(),
                Value<String?> modelCalled = const Value.absent(),
                Value<String?> sourcesJson = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<bool> isThinking = const Value.absent(),
                Value<bool> isDegraded = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalMessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                role: role,
                content: content,
                status: status,
                syncStatus: syncStatus,
                localSeq: localSeq,
                remoteId: remoteId,
                intentDetected: intentDetected,
                modelCalled: modelCalled,
                sourcesJson: sourcesJson,
                attachmentsJson: attachmentsJson,
                isThinking: isThinking,
                isDegraded: isDegraded,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$LocalMessagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({conversationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (conversationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.conversationId,
                                referencedTable: $$LocalMessagesTableReferences
                                    ._conversationIdTable(db),
                                referencedColumn: $$LocalMessagesTableReferences
                                    ._conversationIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LocalMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalMessagesTable,
      LocalMessage,
      $$LocalMessagesTableFilterComposer,
      $$LocalMessagesTableOrderingComposer,
      $$LocalMessagesTableAnnotationComposer,
      $$LocalMessagesTableCreateCompanionBuilder,
      $$LocalMessagesTableUpdateCompanionBuilder,
      (LocalMessage, $$LocalMessagesTableReferences),
      LocalMessage,
      PrefetchHooks Function({bool conversationId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalConversationsTableTableManager get localConversations =>
      $$LocalConversationsTableTableManager(_db, _db.localConversations);
  $$LocalMessagesTableTableManager get localMessages =>
      $$LocalMessagesTableTableManager(_db, _db.localMessages);
}
