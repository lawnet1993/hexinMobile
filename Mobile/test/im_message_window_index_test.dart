import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_message_query.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late ImLocalStore store;
  late Database db;
  late String file;

  ImLocalStore open() =>
      ImLocalStore(factory: databaseFactoryFfi, pathResolver: () async => file);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-uat-window-index-');
    file = '${directory.path}/fixture.db';
    store = open();
    await store.readMessages('a', 'chat', limit: 80);
    db = await databaseFactoryFfi.openDatabase(file);
  });
  tearDown(() async {
    await store.close();
    if (db.isOpen) await db.close();
    await directory.delete(recursive: true);
  });

  Future<List<Map<String, Object?>>> query({bool newest = true}) => db.query(
    'im_messages',
    columns: ImMessageQuery.columns,
    where: ImMessageQuery.visibleWhere,
    whereArgs: ['a', 'chat'],
    orderBy: newest ? ImMessageQuery.newestFirst : ImMessageQuery.oldestFirst,
    limit: newest ? 80 : null,
  );
  Future<String> plan({bool newest = true}) async => (await db.rawQuery(
    'EXPLAIN QUERY PLAN SELECT ${ImMessageQuery.columns.join(', ')} '
    'FROM im_messages WHERE ${ImMessageQuery.visibleWhere} '
    'ORDER BY ${newest ? ImMessageQuery.newestFirst : ImMessageQuery.oldestFirst}'
    '${newest ? ' LIMIT 80' : ''}',
    ['a', 'chat'],
  )).map((row) => row['detail']).join('\n');
  Future<void> seed() async {
    await store.mergeMessages('a', 'chat', [
      for (var i = 1; i <= 150; i++) _message('m$i', i),
      _message('same-sequence', 149, second: 1),
      _message('pending-old', 0),
      _message('pending-new', 0, second: 1),
    ]);
    await store.mergeMessages('b', 'chat', [_message('foreign-account', 999)]);
    await store.mergeMessages('a', 'other', [
      _message('foreign-chat', 999, chat: 'other'),
    ]);
    await db.update('im_messages', {'is_deleted': 1}, where: "id = 'm150'");
    await db.insert('im_sync_state', {
      'account_id': 'a',
      'state_key': 'recipient.read.chat',
      'value': '149',
      'updated_at': '2026-09-03T00:00:00Z',
    });
  }

  test(
    'fresh schema supports both message window orders without a temp sort',
    () async {
      expect(await db.getVersion(), 15);
      for (final newest in [true, false]) {
        final actual = await plan(newest: newest);
        expect(actual, contains(ImMessageQuery.windowIndexName));
        expect(actual, isNot(contains('TEMP B-TREE')));
      }
    },
  );

  test(
    'old plan sorts and new plan preserves exact window and receipt rows',
    () async {
      await seed();
      await db.execute(
        'DROP INDEX IF EXISTS ${ImMessageQuery.windowIndexName}',
      );
      expect(await plan(), contains('TEMP B-TREE'));
      final latest = await query();
      final all = await query(newest: false);
      await db.execute(ImMessageQuery.createWindowIndex);
      expect(await plan(), isNot(contains('TEMP B-TREE')));
      expect(await query(), latest);
      expect(await query(newest: false), all);
      expect(latest.length, 80);
      expect(latest.take(2).map((row) => row['id']), [
        'pending-new',
        'pending-old',
      ]);
      expect(latest.map((row) => row['id']), isNot(contains('m150')));
      expect(latest.skip(2).every((row) => row['recipient_read'] == 1), isTrue);
    },
  );

  test(
    'readMessages keeps pending last, timestamp ties and scoped limits',
    () async {
      await seed();
      for (final limit in [1, 2, 3, 80, 200, null]) {
        await db.execute(
          'DROP INDEX IF EXISTS ${ImMessageQuery.windowIndexName}',
        );
        final before = await store.readMessages('a', 'chat', limit: limit);
        await db.execute(ImMessageQuery.createWindowIndex);
        final after = await store.readMessages('a', 'chat', limit: limit);
        expect(
          after.map((m) => [m.id, m.sequence, m.hasRecipientRead]),
          before.map((m) => [m.id, m.sequence, m.hasRecipientRead]),
        );
        expect(after.last.id, 'pending-new');
        expect(after.any((m) => m.id.startsWith('foreign')), isFalse);
      }
      expect((await store.readMessages('a', 'chat', limit: 0)), isEmpty);
    },
  );

  test(
    'v14 migration preserves every table row and creates the window index',
    () async {
      await seed();
      await store.enqueueText(
        accountId: 'a',
        senderId: 'sender',
        conversationId: 'chat',
        clientMessageId: 'outbox-id',
        content: 'AI-UAT draft',
      );
      await db.execute(
        'DROP INDEX IF EXISTS ${ImMessageQuery.windowIndexName}',
      );
      await db.setVersion(14);
      final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )).map((row) => row['name']! as String).toList();
      final before = <String, List<Map<String, Object?>>>{
        for (final table in tables)
          table: await db.query(table, orderBy: 'rowid'),
      };
      await store.close();
      store = open();
      await store.readMessages('a', 'chat', limit: 80);
      db = await databaseFactoryFfi.openDatabase(file);
      expect(await db.getVersion(), 15);
      expect(await plan(), isNot(contains('TEMP B-TREE')));
      for (final table in tables) {
        expect(
          await db.query(table, orderBy: 'rowid'),
          before[table],
          reason: table,
        );
      }
    },
  );

  test(
    'index tracks confirmation, tombstones, restoration and timestamp updates',
    () async {
      await seed();
      await db.update('im_messages', {
        'sequence': 151,
      }, where: "id = 'pending-old'");
      await db.update('im_messages', {'is_deleted': 0}, where: "id = 'm150'");
      await db.update('im_messages', {
        'is_deleted': 1,
      }, where: "id = 'pending-new'");
      await db.update('im_messages', {
        'created_at': '2026-09-03T00:00:02Z',
      }, where: "id = 'm149'");
      expect(
        (await store.readMessages('a', 'chat', limit: 4)).map((m) => m.id),
        ['same-sequence', 'm149', 'm150', 'pending-old'],
      );
    },
  );

  test(
    'older history retains sequence index and deletion continuity',
    () async {
      await seed();
      final rows = await db.rawQuery(
        'EXPLAIN QUERY PLAN SELECT * FROM im_messages '
        'WHERE account_id = ? AND conversation_id = ? AND sequence > 0 AND sequence < ? '
        'ORDER BY sequence DESC LIMIT 80',
        ['a', 'chat', 151],
      );
      expect(
        rows.map((r) => r['detail']).join(),
        contains('ix_im_messages_conversation_sequence'),
      );
      await db.delete('im_messages', where: "id = 'same-sequence'");
      expect(
        (await store.readAdjacentOlderMessages(
          'a',
          'chat',
          beforeSequence: 151,
          limit: 3,
        )).map((m) => m.id),
        ['m148', 'm149'],
      );
    },
  );
}

ImMessage _message(
  String id,
  int sequence, {
  int second = 0,
  String chat = 'chat',
}) => ImMessage(
  id: id,
  sequence: sequence,
  conversationId: chat,
  senderId: 'sender',
  content: 'AI-UAT fixture',
  kind: 'text',
  createdAt: DateTime.utc(2026, 9, 3, 0, 0, second),
);
