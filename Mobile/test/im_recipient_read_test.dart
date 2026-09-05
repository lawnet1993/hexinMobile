import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late ImLocalStore store;
  ImLocalStore open() => ImLocalStore(
    factory: databaseFactoryFfi,
    pathResolver: () async => '${directory.path}/receipts.db',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('im-recipient-read-');
    store = open();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  Future<void> event(
    String reader,
    int sequence, {
    String conversation = 'group',
    String account = 'account-a',
    int eventSequence = 1,
  }) => store.applySyncBatch(
    accountId: account,
    deviceId: 'mobile-a',
    bootstrap: _bootstrap,
    events: [
      ImSyncEvent(
        sequence: eventSequence,
        id: 'event-$eventSequence',
        type: 'conversation.read',
        createdAt: DateTime.utc(2026, 9, 2),
        payloadJson: jsonEncode({
          'conversationId': conversation,
          'readerId': reader,
          'sequence': sequence,
        }),
      ),
    ],
  );
  Future<List<bool>> flags([
    String account = 'account-a',
    String conversation = 'group',
  ]) async => (await store.readMessages(
    account,
    conversation,
  )).map((m) => m.hasRecipientRead).toList();

  test('permission and own read never imply recipient reading', () async {
    await store.mergeMessages('account-a', 'group', [_message(1), _message(2)]);
    expect(await flags(), [false, false]);
    await event('self-member', 2);
    await event('account-a', 2, eventSequence: 2);
    await event('', 2, eventSequence: 3);
    expect(await flags(), [false, false]);
    expect(
      (await store.readBootstrap('account-a'))!
          .conversations
          .single
          .lastReadSequence,
      2,
    );
  });

  test(
    'peer read is monotonic and only covers acknowledged sequences',
    () async {
      await store.mergeMessages('account-a', 'group', [
        _message(1),
        _message(2),
        _message(3),
      ]);
      await event('peer', 2);
      expect(await flags(), [true, true, false]);
      expect(
        (await store.readBootstrap('account-a'))!
            .conversations
            .single
            .lastReadSequence,
        0,
      );
      await event('peer', 1, eventSequence: 2);
      await event('peer', 2);
      expect(await flags(), [true, true, false]);
      final older = await store.readAdjacentOlderMessages(
        'account-a',
        'group',
        beforeSequence: 3,
      );
      expect(older.map((m) => m.hasRecipientRead), [true, true]);
    },
  );

  test(
    'read before message survives replay and cold reopen before ACK',
    () async {
      await event('peer', 2);
      expect(await store.lastAckedEventSequence('account-a', 'mobile-a'), 0);
      await store.close();
      store = open();
      await event('peer', 2);
      await store.mergeMessages('account-a', 'group', [
        _message(1),
        _message(2),
        _message(3),
      ]);
      expect(await flags(), [true, true, false]);
      await store.mergeMessages('account-a', 'group', [_message(2)]);
      expect(await flags(), [true, true, false]);
    },
  );

  test('recipient read is isolated by account and conversation', () async {
    await store.mergeMessages('account-a', 'group', [_message(1)]);
    await store.mergeMessages('account-b', 'group', [_message(1)]);
    await store.mergeMessages('account-a', 'other', [
      _message(1, conversation: 'other'),
    ]);
    await event('peer', 1);
    expect(await flags(), [true]);
    expect(await flags('account-b'), [false]);
    expect(await flags('account-a', 'other'), [false]);
  });

  test(
    'explicit receipt records only its message and persists positive evidence',
    () async {
      await store.mergeMessages('account-a', 'group', [
        _message(1),
        _message(2),
      ]);
      await store.recordMessageReadReceipt('account-a', _receipt(1, 0));
      expect(await flags(), [false, false]);
      await store.recordMessageReadReceipt('account-a', _receipt(1, 1));
      await store.recordMessageReadReceipt('account-a', _receipt(1, 0));
      await store.close();
      store = open();
      expect(await flags(), [true, false]);
      await store.mergeMessages('account-a', 'group', [_message(1)]);
      expect(await flags(), [true, false]);
    },
  );

  test(
    'empty recipients and local pending messages are not marked read',
    () async {
      await store.mergeMessages('account-a', 'group', [
        _message(0),
        _message(1),
      ]);
      await store.recordMessageReadReceipt(
        'account-a',
        _receipt(1, 0, all: true, total: 0),
      );
      expect(await flags(), [false, false]);
      await event('peer', 10);
      expect(await flags(), [true, false]);
    },
  );
}

ImMessage _message(int seq, {String conversation = 'group'}) => ImMessage(
  id: '$conversation-$seq',
  conversationId: conversation,
  sequence: seq,
  senderId: 'self-member',
  content: 'receipt test $seq',
  kind: 'text',
  createdAt: DateTime.utc(2026, 9, 2),
);
ImMessageReadReceipt _receipt(
  int seq,
  int count, {
  bool all = false,
  int total = 2,
}) => ImMessageReadReceipt(
  conversationId: 'group',
  messageId: 'group-$seq',
  sequence: seq,
  readCount: count,
  totalRecipientCount: total,
  isReadByAll: all,
  peerRead: false,
  readers: const [],
);
const _bootstrap = ImBootstrap(
  currentMember: ImMember(
    id: 'self-member',
    username: 'self',
    displayName: 'Self',
    isOnline: true,
  ),
  contacts: [],
  conversations: [
    ImConversation(
      id: 'group',
      type: 'group',
      title: 'Test group',
      preview: '',
      updatedAt: null,
      unreadCount: 2,
      lastMessageSequence: 3,
    ),
  ],
);
