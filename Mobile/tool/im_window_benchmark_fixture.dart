import 'dart:io';

import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_message_query.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite/sqflite.dart';

/// Synthetic, isolated, encrypted fixture. Never opens the application's DB,
/// secure storage, network or account providers. Caller owns the temp directory.
Future<Map<String, Object?>> runImWindowBenchmark(
  DatabaseFactory factory,
  Directory directory, {
  List<int> sizes = const [1000, 10000, 50000],
}) async {
  final file = '${directory.path}/ai-uat-window.db';
  if (await File(file).exists()) throw StateError('Fixture already exists');
  final store = ImLocalStore(
    factory: factory,
    pathResolver: () async => file,
    // Only synthetic content is encrypted with this throwaway fixture key.
    cipher: AesGcmImCacheCipher((_) async => List.generate(32, (i) => i)),
  );
  Database? connection;
  const account = 'ai-uat-fixture-account';
  const chat = 'ai-uat-fixture-chat';
  const content = 'AI-UAT synthetic query fixture, not a business message.';
  try {
    await store.mergeMessages(account, chat, [
      ImMessage(
        id: 'fixture-1',
        sequence: 1,
        conversationId: chat,
        senderId: 'fixture-peer',
        content: content,
        kind: 'text',
        createdAt: DateTime.utc(2026, 9, 3),
      ),
    ]);
    final db = connection = await factory.openDatabase(file);
    final seed = (await db.query('im_messages')).single;
    if (!(seed['content'] as String).startsWith('enc:v1:')) {
      throw StateError('Fixture must be encrypted');
    }
    for (var i = 0; i < 3; i++) {
      await store.enqueueText(
        accountId: account,
        senderId: 'fixture-self',
        conversationId: chat,
        clientMessageId: 'fixture-outbox-$i',
        content: content,
      );
    }
    await db.insert('im_sync_state', {
      'account_id': account,
      'state_key': 'recipient.read.$chat',
      'value': '50000',
      'updated_at': '2026-09-03T00:00:00Z',
    });
    final sql =
        'SELECT ${ImMessageQuery.columns.join(', ')} FROM im_messages '
        'WHERE ${ImMessageQuery.visibleWhere} ORDER BY ${ImMessageQuery.newestFirst} LIMIT 80';
    Future<List<Map<String, Object?>>> read() =>
        db.rawQuery(sql, [account, chat]);
    Future<List<String>> plan() async => (await db.rawQuery(
      'EXPLAIN QUERY PLAN $sql',
      [account, chat],
    )).map((r) => r['detail']! as String).toList();
    Future<int> pages() async =>
        (await db.rawQuery('PRAGMA page_count')).single.values.single as int;
    final rows = <Map<String, Object?>>[];
    var previousSize = 1;
    for (final size in sizes) {
      if (size <= previousSize || size > 100000) {
        throw ArgumentError('Invalid fixture size');
      }
      await db.execute(
        'DROP INDEX IF EXISTS ${ImMessageQuery.windowIndexName}',
      );
      final keys = seed.keys.toList();
      await db.rawInsert(
        'WITH RECURSIVE numbered(n) AS (VALUES(?) UNION ALL SELECT n+1 FROM numbered WHERE n < ?) '
        'INSERT INTO im_messages (${keys.join(',')}) SELECT ${keys.map((key) => switch (key) {
          'id' => "'fixture-' || n",
          'sequence' => 'n',
          _ => '?',
        }).join(',')} FROM numbered',
        [
          previousSize + 1,
          size,
          for (final key in keys)
            if (key != 'id' && key != 'sequence') seed[key],
        ],
      );
      await db.execute(
        'UPDATE im_messages SET is_deleted = 1 WHERE sequence > 0 AND sequence % 101 = 0',
      );
      previousSize = size;
      final beforePlan = await plan();
      if (!beforePlan.any((p) => p.contains('TEMP B-TREE'))) {
        throw StateError('Old plan control failed');
      }
      final expected = await read();
      final oldSql = await _measure(read);
      final oldModel = await _measure(
        () => store.readMessages(account, chat, limit: 80),
      );
      final pagesBefore = await pages();
      final indexTimer = Stopwatch()..start();
      await db.execute(ImMessageQuery.createWindowIndex);
      indexTimer.stop();
      final afterPlan = await plan();
      if (afterPlan.any((p) => p.contains('TEMP B-TREE')) ||
          !afterPlan.any((p) => p.contains(ImMessageQuery.windowIndexName))) {
        throw StateError('Indexed plan failed');
      }
      final actual = await read();
      if (actual.length != 80 ||
          actual.length != expected.length ||
          List.generate(
            actual.length,
            (i) => actual[i].toString() == expected[i].toString(),
          ).contains(false)) {
        throw StateError('Message rows changed');
      }
      final newSql = await _measure(read);
      final decoded = await store.readMessages(account, chat, limit: 80);
      if (!decoded.every((m) => m.content == content) ||
          decoded.where((m) => m.sequence == 0).length != 3) {
        throw StateError('Decoded messages or pending placement changed');
      }
      final newModel = await _measure(
        () => store.readMessages(account, chat, limit: 80),
      );
      final pagesAfter = await pages();
      // Recheck old query after the new query to expose warm-up/order bias.
      await db.execute('DROP INDEX ${ImMessageQuery.windowIndexName}');
      final oldSqlAgain = await _measure(read);
      await db.execute(ImMessageQuery.createWindowIndex);
      rows.add({
        'confirmedFixtureRows': size,
        'pendingRows': 3,
        'visibleWindowRows': actual.length,
        'sameRowsAndReceipts': true,
        'encryptedDecodedContentMatches': true,
        'beforePlan': beforePlan,
        'afterPlan': afterPlan,
        'oldSql': oldSql,
        'newSql': newSql,
        'oldSqlAgain': oldSqlAgain,
        'oldReadMessagesWithDecrypt': oldModel,
        'newReadMessagesWithDecrypt': newModel,
        'indexCreationMicros': indexTimer.elapsedMicroseconds,
        'databasePagesBefore': pagesBefore,
        'databasePagesAfter': pagesAfter,
      });
    }
    return {
      'scope': 'Synthetic SQLite + platform channel + model decoding; not touch-to-frame latency',
      'sqliteVersion': (await db.rawQuery('SELECT sqlite_version() AS version'))
          .single['version'],
      'schemaVersion': await db.getVersion(),
      'pageBytes': (await db.rawQuery('PRAGMA page_size')).single.values.single,
      'results': rows,
    };
  } finally {
    await store.close();
    if (connection?.isOpen == true) await connection!.close();
  }
}

Future<Map<String, Object>> _measure(Future<Object?> Function() action) async {
  for (var i = 0; i < 2; i++) {
    await action();
  }
  final samples = <int>[];
  for (var i = 0; i < 9; i++) {
    final timer = Stopwatch()..start();
    await action();
    timer.stop();
    samples.add(timer.elapsedMicroseconds);
  }
  final sorted = [...samples]..sort();
  return {
    'samplesMicros': samples,
    'medianMicros': sorted[4],
    'maxMicros': sorted.last,
  };
}
