import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/storage/im_cache_cipher.dart';
import '../domain/collaboration_models.dart';
import '../domain/im_event_semantics.dart';
import 'im_message_query.dart';
import 'im_decoded_message_cache.dart';
import 'im_outbox_file_store.dart';

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
    this.mediaFiles = const <ImOutboxStoredFile>[],
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
  final List<ImOutboxStoredFile> mediaFiles;
  final String? contactMemberId;
}

final class ImLocalStore {
  ImLocalStore({
    DatabaseFactory? factory,
    Future<String> Function()? pathResolver,
    ImCacheCipher cipher = const PlainImCacheCipher(),
    DateTime Function()? clock,
    ImDecodedMessageCache? decodedMessageCache,
    void Function(int rows, int cacheHits, int durationMicros)? onMessageRead,
  }) : this.withOptions(
         factory ?? databaseFactory,
         pathResolver ?? _defaultPath,
         cipher,
         clock: clock,
         decodedMessageCache: decodedMessageCache,
         onMessageRead: onMessageRead,
       );

  ImLocalStore.withOptions(
    this._factory,
    this._pathResolver,
    this._cipher, {
    DateTime Function()? clock,
    ImDecodedMessageCache? decodedMessageCache,
    this._onMessageRead,
  }) : _clock = clock ?? DateTime.now,
       _decodedMessages = decodedMessageCache ?? ImDecodedMessageCache();

  final DatabaseFactory _factory;
  final Future<String> Function() _pathResolver;
  final ImCacheCipher _cipher;
  final DateTime Function() _clock;
  final ImDecodedMessageCache _decodedMessages;
  final void Function(int rows, int cacheHits, int durationMicros)?
  _onMessageRead;
  Future<Database>? _opening;

  static Future<String> _defaultPath() async => path.join(
    await getDatabasesPath(),
    AppEnvironment.databaseFileName('im'),
  );

  Future<Database> get _database => _opening ??= _open();

  Future<Database> _open() async {
    final database = await _factory.openDatabase(
      await _pathResolver(),
      options: OpenDatabaseOptions(
        version: 15,
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
            last_seen_at TEXT,
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
            last_read_sequence INTEGER NOT NULL DEFAULT 0,
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
            media_files_json TEXT NOT NULL DEFAULT '[]',
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
          await database.execute(ImMessageQuery.createWindowIndex);
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
          if (oldVersion < 10) {
            await _addGroupProfileCurrentUserRoleColumn(database);
          }
          if (oldVersion < 11) {
            await _addConversationReadSequenceColumn(database);
          }
          if (oldVersion < 12) {
            await _addOutboxMediaFilesColumn(database);
          }
          if (oldVersion < 13) {
            await _normalizeOutboxTimestamps(database);
          }
          if (oldVersion < 14) {
            await _addMemberLastSeenColumns(database);
          }
          if (oldVersion < 15) {
            // Preserve the sequence index: adjacent-history queries also need
            // deletion tombstones, while the latest window excludes them.
            await database.execute(ImMessageQuery.createWindowIndex);
          }
        },
      ),
    );
    if (_cipher.isEnabled) {
      await _protectLegacySensitivePayloads(database);
    }
    return database;
  }

  static Future<void> _addMemberLastSeenColumns(
    DatabaseExecutor database,
  ) async {
    for (final table in ['im_members', 'im_conversation_members']) {
      final columns = await database.rawQuery('PRAGMA table_info($table)');
      if (columns.isNotEmpty &&
          !columns.any((row) => row['name'] == 'last_seen_at')) {
        await database.execute(
          'ALTER TABLE $table ADD COLUMN last_seen_at TEXT',
        );
      }
    }
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

  static Future<void> _addConversationReadSequenceColumn(
    DatabaseExecutor database,
  ) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'im_conversations'",
    );
    if (tables.isEmpty) return;
    final columns = (await database.rawQuery(
      'PRAGMA table_info(im_conversations)',
    )).map((row) => row['name']?.toString() ?? '').toSet();
    if (!columns.contains('last_read_sequence')) {
      await database.execute(
        'ALTER TABLE im_conversations ADD COLUMN last_read_sequence INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  static Future<void> _addGroupProfileCurrentUserRoleColumn(
    DatabaseExecutor database,
  ) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'im_group_profiles'",
    );
    if (tables.isEmpty) return;
    final columns = (await database.rawQuery(
      'PRAGMA table_info(im_group_profiles)',
    )).map((row) => row['name']?.toString() ?? '').toSet();
    if (!columns.contains('current_user_role')) {
      await database.execute(
        "ALTER TABLE im_group_profiles ADD COLUMN current_user_role TEXT NOT NULL DEFAULT ''",
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

  static Future<void> _addOutboxMediaFilesColumn(
    DatabaseExecutor database,
  ) async {
    await _addOutboxColumns(database, {
      'media_files_json': "TEXT NOT NULL DEFAULT '[]'",
    });
  }

  static Future<void> _normalizeOutboxTimestamps(
    DatabaseExecutor database,
  ) async {
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'im_outbox'",
    );
    if (tables.isEmpty) return;
    // Runs in the schema-upgrade transaction. Read only scheduling metadata;
    // never decrypt/recreate payloads or change stable client message IDs.
    final rows = await database.query(
      'im_outbox',
      columns: [
        'account_id',
        'client_message_id',
        'created_at',
        'next_retry_at',
      ],
    );
    for (final row in rows) {
      final values = <String, Object?>{};
      for (final column in ['created_at', 'next_retry_at']) {
        final parsed = DateTime.tryParse(row[column]?.toString() ?? '');
        if (parsed != null) {
          final normalized = _sortableOutboxTimestamp(parsed);
          if (normalized != row[column]) values[column] = normalized;
        }
      }
      if (values.isEmpty) continue;
      await database.update(
        'im_outbox',
        values,
        where: 'account_id = ? AND client_message_id = ?',
        whereArgs: [row['account_id'], row['client_message_id']],
      );
    }
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
        last_seen_at TEXT,
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
        current_user_role TEXT NOT NULL DEFAULT '',
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
        table: 'im_outbox',
        column: 'media_files_json',
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

  Future<String?> readCurrentMemberId(String accountId) =>
      _readState(accountId, 'bootstrap.current_member_id');

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
    // Join only the newest queued message per conversation. Do not load media
    // bytes or rewrite the server summary/read cursors for an unconfirmed send.
    final conversationRows = await database.rawQuery(
      '''
      SELECT c.*, m.kind AS local_preview_kind,
             m.content AS local_preview_content,
             m.attachment_name AS local_preview_file_name,
             m.created_at AS local_preview_created_at,
             m.local_status AS local_preview_status,
             o.rowid AS local_preview_order, s.value AS local_confirmed_order
      FROM im_conversations c
      LEFT JOIN (
        SELECT conversation_id, MAX(rowid) AS newest_row
        FROM im_outbox WHERE account_id = ? GROUP BY conversation_id
      ) newest ON newest.conversation_id = c.id
      LEFT JOIN im_outbox o ON o.rowid = newest.newest_row
      LEFT JOIN im_messages m
        ON m.account_id = c.account_id AND m.conversation_id = c.id
       AND m.client_message_id = o.client_message_id
       AND m.sequence = 0 AND m.local_status IN ('pending', 'failed')
      LEFT JOIN im_sync_state s ON s.account_id = c.account_id
       AND s.state_key = 'preview.confirmed_order.' || c.id
      WHERE c.account_id = ?
    ''',
      [accountId, accountId],
    );
    final conversations = await Future.wait(
      conversationRows.map((row) => _conversationFromRow(accountId, row)),
    );
    conversations.sort((left, right) {
      if (left.isPinned != right.isPinned) return left.isPinned ? -1 : 1;
      final byTime = (right.updatedAt ?? DateTime(0)).compareTo(
        left.updatedAt ?? DateTime(0),
      );
      return byTime != 0 ? byTime : left.id.compareTo(right.id);
    });
    final permissions = _decodeStateMap(
      await _readState(accountId, 'bootstrap.permissions'),
    );
    final config = _decodeStateMap(
      await _readState(accountId, 'bootstrap.config'),
    );
    return ImBootstrap(
      currentMember: _memberFromRow(currentRows.single),
      contacts: contactRows.map(_memberFromRow).toList(),
      conversations: conversations,
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

  /// A lightweight list may be partial. Merge its entries; absence is not a
  /// deletion event. Directory, permissions and message bodies remain intact.
  Future<bool> mergeConversationIndex(
    String accountId,
    List<ImConversation> values,
  ) async {
    final database = await _database;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'im_conversations',
        where: 'account_id = ?',
        whereArgs: [accountId],
      );
      final current = {for (final row in rows) row['id']: row};
      final changed = <ImConversation>[];
      for (final value in values) {
        final previous = current[value.id];
        if (previous != null &&
            ((previous['last_message_sequence'] as int) >
                    value.lastMessageSequence ||
                (previous['last_read_sequence'] as int) >
                    value.lastReadSequence)) {
          // A response started before a newer send/read must not undo it.
          continue;
        }
        final data = <String, Object?>{
          'id': value.id,
          'type': value.type,
          'title': value.title,
          'preview': value.preview,
          'updated_at': value.updatedAt?.toUtc().toIso8601String(),
          'unread_count': value.unreadCount,
          'last_message_sequence': value.lastMessageSequence,
          'last_read_sequence': value.lastReadSequence,
          'is_pinned': value.isPinned ? 1 : 0,
          'is_muted': value.isMuted ? 1 : 0,
          'unread_mention_sequences_json': jsonEncode(
            value.unreadMentionSequences,
          ),
        };
        final previousPlain = previous == null
            ? null
            : <String, Object?>{
                ...previous,
                'preview': await _cipher.reveal(
                  accountId,
                  previous['preview'] as String,
                ),
              };
        if (previousPlain != null &&
            data.entries.every(
              (entry) => previousPlain[entry.key] == entry.value,
            )) {
          continue;
        }
        await transaction.insert('im_conversations', {
          ...data,
          'account_id': accountId,
          'preview': await _cipher.protect(accountId, value.preview),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        changed.add(value);
      }
      if (changed.isNotEmpty) {
        await _prepareHistoryCatchups(transaction, accountId, changed);
      }
      return changed.isNotEmpty;
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
          'last_seen_at': member.lastSeenAt?.toUtc().toIso8601String(),
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

  Future<void> mergeConversationMembers(
    String accountId,
    String conversationId,
    List<ImMember> members, {
    int positionOffset = 0,
  }) async {
    if (members.isEmpty) return;
    final database = await _database;
    await database.transaction((transaction) async {
      for (var index = 0; index < members.length; index += 1) {
        final member = members[index];
        await transaction.insert('im_conversation_members', {
          'account_id': accountId,
          'conversation_id': conversationId,
          'id': member.id,
          'username': member.username,
          'display_name': member.displayName,
          'is_online': member.isOnline ? 1 : 0,
          'last_seen_at': member.lastSeenAt?.toUtc().toIso8601String(),
          'avatar_key': member.avatarKey,
          'avatar_data_url': member.avatarDataUrl,
          'department_id': member.departmentId,
          'department_name': member.departmentName,
          'is_organization_manager': member.isOrganizationManager ? 1 : 0,
          'is_friend': member.isFriend ? 1 : 0,
          'can_start_direct': member.canStartDirect ? 1 : 0,
          'position': positionOffset + index,
          'updated_at': _now(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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
      'current_user_role': profile.currentUserRole,
      'server_updated_at': profile.updatedAt?.toUtc().toIso8601String(),
      'updated_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DateTime?> bootstrapUpdatedAt(String accountId) =>
      _readStateDate(accountId, 'bootstrap.updated_at');

  // Receipt projection stays account/conversation scoped in SQLite. The
  // indexed state lookups avoid one HTTP request per rendered message and
  // retain evidence even when a read event precedes the message itself.
  static const _messageReceiptColumns = ImMessageQuery.columns;

  Future<void> recordMessageReadReceipt(
    String accountId,
    ImMessageReadReceipt receipt,
  ) async {
    if (receipt.conversationId.isEmpty ||
        receipt.messageId.isEmpty ||
        receipt.sequence <= 0 ||
        !(receipt.peerRead || receipt.readCount > 0)) {
      return;
    }
    final database = await _database;
    await _writeState(
      database,
      accountId,
      'message.read.${receipt.conversationId}.${receipt.messageId}',
      '1',
    );
  }

  Future<List<ImMessage>> readMessages(
    String accountId,
    String conversationId, {
    int? limit,
    int? beforeSequence,
  }) async {
    final generation = _decodedMessages.generation;
    final watch = _onMessageRead == null ? null : (Stopwatch()..start());
    final database = await _database;
    final rows = await database.query(
      'im_messages',
      columns: _messageReceiptColumns,
      where: beforeSequence == null
          ? ImMessageQuery.visibleWhere
          : '${ImMessageQuery.visibleWhere} AND sequence > 0 AND sequence < ?',
      whereArgs: [accountId, conversationId, ?beforeSequence],
      orderBy: limit == null
          ? ImMessageQuery.oldestFirst
          : ImMessageQuery.newestFirst,
      limit: limit,
    );
    var hits = 0;
    final messages = await Future.wait(
      rows.map(
        (row) => _decodedMessages.read(
          accountId,
          row,
          generation: generation,
          decode: () => _messageFromRow(accountId, row),
          onReuse: () => hits++,
        ),
      ),
    );
    if (limit != null) {
      messages.sort((left, right) {
        if (left.sequence == 0 && right.sequence != 0) return 1;
        if (left.sequence != 0 && right.sequence == 0) return -1;
        final sequence = left.sequence.compareTo(right.sequence);
        if (sequence != 0) return sequence;
        return (left.createdAt ?? DateTime(0)).compareTo(
          right.createdAt ?? DateTime(0),
        );
      });
    }
    if (watch != null) {
      _onMessageRead?.call(rows.length, hits, watch.elapsedMicroseconds);
    }
    return messages;
  }

  /// Reads only the cached sequence run directly preceding the visible window.
  /// A cache can have holes after a cold start or missed event. Never jump over
  /// such a hole just because older rows happen to exist locally.
  Future<List<ImMessage>> readAdjacentOlderMessages(
    String accountId,
    String conversationId, {
    required int beforeSequence,
    int limit = 80,
  }) async {
    if (beforeSequence <= 1 || limit <= 0) return const [];
    final generation = _decodedMessages.generation;
    final watch = _onMessageRead == null ? null : (Stopwatch()..start());
    final database = await _database;
    final rows = await database.query(
      'im_messages',
      columns: _messageReceiptColumns,
      where:
          'account_id = ? AND conversation_id = ? '
          'AND sequence > 0 AND sequence < ?',
      whereArgs: [accountId, conversationId, beforeSequence],
      orderBy: 'sequence DESC',
      limit: limit.clamp(1, 80),
    );
    var expected = beforeSequence - 1;
    final adjacent = <Map<String, Object?>>[];
    for (final row in rows) {
      if (row['sequence'] as int != expected) break;
      expected--;
      // Retained deletion tombstones prove continuity, but are not rendered.
      if (row['is_deleted'] as int == 0) adjacent.add(row);
    }
    var hits = 0;
    final messages = await Future.wait(
      adjacent.reversed.map(
        (row) => _decodedMessages.read(
          accountId,
          row,
          generation: generation,
          decode: () => _messageFromRow(accountId, row),
          onReuse: () => hits++,
        ),
      ),
    );
    if (watch != null) {
      _onMessageRead?.call(adjacent.length, hits, watch.elapsedMicroseconds);
    }
    return messages;
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

  /// Durable history repair jobs are separate from event ACK/read cursors.
  Future<List<ImHistoryCatchup>> pendingHistoryCatchups(
    String accountId,
  ) async {
    final database = await _database;
    final rows = await database.rawQuery(
      '''
      SELECT s.state_key, s.value FROM im_sync_state s
      JOIN im_conversations c ON c.account_id = s.account_id
        AND s.state_key = 'history.catchup.' || c.id
      WHERE s.account_id = ? ORDER BY s.updated_at, s.state_key
    ''',
      [accountId],
    );
    return rows
        .map(
          (row) => ImHistoryCatchup.fromJson(
            row['state_key'].toString().substring('history.catchup.'.length),
            _decodeStateMap(row['value'] as String?),
          ),
        )
        .where(
          (job) =>
              job.conversationId.isNotEmpty &&
              job.afterSequence >= 0 &&
              job.beforeSequence > job.afterSequence &&
              job.targetSequence >= job.afterSequence,
        )
        .toList();
  }

  Future<bool> historyCatchupAlreadyCached(
    String accountId,
    ImHistoryCatchup job,
  ) async {
    final database = await _database;
    final rows = await database.rawQuery(
      '''
      SELECT COUNT(DISTINCT sequence) AS total FROM im_messages
      WHERE account_id = ? AND conversation_id = ? AND sequence > ? AND sequence < ?
    ''',
      [accountId, job.conversationId, job.afterSequence, job.beforeSequence],
    );
    return rows.single['total'] == job.beforeSequence - job.afterSequence - 1;
  }

  Future<bool> commitHistoryCatchupPage(
    String accountId,
    ImHistoryCatchup job,
    List<ImMessage> messages, {
    required int nextBeforeSequence,
    required bool complete,
  }) async {
    final database = await _database;
    return database.transaction((transaction) async {
      final key = 'history.catchup.${job.conversationId}';
      final current = await _readStateFromExecutor(transaction, accountId, key);
      if (current != jsonEncode(job.toJson())) {
        return false;
      }
      for (final message in messages) {
        await _upsertMessage(transaction, accountId, message);
      }
      if (complete) {
        await _writeState(
          transaction,
          accountId,
          'history.coverage.${job.conversationId}',
          job.targetSequence.toString(),
        );
        await transaction.delete(
          'im_sync_state',
          where: 'account_id = ? AND state_key = ?',
          whereArgs: [accountId, key],
        );
        final rows = await transaction.query(
          'im_conversations',
          columns: ['last_message_sequence'],
          where: 'account_id = ? AND id = ?',
          whereArgs: [accountId, job.conversationId],
        );
        final latest = rows.isEmpty
            ? 0
            : rows.single['last_message_sequence'] as int;
        if (latest > job.targetSequence) {
          await _writeState(
            transaction,
            accountId,
            key,
            jsonEncode(
              ImHistoryCatchup(
                conversationId: job.conversationId,
                afterSequence: job.targetSequence,
                targetSequence: latest,
                beforeSequence: latest + 1,
              ).toJson(),
            ),
          );
        }
      } else {
        await _writeState(
          transaction,
          accountId,
          key,
          jsonEncode(
            ImHistoryCatchup(
              conversationId: job.conversationId,
              afterSequence: job.afterSequence,
              targetSequence: job.targetSequence,
              beforeSequence: nextBeforeSequence,
            ).toJson(),
          ),
        );
      }
      return true;
    });
  }

  Future<void> _prepareHistoryCatchups(
    DatabaseExecutor executor,
    String accountId,
    List<ImConversation> conversations,
  ) async {
    final maxima = await executor.rawQuery(
      '''
      SELECT conversation_id, MAX(sequence) AS latest FROM im_messages
      WHERE account_id = ? GROUP BY conversation_id
    ''',
      [accountId],
    );
    final localMax = {
      for (final row in maxima) row['conversation_id']: row['latest'] as int,
    };
    final states = await executor.query(
      'im_sync_state',
      columns: ['state_key', 'value'],
      where: 'account_id = ? AND state_key LIKE ?',
      whereArgs: [accountId, 'history.%'],
    );
    final state = {
      for (final row in states) row['state_key']: row['value'].toString(),
    };
    for (final conversation in conversations) {
      if (!conversation.isSupported || conversation.lastMessageSequence <= 0) {
        continue;
      }
      final id = conversation.id;
      final coverageKey = 'history.coverage.$id';
      var coverage = int.tryParse(state[coverageKey] ?? '');
      if (coverage == null) {
        // Bootstrap a new installation with its latest window; older history
        // remains available through paging. Existing caches resume at their tip.
        final cached = localMax[id] ?? 0;
        coverage = cached > 0
            ? cached
            : (conversation.lastMessageSequence - 50).clamp(
                0,
                conversation.lastMessageSequence,
              );
        await _writeState(
          executor,
          accountId,
          coverageKey,
          coverage.toString(),
        );
      }
      final jobKey = 'history.catchup.$id';
      if (state.containsKey(jobKey) ||
          coverage >= conversation.lastMessageSequence) {
        continue;
      }
      final job = ImHistoryCatchup(
        conversationId: id,
        afterSequence: coverage,
        targetSequence: conversation.lastMessageSequence,
        beforeSequence: conversation.lastMessageSequence + 1,
      );
      await _writeState(executor, accountId, jobKey, jsonEncode(job.toJson()));
    }
  }

  Future<void> clearConversationMessages(
    String accountId,
    String conversationId,
  ) async {
    final database = await _database;
    await database.transaction((transaction) async {
      await transaction.delete(
        'im_messages',
        where: 'account_id = ? AND conversation_id = ?',
        whereArgs: [accountId, conversationId],
      );
      await transaction.delete(
        'im_sync_state',
        where: 'account_id = ? AND state_key IN (?, ?)',
        whereArgs: [
          accountId,
          'history.catchup.$conversationId',
          'history.coverage.$conversationId',
        ],
      );
    });
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
    final createdAt = _clock();
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
        'next_retry_at': _outboxNow(),
        'last_error': '',
        'created_at': _sortableOutboxTimestamp(createdAt),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return message;
  }

  Future<ImMessage> enqueueAttachment({
    required String accountId,
    required String senderId,
    required String conversationId,
    required String clientMessageId,
    required ImOutboxStoredFile file,
  }) async {
    if (file.role != 'file') {
      throw ArgumentError('Queued attachment role is invalid.');
    }
    final createdAt = _clock();
    final message = ImMessage(
      id: 'local-$clientMessageId',
      conversationId: conversationId,
      sequence: 0,
      senderId: senderId,
      clientMessageId: clientMessageId,
      content: '附件：${file.fileName}',
      kind: 'file',
      attachmentName: file.fileName,
      attachmentSize: file.length,
      attachmentContentType: file.contentType,
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
        'attachment_name': await _cipher.protect(accountId, file.fileName),
        'attachment_content_type': file.contentType,
        'attachment_bytes_base64': '',
        'media_files_json': await _cipher.protect(
          accountId,
          jsonEncode([file.toJson()]),
        ),
        'contact_member_id': null,
        'attempts': 0,
        'next_retry_at': _outboxNow(),
        'last_error': '',
        'created_at': _sortableOutboxTimestamp(createdAt),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return message;
  }

  Future<ImMessage> enqueueImages({
    required String accountId,
    required String senderId,
    required String conversationId,
    required String clientMessageId,
    required List<ImOutboxStoredFile> files,
    String caption = '',
  }) async {
    if (files.isEmpty) throw ArgumentError('At least one image is required.');
    final createdAt = _clock();
    final images = files
        .map(
          (file) => ImMessageImage(
            id: imOutboxSyntheticFileId(clientMessageId, file.token),
            fileName: file.fileName,
            size: file.length,
            contentType: file.contentType,
            sha256: file.sha256,
          ),
        )
        .toList(growable: false);
    final message = ImMessage(
      id: 'local-$clientMessageId',
      conversationId: conversationId,
      sequence: 0,
      senderId: senderId,
      clientMessageId: clientMessageId,
      content: caption.trim(),
      kind: 'image',
      images: images,
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
        'kind': 'image',
        'mentioned_member_ids_json': '[]',
        'mention_all': 0,
        'reply_to_message_id': null,
        'attachment_name': '',
        'attachment_content_type': '',
        'attachment_bytes_base64': '',
        'media_files_json': await _cipher.protect(
          accountId,
          jsonEncode(files.map((file) => file.toJson()).toList()),
        ),
        'contact_member_id': null,
        'attempts': 0,
        'next_retry_at': _outboxNow(),
        'last_error': '',
        'created_at': _sortableOutboxTimestamp(createdAt),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return message;
  }

  Future<ImMessage> enqueueMedia({
    required String accountId,
    required String senderId,
    required String conversationId,
    required String clientMessageId,
    required String kind,
    required ImOutboxStoredFile mediaFile,
    ImOutboxStoredFile? coverFile,
    String caption = '',
  }) async {
    if (!const {'video', 'audio'}.contains(kind)) {
      throw ArgumentError('Queued media kind is invalid.');
    }
    final createdAt = _clock();
    final attachment = ImMessageAttachment(
      id: imOutboxSyntheticFileId(clientMessageId, mediaFile.token),
      type: kind,
      fileName: mediaFile.fileName,
      contentType: mediaFile.contentType,
      size: mediaFile.length,
      sha256: mediaFile.sha256,
      width: mediaFile.width,
      height: mediaFile.height,
      coverObjectId: coverFile == null
          ? ''
          : imOutboxSyntheticFileId(clientMessageId, coverFile.token),
      coverContentType: coverFile?.contentType ?? '',
      coverSize: coverFile?.length,
      coverSha256: coverFile?.sha256 ?? '',
      coverWidth: coverFile?.width,
      coverHeight: coverFile?.height,
    );
    final message = ImMessage(
      id: 'local-$clientMessageId',
      conversationId: conversationId,
      sequence: 0,
      senderId: senderId,
      clientMessageId: clientMessageId,
      content: caption.trim(),
      kind: kind,
      attachments: [attachment],
      createdAt: createdAt,
      localStatus: ImLocalMessageStatus.pending,
    );
    final files = [mediaFile, ?coverFile];
    final database = await _database;
    await database.transaction((transaction) async {
      await _upsertMessage(transaction, accountId, message);
      await transaction.insert('im_outbox', {
        'account_id': accountId,
        'client_message_id': clientMessageId,
        'conversation_id': conversationId,
        'content': await _cipher.protect(accountId, message.content),
        'kind': kind,
        'mentioned_member_ids_json': '[]',
        'mention_all': 0,
        'reply_to_message_id': null,
        'attachment_name': '',
        'attachment_content_type': '',
        'attachment_bytes_base64': '',
        'media_files_json': await _cipher.protect(
          accountId,
          jsonEncode(files.map((file) => file.toJson()).toList()),
        ),
        'contact_member_id': null,
        'attempts': 0,
        'next_retry_at': _outboxNow(),
        'last_error': '',
        'created_at': _sortableOutboxTimestamp(createdAt),
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
    final createdAt = _clock();
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
        'next_retry_at': _outboxNow(),
        'last_error': '',
        'created_at': _sortableOutboxTimestamp(createdAt),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
    return message;
  }

  Future<List<ImOutboxItem>> dueOutbox(String accountId) async {
    final database = await _database;
    final now = _outboxNow();
    // Ordering belongs to a conversation, not the whole account. Apply the
    // eligibility filter before LIMIT so a long blocked chat cannot starve
    // another chat. A later retry never overtakes its own earlier pending item.
    final dueRows = await database.rawQuery(
      '''
      SELECT queued.* FROM im_outbox AS queued
      WHERE queued.account_id = ? AND queued.next_retry_at <= ?
        AND NOT EXISTS (
          SELECT 1 FROM im_outbox AS earlier
          WHERE earlier.account_id = queued.account_id
            AND earlier.conversation_id = queued.conversation_id
            AND earlier.next_retry_at > ?
            AND (earlier.created_at < queued.created_at OR
              (earlier.created_at = queued.created_at AND earlier.rowid < queued.rowid))
        )
      ORDER BY queued.created_at, queued.rowid LIMIT 50
    ''',
      [accountId, now, now],
    );
    return Future.wait(
      dueRows.map((row) => _outboxItemFromRow(accountId, row)),
    );
  }

  Future<ImOutboxItem?> outboxItem(
    String accountId,
    String clientMessageId,
  ) async {
    final database = await _database;
    final rows = await database.query(
      'im_outbox',
      where: 'account_id = ? AND client_message_id = ?',
      whereArgs: [accountId, clientMessageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _outboxItemFromRow(accountId, rows.single);
  }

  Future<ImOutboxItem> _outboxItemFromRow(
    String accountId,
    Map<String, Object?> row,
  ) async {
    final mediaJson = await _cipher.reveal(
      accountId,
      row['media_files_json']?.toString() ?? '',
    );
    return ImOutboxItem(
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
      mediaFiles: _decodeOutboxFiles(mediaJson),
      contactMemberId: row['contact_member_id'] as String?,
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
      // The send response is authoritative even if this device never receives
      // its own message.created event. Commit the list projection with the
      // message/outbox transaction, without marking unseen messages as read.
      if (serverMessage.sequence > 0 &&
          serverMessage.conversationId.isNotEmpty) {
        final preview = switch (serverMessage.kind) {
          'image' => '[图片]',
          'video' => '[视频]',
          'audio' => '[语音]',
          'file' => '[文件] ${serverMessage.attachmentName}'.trim(),
          'contact' => '[名片]',
          _ => serverMessage.content,
        };
        await transaction.update(
          'im_conversations',
          {
            'preview': await _cipher.protect(accountId, preview),
            'last_message_sequence': serverMessage.sequence,
            if (serverMessage.createdAt != null)
              'updated_at': serverMessage.createdAt!.toUtc().toIso8601String(),
          },
          where: 'account_id = ? AND id = ? AND last_message_sequence < ?',
          whereArgs: [
            accountId,
            serverMessage.conversationId,
            serverMessage.sequence,
          ],
        );
      }
      await transaction.delete(
        'im_outbox',
        where: 'account_id = ? AND client_message_id = ?',
        whereArgs: [accountId, clientMessageId],
      );
      final remaining = await transaction.query(
        'im_outbox',
        columns: ['client_message_id'],
        where: 'account_id = ? AND conversation_id = ?',
        whereArgs: [accountId, serverMessage.conversationId],
        limit: 1,
      );
      if (remaining.isEmpty) {
        // SQLite may reuse rowids after a queue empties. An old batch's order
        // must never affect a later independent batch.
        await transaction.delete(
          'im_sync_state',
          where: 'account_id = ? AND state_key = ?',
          whereArgs: [
            accountId,
            'preview.confirmed_order.${serverMessage.conversationId}',
          ],
        );
      }
      await transaction.delete(
        'im_sync_state',
        where: 'account_id = ? AND state_key = ?',
        whereArgs: [accountId, 'outbox.transport.$clientMessageId'],
      );
    });
  }

  Future<void> markOutboxFailed(
    String accountId,
    ImOutboxItem item,
    String error, {
    bool retryScheduled = false,
    bool retryOnConnectionChange = false,
  }) async {
    final attempts = item.attempts + 1;
    final delay = Duration(seconds: 5 * (1 << attempts.clamp(0, 6)));
    final nextRetryAt = _sortableOutboxTimestamp(_clock().add(delay));
    final database = await _database;
    await database.transaction((transaction) async {
      final transportKey = 'outbox.transport.${item.clientMessageId}';
      if (retryScheduled && retryOnConnectionChange) {
        await _writeState(transaction, accountId, transportKey, '1');
      } else {
        await transaction.delete(
          'im_sync_state',
          where: 'account_id = ? AND state_key = ?',
          whereArgs: [accountId, transportKey],
        );
      }
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
          'local_status': retryScheduled
              ? ImLocalMessageStatus.pending.name
              : ImLocalMessageStatus.failed.name,
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
        {'next_retry_at': _outboxNow(), 'last_error': ''},
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
    int sequence,
  ) async {
    final database = await _database;
    await database.transaction((transaction) async {
      await _applyOwnRead(transaction, accountId, conversationId, sequence);
    });
  }

  Future<int> lastEventSequence(String accountId, String deviceId) async {
    final value = await _readState(accountId, _eventSequenceKey(deviceId));
    return int.tryParse(value ?? '') ?? 0;
  }

  Future<int> lastAckedEventSequence(String accountId, String deviceId) async {
    final value = await _readState(accountId, _eventAckSequenceKey(deviceId));
    return int.tryParse(value ?? '') ?? 0;
  }

  Future<({int appliedSequence, int acknowledgedSequence})> syncCursors(
    String accountId,
    String deviceId,
  ) async => (
    appliedSequence: await lastEventSequence(accountId, deviceId),
    acknowledgedSequence: await lastAckedEventSequence(accountId, deviceId),
  );

  Future<void> markEventsAcked(
    String accountId,
    String deviceId,
    int sequence,
  ) async {
    if (sequence <= 0) return;
    final database = await _database;
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'im_sync_state',
        columns: ['value'],
        where: 'account_id = ? AND state_key = ?',
        whereArgs: [accountId, _eventAckSequenceKey(deviceId)],
        limit: 1,
      );
      final current = rows.isEmpty
          ? 0
          : int.tryParse(rows.single['value']?.toString() ?? '') ?? 0;
      final next = sequence > current ? sequence : current;
      await _writeState(
        transaction,
        accountId,
        _eventAckSequenceKey(deviceId),
        next.toString(),
      );
    });
  }

  Future<void> applySyncBatch({
    required String accountId,
    required String deviceId,
    required List<ImSyncEvent> events,
    required ImBootstrap bootstrap,
  }) async {
    final database = await _database;
    await database.transaction((transaction) async {
      await _replaceBootstrap(transaction, accountId, bootstrap);
      for (final event in events) {
        await transaction.insert('im_event_inbox', {
          'account_id': accountId,
          'sequence': event.sequence,
          'event_id': event.id,
          'type': event.type,
          'payload_json': await _cipher.protect(accountId, event.payloadJson),
          'created_at': event.createdAt?.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        await _applyEvent(
          transaction,
          accountId,
          bootstrap.currentMember.id,
          event,
        );
      }
      final current = await _readStateFromExecutor(
        transaction,
        accountId,
        _eventSequenceKey(deviceId),
      );
      final currentSequence = int.tryParse(current ?? '') ?? 0;
      final latestSequence = events.fold<int>(
        currentSequence,
        (latest, event) => event.sequence > latest ? event.sequence : latest,
      );
      await _writeState(
        transaction,
        accountId,
        _eventSequenceKey(deviceId),
        latestSequence.toString(),
      );
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
    String currentMemberId,
    ImSyncEvent event,
  ) async {
    Map<String, Object?> payload;
    try {
      payload = (jsonDecode(event.payloadJson) as Map).cast<String, Object?>();
    } catch (_) {
      return;
    }
    if (ImEventSemantics.isMessageCreated(event.type)) {
      await _upsertMessage(executor, accountId, ImMessage.fromJson(payload));
      return;
    }
    if (ImEventSemantics.isConversationRead(event.type)) {
      final readerId = _jsonText(payload, 'readerId');
      final conversationId = _jsonText(payload, 'conversationId');
      final sequence = int.tryParse(_jsonText(payload, 'sequence')) ?? 0;
      if (ImEventSemantics.isCurrentReader(
            readerId: readerId,
            accountId: accountId,
            currentMemberId: currentMemberId,
          ) &&
          conversationId.isNotEmpty) {
        await _applyOwnRead(
          executor,
          accountId,
          conversationId,
          sequence,
          currentMemberId: currentMemberId,
        );
      } else if (readerId.isNotEmpty &&
          currentMemberId.isNotEmpty &&
          conversationId.isNotEmpty &&
          sequence > 0) {
        // Own read moves the inbox cursor; another member's read confirms
        // outgoing delivery. Never infer peer reading from our own read.
        final key = 'recipient.read.$conversationId';
        final previous =
            int.tryParse(
              await _readStateFromExecutor(executor, accountId, key) ?? '',
            ) ??
            0;
        if (sequence > previous) {
          await _writeState(executor, accountId, key, sequence.toString());
        }
      }
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
    final previousConversationRows = await executor.query(
      'im_conversations',
      columns: ['id', 'last_read_sequence'],
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    final previousReadSequences = <String, int>{
      for (final row in previousConversationRows)
        row['id']!.toString(): row['last_read_sequence'] as int? ?? 0,
    };
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
      final previousReadSequence = previousReadSequences[conversation.id] ?? 0;
      final lastReadSequence =
          conversation.lastReadSequence > previousReadSequence
          ? conversation.lastReadSequence
          : previousReadSequence;
      await executor.insert('im_conversations', {
        'account_id': accountId,
        'id': conversation.id,
        'type': conversation.type,
        'title': conversation.title,
        'preview': await _cipher.protect(accountId, conversation.preview),
        'updated_at': conversation.updatedAt?.toUtc().toIso8601String(),
        'unread_count': conversation.unreadCount,
        'last_message_sequence': conversation.lastMessageSequence,
        'last_read_sequence': lastReadSequence,
        'is_pinned': conversation.isPinned ? 1 : 0,
        'is_muted': conversation.isMuted ? 1 : 0,
        'unread_mention_sequences_json': jsonEncode(
          conversation.unreadMentionSequences,
        ),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await _prepareHistoryCatchups(executor, accountId, value.conversations);
    await _writeState(
      executor,
      accountId,
      'bootstrap.permissions',
      jsonEncode(value.permissions.toJson()),
    );
    await _writeState(
      executor,
      accountId,
      'bootstrap.current_member_id',
      value.currentMember.id,
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
    'last_seen_at': member.lastSeenAt?.toUtc().toIso8601String(),
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
    final clientDedupeKey = ImEventSemantics.messageDedupeKey(
      serverMessageId: '',
      senderId: message.senderId,
      clientMessageId: message.clientMessageId,
    );
    if (message.sequence > 0 && clientDedupeKey.isNotEmpty) {
      // Keep local FIFO identity across a late send response or sync echo. A
      // server confirmation timestamp is not the original enqueue timestamp.
      final queued = await executor.rawQuery(
        '''
        SELECT o.rowid AS enqueue_order FROM im_outbox o
        JOIN im_members member ON member.account_id = o.account_id
         AND member.is_current = 1 AND member.id = ?
        WHERE o.account_id = ? AND o.conversation_id = ?
          AND o.client_message_id = ? LIMIT 1
      ''',
        [
          message.senderId,
          accountId,
          message.conversationId,
          message.clientMessageId,
        ],
      );
      if (queued.isNotEmpty) {
        final key = 'preview.confirmed_order.${message.conversationId}';
        final previous = _decodeStateMap(
          await _readStateFromExecutor(executor, accountId, key),
        );
        if ((previous['sequence'] as int? ?? 0) < message.sequence) {
          await _writeState(
            executor,
            accountId,
            key,
            jsonEncode({
              'sequence': message.sequence,
              'order': queued.single['enqueue_order'],
            }),
          );
        }
      }
    }
    if (clientDedupeKey.isNotEmpty) {
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

  Future<String?> _readStateFromExecutor(
    DatabaseExecutor executor,
    String accountId,
    String key,
  ) async {
    final rows = await executor.query(
      'im_sync_state',
      columns: ['value'],
      where: 'account_id = ? AND state_key = ?',
      whereArgs: [accountId, key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> _applyOwnRead(
    DatabaseExecutor executor,
    String accountId,
    String conversationId,
    int sequence, {
    String currentMemberId = '',
  }) async {
    if (sequence <= 0) return;
    final resolvedCurrentMemberId = currentMemberId.isNotEmpty
        ? currentMemberId
        : await _readStateFromExecutor(
                executor,
                accountId,
                'bootstrap.current_member_id',
              ) ??
              '';
    final rows = await executor.query(
      'im_conversations',
      columns: ['last_read_sequence', 'unread_mention_sequences_json'],
      where: 'account_id = ? AND id = ?',
      whereArgs: [accountId, conversationId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final current = rows.single['last_read_sequence'] as int? ?? 0;
    final next = ImEventSemantics.mergeReadSequence(current, sequence);
    final mentions = _decodeIntegerList(
      rows.single['unread_mention_sequences_json']?.toString() ?? '[]',
    ).where((value) => value > next).toList();
    final unreadRows = await executor.rawQuery(
      '''
      SELECT COUNT(*) AS unread_count
      FROM im_messages
      WHERE account_id = ? AND conversation_id = ? AND sequence > ?
        AND is_deleted = 0
        ${resolvedCurrentMemberId.isEmpty ? '' : 'AND sender_id <> ?'}
      ''',
      [
        accountId,
        conversationId,
        next,
        if (resolvedCurrentMemberId.isNotEmpty) resolvedCurrentMemberId,
      ],
    );
    final unread = Sqflite.firstIntValue(unreadRows) ?? 0;
    await executor.update(
      'im_conversations',
      {
        'last_read_sequence': next,
        'unread_count': unread,
        'unread_mention_sequences_json': jsonEncode(mentions),
      },
      where: 'account_id = ? AND id = ?',
      whereArgs: [accountId, conversationId],
    );
  }

  static String _eventSequenceKey(String deviceId) =>
      'events.last_sequence.${_stateKeySuffix(deviceId)}';

  static String _eventAckSequenceKey(String deviceId) =>
      'events.last_ack_sequence.${_stateKeySuffix(deviceId)}';

  static String _stateKeySuffix(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

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

  void clearDecodedMessages() => _decodedMessages.clear();

  Future<void> close() async {
    clearDecodedMessages();
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }

  String _now() => _clock().toUtc().toIso8601String();

  String _outboxNow() => _sortableOutboxTimestamp(_clock());

  static String _sortableOutboxTimestamp(DateTime value) {
    final utc = value.toUtc();
    final iso = utc.toIso8601String();
    // Dart omits microseconds when zero: .123Z sorts AFTER .123001Z.
    // SQLite text comparisons need a fixed six-digit fractional component.
    return utc.microsecond == 0
        ? '${iso.substring(0, iso.length - 1)}000Z'
        : iso;
  }

  /// Consume only classified transport failures, once per recovery hint. Keep
  /// IDs, attempts, media and FIFO intact; never accelerate HTTP 429/5xx or
  /// infer a legacy failure's category by parsing its human-readable message.
  Future<int> resumeNetworkOutbox(String accountId) async {
    final database = await _database;
    return database.transaction((transaction) async {
      final now = _outboxNow();
      final changed = await transaction.rawUpdate(
        '''
        UPDATE im_outbox SET next_retry_at = ?
        WHERE account_id = ? AND next_retry_at > ? AND EXISTS (
          SELECT 1 FROM im_sync_state s
          WHERE s.account_id = im_outbox.account_id
            AND s.state_key = 'outbox.transport.' || im_outbox.client_message_id
            AND s.value = '1'
        )
      ''',
        [now, accountId, now],
      );
      await transaction.delete(
        'im_sync_state',
        where: "account_id = ? AND state_key LIKE 'outbox.transport.%'",
        whereArgs: [accountId],
      );
      return changed;
    });
  }

  static ImMember _memberFromRow(Map<String, Object?> row) => ImMember(
    id: row['id'] as String,
    username: row['username'] as String,
    displayName: row['display_name'] as String,
    isOnline: (row['is_online'] as int) != 0,
    lastSeenAt: DateTime.tryParse(row['last_seen_at'] as String? ?? '')
        ?.toLocal(),
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
        lastSeenAt: DateTime.tryParse(row['last_seen_at'] as String? ?? '')
            ?.toLocal(),
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
    currentUserRole: row['current_user_role']?.toString() ?? '',
    updatedAt: DateTime.tryParse(row['server_updated_at']?.toString() ?? '')
        ?.toLocal(),
  );

  Future<ImConversation> _conversationFromRow(
    String accountId,
    Map<String, Object?> row,
  ) async {
    final serverUpdatedAt = DateTime.tryParse(
      row['updated_at']?.toString() ?? '',
    )?.toLocal();
    final localCreatedAt = DateTime.tryParse(
      row['local_preview_created_at']?.toString() ?? '',
    )?.toLocal();
    final confirmedOrder = _decodeStateMap(
      row['local_confirmed_order'] as String?,
    );
    final sameLocalBatch =
        confirmedOrder['sequence'] == row['last_message_sequence'];
    final useLocalPreview =
        localCreatedAt != null &&
        (sameLocalBatch
            ? (row['local_preview_order'] as int? ?? 0) >
                  (confirmedOrder['order'] as int? ?? 0)
            : serverUpdatedAt == null ||
                  !localCreatedAt.isBefore(serverUpdatedAt));
    final String preview;
    if (useLocalPreview) {
      preview = switch (row['local_preview_kind']) {
        'image' => '[图片]',
        'video' => '[视频]',
        'audio' => '[语音]',
        'contact' => '[名片]',
        'file' =>
          '[文件] ${await _cipher.reveal(accountId, row['local_preview_file_name'] as String)}'
              .trim(),
        _ => await _cipher.reveal(
          accountId,
          row['local_preview_content'] as String,
        ),
      };
    } else {
      preview = await _cipher.reveal(accountId, row['preview'] as String);
    }
    return ImConversation(
      id: row['id'] as String,
      type: row['type'] as String,
      title: row['title'] as String,
      preview: preview,
      updatedAt: useLocalPreview ? localCreatedAt : serverUpdatedAt,
      localPreviewStatus: useLocalPreview
          ? row['local_preview_status'] == 'failed'
                ? ImLocalMessageStatus.failed
                : ImLocalMessageStatus.pending
          : null,
      unreadCount: row['unread_count'] as int,
      lastMessageSequence: row['last_message_sequence'] as int,
      lastReadSequence: row['last_read_sequence'] as int? ?? 0,
      isPinned: (row['is_pinned'] as int) != 0,
      isMuted: (row['is_muted'] as int) != 0,
      unreadMentionSequences: _decodeIntegerList(
        row['unread_mention_sequences_json']?.toString() ?? '[]',
      ),
    );
  }

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
    images: List.unmodifiable(
      _decodeImages(
        await _cipher.reveal(accountId, row['images_json']?.toString() ?? ''),
      ),
    ),
    attachments: List.unmodifiable(
      _decodeAttachments(
        await _cipher.reveal(
          accountId,
          row['media_attachments_json']?.toString() ?? '',
        ),
      ),
    ),
    createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')
        ?.toLocal(),
    recalledAt: DateTime.tryParse(row['recalled_at']?.toString() ?? '')
        ?.toLocal(),
    mentions: List.unmodifiable(
      _decodeMentions(
        await _cipher.reveal(accountId, row['mentions_json'] as String),
      ),
    ),
    replyTo: _decodeReply(
      await _cipher.reveal(accountId, row['reply_to_json'] as String),
    ),
    localStatus: ImLocalMessageStatus.values.byName(
      row['local_status'] as String,
    ),
    lastError: row['last_error'] as String,
    hasRecipientRead: (row['recipient_read'] as int? ?? 0) != 0,
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

  static List<ImOutboxStoredFile> _decodeOutboxFiles(String value) {
    if (value.isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      return decoded is List
          ? decoded
                .whereType<Map>()
                .map(
                  (item) =>
                      ImOutboxStoredFile.fromJson(item.cast<String, Object?>()),
                )
                .where((item) => item.token.isNotEmpty && item.length > 0)
                .toList(growable: false)
          : const [];
    } catch (_) {
      return const [];
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

final class ImHistoryCatchup {
  const ImHistoryCatchup({
    required this.conversationId,
    required this.afterSequence,
    required this.beforeSequence,
    required this.targetSequence,
  });
  factory ImHistoryCatchup.fromJson(String id, Map<String, Object?> json) =>
      ImHistoryCatchup(
        conversationId: id,
        afterSequence: json['after'] as int,
        beforeSequence: json['before'] as int,
        targetSequence: json['target'] as int,
      );
  final String conversationId;
  final int afterSequence;
  final int beforeSequence;
  final int targetSequence;
  Map<String, Object?> toJson() => {
    'after': afterSequence,
    'before': beforeSequence,
    'target': targetSequence,
  };
}
