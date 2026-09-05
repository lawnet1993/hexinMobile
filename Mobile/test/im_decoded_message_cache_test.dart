import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_decoded_message_cache.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'expanding history does not decrypt the unchanged window again',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ai-uat-row-decode-',
      );
      final cipher = _CountingCipher();
      final store = ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => '${directory.path}/messages.db',
        cipher: cipher,
      );
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });
      await store.mergeMessages('account-a', 'group', [
        for (var i = 1; i <= 510; i++) _message(i),
      ]);
      final recent = await store.readMessages('account-a', 'group', limit: 80);
      expect(recent.first.sequence, 431);
      final firstCost = cipher.reveals;
      expect(firstCost, greaterThan(0));
      await store.readAdjacentOlderMessages(
        'account-a',
        'group',
        beforeSequence: 431,
      );
      final loadedCost = cipher.reveals;
      expect(loadedCost, firstCost * 2);
      final expanded = await store.readMessages(
        'account-a',
        'group',
        limit: 160,
      );
      expect(expanded.first.sequence, 351);
      expect(expanded.last.sequence, 510);
      expect(
        cipher.reveals,
        loadedCost,
        reason: 'both pages are already decrypted',
      );
    },
  );

  test('fresh SQL edits and computed receipts invalidate without timestamp changes', () async {
    final f = await _fixture();
    await f.store.mergeMessages('account-a', 'group', [_message(1)]);
    final original = (await f.read()).single;
    final stamp = (await f.row())['updated_at'];
    await f.patch({'content': await f.cipher.protect('account-a', 'Edited')});
    expect((await f.row())['updated_at'], stamp);
    final edited = (await f.read()).single;
    expect(edited.content, 'Edited');
    expect(identical(edited, original), isFalse);
    expect(edited.hasRecipientRead, isFalse);
    await f.store.recordMessageReadReceipt(
      'account-a',
      const ImMessageReadReceipt(
        conversationId: 'group',
        messageId: 'message-1',
        sequence: 1,
        readCount: 1,
        totalRecipientCount: 1,
        isReadByAll: true,
        peerRead: true,
        readers: [],
      ),
    );
    expect((await f.row())['updated_at'], stamp);
    expect((await f.read()).single.hasRecipientRead, isTrue);
    await f.patch({
      'recalled_at': '2026-09-03T01:00:00Z',
      'local_status': 'failed',
      'last_error': 'Synthetic failure',
    });
    final recalled = (await f.read()).single;
    expect(recalled.recalledAt?.toUtc(), DateTime.utc(2026, 9, 3, 1));
    expect(recalled.localStatus, ImLocalMessageStatus.failed);
    expect(recalled.lastError, 'Synthetic failure');
    await f.patch({'is_deleted': 1});
    expect(await f.read(), isEmpty);
    expect(
      await f.store.readAdjacentOlderMessages(
        'account-a',
        'group',
        beforeSequence: 2,
      ),
      isEmpty,
    );
    await f.patch({'is_deleted': 0});
    expect((await f.read()).single.recalledAt, recalled.recalledAt);
    await f.db.delete('im_messages');
    expect(await f.read(), isEmpty);
  });

  test('media mention reply changes are fresh and cached nested lists are immutable', () async {
    final f = await _fixture();
    await f.store.mergeMessages('account-a', 'group', [_message(1)]);
    await f.read();
    final values = <String, Object?>{
      'images_json': [
        {'url': 'synthetic-image', 'width': 12, 'height': 34},
      ],
      'media_attachments_json': [
        {'name': 'synthetic.txt', 'url': 'synthetic-file', 'size': 42},
      ],
      'mentions_json': [
        {'userId': 'peer', 'displayName': 'Peer'},
      ],
      'reply_to_json': {
        'messageId': 'reply-id',
        'senderId': 'peer',
        'content': 'Reply',
      },
    };
    for (final entry in values.entries) {
      await f.patch({
        entry.key: await f.cipher.protect('account-a', jsonEncode(entry.value)),
      });
    }
    final result = await f.read();
    final message = result.single;
    expect(message.images, hasLength(1));
    expect(message.attachments, hasLength(1));
    expect(message.mentions, hasLength(1));
    expect(message.replyTo?.messageId, 'reply-id');
    expect(() => message.images.clear(), throwsUnsupportedError);
    expect(() => message.attachments.clear(), throwsUnsupportedError);
    expect(() => message.mentions.clear(), throwsUnsupportedError);
    result.clear();
    expect(identical((await f.read()).single, message), isTrue);
  });

  test(
    'tamper and cross-account ciphertext fail even when message ID was cached',
    () async {
      final f = await _fixture();
      await f.store.mergeMessages('account-a', 'group', [
        _message(1, content: 'A'),
      ]);
      await f.store.mergeMessages('account-b', 'group', [
        _message(1, content: 'B'),
      ]);
      expect((await f.read()).single.content, 'A');
      expect(
        (await f.store.readMessages('account-b', 'group')).single.content,
        'B',
      );
      final encryptedA = (await f.row())['content'];
      await f.db.update(
        'im_messages',
        {'content': encryptedA},
        where: 'account_id = ?',
        whereArgs: ['account-b'],
      );
      await expectLater(
        f.store.readMessages('account-b', 'group'),
        throwsA(anything),
      );
      await f.db.update(
        'im_messages',
        {'content': await f.cipher.protect('account-b', 'Repaired B')},
        where: 'account_id = ?',
        whereArgs: ['account-b'],
      );
      expect(
        (await f.store.readMessages('account-b', 'group')).single.content,
        'Repaired B',
      );
      final tampered = '${'$encryptedA'.substring(0, '$encryptedA'.length - 6)}AAAAAA';
      await f.patch({'content': tampered});
      await expectLater(f.read(), throwsA(anything));
      await f.patch({'content': encryptedA});
      expect((await f.read()).single.content, 'A');
    },
  );

  test(
    'independent stores do not share decoded values and close clears retention',
    () async {
      final a = await _fixture();
      final b = await _fixture();
      await a.store.mergeMessages('account-a', 'group', [
        _message(1, content: 'Test'),
      ]);
      await b.store.mergeMessages('account-a', 'group', [
        _message(1, content: 'Other environment'),
      ]);
      expect((await a.read()).single.content, 'Test');
      expect((await b.read()).single.content, 'Other environment');
      expect(a.cache.entryCount, 1);
      await a.store.close();
      expect(a.cache.entryCount, 0);
    },
  );

  test('identical concurrent rows coalesce and every column participates in equality', () async {
    final cache = ImDecodedMessageCache();
    final pending = Completer<ImMessage>();
    var calls = 0;
    var hits = 0;
    final row = _row(1);
    Future<ImMessage> read() => cache.read(
      'a',
      row,
      generation: cache.generation,
      decode: () {
        calls++;
        return pending.future;
      },
      onReuse: () => hits++,
    );
    final first = read();
    final second = read();
    expect(calls, 1);
    expect(hits, 1);
    pending.complete(_message(1));
    expect(identical(await first, await second), isTrue);
    // Mutating the caller's row cannot alter the cached snapshot.
    row['recipient_read'] = 1;
    await read();
    expect(calls, 2);
    row['new_column'] = null;
    await read();
    expect(calls, 3);
    row.remove('new_column');
    await read();
    expect(calls, 4);
  });

  test('LRU entry and exact source-character budgets are enforced; oversized rows still decode', () async {
    final cache = ImDecodedMessageCache(maxEntries: 2, maxSourceCharacters: 12);
    var calls = 0;
    Future<ImMessage> read(int id, {String content = 'ab'}) => cache.read(
      'a',
      _row(id, content: content),
      generation: cache.generation,
      decode: () async {
        calls++;
        return _message(id);
      },
    );
    await read(1);
    await read(2);
    await read(1);
    await read(3);
    expect(calls, 3);
    expect(cache.entryCount, 2);
    expect(cache.sourceCharacters, 8); // id + conversation + two content chars.
    await read(2);
    expect(calls, 4, reason: 'least recently used row was evicted');
    await read(4, content: '12345678');
    expect(cache.entryCount, 1);
    expect(cache.sourceCharacters, 10);
    await read(5, content: '12345678901234567890');
    await read(5, content: '12345678901234567890');
    expect(calls, 7);
    expect(cache.entryCount, 1);
    expect(cache.sourceCharacters, 10);
  });

  test('account and conversation keys cannot reuse each other', () async {
    final cache = ImDecodedMessageCache();
    var calls = 0;
    for (final scope in [('a', 'g'), ('b', 'g'), ('a', 'h')]) {
      await cache.read(
        scope.$1,
        {..._row(1), 'conversation_id': scope.$2},
        generation: cache.generation,
        decode: () async {
          calls++;
          return _message(1);
        },
      );
    }
    expect(calls, 3);
    expect(cache.entryCount, 3);
  });

  test('clear prevents pending decode and stale query generation from repopulating', () async {
    final cache = ImDecodedMessageCache();
    final oldGeneration = cache.generation;
    final pending = Completer<ImMessage>();
    final first = cache.read(
      'a',
      _row(1),
      generation: oldGeneration,
      decode: () => pending.future,
    );
    expect(cache.entryCount, 1);
    cache.clear();
    pending.complete(_message(1));
    await first;
    await cache.read(
      'a',
      _row(2),
      generation: oldGeneration,
      decode: () async => _message(2),
    );
    expect(cache.entryCount, 0);
    expect(cache.sourceCharacters, 0);
    await cache.read(
      'a',
      _row(2),
      generation: cache.generation,
      decode: () async => _message(2),
    );
    expect(cache.entryCount, 1);
  });

  test(
    'failed decode is retried; late old failure cannot evict new row',
    () async {
      final cache = ImDecodedMessageCache();
      final old = Completer<ImMessage>();
      final first = cache.read(
        'a',
        _row(1),
        generation: cache.generation,
        decode: () => old.future,
      );
      final failed = expectLater(first, throwsStateError);
      final fresh = await cache.read(
        'a',
        _row(1, content: 'new'),
        generation: cache.generation,
        decode: () async => _message(1, content: 'new'),
      );
      old.completeError(StateError('synthetic decode failure'));
      await failed;
      expect(cache.entryCount, 1);
      expect(
        await cache.read(
          'a',
          _row(1, content: 'new'),
          generation: cache.generation,
          decode: () => throw StateError('must be cached'),
        ),
        same(fresh),
      );
      cache.clear();
      await expectLater(
        cache.read(
          'a',
          _row(1),
          generation: cache.generation,
          decode: () => throw StateError('synthetic'),
        ),
        throwsStateError,
      );
      expect(cache.entryCount, 0);
      expect(cache.sourceCharacters, 0);
      await cache.read(
        'a',
        _row(1),
        generation: cache.generation,
        decode: () async => _message(1),
      );
      expect(cache.entryCount, 1);
    },
  );

  test('production store provider clears plaintext retention on account switch and logout', () async {
    final cache = ImDecodedMessageCache();
    final container = ProviderContainer.test(
      overrides: [
        collaborationAccountScopeProvider.overrideWith(
          (ref) => ref.watch(_accountProvider),
        ),
        imDecodedMessageCacheProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    container.read(imLocalStoreProvider);
    for (final next in ['account-b', '']) {
      await cache.read(
        'account-a',
        _row(1),
        generation: cache.generation,
        decode: () async => _message(1),
      );
      expect(cache.entryCount, 1);
      container.read(_accountProvider.notifier).change(next);
      await container.pump();
      expect(cache.entryCount, 0);
    }
  });
}

final _accountProvider = NotifierProvider<_Account, String>(_Account.new);

class _Account extends Notifier<String> {
  @override
  String build() => 'account-a';
  void change(String value) => state = value;
}

Map<String, Object?> _row(int id, {String content = 'ab'}) => {
  'id': '$id',
  'conversation_id': 'g',
  'content': content,
  'recipient_read': 0,
};

Future<_Fixture> _fixture() async {
  final directory = await Directory.systemTemp.createTemp('ai-uat-row-safety-');
  final file = '${directory.path}/messages.db';
  final cipher = _CountingCipher();
  final cache = ImDecodedMessageCache();
  final store = ImLocalStore(
    factory: databaseFactoryFfi,
    pathResolver: () async => file,
    cipher: cipher,
    decodedMessageCache: cache,
  );
  await store.readMessages('account-a', 'group');
  final db = await databaseFactoryFfi.openDatabase(file);
  addTearDown(() async {
    await store.close();
    await db.close();
    await directory.delete(recursive: true);
  });
  return _Fixture(store, db, cipher, cache);
}

class _Fixture {
  _Fixture(this.store, this.db, this.cipher, this.cache);
  final ImLocalStore store;
  final Database db;
  final _CountingCipher cipher;
  final ImDecodedMessageCache cache;
  Future<List<ImMessage>> read() => store.readMessages('account-a', 'group');
  Future<Map<String, Object?>> row() async => (await db.query(
    'im_messages',
    where: 'account_id = ?',
    whereArgs: ['account-a'],
  )).single;
  Future<int> patch(Map<String, Object?> values) => db.update(
    'im_messages',
    values,
    where: 'account_id = ? AND id = ?',
    whereArgs: ['account-a', 'message-1'],
  );
}

ImMessage _message(int sequence, {String content = 'Synthetic message'}) =>
    ImMessage(
      id: 'message-$sequence',
      conversationId: 'group',
      sequence: sequence,
      senderId: 'sender',
      content: content,
      kind: 'text',
      createdAt: DateTime.utc(2026, 9, 3, 0, 0, sequence),
    );

class _CountingCipher implements ImCacheCipher {
  final delegate = AesGcmImCacheCipher(
    (account) async => List<int>.filled(32, account == 'account-a' ? 17 : 29),
  );
  int reveals = 0;
  @override
  bool get isEnabled => delegate.isEnabled;
  @override
  bool isProtected(String value) => delegate.isProtected(value);
  @override
  Future<String> protect(String accountId, String value) =>
      delegate.protect(accountId, value);
  @override
  Future<String> reveal(String accountId, String value) {
    if (isProtected(value)) reveals++;
    return delegate.reveal(accountId, value);
  }
}
