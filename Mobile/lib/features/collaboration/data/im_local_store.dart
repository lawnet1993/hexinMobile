import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/im_cache_cipher.dart';
import '../domain/collaboration_models.dart';

final class ImOutboxItem {
  const ImOutboxItem({
    required this.clientMessageId,
    required this.conversationId,
    required this.content,
    required this.kind,
    required this.attempts,
    this.mentionedMemberIds = const [],
    this.mentionAll = false,
    this.replyToMessageId,
    this.attachmentName = '',
    this.attachmentContentType = '',
    this.attachmentBytes = const <int>[],
    this.contactMemberId,
  });

  final String clientMessageId;
  final String conversationId;
  final String content;
  final String kind;
  final int attempts;
  final List<String> mentionedMemberIds;
  final bool mentionAll;
  final String? replyToMessageId;
  final String attachmentName;
  final String attachmentContentType;
  final List<int> attachmentBytes;
  final String? contactMemberId;
}

final class ImLocalStore {
  ImLocalStore({
    DatabaseFactory? factory,
    Future<String> Function()? pathResolver,
    ImCacheCipher cipher = const PlainImCacheCipher(),
  }) : this.withOptions(
         factory ?? databaseFactory,
         pathResolver ?? _defaultPath,
         cipher,
       );

  ImLocalStore.withOptions(this._factory, this._pathResolver, this._cipher);

  final DatabaseFactory _factory;
  final Future<String> Function() _pathResolver;
  final ImCacheCipher _cipher;
  Future<Database>? _opening;

  static Future<String> _defaultPath() async =>
      path.join(await getDatabasesPath(), 'hexing-mobile-im.db');

  Future<Database> get _database => _opening ??= _open();

  Future<Database> _open() async {
    final database = await _factory.openDatabase(
      await _pathResolver(),
      options: OpenDatabaseOptions(
        version: 9,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
          // journal_mode returns a result row on Android SQLite and therefore
          // must be issued through rawQuery rather than execute.
          await database.rawQuery('PRAGMA journal_mode = WAL');
        },
        onCreate: (database, _) async {
          await database.execute('''
          CREATE TABLE im_members (
            account_id TEXT NOT NULL,
            id TEXT NOT NULL,
            username TEXT NOT NULL,
            display_name TEXT NOT NULL,
            is_online INTEGER NOT NULL,
            avatar_key TEXT NOT NULL,
            avatar_data_url TEXT NOT NULL,
            department_id TEXT NOT NULL,
            department_name TEXT NOT NULL,
            is_organization_manager INTEGER NOT NULL,
            is_friend INTEGER NOT NULL,
            can_start_direct INTEGER NOT NULL,
            is_current INTEGER NOT NULL,
            is_contact INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (account_id, id)
          )
        ''');
          await database.execute('''
          CREATE TABLE im_conversations (
            account_id TEXT NOT NULL,
            id TEXT NOT NULL,
            type TEXT NOT NULL,
            title TEXT NOT NULL,
            preview TEXT NOT NULL,
            updated_at TEXT,
            unread_count INTEGER NOT NULL,
            last_message_sequence INTEGER NOT NULL,
            is_pinned INTEGER NOT NULL,
            is_muted INTEGER NOT NULL,
            unread_mention_sequences_json TEXT NOT NULL DEFAULT '[]',
            PRIMARY KEY (account_id, id)
          )
        ''');
          await database.execute('''
          CREATE TABLE im_messages (
            account_id TEXT NOT NULL,
            id TEXT NOT NULL,
            conversation_id TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            sender_id TEXT NOT NULL,
            client_message_id TEXT NOT NULL,
            content TEXT NOT NULL,
            kind TEXT NOT NULL,
            attachment_name TEXT NOT NULL DEFAULT '',
            attachment_size INTEGER,
            attachment_content_type TEXT NOT NULL DEFAULT '',
            attachment_sha256 TEXT NOT NULL DEFAULT '',
            contact_card_json TEXT NOT NULL DEFAULT '',
            images_json TEXT NOT NULL DEFAULT '',
            media_attachments_json TEXT NOT NULL DEFAULT '',
            created_at TEXT,
            recalled_at TEXT,
            mentions_json TEXT NOT NULL DEFAULT '',
            reply_to_json TEXT NOT NULL DEFAULT '',
            local_status TEXT NOT NULL,
            last_error TEXT NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (account_id, id)
          )
        ''');
          await database.execute('''
          CREATE UNIQUE INDEX ux_im_messages_client_id
          ON im_messages(account_id, sender_id, client_message_id)
          WHERE client_message_id <> ''
        ''');
          await database.execute('''
          CREATE INDEX ix_im_messages_conversation_sequence
          ON im_messages(account_id, conversation_id, sequence)
        ''');
          await database.execute('''
          CREATE TABLE im_outbox (
            account_id TEXT NOT NULL,
            client_message_id TEXT NOT NULL,
            conversation_id TEXT NOT NULL,
            content TEXT NOT NULL,
            kind TEXT NOT NULL DEFAULT 'text',
            mentioned_member_ids_json TEXT NOT NULL DEFAULT '[]',
            mention_all INTEGER NOT NULL DEFAULT 0,
            reply_to_message_id TEXT,
            attachment_name TEXT NOT NULL DEFAULT '',
            attachment_content_type TEXT NOT NULL DEFAULT '',
            attachment_bytes_base64 TEXT NOT NULL DEFAULT '',
            contact_member_id TEXT,
            attempts INTEGER NOT NULL,
            next_retry_at TEXT NOT NULL,
            last_error TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY (account_id, client_message_id)
          )
        ''');
          await database.execute('''
          CREATE TABLE im_event_inbox (
            account_id TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            event_id TEXT NOT NULL,
            type TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT,
            PRIMARY KEY (account_id, sequence),
            UNIQUE (account_id, event_id)
          )
        ''');
          await database.execute('''
          CREATE TABLE im_sync_state (
            account_id TEXT NOT NULL,
            state_key TEXT NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (account_id, state_key)
          )
        ''');
          await _createConversationDetailTables(database);
        },
        onUpgrade: (database, oldVersion, _) async {
          if (oldVersion < 2) {
            await database.execute(
              'ALTER TABLE im_members ADD COLUMN is_organization_manager INTEGER NOT NULL DEFAULT 0',
            );
            await database.execute(
              'ALTER TABLE im_members ADD COLUMN is_friend INTEGER NOT NULL DEFAULT 0',
            );
            await database.execute(
              'ALTER TABLE im_members ADD COLUMN can_start_direct INTEGER NOT NULL DEFAULT 0',
            );
            await _createConversationDetailTables(database);
          }
          if (oldVersion < 3) {
            await _addMessageMetadataColumns(database);
          }
          if (oldVersion < 5) {
            await _addMessageMetadataColumns(database);
            await _addOutboxMessageColumns(database);
          }
          if (oldVersion < 6) {
            await _addOutboxPayloadColumns(database);
          }
          if (oldVersion < 7) {
            await _addConversationMentionColumn(database);
          }
          if (oldVersion < 8) {
            await _addMessageMetadataColumns(database);
          }
          if (oldVersion < 9) {
            await _addMessageMetadataColumns(database);
          }
        },
      ),
    );
    if (_cipher.isEnabled) {
      await _protectLegacySensitivePayloads(database);
    }
    return database;
  }

  static Future<void> _addMessageMetadataColumns(
    DatabaseExecutor database,
  ) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'im_messages'",
    );
    if (tables.isEmpty) return;
    final columns = (await database.rawQuery('PRAGMA table_info(im_messages)'))
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    final additions = <String, String>{
      'attachment_name': "TEXT NOT NULL DEFAULT ''",
      'attachment_size': 'INTEGER',
      'attachment_content_type': "TEXT NOT NULL DEFAULT ''",
      'attachment_sha256': "TEXT NOT NULL DEFAULT ''",
      'contact_card_json': "TEXT NOT NULL DEFAULT ''",
      'images_json': "TEXT NOT NULL DEFAULT ''",
      'media_attachments_json': "TEXT NOT NULL DEFAULT ''",
      'mentions_json': "TEXT NOT NULL DEFAULT ''",
      'reply_to_json': "TEXT NOT NULL DEFAULT ''",
    };
    for (final entry in additions.entries) {
      if (!columns.contains(entry.key)) {
        await database.execute(
          'ALTER TABLE im_messages ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }

  static Future<void> _addConversationMentionColumn(
    DatabaseExecutor database,
  ) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'im_conversations'",
    );
    if (tables.isEmpty) return;
    final columns = (await database.rawQuery(
      'PRAGMA table_info(im_conversations)',
    )).map((row) => row['name']?.toString() ?? '').toSet();
    if (!columns.contains('unread_mention_sequences_json')) {
      await database.execute(
        "ALTER TABLE im_conversations ADD COLUMN unread_mention_sequences_json TEXT NOT NULL DEFAULT '[]'",
      );
    }
  }

  static Future<void> _addOutboxPayloadColumns(
    DatabaseExecutor database,
  ) async {
    await _addOutboxColumns(database, {
      'kind': "TEXT NOT NULL DEFAULT 'text'",
      'attachment_name': "TEXT NOT NULL DEFAULT ''",
      'attachment_content_type': "TEXT NOT NULL DEFAULT ''",
      'attachment_bytes_base64': "TEXT NOT NULL DEFAULT ''",
      'contact_member_id': 'TEXT',
    });
  }

  static Future<void> _addOutboxMessageColumns(
    DatabaseExecutor database,
  ) async {
    await _addOutboxColumns(database, {
      'mentioned_member_ids_json': "TEXT NOT NULL DEFAULT '[]'",
      'mention_all': 'INTEGER NOT NULL DEFAULT 0',
      'reply_to_message_id': 'TEXT',
    });
  }

  static Future<void> _addOutboxColumns(
    DatabaseExecutor database,
    Map<String, String> additions,
  ) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'im_outbox'",
    );
    if (tables.isEmpty) return;
    final columns = (await database.rawQuery('PRAGMA table_info(im_outbox)'))
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    for (final entry in additions.entries) {
      if (!columns.contains(entry.key)) {
        await database.execute(
          'ALTER TABLE im_outbox ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }

  static Future<void> _createConversationDetailTables(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS im_conversation_members (
        account_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        id TEXT NOT NULL,
        username TEXT NOT NULL,
        display_name TEXT NOT NULL,
        is_online INTEGER NOT NULL,
        avatar_key TEXT NOT NULL,
        avatar_data_url TEXT NOT NULL,
        department_id TEXT NOT NULL,
        department_name TEXT NOT NULL,
        is_organization_manager INTEGER NOT NULL,
        is_friend INTEGER NOT NULL,
        can_start_direct INTEGER NOT NULL,
        position INTEGER NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (account_id, conversation_id, id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS ix_im_conversation_members_position
      ON im_conversation_members(account_id, conversation_id, position)
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS im_group_profiles (
        account_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        title TEXT NOT NULL,
        group_no TEXT NOT NULL,
        avatar_url TEXT NOT NULL,
        introduction TEXT NOT NULL,
        notice TEXT NOT NULL,
        max_member_count INTEGER NOT NULL,
        review_enabled INTEGER NOT NULL,
        view_members_enabled INTEGER NOT NULL,
        screenshot_enabled INTEGER NOT NULL,
        at_enabled INTEGER NOT NULL,
        identity_enabled INTEGER NOT NULL,
        muted INTEGER NOT NULL,
        status TEXT NOT NULL,
        server_updated_at TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (account_id, conversation_id)
      )
    ''');
  }

  Future<void> _protectLegacySensitivePayloads(Database database) async {
    const columns = <({String table, String column, List<String> keys})>[
      (
        table: 'im_conversations',
        column: 'preview',
        keys: ['account_id', 'id'],
      ),
      (table: 'im_messages', column: 'content', keys: ['account_id', 'id']),
      (
        table: 'im_messages',
        column: 'attachment_name',
        keys: ['account_id', 'id'],
      ),
      (
        table: 'im_messages',
        column: 'contact_card_json',
        keys: ['account_id', 'id'],
      ),
      (
        table: 'im_outbox',
        column: 'content',
        keys: ['account_id', 'client_message_id'],
      ),
      (
        table: 'im_outbox',
        column: 'attachment_name',
        keys: ['account_id', 'client_message_id'],
      ),
      (
        table: 'im_outbox',
        column: 'attachment_bytes_base64',
        keys: ['account_id', 'client_message_id'],
      ),
      (
        table: 'im_event_inbox',
        column: 'payload_json',
        keys: ['account_id', 'sequence'],
      ),
      (
        table: 'im_group_profiles',
        column: 'introduction',
        keys: ['account_id', 'conversation_id'],
      ),
      (
        table: 'im_group_profiles',
        column: 'notice',
        keys: ['account_id', 'conversation_id'],
      ),
    ];
    await database.transaction((transaction) async {
      for (final item in columns) {
        if (!await _tableExists(transaction, item.table)) continue;
        final rows = await transaction.query(
          item.table,
          columns: [...item.keys, item.column],
          where: '${item.column} <> ?',
          whereArgs: [''],
        );
        for (final row in rows) {
          final value = row[item.column]?.toString() ?? '';
          if (value.isEmpty || _cipher.isProtected(value)) continue;
          final accountId = row['account_id']?.toString() ?? '';
          if (accountId.isEmpty) continue;
          await transaction.update(
            item.table,
            {item.column: await _cipher.protect(accountId, value)},
            where: item.keys.map((key) => '$key = ?').join(' AND '),
            whereArgs: item.keys.map((key) => row[key]).toList(),
          );
        }
      }
    });
  }

  static Future<bool> _tableExists(
    DatabaseExecutor database,
    String table,
  ) async => (await database.rawQuery(
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
    [table],
  )).isNotEmpty;

  Future<ImBootstrap?> readBootstrap(String accountId) async {
    final database = await _database;
    final currentRows = await database.query(
      'im_members',
      where: 'account_id = ? AND is_current = 1',
      whereArgs: [accountId],
      limit: 1,
    );
    if (currentRows.isEmpty) return null;
    final contactRows = await database.query(
      'im_members',
      where: 'account_id = ? AND is_contact = 1',
      whereArgs: [accountId],
      orderBy: 'display_name COLLATE NOCASE',
    );
    final conversationRows = await database.query(
      'im_conversations',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'is_pinned DESC, updated_at DESC',
    );
    final permissions = _decodeStateMap(
      await _readState(accountId, 'bootstrap.permissions'),
    );
    final config = _decodeStateMap(
      await _readState(accountId, 'bootstrap.config'),
    );
    return ImBootstrap(
      currentMember: _memberFromRow(currentRows.single),
      contacts: contactRows.map(_memberFromRow).toList(),
      conversations: await Future.wait(
        conversationRows.map((row) => _conversationFromRow(accountId, row)),
      ),
      permissions: ImPermissionSnapshot.fromJson(permissions),
      config: ImClientConfig.fromJson(config),
    );
  }

  Future<void> replaceBootstrap(String accountId, ImBootstrap value) async {
    final database = await _database;
    await database.transaction((transaction) async {
      await _replaceBootstrap(transaction, accountId, value);
    });
  }

  Future<List<ImDepartment>> readDepartments(String accountId) async {
    final raw = await _readState(accountId, 'directory.departments');
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => ImDepartment.fromJson(item.cast<String, Object?>()))
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> writeDepartments(
    String accountId,
    List<ImDepartment> departments,
  ) async {
    final database = await _database;
    await _writeState(
      database,
      accountId,
      'directory.departments',
      jsonEncode(departments.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<ImMember>> readConversationMembers(
    String accountId,
    String conversationId,
  ) async {
    final database = await _database;
    final rows = await database.query(
      'im_conversation_members',
      where: 'account_id = ? AND conversation_id = ?',
      whereArgs: [accountId, conversationId],
      orderBy: 'position, display_name COLLATE NOCASE',
    );
    return rows.map(_conversationMemberFromRow).toList();
  }

  Future<void> replaceConversationMembers(
    String accountId,
    String conversationId,
    List<ImMember> members,
  ) async {
    final database = await _database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'im_conversation_members',
        where: 'account_id = ? AND conversation_id = ?',
        whereArgs: [accountId, conversationId],
      );
      for (var index = 0; index < members.length; index += 1) {
        final member = members[index];
        await transaction.insert('im_conversation_members', {
          'account_id': accountId,
          'conversation_id': conversationId,
          'id': member.id,
          'username': member.username,
          'display_name': member.displayName,
          'is_online': member.isOnline ? 1 : 0,
          'avatar_key': member.avatarKey,
          'avatar_data_url': member.avatarDataUrl,
          'department_id': member.departmentId,
          'department_name': member.departmentName,
          'is_organization_manager': member.isOrganizationManager ? 1 : 0,
          'is_friend': member.isFriend ? 1 : 0,
          'can_start_direct': member.canStartDirect ? 1 : 0,
          'position': index,
          'updated_at': _now(),
        });
      }
    });
  }

  Future<ImGroupProfile?> readGroupProfile(
    String accountId,
    String conversationId,
  ) async {
    final database = await _database;
    final rows = await database.query(
      'im_group_profiles',
      where: 'account_id = ? AND conversation_id = ?',
      whereArgs: [accountId, conversationId],
      limit: 1,
    );
    return rows.isEmpty ? null : _groupProfileFromRow(accountId, rows.single);
  }

  Future<void> writeGroupProfile(
    String accountId,
    ImGroupProfile profile,
  ) async {
    final database = await _database;
    await database.insert('im_group_profiles', {
      'account_id': accountId,
      'conversation_id': profile.conversationId,
      'title': profile.title,
      'group_no': profile.groupNo,
      'avatar_url': profile.avatarUrl,
      'introduction': await _cipher.protect(accountId, profile.introduction),
      'notice': await _cipher.protect(accountId, profile.notice),
      'max_member_count': profile.maxMemberCount,
      'review_enabled': profile.reviewEnabled ? 1 : 0,
      'view_members_enabled': profile.viewMembersEnabled ? 1 : 0,
      'screenshot_enabled': profile.screenshotEnabled ? 1 : 0,
      'at_enabled': profile.atEnabled ? 1 : 0,
      'identity_enabled': profile.identityEnabled ? 1 : 0,
      'muted': profile.muted ? 1 : 0,
      'status': profile.status,
      'server_updated_at': profile.updatedAt?.toUtc().toIso8601String(),
      'updated_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DateTime?> bootstrapUpdatedAt(String accountId) =>
      _readStateDate(accountId, 'bootstrap.updated_at');

  Future<List<ImMessage>> readMessages(
    String accountId,
    String conversationId,
  ) async {
    final database = await _database;
    final rows = await database.query(
      'im_messages',
      where: 'account_id = ? AND conversation_id = ? AND is_deleted = 0',
      whereArgs: [accountId, conversationId],
      orderBy: 'CASE WHEN sequence = 0 THEN 1 ELSE 0 END, sequence, created_at',
    );
    return Future.wait(rows.map((row) => _messageFromRow(accountId, row)));
  }

  Future<void> mergeMessages(
    String accountId,
    String conversationId,
    List<ImMessage> messages,
  ) async {
    final database = await _database;
    await database.transaction((transaction) async {
      for (final message in messages) {
        await _upsertMessage(transaction, accountId, message);
      }
      await _writeState(
        transaction,
        accountId,
        'messages.$conversationId.updated_at',
        _now(),
      );
    });
  }

  Future<void> clearConversationMessages(
    String accountId,
    String conversationId,
  ) async {
    final database = await _database;
    await database.delete(
      'im_messages',
      where: 'account_id = ? AND conversation_id = ?',
      whereArgs: [accountId, conversationId],
    );
  }

  Future<void> deleteMessage(String accountId, String messageId) async {
    final database = await _database;
    await database.delete(
      'im_messages',
      where: 'account_id = ? AND id = ?',
      whereArgs: [accountId, messageId],
    );
  }

  Future<ImMessage> enqueueText({
    required String accountId,
    required String senderId,
    required String conversationId,
    required String clientMessageId,
    required String content,
    List<String> mentionedMemberIds = const [],
    bool mentionAll = false,
    String? replyToMessageId,
    ImMessageReply? replyTo,
  }) async {
    final createdAt = DateTime.now();
    final message = ImMessage(
      id: 'local-$clientMessageId',
      conversationId: conversationId,
      sequence: 0,
      senderId: senderId,
      clientMessageId: clientMessageId,
      content: content,
      kind: 'text',
      createdAt: createdAt,
      mentions: mentionedMemberIds
          .map(
            (memberId) =>
                ImMessageMention(mentionedMemberId: memberId, displayName: ''),
          )
          .toList(growable: false),
      replyTo: replyTo,
      localStatus: ImLocalMessageStatus.pending,
    );
    final database = await _database;
    await database.transaction((transaction) async {
      await _upsertMessage(transaction, accountId, message);
      await transaction.insert('im_outbox', {
        'account_id': accountId,
        'client_message_id': clientMessageId,
        'conversation_id': conversationId,
        'content': await _cipher.protect(accountId, content),
        'kind': 'text',
        'mentioned_member_ids_json': jsonEncode(mentionedMemberIds),
        'mention_all': mentionAll ? 1 : 0,
        'reply_to_message_id': replyToMessageId,
        'attachment_name': '',
        'attachment_content_type': '',
        'attachment_bytes_base64': '',
        'contact_member_id': null,
        'attempts': 0,
        'next_retry_at': _now(),
        'last_error': '',
        'created_at': createdAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return message;
  }

  Future<ImMessage> enqueueAttachment({
    required String accountId,
    required String senderId,
    required String conversationId,
    required String clientMessageId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final createdAt = DateTime.now();
    final message = ImMessage(
      id: 'local-$clientMessageId',
      conversationId: conversationId,
      sequence: 0,
      senderId: senderId,
      clientMessageId: clientMessageId,
      content: '附件：$fileName',
      kind: 'file',
      attachmentName: fileName,
      attachmentSize: bytes.length,
      attachmentContentType: contentType,
      createdAt: createdAt,
      localStatus: ImLocalMessageStatus.pending,
    );
    final database = await _database;
    await database.transaction((transaction) async {
      await _upsertMessage(transaction, accountId, message);
      await transaction.insert('im_outbox', {
        'account_id': accountId,
        'client_message_id': clientMessageId,
        'conversation_id': conversationId,
        'content': await _cipher.protect(accountId, message.content),
        'kind': 'file',
        'mentioned_member_ids_json': '[]',
        'mention_all': 0,
        'reply_to_message_id': null,
        'attachment_name': await _cipher.protect(accountId, fileName),
        'attachment_content_type': contentType,
        'attachment_bytes_base64': await _cipher.protect(
          accountId,
          base64Encode(bytes),
        ),
        'contact_member_id': null,
        'attempts': 0,
        'next_retry_at': _now(),
        'last_error': '',
        'created_at': createdAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return message;
  }

  Future<ImMessage> enqueueContactCard({
    required String accountId,
    required String senderId,
    required String conversationId,
    required String clientMessageId,
    required String memberId,
  }) async {
    final createdAt = DateTime.now();
    final message = ImMessage(
      id: 'local-$clientMessageId',
      conversationId: conversationId,
      sequence: 0,
      senderId: senderId,
      clientMessageId: clientMessageId,
      content: '联系人名片',
      kind: 'contact',
      createdAt: createdAt,
      localStatus: ImLocalMessageStatus.pending,
    );
    final database = await _database;
    await database.transaction((transaction) async {
      await _upsertMessage(transaction, accountId, message);
      await transaction.insert('im_outbox', {
        'account_id': accountId,
        'client_message_id': clientMessageId,
        'conversation_id': conversationId,
        'content': await _cipher.protect(accountId, message.content),
        'kind': 'contact',
        'mentioned_member_ids_json': '[]',
        'mention_all': 0,
        'reply_to_message_id': null,
        'attachment_name': '',
        'attachment_content_type': '',
        'attachment_bytes_base64': '',
        'contact_member_id': memberId,
        'attempts': 0,
        'next_retry_at': _now(),
        'last_error': '',
        'created_at': createdAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return message;
  }

  Future<List<ImOutboxItem>> dueOutbox(String accountId) async {
    final database = await _database;
    final rows = await database.query(
      'im_outbox',
      where: 'account_id = ? AND next_retry_at <= ?',
      whereArgs: [accountId, _now()],
      orderBy: 'created_at',
      limit: 50,
    );
    return Future.wait(
      rows.map(
        (row) async => ImOutboxItem(
          clientMessageId: row['client_message_id'] as String,
          conversationId: row['conversation_id'] as String,
          content: await _cipher.reveal(accountId, row['content'] as String),
          kind: row['kind'] as String,
          attempts: row['attempts'] as int,
          mentionedMemberIds: _decodeStringList(
            await _cipher.reveal(
              accountId,
              row['mentioned_member_ids_json'] as String,
            ),
          ),
          mentionAll: (row['mention_all'] as int) != 0,
          replyToMessageId: row['reply_to_message_id'] as String?,
          attachmentName: await _cipher.reveal(
            accountId,
            row['attachment_name'] as String,
          ),
          attachmentContentType: row['attachment_content_type'] as String,
          attachmentBytes: _decodeBytes(
            await _cipher.reveal(
              accountId,
              row['attachment_bytes_base64'] as String,
            ),
          ),
          contactMemberId: row['contact_member_id'] as String?,
        ),
      ),
    );
  }

  Future<void> markOutboxSent(
    String accountId,
    String clientMessageId,
    ImMessage serverMessage,
  ) async {
    final database = await _database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'im_messages',
        where: 'account_id = ? AND client_message_id = ?',
        whereArgs: [accountId, clientMessageId],
      );
      await _upsertMessage(
        transaction,
        accountId,
        serverMessage.copyWith(
          localStatus: ImLocalMessageStatus.sent,
          lastError: '',
        ),
      );
      await transaction.delete(
        'im_outbox',
        where: 'account_id = ? AND client_message_id = ?',
        whereArgs: [accountId, clientMessageId],
      );
    });
  }

  Future<void> markOutboxFailed(
    String accountId,
    ImOutboxItem item,
    String error,
  ) async {
    final attempts = item.attempts + 1;
    final delay = Duration(seconds: 5 * (1 << attempts.clamp(0, 6)));
    final nextRetryAt = DateTime.now().add(delay).toUtc().toIso8601String();
    final database = await _database;
    await database.transaction((transaction) async {
      await transaction.update(
        'im_outbox',
        {
          'attempts': attempts,
          'next_retry_at': nextRetryAt,
          'last_error': error,
        },
        where: 'account_id = ? AND client_message_id = ?',
        whereArgs: [accountId, item.clientMessageId],
      );
      await transaction.update(
        'im_messages',
        {
          'local_status': ImLocalMessageStatus.failed.name,
          'last_error': error,
          'updated_at': _now(),
        },
        where: 'account_id = ? AND client_message_id = ?',
        whereArgs: [accountId, item.clientMessageId],
      );
    });
  }

  Future<void> retryOutboxNow(String accountId, String clientMessageId) async {
    final database = await _database;
    await database.transaction((transaction) async {
      await transaction.update(
        'im_outbox',
        {'next_retry_at': _now(), 'last_error': ''},
        where: 'account_id = ? AND client_message_id = ?',
        whereArgs: [accountId, clientMessageId],
      );
      await transaction.update(
        'im_messages',
        {
          'local_status': ImLocalMessageStatus.pending.name,
          'last_error': '',
          'updated_at': _now(),
        },
        where: 'account_id = ? AND client_message_id = ?',
        whereArgs: [accountId, clientMessageId],
      );
    });
  }

  Future<void> markConversationRead(
    String accountId,
    String conversationId,
  ) async {
    final database = await _database;
    await database.update(
      'im_conversations',
      {'unread_count': 0},
      where: 'account_id = ? AND id = ?',
      whereArgs: [accountId, conversationId],
    );
  }

  Future<int> lastEventSequence(String accountId) async {
    final value = await _readState(accountId, 'events.last_sequence');
    return int.tryParse(value ?? '') ?? 0;
  }

  Future<void> markEventsAcked(String accountId, int sequence) async {
    if (sequence <= 0) return;
    final database = await _database;
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'im_sync_state',
        columns: ['value'],
        where: 'account_id = ? AND state_key = ?',
        whereArgs: [accountId, 'events.last_sequence'],
        limit: 1,
      );
      final current = rows.isEmpty
          ? 0
          : int.tryParse(rows.single['value']?.toString() ?? '') ?? 0;
      final next = sequence > current ? sequence : current;
      await _writeState(
        transaction,
        accountId,
        'events.last_sequence',
        next.toString(),
      );
    });
  }

  Future<void> applySyncBatch({
    required String accountId,
    required List<ImSyncEvent> events,
    required ImBootstrap bootstrap,
  }) async {
    final database = await _database;
    await database.transaction((transaction) async {
      for (final event in events) {
        final inserted = await transaction.insert('im_event_inbox', {
          'account_id': accountId,
          'sequence': event.sequence,
          'event_id': event.id,
          'type': event.type,
          'payload_json': await _cipher.protect(accountId, event.payloadJson),
          'created_at': event.createdAt?.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (inserted > 0) {
          await _applyEvent(transaction, accountId, event);
        }
      }
      await _replaceBootstrap(transaction, accountId, bootstrap);
      await transaction.rawDelete(
        '''
        DELETE FROM im_event_inbox
        WHERE account_id = ? AND sequence < (
          SELECT COALESCE(MAX(sequence), 0) - 2000
          FROM im_event_inbox WHERE account_id = ?
        )
      ''',
        [accountId, accountId],
      );
    });
  }

  Future<void> _applyEvent(
    DatabaseExecutor executor,
    String accountId,
    ImSyncEvent event,
  ) async {
    Map<String, Object?> payload;
    try {
      payload = (jsonDecode(event.payloadJson) as Map).cast<String, Object?>();
    } catch (_) {
      return;
    }
    if (event.type == 'message.created') {
      await _upsertMessage(executor, accountId, ImMessage.fromJson(payload));
      return;
    }
    final messageId = _jsonText(payload, 'id');
    if (messageId.isEmpty) return;
    if (event.type == 'message.edited') {
      final rawDetail = payload['detail'] ?? payload['Detail'];
      final detail = rawDetail is Map
          ? rawDetail.cast<String, Object?>()
          : <String, Object?>{};
      await executor.update(
        'im_messages',
        {
          'content': await _cipher.protect(
            accountId,
            _jsonText(detail, 'newContent'),
          ),
          'updated_at': _now(),
        },
        where: 'account_id = ? AND id = ?',
        whereArgs: [accountId, messageId],
      );
    } else if (event.type == 'message.recalled') {
      await executor.update(
        'im_messages',
        {'recalled_at': _now(), 'updated_at': _now()},
        where: 'account_id = ? AND id = ?',
        whereArgs: [accountId, messageId],
      );
    } else if (event.type == 'message.deleted') {
      await executor.update(
        'im_messages',
        {'is_deleted': 1, 'updated_at': _now()},
        where: 'account_id = ? AND id = ?',
        whereArgs: [accountId, messageId],
      );
    }
  }

  Future<void> _replaceBootstrap(
    DatabaseExecutor executor,
    String accountId,
    ImBootstrap value,
  ) async {
    await executor.delete(
      'im_members',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    await executor.delete(
      'im_conversations',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    await _writeMember(executor, accountId, value.currentMember, true, false);
    for (final member in value.contacts) {
      await _writeMember(executor, accountId, member, false, true);
    }
    for (final conversation in value.conversations) {
      await executor.insert('im_conversations', {
        'account_id': accountId,
        'id': conversation.id,
        'type': conversation.type,
        'title': conversation.title,
        'preview': await _cipher.protect(accountId, conversation.preview),
        'updated_at': conversation.updatedAt?.toUtc().toIso8601String(),
        'unread_count': conversation.unreadCount,
        'last_message_sequence': conversation.lastMessageSequence,
        'is_pinned': conversation.isPinned ? 1 : 0,
        'is_muted': conversation.isMuted ? 1 : 0,
        'unread_mention_sequences_json': jsonEncode(
          conversation.unreadMentionSequences,
        ),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await _writeState(
      executor,
      accountId,
      'bootstrap.permissions',
      jsonEncode(value.permissions.toJson()),
    );
    await _writeState(
      executor,
      accountId,
      'bootstrap.config',
      jsonEncode(value.config.toJson()),
    );
    await _writeState(executor, accountId, 'bootstrap.updated_at', _now());
  }

  static Map<String, Object?> _decodeStateMap(String? value) {
    if (value == null || value.isEmpty) return const <String, Object?>{};
    try {
      return (jsonDecode(value) as Map).cast<String, Object?>();
    } on FormatException {
      return const <String, Object?>{};
    } on TypeError {
      return const <String, Object?>{};
    }
  }

  Future<void> _writeMember(
    DatabaseExecutor executor,
    String accountId,
    ImMember member,
    bool isCurrent,
    bool isContact,
  ) => executor.insert('im_members', {
    'account_id': accountId,
    'id': member.id,
    'username': member.username,
    'display_name': member.displayName,
    'is_online': member.isOnline ? 1 : 0,
    'avatar_key': member.avatarKey,
    'avatar_data_url': member.avatarDataUrl,
    'department_id': member.departmentId,
    'department_name': member.departmentName,
    'is_organization_manager': member.isOrganizationManager ? 1 : 0,
    'is_friend': member.isFriend ? 1 : 0,
    'can_start_direct': member.canStartDirect ? 1 : 0,
    'is_current': isCurrent ? 1 : 0,
    'is_contact': isContact ? 1 : 0,
    'updated_at': _now(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> _upsertMessage(
    DatabaseExecutor executor,
    String accountId,
    ImMessage message,
  ) async {
    if (message.clientMessageId.isNotEmpty) {
      await executor.delete(
        'im_messages',
        where: 'account_id = ? AND sender_id = ? AND client_message_id = ? AND id <> ?',
        whereArgs: [
          accountId,
          message.senderId,
          message.clientMessageId,
          message.id,
        ],
      );
    }
    await executor.insert('im_messages', {
      'account_id': accountId,
      'id': message.id,
      'conversation_id': message.conversationId,
      'sequence': message.sequence,
      'sender_id': message.senderId,
      'client_message_id': message.clientMessageId,
      'content': await _cipher.protect(accountId, message.content),
      'kind': message.kind,
      'attachment_name': await _cipher.protect(
        accountId,
        message.attachmentName,
      ),
      'attachment_size': message.attachmentSize,
      'attachment_content_type': message.attachmentContentType,
      'attachment_sha256': message.attachmentSha256,
      'contact_card_json': await _cipher.protect(
        accountId,
        message.contactCard == null
            ? ''
            : jsonEncode(message.contactCard!.toJson()),
      ),
      'images_json': await _cipher.protect(
        accountId,
        jsonEncode(message.images.map((item) => item.toJson()).toList()),
      ),
      'media_attachments_json': await _cipher.protect(
        accountId,
        jsonEncode(message.attachments.map((item) => item.toJson()).toList()),
      ),
      'created_at': message.createdAt?.toUtc().toIso8601String(),
      'recalled_at': message.recalledAt?.toUtc().toIso8601String(),
      'mentions_json': await _cipher.protect(
        accountId,
        jsonEncode(
          message.mentions
              .map(
                (item) => {
                  'mentionedMemberId': item.mentionedMemberId,
                  'displayName': item.displayName,
                  'isMentionAll': item.isMentionAll,
                },
              )
              .toList(),
        ),
      ),
      'reply_to_json': await _cipher.protect(
        accountId,
        message.replyTo == null
            ? ''
            : jsonEncode({
                'messageId': message.replyTo!.messageId,
                'senderId': message.replyTo!.senderId,
                'content': message.replyTo!.content,
                'kind': message.replyTo!.kind,
                'createdAt': message.replyTo!.createdAt
                    ?.toUtc()
                    .toIso8601String(),
                'recalledAt': message.replyTo!.recalledAt
                    ?.toUtc()
                    .toIso8601String(),
              }),
      ),
      'local_status': message.localStatus.name,
      'last_error': message.lastError,
      'is_deleted': 0,
      'updated_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> _readState(String accountId, String key) async {
    final database = await _database;
    final rows = await database.query(
      'im_sync_state',
      columns: ['value'],
      where: 'account_id = ? AND state_key = ?',
      whereArgs: [accountId, key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<DateTime?> _readStateDate(String accountId, String key) async {
    final value = await _readState(accountId, key);
    return value == null ? null : DateTime.tryParse(value)?.toLocal();
  }

  Future<void> _writeState(
    DatabaseExecutor executor,
    String accountId,
    String key,
    String value,
  ) => executor.insert('im_sync_state', {
    'account_id': accountId,
    'state_key': key,
    'value': value,
    'updated_at': _now(),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();

  static ImMember _memberFromRow(Map<String, Object?> row) => ImMember(
    id: row['id'] as String,
    username: row['username'] as String,
    displayName: row['display_name'] as String,
    isOnline: (row['is_online'] as int) != 0,
    avatarKey: row['avatar_key'] as String,
    avatarDataUrl: row['avatar_data_url'] as String,
    departmentId: row['department_id'] as String,
    departmentName: row['department_name'] as String,
    isOrganizationManager: (row['is_organization_manager'] as int) != 0,
    isFriend: (row['is_friend'] as int) != 0,
    canStartDirect: (row['can_start_direct'] as int) != 0,
  );

  static ImMember _conversationMemberFromRow(Map<String, Object?> row) =>
      ImMember(
        id: row['id'] as String,
        username: row['username'] as String,
        displayName: row['display_name'] as String,
        isOnline: (row['is_online'] as int) != 0,
        avatarKey: row['avatar_key'] as String,
        avatarDataUrl: row['avatar_data_url'] as String,
        departmentId: row['department_id'] as String,
        departmentName: row['department_name'] as String,
        isOrganizationManager: (row['is_organization_manager'] as int) != 0,
        isFriend: (row['is_friend'] as int) != 0,
        canStartDirect: (row['can_start_direct'] as int) != 0,
      );

  Future<ImGroupProfile> _groupProfileFromRow(
    String accountId,
    Map<String, Object?> row,
  ) async => ImGroupProfile(
    conversationId: row['conversation_id'] as String,
    title: row['title'] as String,
    groupNo: row['group_no'] as String,
    avatarUrl: row['avatar_url'] as String,
    introduction: await _cipher.reveal(
      accountId,
      row['introduction'] as String,
    ),
    notice: await _cipher.reveal(accountId, row['notice'] as String),
    maxMemberCount: row['max_member_count'] as int,
    reviewEnabled: (row['review_enabled'] as int) != 0,
    viewMembersEnabled: (row['view_members_enabled'] as int) != 0,
    screenshotEnabled: (row['screenshot_enabled'] as int) != 0,
    atEnabled: (row['at_enabled'] as int) != 0,
    identityEnabled: (row['identity_enabled'] as int) != 0,
    muted: (row['muted'] as int) != 0,
    status: row['status'] as String,
    updatedAt: DateTime.tryParse(row['server_updated_at']?.toString() ?? '')
        ?.toLocal(),
  );

  Future<ImConversation> _conversationFromRow(
    String accountId,
    Map<String, Object?> row,
  ) async => ImConversation(
    id: row['id'] as String,
    type: row['type'] as String,
    title: row['title'] as String,
    preview: await _cipher.reveal(accountId, row['preview'] as String),
    updatedAt: DateTime.tryParse(row['updated_at']?.toString() ?? '')
        ?.toLocal(),
    unreadCount: row['unread_count'] as int,
    lastMessageSequence: row['last_message_sequence'] as int,
    isPinned: (row['is_pinned'] as int) != 0,
    isMuted: (row['is_muted'] as int) != 0,
    unreadMentionSequences: _decodeIntegerList(
      row['unread_mention_sequences_json']?.toString() ?? '[]',
    ),
  );

  static List<int> _decodeIntegerList(String value) {
    try {
      return (jsonDecode(value) as List)
          .map((item) => int.tryParse(item.toString()) ?? 0)
          .where((item) => item > 0)
          .toList();
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<ImMessage> _messageFromRow(
    String accountId,
    Map<String, Object?> row,
  ) async => ImMessage(
    id: row['id'] as String,
    conversationId: row['conversation_id'] as String,
    sequence: row['sequence'] as int,
    senderId: row['sender_id'] as String,
    clientMessageId: row['client_message_id'] as String,
    content: await _cipher.reveal(accountId, row['content'] as String),
    kind: row['kind'] as String,
    attachmentName: await _cipher.reveal(
      accountId,
      row['attachment_name'] as String,
    ),
    attachmentSize: row['attachment_size'] as int?,
    attachmentContentType: row['attachment_content_type'] as String,
    attachmentSha256: row['attachment_sha256'] as String,
    contactCard: _decodeContactCard(
      await _cipher.reveal(accountId, row['contact_card_json'] as String),
    ),
    images: _decodeImages(
      await _cipher.reveal(accountId, row['images_json']?.toString() ?? ''),
    ),
    attachments: _decodeAttachments(
      await _cipher.reveal(
        accountId,
        row['media_attachments_json']?.toString() ?? '',
      ),
    ),
    createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')
        ?.toLocal(),
    recalledAt: DateTime.tryParse(row['recalled_at']?.toString() ?? '')
        ?.toLocal(),
    mentions: _decodeMentions(
      await _cipher.reveal(accountId, row['mentions_json'] as String),
    ),
    replyTo: _decodeReply(
      await _cipher.reveal(accountId, row['reply_to_json'] as String),
    ),
    localStatus: ImLocalMessageStatus.values.byName(
      row['local_status'] as String,
    ),
    lastError: row['last_error'] as String,
  );

  static List<ImMessageImage> _decodeImages(String value) {
    if (value.isEmpty) return const [];
    try {
      return (jsonDecode(value) as List)
          .whereType<Map>()
          .map((item) => ImMessageImage.fromJson(item.cast<String, Object?>()))
          .toList();
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  static List<ImMessageAttachment> _decodeAttachments(String value) {
    if (value.isEmpty) return const [];
    try {
      return (jsonDecode(value) as List)
          .whereType<Map>()
          .map(
            (item) =>
                ImMessageAttachment.fromJson(item.cast<String, Object?>()),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _jsonText(Map<String, Object?> json, String key) =>
      (json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'])
          ?.toString() ??
      '';

  static ImContactCard? _decodeContactCard(String value) {
    if (value.isEmpty) return null;
    try {
      return ImContactCard.fromJson(
        (jsonDecode(value) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  static List<String> _decodeStringList(String value) {
    if (value.isEmpty) return const [];
    try {
      final json = jsonDecode(value);
      return json is List
          ? json.map((item) => item.toString()).toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  static List<int> _decodeBytes(String value) {
    if (value.isEmpty) return const <int>[];
    try {
      return base64Decode(value);
    } on FormatException {
      return const <int>[];
    }
  }

  static List<ImMessageMention> _decodeMentions(String value) {
    if (value.isEmpty) return const [];
    try {
      final json = jsonDecode(value);
      return json is List
          ? json
                .whereType<Map>()
                .map(
                  (item) =>
                      ImMessageMention.fromJson(item.cast<String, Object?>()),
                )
                .toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  static ImMessageReply? _decodeReply(String value) {
    if (value.isEmpty) return null;
    try {
      final json = jsonDecode(value);
      return json is Map
          ? ImMessageReply.fromJson(json.cast<String, Object?>())
          : null;
    } catch (_) {
      return null;
    }
  }
}
