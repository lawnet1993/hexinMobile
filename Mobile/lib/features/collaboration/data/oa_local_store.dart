import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/im_cache_cipher.dart';

final class OaApprovalDraft {
  const OaApprovalDraft({
    required this.id,
    required this.applicationKey,
    required this.templateId,
    required this.workflowKey,
    required this.title,
    required this.formData,
    required this.updatedAt,
    this.attachments = const [],
  });

  final String id;
  final String applicationKey;
  final String templateId;
  final String workflowKey;
  final String title;
  final Map<String, Object?> formData;
  final DateTime updatedAt;
  final List<OaLocalAttachment> attachments;
}

final class OaLocalAttachment {
  const OaLocalAttachment({
    required this.id,
    required this.fileName,
    required this.contentType,
    required this.bytes,
    this.formFieldId = '',
  });

  factory OaLocalAttachment.fromJson(Map<String, Object?> json) =>
      OaLocalAttachment(
        id: json['id']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? '',
        contentType:
            json['contentType']?.toString() ?? 'application/octet-stream',
        bytes: _decodeBytes(json['bytesBase64']),
        formFieldId: json['formFieldId']?.toString() ?? '',
      );

  final String id;
  final String fileName;
  final String contentType;
  final List<int> bytes;
  final String formFieldId;

  int get size => bytes.length;

  Map<String, Object?> toJson() => {
    'id': id,
    'fileName': fileName,
    'contentType': contentType,
    'bytesBase64': base64Encode(bytes),
    'formFieldId': formFieldId,
  };
}

final class OaOutboxItem {
  const OaOutboxItem({
    required this.id,
    required this.idempotencyKey,
    required this.commandType,
    required this.payload,
    required this.state,
    required this.attempts,
    required this.nextRetryAt,
    required this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String idempotencyKey;
  final String commandType;
  final Map<String, Object?> payload;
  final String state;
  final int attempts;
  final DateTime nextRetryAt;
  final String lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class OaSyncEvent {
  const OaSyncEvent({
    required this.sequence,
    required this.id,
    required this.type,
    required this.payloadJson,
    required this.createdAt,
  });

  factory OaSyncEvent.fromJson(Map<String, Object?> json) => OaSyncEvent(
    sequence: _integer(json['sequence']),
    id: json['id']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    payloadJson: json['payloadJson']?.toString() ?? '{}',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now().toUtc(),
  );

  final int sequence;
  final String id;
  final String type;
  final String payloadJson;
  final DateTime createdAt;
}

final class OaLocalStore {
  OaLocalStore({
    DatabaseFactory? factory,
    Future<String> Function()? pathResolver,
    ImCacheCipher cipher = const PlainImCacheCipher(),
  }) : this.withOptions(
         factory ?? databaseFactory,
         pathResolver ?? _defaultPath,
         cipher,
       );

  OaLocalStore.withOptions(this._factory, this._pathResolver, this._cipher);

  static const bootstrapCacheKey = 'bootstrap';
  static const catalogCacheKey = 'app-catalog';
  static const notificationsCacheKey = 'notifications';
  static const notificationPageCacheKey = 'notifications-page';
  static const attendanceCacheKey = 'attendance-overview';

  final DatabaseFactory _factory;
  final Future<String> Function() _pathResolver;
  final ImCacheCipher _cipher;
  Future<Database>? _opening;

  static Future<String> _defaultPath() async =>
      path.join(await getDatabasesPath(), 'hexing-mobile-oa.db');

  Future<Database> get _database => _opening ??= _open();

  Future<Database> _open() async => _factory.openDatabase(
    await _pathResolver(),
    options: OpenDatabaseOptions(
      version: 2,
      onConfigure: (database) async {
        // journal_mode returns a result row on Android SQLite and therefore
        // must be issued through rawQuery rather than execute.
        await database.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: (database, _) async {
        await database.execute('''
          CREATE TABLE oa_cache (
            account_id TEXT NOT NULL,
            cache_key TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (account_id, cache_key)
          )
        ''');
        await database.execute('''
          CREATE TABLE oa_approval_drafts (
            account_id TEXT NOT NULL,
            id TEXT NOT NULL,
            application_key TEXT NOT NULL,
            template_id TEXT NOT NULL,
            workflow_key TEXT NOT NULL,
            title TEXT NOT NULL,
            form_data_json TEXT NOT NULL,
            attachments_json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (account_id, id)
          )
        ''');
        await database.execute('''
          CREATE INDEX ix_oa_approval_drafts_updated
          ON oa_approval_drafts(account_id, updated_at DESC)
        ''');
        await database.execute('''
          CREATE TABLE oa_outbox (
            account_id TEXT NOT NULL,
            id TEXT NOT NULL,
            idempotency_key TEXT NOT NULL,
            command_type TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            state TEXT NOT NULL,
            attempts INTEGER NOT NULL,
            next_retry_at TEXT NOT NULL,
            last_error TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (account_id, id),
            UNIQUE (account_id, idempotency_key)
          )
        ''');
        await database.execute('''
          CREATE INDEX ix_oa_outbox_due
          ON oa_outbox(account_id, state, next_retry_at)
        ''');
        await database.execute('''
          CREATE TABLE oa_event_inbox (
            account_id TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            event_id TEXT NOT NULL,
            type TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            created_at TEXT NOT NULL,
            applied_at TEXT NOT NULL,
            PRIMARY KEY (account_id, sequence),
            UNIQUE (account_id, event_id)
          )
        ''');
        await database.execute('''
          CREATE TABLE oa_sync_state (
            account_id TEXT NOT NULL,
            state_key TEXT NOT NULL,
            value TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (account_id, state_key)
          )
        ''');
      },
      onUpgrade: (database, oldVersion, _) async {
        if (oldVersion < 2) {
          await database.execute(
            "ALTER TABLE oa_approval_drafts ADD COLUMN attachments_json TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    ),
  );

  Future<Map<String, Object?>?> readObject(
    String accountId,
    String cacheKey,
  ) async {
    final database = await _database;
    final rows = await database.query(
      'oa_cache',
      columns: ['payload_json'],
      where: 'account_id = ? AND cache_key = ?',
      whereArgs: [accountId, cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload = await _cipher.reveal(
      accountId,
      rows.single['payload_json']?.toString() ?? '{}',
    );
    final decoded = jsonDecode(payload);
    return decoded is Map ? decoded.cast<String, Object?>() : null;
  }

  Future<List<Object?>?> readList(String accountId, String cacheKey) async {
    final database = await _database;
    final rows = await database.query(
      'oa_cache',
      columns: ['payload_json'],
      where: 'account_id = ? AND cache_key = ?',
      whereArgs: [accountId, cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final payload = await _cipher.reveal(
      accountId,
      rows.single['payload_json']?.toString() ?? '[]',
    );
    final decoded = jsonDecode(payload);
    return decoded is List ? decoded.cast<Object?>() : null;
  }

  Future<DateTime?> cacheUpdatedAt(String accountId, String cacheKey) async {
    final database = await _database;
    final rows = await database.query(
      'oa_cache',
      columns: ['updated_at'],
      where: 'account_id = ? AND cache_key = ?',
      whereArgs: [accountId, cacheKey],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : DateTime.tryParse(rows.single['updated_at']?.toString() ?? '');
  }

  Future<void> writeObject(
    String accountId,
    String cacheKey,
    Map<String, Object?> value,
  ) => _writeCache(accountId, cacheKey, jsonEncode(value));

  Future<void> writeList(
    String accountId,
    String cacheKey,
    List<Object?> value,
  ) => _writeCache(accountId, cacheKey, jsonEncode(value));

  Future<void> _writeCache(
    String accountId,
    String cacheKey,
    String payload,
  ) async {
    final database = await _database;
    await _writeCacheWith(
      database,
      accountId,
      cacheKey,
      payload,
      DateTime.now().toUtc(),
    );
  }

  Future<void> invalidate(String accountId, Iterable<String> keys) async {
    final values = keys.toList();
    if (values.isEmpty) return;
    final database = await _database;
    final placeholders = List.filled(values.length, '?').join(',');
    await database.delete(
      'oa_cache',
      where: 'account_id = ? AND cache_key IN ($placeholders)',
      whereArgs: [accountId, ...values],
    );
  }

  Future<OaApprovalDraft?> readDraftForTemplate(
    String accountId,
    String templateId,
  ) async {
    final database = await _database;
    final rows = await database.query(
      'oa_approval_drafts',
      where: 'account_id = ? AND template_id = ?',
      whereArgs: [accountId, templateId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _draftFromRow(accountId, rows.single);
  }

  Future<List<OaApprovalDraft>> readDrafts(String accountId) async {
    final database = await _database;
    final rows = await database.query(
      'oa_approval_drafts',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'updated_at DESC',
    );
    return Future.wait(rows.map((row) => _draftFromRow(accountId, row)));
  }

  Future<OaApprovalDraft> saveDraft(
    String accountId,
    OaApprovalDraft draft,
  ) async {
    final database = await _database;
    await database.insert('oa_approval_drafts', {
      'account_id': accountId,
      'id': draft.id,
      'application_key': draft.applicationKey,
      'template_id': draft.templateId,
      'workflow_key': draft.workflowKey,
      'title': await _cipher.protect(accountId, draft.title),
      'form_data_json': await _cipher.protect(
        accountId,
        jsonEncode(draft.formData),
      ),
      'attachments_json': await _cipher.protect(
        accountId,
        jsonEncode(draft.attachments.map((item) => item.toJson()).toList()),
      ),
      'updated_at': draft.updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return draft;
  }

  Future<void> deleteDraft(String accountId, String draftId) async {
    final database = await _database;
    await database.delete(
      'oa_approval_drafts',
      where: 'account_id = ? AND id = ?',
      whereArgs: [accountId, draftId],
    );
  }

  Future<OaOutboxItem> enqueue(
    String accountId, {
    required String id,
    required String idempotencyKey,
    required String commandType,
    required Map<String, Object?> payload,
  }) async {
    final database = await _database;
    final now = DateTime.now().toUtc();
    await database.insert('oa_outbox', {
      'account_id': accountId,
      'id': id,
      'idempotency_key': idempotencyKey,
      'command_type': commandType,
      'payload_json': await _cipher.protect(accountId, jsonEncode(payload)),
      'state': 'pending',
      'attempts': 0,
      'next_retry_at': now.toIso8601String(),
      'last_error': '',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return (await readOutbox(accountId)).firstWhere((item) => item.id == id);
  }

  Future<List<OaOutboxItem>> readOutbox(String accountId) async {
    final database = await _database;
    final rows = await database.query(
      'oa_outbox',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'created_at DESC',
    );
    return Future.wait(rows.map((row) => _outboxFromRow(accountId, row)));
  }

  Future<List<OaOutboxItem>> dueOutbox(String accountId) async {
    final database = await _database;
    final rows = await database.query(
      'oa_outbox',
      where: "account_id = ? AND state = 'pending' AND next_retry_at <= ?",
      whereArgs: [accountId, DateTime.now().toUtc().toIso8601String()],
      orderBy: 'created_at',
    );
    return Future.wait(rows.map((row) => _outboxFromRow(accountId, row)));
  }

  Future<void> removeOutbox(String accountId, String id) async {
    final database = await _database;
    await database.delete(
      'oa_outbox',
      where: 'account_id = ? AND id = ?',
      whereArgs: [accountId, id],
    );
  }

  Future<void> updateOutboxPayload(
    String accountId,
    String id,
    Map<String, Object?> payload,
  ) async {
    final database = await _database;
    await database.update(
      'oa_outbox',
      {
        'payload_json': await _cipher.protect(accountId, jsonEncode(payload)),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'account_id = ? AND id = ?',
      whereArgs: [accountId, id],
    );
  }

  Future<void> retryOutbox(String accountId, String id) async {
    final database = await _database;
    final now = DateTime.now().toUtc().toIso8601String();
    await database.update(
      'oa_outbox',
      {
        'state': 'pending',
        'next_retry_at': now,
        'last_error': '',
        'updated_at': now,
      },
      where: 'account_id = ? AND id = ?',
      whereArgs: [accountId, id],
    );
  }

  Future<void> markOutboxFailed(
    String accountId,
    OaOutboxItem item,
    String error, {
    required bool permanent,
  }) async {
    final database = await _database;
    final attempts = item.attempts + 1;
    final delaySeconds = (attempts * attempts * 5).clamp(5, 300);
    final now = DateTime.now().toUtc();
    await database.update(
      'oa_outbox',
      {
        'state': permanent ? 'failed' : 'pending',
        'attempts': attempts,
        'next_retry_at': now
            .add(Duration(seconds: delaySeconds))
            .toIso8601String(),
        'last_error': await _cipher.protect(accountId, error),
        'updated_at': now.toIso8601String(),
      },
      where: 'account_id = ? AND id = ?',
      whereArgs: [accountId, item.id],
    );
  }

  Future<int> lastEventSequence(String accountId) async {
    final database = await _database;
    final rows = await database.query(
      'oa_sync_state',
      columns: ['value'],
      where: "account_id = ? AND state_key = 'last-event-sequence'",
      whereArgs: [accountId],
      limit: 1,
    );
    return rows.isEmpty ? 0 : _integer(rows.single['value']);
  }

  Future<void> applySyncBatch({
    required String accountId,
    required List<OaSyncEvent> events,
    required Map<String, String> refreshedCaches,
  }) async {
    if (events.isEmpty && refreshedCaches.isEmpty) return;
    final database = await _database;
    final now = DateTime.now().toUtc();
    final protectedCaches = <String, String>{};
    for (final entry in refreshedCaches.entries) {
      protectedCaches[entry.key] = await _cipher.protect(
        accountId,
        entry.value,
      );
    }
    final protectedEvents = <({OaSyncEvent event, String payload})>[];
    for (final event in events) {
      protectedEvents.add((
        event: event,
        payload: await _cipher.protect(accountId, event.payloadJson),
      ));
    }
    await database.transaction((transaction) async {
      for (final entry in protectedCaches.entries) {
        await transaction.insert('oa_cache', {
          'account_id': accountId,
          'cache_key': entry.key,
          'payload_json': entry.value,
          'updated_at': now.toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final protectedEvent in protectedEvents) {
        final event = protectedEvent.event;
        await transaction.insert('oa_event_inbox', {
          'account_id': accountId,
          'sequence': event.sequence,
          'event_id': event.id,
          'type': event.type,
          'payload_json': protectedEvent.payload,
          'created_at': event.createdAt.toUtc().toIso8601String(),
          'applied_at': now.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final cursorRows = await transaction.query(
        'oa_sync_state',
        columns: ['value'],
        where: "account_id = ? AND state_key = 'last-event-sequence'",
        whereArgs: [accountId],
        limit: 1,
      );
      final currentSequence = cursorRows.isEmpty
          ? 0
          : _integer(cursorRows.single['value']);
      final lastSequence = events.fold<int>(
        currentSequence,
        (value, event) => event.sequence > value ? event.sequence : value,
      );
      if (lastSequence > 0) {
        await transaction.insert('oa_sync_state', {
          'account_id': accountId,
          'state_key': 'last-event-sequence',
          'value': lastSequence.toString(),
          'updated_at': now.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> _writeCacheWith(
    DatabaseExecutor database,
    String accountId,
    String cacheKey,
    String payload,
    DateTime updatedAt,
  ) async {
    await database.insert('oa_cache', {
      'account_id': accountId,
      'cache_key': cacheKey,
      'payload_json': await _cipher.protect(accountId, payload),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<OaApprovalDraft> _draftFromRow(
    String accountId,
    Map<String, Object?> row,
  ) async {
    final title = await _cipher.reveal(
      accountId,
      row['title']?.toString() ?? '',
    );
    final formDataJson = await _cipher.reveal(
      accountId,
      row['form_data_json']?.toString() ?? '{}',
    );
    final decoded = jsonDecode(formDataJson);
    final attachmentPayload = row['attachments_json']?.toString() ?? '';
    final attachmentJson = attachmentPayload.isEmpty
        ? '[]'
        : await _cipher.reveal(accountId, attachmentPayload);
    final attachmentData = jsonDecode(attachmentJson);
    return OaApprovalDraft(
      id: row['id']?.toString() ?? '',
      applicationKey: row['application_key']?.toString() ?? '',
      templateId: row['template_id']?.toString() ?? '',
      workflowKey: row['workflow_key']?.toString() ?? '',
      title: title,
      formData: decoded is Map
          ? decoded.cast<String, Object?>()
          : <String, Object?>{},
      attachments: attachmentData is List
          ? attachmentData
                .whereType<Map>()
                .map(
                  (item) =>
                      OaLocalAttachment.fromJson(item.cast<String, Object?>()),
                )
                .toList()
          : const [],
      updatedAt:
          DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Future<OaOutboxItem> _outboxFromRow(
    String accountId,
    Map<String, Object?> row,
  ) async {
    final payloadJson = await _cipher.reveal(
      accountId,
      row['payload_json']?.toString() ?? '{}',
    );
    final decoded = jsonDecode(payloadJson);
    final lastError = await _cipher.reveal(
      accountId,
      row['last_error']?.toString() ?? '',
    );
    return OaOutboxItem(
      id: row['id']?.toString() ?? '',
      idempotencyKey: row['idempotency_key']?.toString() ?? '',
      commandType: row['command_type']?.toString() ?? '',
      payload: decoded is Map
          ? decoded.cast<String, Object?>()
          : <String, Object?>{},
      state: row['state']?.toString() ?? 'pending',
      attempts: _integer(row['attempts']),
      nextRetryAt:
          DateTime.tryParse(row['next_retry_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastError: lastError,
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}

int _integer(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

List<int> _decodeBytes(Object? value) {
  try {
    return base64Decode(value?.toString() ?? '');
  } on FormatException {
    return const [];
  }
}
