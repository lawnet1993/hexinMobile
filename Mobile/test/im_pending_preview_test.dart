import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_outbox_file_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/messages_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _queuedAt = DateTime.utc(2026, 9, 3, 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'pending text updates list order without fabricating server state',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('a', _bootstrap());
      await store.replaceBootstrap('b', _bootstrap());
      await _text(store, 'one', 'AI-UAT-pending');
      final result = (await store.readBootstrap('a'))!;
      expect(result.conversations.map((c) => c.id), [
        'pinned',
        'group',
        'direct',
      ]);
      final item = result.conversations[1];
      expect(item.preview, 'AI-UAT-pending');
      expect(item.updatedAt?.toUtc(), _queuedAt);
      expect(item.localPreviewStatus, ImLocalMessageStatus.pending);
      expect(item.type, 'group');
      expect(item.isMuted, isTrue);
      expect(item.lastMessageSequence, 11);
      expect(item.lastReadSequence, 8);
      expect(item.unreadCount, 2);
      expect(item.unreadMentionSequences, [10]);
      expect(await store.lastEventSequence('a', 'device'), 0);
      final other = (await store.readBootstrap('b'))!.conversations
          .singleWhere((c) => c.id == 'group');
      expect(other.preview, 'older group');
      expect(other.localPreviewStatus, isNull);
    },
  );

  for (final kind in ['image', 'video', 'audio', 'file', 'contact']) {
    test(
      'pending $kind has a compact preview without reading media bytes',
      () async {
        final store = _store();
        addTearDown(store.close);
        await store.replaceBootstrap('a', _bootstrap());
        final file = ImOutboxStoredFile(
          token: 'fixture-only',
          role: kind == 'image'
              ? 'image'
              : kind == 'file'
              ? 'file'
              : 'media',
          fileName: 'AI-UAT-file.pdf',
          contentType: 'application/octet-stream',
          length: 10,
          sha256: 'fixture',
        );
        if (kind == 'image') {
          await store.enqueueImages(
            accountId: 'a',
            senderId: 'self',
            conversationId: 'group',
            clientMessageId: kind,
            files: [file],
          );
        } else if (kind == 'video' || kind == 'audio') {
          await store.enqueueMedia(
            accountId: 'a',
            senderId: 'self',
            conversationId: 'group',
            clientMessageId: kind,
            kind: kind,
            mediaFile: file,
          );
        } else if (kind == 'file') {
          await store.enqueueAttachment(
            accountId: 'a',
            senderId: 'self',
            conversationId: 'group',
            clientMessageId: kind,
            file: file,
          );
        } else {
          await store.enqueueContactCard(
            accountId: 'a',
            senderId: 'self',
            conversationId: 'group',
            clientMessageId: kind,
            memberId: 'peer',
          );
        }
        final item = (await store.readBootstrap('a'))!.conversations
            .singleWhere((c) => c.id == 'group');
        expect(
          item.preview,
          {
            'image': '[图片]',
            'video': '[视频]',
            'audio': '[语音]',
            'file': '[文件] AI-UAT-file.pdf',
            'contact': '[名片]',
          }[kind],
        );
        expect(item.localPreviewStatus, ImLocalMessageStatus.pending);
        expect(item.lastMessageSequence, 11);
      },
    );
  }

  test(
    'latest local insertion wins ties and failure retry does not reorder it',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('a', _bootstrap());
      await _text(store, 'one', 'first');
      await _text(store, 'two', 'latest');
      await store.markOutboxFailed(
        'a',
        (await store.dueOutbox('a')).last,
        'HTTP 403',
      );
      var item = (await store.readBootstrap('a'))!.conversations
          .singleWhere((c) => c.id == 'group');
      expect(item.preview, 'latest');
      expect(item.localPreviewStatus, ImLocalMessageStatus.failed);
      await store.retryOutboxNow('a', 'one');
      item = (await store.readBootstrap('a'))!.conversations
          .singleWhere((c) => c.id == 'group');
      expect(item.preview, 'latest');
      await store.retryOutboxNow('a', 'two');
      item = (await store.readBootstrap('a'))!.conversations
          .singleWhere((c) => c.id == 'group');
      expect(item.localPreviewStatus, ImLocalMessageStatus.pending);
      expect(item.updatedAt?.toUtc(), _queuedAt);
    },
  );

  test(
    'bootstrap and index refresh do not erase a newer durable pending preview',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('a', _bootstrap());
      await _text(store, 'one', 'AI-UAT-pending');
      await store.replaceBootstrap('a', _bootstrap());
      await store.mergeConversationIndex('a', _bootstrap().conversations);
      final item = (await store.readBootstrap('a'))!.conversations
          .singleWhere((c) => c.id == 'group');
      expect(item.preview, 'AI-UAT-pending');
      expect(item.localPreviewStatus, ImLocalMessageStatus.pending);
      expect(await store.dueOutbox('a'), hasLength(1));
    },
  );

  test('newer remote message remains the preview while older unsent item stays queued', () async {
    final store = _store();
    addTearDown(store.close);
    await store.replaceBootstrap('a', _bootstrap());
    await _text(store, 'one', 'older pending');
    await store.mergeConversationIndex('a', [
      ImConversation(
        id: 'group',
        type: 'group',
        title: '测试群',
        preview: 'new remote',
        updatedAt: _queuedAt.add(const Duration(minutes: 1)),
        unreadCount: 3,
        lastMessageSequence: 12,
        lastReadSequence: 8,
      ),
    ]);
    final item = (await store.readBootstrap('a'))!.conversations
        .singleWhere((c) => c.id == 'group');
    expect(item.preview, 'new remote');
    expect(item.localPreviewStatus, isNull);
    expect(item.unreadCount, 3);
    expect(await store.dueOutbox('a'), hasLength(1));
  });

  test(
    'confirmation removes local status and duplicate confirmation stays unique',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('a', _bootstrap());
      await _text(store, 'one', 'queued');
      expect(
        (await store.readBootstrap('a'))!.conversations
            .singleWhere((c) => c.id == 'group')
            .localPreviewStatus,
        ImLocalMessageStatus.pending,
      );
      final confirmed = ImMessage(
        id: 'server-one',
        kind: 'text',
        conversationId: 'group',
        sequence: 12,
        senderId: 'self',
        clientMessageId: 'one',
        content: 'confirmed',
        createdAt: _queuedAt.add(const Duration(seconds: 1)),
      );
      await store.markOutboxSent('a', 'one', confirmed);
      await store.markOutboxSent('a', 'one', confirmed);
      final item = (await store.readBootstrap('a'))!.conversations
          .singleWhere((c) => c.id == 'group');
      expect(item.preview, 'confirmed');
      expect(item.localPreviewStatus, isNull);
      expect(item.lastMessageSequence, 12);
      expect(item.unreadCount, 2);
      expect(await store.readMessages('a', 'group'), hasLength(1));
      expect(await store.dueOutbox('a'), isEmpty);
    },
  );

  test('partial confirmation preserves the later pending preview', () async {
    final store = _store();
    addTearDown(store.close);
    await store.replaceBootstrap('a', _bootstrap());
    await _text(store, 'one', 'first');
    await _text(store, 'two', 'latest pending');
    await store.markOutboxSent(
      'a',
      'one',
      ImMessage(
        id: 'server-one',
        kind: 'text',
        conversationId: 'group',
        sequence: 12,
        senderId: 'self',
        clientMessageId: 'one',
        content: 'first',
        createdAt: _queuedAt.add(const Duration(minutes: 2)),
      ),
    );
    final item = (await store.readBootstrap('a'))!.conversations
        .singleWhere((c) => c.id == 'group');
    expect(item.preview, 'latest pending');
    expect(item.localPreviewStatus, ImLocalMessageStatus.pending);
    expect(item.lastMessageSequence, 12);
  });

  test(
    'older failed send cannot replace a later confirmed local preview',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('a', _bootstrap());
      await _text(store, 'one', 'older failed');
      await store.markOutboxFailed(
        'a',
        (await store.dueOutbox('a')).single,
        'HTTP 403',
      );
      await _text(store, 'two', 'later confirmed');
      await store.markOutboxSent(
        'a',
        'two',
        ImMessage(
          id: 'server-two',
          kind: 'text',
          conversationId: 'group',
          sequence: 12,
          senderId: 'self',
          clientMessageId: 'two',
          content: 'later confirmed',
          createdAt: _queuedAt.add(const Duration(minutes: 2)),
        ),
      );
      final item = (await store.readBootstrap('a'))!.conversations
          .singleWhere((c) => c.id == 'group');
      expect(item.preview, 'later confirmed');
      expect(item.localPreviewStatus, isNull);
      expect(await store.readMessages('a', 'group'), hasLength(2));
    },
  );

  test(
    'sync echo before send response preserves later pending preview',
    () async {
      final store = _store();
      addTearDown(store.close);
      await store.replaceBootstrap('a', _bootstrap());
      await _text(store, 'one', 'first');
      await _text(store, 'two', 'latest pending');
      final echo = ImMessage(
        id: 'server-one',
        kind: 'text',
        conversationId: 'group',
        sequence: 12,
        senderId: 'self',
        clientMessageId: 'one',
        content: 'first',
        createdAt: _queuedAt.add(const Duration(minutes: 2)),
      );
      await store.mergeMessages('a', 'group', [echo, echo]);
      await store.mergeConversationIndex('a', [
        ImConversation(
          id: 'group',
          type: 'group',
          title: '测试群',
          preview: 'first',
          updatedAt: echo.createdAt,
          unreadCount: 2,
          lastMessageSequence: 12,
          lastReadSequence: 8,
        ),
      ]);
      final item = (await store.readBootstrap('a'))!.conversations
          .singleWhere((c) => c.id == 'group');
      expect(item.preview, 'latest pending');
      expect(item.localPreviewStatus, ImLocalMessageStatus.pending);
      expect(await store.readMessages('a', 'group'), hasLength(2));
    },
  );

  test(
    'empty batch forgets confirmation order before SQLite reuses rowids',
    () async {
      var now = _queuedAt;
      final store = _store(clock: () => now);
      addTearDown(store.close);
      await store.replaceBootstrap('a', _bootstrap());
      await _text(store, 'one', 'one');
      await _text(store, 'two', 'two');
      for (final record in [
        (id: 'one', sequence: 12),
        (id: 'two', sequence: 13),
      ]) {
        await store.markOutboxSent(
          'a',
          record.id,
          ImMessage(
            id: 'server-${record.id}',
            kind: 'text',
            conversationId: 'group',
            sequence: record.sequence,
            senderId: 'self',
            clientMessageId: record.id,
            content: record.id,
            createdAt: _queuedAt.add(const Duration(minutes: 2)),
          ),
        );
      }
      now = _queuedAt.add(const Duration(minutes: 3));
      await _text(store, 'three', 'new batch');
      final item = (await store.readBootstrap('a'))!.conversations
          .singleWhere((c) => c.id == 'group');
      expect(item.preview, 'new batch');
      expect(item.localPreviewStatus, ImLocalMessageStatus.pending);
      expect(item.lastMessageSequence, 13);
    },
  );

  test('encrypted pending preview survives restart without rewriting server projection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'im-pending-preview-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final dbPath = '${directory.path}/im.db';
    final cipher = AesGcmImCacheCipher((_) async => List<int>.filled(32, 8));
    final store = _store(path: dbPath, cipher: cipher);
    await store.replaceBootstrap('a', _bootstrap());
    await _text(store, 'one', 'AI-UAT-durable-pending');
    await store.close();
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    final row = (await db.query(
      'im_conversations',
      where: 'account_id = ? AND id = ?',
      whereArgs: ['a', 'group'],
    )).single;
    expect(row['preview'], startsWith('enc:v1:'));
    expect(await cipher.reveal('a', row['preview'] as String), 'older group');
    expect(row['last_message_sequence'], 11);
    final pending = (await db.query('im_outbox')).single;
    expect(pending['content'], startsWith('enc:v1:'));
    expect(pending['content'], isNot(contains('AI-UAT-durable-pending')));
    await db.close();
    final reopened = _store(path: dbPath, cipher: cipher);
    addTearDown(reopened.close);
    final item = (await reopened.readBootstrap('a'))!.conversations
        .singleWhere((c) => c.id == 'group');
    expect(item.preview, 'AI-UAT-durable-pending');
    expect(item.localPreviewStatus, ImLocalMessageStatus.pending);
  });

  for (final status in [
    ImLocalMessageStatus.pending,
    ImLocalMessageStatus.failed,
  ]) {
    testWidgets('compact list shows $status separately from unread', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final data = ImBootstrap(
        currentMember: _bootstrap().currentMember,
        contacts: const [],
        conversations: [
          ImConversation(
            id: 'group',
            type: 'group',
            title: '测试群',
            preview: '[视频]',
            updatedAt: _queuedAt,
            unreadCount: 2,
            localPreviewStatus: status,
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imBootstrapProvider.overrideWith((ref) async => data),
            imRealtimeAvailabilityProvider.overrideWithValue(
              ImRealtimeAvailability.unavailable,
            ),
          ],
          child: const MaterialApp(home: MessagesPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('[视频]'), findsOneWidget);
      expect(
        find.byTooltip(status == ImLocalMessageStatus.failed ? '发送失败' : '等待发送'),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

ImLocalStore _store({
  String path = inMemoryDatabasePath,
  ImCacheCipher cipher = const PlainImCacheCipher(),
  DateTime Function()? clock,
}) => ImLocalStore(
  factory: databaseFactoryFfi,
  pathResolver: () async => path,
  cipher: cipher,
  clock: clock ?? () => _queuedAt,
);
Future<ImMessage> _text(ImLocalStore store, String id, String content) =>
    store.enqueueText(
      accountId: 'a',
      senderId: 'self',
      conversationId: 'group',
      clientMessageId: id,
      content: content,
    );
ImBootstrap _bootstrap() => ImBootstrap(
  currentMember: const ImMember(
    id: 'self',
    username: 'test03',
    displayName: '测试用户',
    isOnline: false,
  ),
  contacts: const [],
  conversations: [
    ImConversation(
      id: 'group',
      type: 'group',
      title: '测试群',
      preview: 'older group',
      updatedAt: _queuedAt.subtract(const Duration(minutes: 2)),
      unreadCount: 2,
      lastMessageSequence: 11,
      lastReadSequence: 8,
      unreadMentionSequences: const [10],
      isMuted: true,
    ),
    ImConversation(
      id: 'direct',
      type: 'direct',
      title: '测试联系人',
      preview: 'direct unchanged',
      updatedAt: _queuedAt.subtract(const Duration(minutes: 1)),
      unreadCount: 0,
    ),
    ImConversation(
      id: 'pinned',
      type: 'group',
      title: '置顶测试群',
      preview: 'pinned',
      updatedAt: _queuedAt.subtract(const Duration(days: 1)),
      unreadCount: 0,
      isPinned: true,
    ),
  ],
);
