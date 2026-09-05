import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'send confirmation updates only its own conversation without a sync echo',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('account-a', _bootstrap());
      await store.replaceBootstrap('account-b', _bootstrap());
      await store.enqueueText(
        accountId: 'account-a',
        senderId: 'member-a',
        conversationId: 'group',
        clientMessageId: 'send-1',
        content: 'new group message',
      );
      await store.markOutboxSent('account-a', 'send-1', _message(12));

      final bootstrap = (await store.readBootstrap('account-a'))!;
      final group = bootstrap.conversations.first;
      expect(group.id, 'group');
      expect(group.type, 'group');
      expect(group.preview, 'new group message');
      expect(group.lastMessageSequence, 12);
      expect(group.updatedAt?.toUtc(), _message(12).createdAt);
      expect(group.unreadCount, 2);
      expect(group.lastReadSequence, 8);
      expect(group.unreadMentionSequences, [10]);
      expect(bootstrap.conversations.last.preview, 'direct unchanged');
      expect(
        (await store.readBootstrap('account-b'))!.conversations
            .singleWhere((c) => c.id == 'group')
            .preview,
        'older group',
      );
      expect(await store.dueOutbox('account-a'), isEmpty);
      expect(await store.readMessages('account-a', 'group'), hasLength(1));
    },
  );

  test(
    'older or duplicate confirmations do not roll back a newer preview',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('account-a', _bootstrap());
      await store.markOutboxSent(
        'account-a',
        'send-1',
        _message(13, content: 'latest'),
      );
      await store.markOutboxSent(
        'account-a',
        'send-2',
        _message(12, content: 'late older', clientId: 'send-2'),
      );
      await store.markOutboxSent(
        'account-a',
        'send-1',
        _message(13, content: 'latest'),
      );
      final group = (await store.readBootstrap('account-a'))!
          .conversations
          .first;
      expect(group.preview, 'latest');
      expect(group.lastMessageSequence, 13);
      expect(group.unreadCount, 2);
      expect(await store.readMessages('account-a', 'group'), hasLength(2));
    },
  );

  test('confirmed preview persists encrypted across restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'im-sent-projection-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final databasePath = '${directory.path}/im.db';
    final cipher = AesGcmImCacheCipher((_) async => List<int>.filled(32, 7));
    final store = _store(path: databasePath, cipher: cipher);
    await store.replaceBootstrap('account-a', _bootstrap());
    await store.markOutboxSent('account-a', 'send-1', _message(12));
    await store.close();

    final database = await databaseFactoryFfi.openDatabase(databasePath);
    final row = (await database.query(
      'im_conversations',
      where: 'account_id = ? AND id = ?',
      whereArgs: ['account-a', 'group'],
    )).single;
    expect(row['preview'], startsWith('enc:v1:'));
    expect(row['preview'], isNot(contains('new group message')));
    await database.close();
    final reopened = _store(path: databasePath, cipher: cipher);
    try {
      final group = (await reopened.readBootstrap('account-a'))!
          .conversations
          .first;
      expect(group.preview, 'new group message');
      expect(group.lastReadSequence, 8);
      expect(await reopened.dueOutbox('account-a'), isEmpty);
    } finally {
      await reopened.close();
    }
  });
}

ImLocalStore _store({
  String path = inMemoryDatabasePath,
  ImCacheCipher cipher = const PlainImCacheCipher(),
}) => ImLocalStore(
  factory: databaseFactoryFfi,
  pathResolver: () async => path,
  cipher: cipher,
);

ImBootstrap _bootstrap() => ImBootstrap(
  currentMember: const ImMember(
    id: 'member-a',
    username: 'test',
    displayName: 'Test',
    isOnline: true,
  ),
  contacts: const [],
  conversations: [
    ImConversation(
      id: 'group',
      type: 'group',
      title: 'Test group',
      preview: 'older group',
      updatedAt: DateTime.utc(2026, 9, 2, 8),
      unreadCount: 2,
      lastMessageSequence: 11,
      lastReadSequence: 8,
      unreadMentionSequences: const [10],
    ),
    ImConversation(
      id: 'direct',
      type: 'direct',
      title: 'Test direct',
      preview: 'direct unchanged',
      updatedAt: DateTime.utc(2026, 9, 2, 8, 1),
      unreadCount: 0,
    ),
  ],
);

ImMessage _message(
  int sequence, {
  String content = 'new group message',
  String clientId = 'send-1',
}) => ImMessage(
  id: 'message-$sequence',
  sequence: sequence,
  senderId: 'member-a',
  conversationId: 'group',
  clientMessageId: clientId,
  content: content,
  kind: 'text',
  createdAt: DateTime.utc(2026, 9, 2, 8, 2, sequence),
);
