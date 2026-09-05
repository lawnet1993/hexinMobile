import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final base = DateTime.utc(2026, 9, 2, 12, 0, 0, 123);
  late DateTime now;
  late ImLocalStore store;
  setUp(() {
    now = base;
    store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
      clock: () => now,
    );
  });
  tearDown(() => store.close());

  Future<void> enqueue(String id) => store.enqueueText(
    accountId: 'account',
    senderId: 'sender',
    conversationId: 'group',
    clientMessageId: id,
    content: 'fixture $id',
  );

  test(
    'a message is due one microsecond after a millisecond timestamp',
    () async {
      await enqueue('first');
      now = now.add(const Duration(microseconds: 1));
      expect((await store.dueOutbox('account')).map((m) => m.clientMessageId), [
        'first',
      ]);
    },
  );

  test(
    'mixed millisecond and microsecond sends remain in chronological order',
    () async {
      await enqueue('first');
      now = now.add(const Duration(microseconds: 1));
      await enqueue('second');
      now = now.add(const Duration(seconds: 1));
      expect((await store.dueOutbox('account')).map((m) => m.clientMessageId), [
        'first',
        'second',
      ]);
    },
  );

  test(
    'retry boundary preserves FIFO and does not send a retry early',
    () async {
      await enqueue('first');
      final first = (await store.dueOutbox('account')).single;
      await store.markOutboxFailed('account', first, 'offline');
      now = now.add(const Duration(microseconds: 1));
      await enqueue('second');
      now = base
          .add(const Duration(seconds: 10))
          .subtract(const Duration(microseconds: 1));
      expect(await store.dueOutbox('account'), isEmpty);
      now = now.add(const Duration(microseconds: 2));
      expect((await store.dueOutbox('account')).map((m) => m.clientMessageId), [
        'first',
        'second',
      ]);
    },
  );

  test(
    'version 12 outbox timestamps migrate without losing queued data',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'hexing-outbox-clock-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}${Platform.pathSeparator}im.db';
      ImLocalStore open() => ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => path,
        clock: () => now,
      );
      final original = open();
      await original.enqueueText(
        accountId: 'account',
        senderId: 'sender',
        conversationId: 'group',
        clientMessageId: 'first',
        content: 'preserve me',
        mentionedMemberIds: ['other'],
      );
      now = now.add(const Duration(microseconds: 1));
      await original.enqueueText(
        accountId: 'account',
        senderId: 'sender',
        conversationId: 'group',
        clientMessageId: 'second',
        content: 'preserve second',
      );
      await original.close();
      final raw = await databaseFactoryFfi.openDatabase(path);
      await raw.update(
        'im_outbox',
        {
          'created_at': base.toIso8601String(),
          'next_retry_at': base.toIso8601String(),
          'attempts': 2,
          'last_error': 'offline',
        },
        where: 'client_message_id = ?',
        whereArgs: ['first'],
      );
      await raw.setVersion(12);
      await raw.close();
      final reopened = open();
      addTearDown(reopened.close);
      final due = await reopened.dueOutbox('account');
      expect(due.map((m) => m.clientMessageId), ['first', 'second']);
      expect(due.first.content, 'preserve me');
      expect(due.first.mentionedMemberIds, ['other']);
      expect(due.first.attempts, 2);
      expect(await reopened.dueOutbox('another-account'), isEmpty);
      expect(await reopened.readMessages('account', 'group'), hasLength(2));
    },
  );
}
