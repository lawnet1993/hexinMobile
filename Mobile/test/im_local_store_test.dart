import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_outbox_file_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late ImLocalStore store;

  setUp(() {
    store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
    );
  });

  tearDown(() => store.close());

  test(
    'member last-seen survives directory and paged member cache writes',
    () async {
      final seen = DateTime.utc(2026, 9, 3, 1, 2).toLocal();
      final member = ImMember(
        id: 'peer',
        username: 'peer',
        displayName: 'Peer',
        isOnline: false,
        lastSeenAt: seen,
      );
      await store.replaceBootstrap(
        'a',
        ImBootstrap(
          currentMember: ImMember(
            id: 'current',
            username: 'current',
            displayName: 'Current',
            isOnline: false,
            lastSeenAt: seen,
          ),
          contacts: [member],
          conversations: const [],
        ),
      );
      expect((await store.readBootstrap('a'))!.currentMember.lastSeenAt, seen);
      expect(
        (await store.readBootstrap('a'))!.contacts.single.lastSeenAt,
        seen,
      );
      await store.replaceConversationMembers('a', 'group', [member]);
      expect(
        (await store.readConversationMembers('a', 'group')).single.lastSeenAt,
        seen,
      );
      await store.mergeConversationMembers('b', 'group', [
        member,
      ], positionOffset: 50);
      expect(
        (await store.readConversationMembers('b', 'group')).single.lastSeenAt,
        seen,
      );
      await store.replaceConversationMembers('a', 'group', const []);
      expect(
        (await store.readConversationMembers('b', 'group')).single.lastSeenAt,
        seen,
      );
    },
  );

  test(
    'version 13 member caches migrate without losing messages or outbox',
    () async {
      final directory = await Directory.systemTemp.createTemp('im-member-v13-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/cache.sqlite';
      ImLocalStore open() => ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => path,
      );
      final initial = open();
      await initial.replaceBootstrap('account-a', _bootstrap('a', unread: 3));
      await initial.replaceBootstrap('account-b', _bootstrap('b', unread: 1));
      await initial.replaceConversationMembers(
        'account-a',
        'conversation-a',
        _bootstrap('a', unread: 3).contacts,
      );
      await initial.enqueueText(
        accountId: 'account-a',
        senderId: 'member-a',
        conversationId: 'conversation-a',
        clientMessageId: 'migration-pending',
        content: 'fixture draft',
      );
      await initial.close();
      final legacy = await databaseFactoryFfi.openDatabase(path);
      await legacy.execute('ALTER TABLE im_members DROP COLUMN last_seen_at');
      await legacy.execute(
        'ALTER TABLE im_conversation_members DROP COLUMN last_seen_at',
      );
      await legacy.setVersion(13);
      await legacy.close();
      final migrated = open();
      try {
        expect(
          (await migrated.readBootstrap('account-a'))!
              .conversations
              .single
              .unreadCount,
          3,
        );
        expect(
          (await migrated.readBootstrap('account-b'))!.currentMember.id,
          'member-b',
        );
        expect(
          (await migrated.readConversationMembers(
            'account-a',
            'conversation-a',
          )).single.lastSeenAt,
          isNull,
        );
        expect(
          (await migrated.readMessages(
            'account-a',
            'conversation-a',
          )).single.clientMessageId,
          'migration-pending',
        );
        final seen = DateTime.utc(2026, 9, 3).toLocal();
        await migrated.mergeConversationMembers('account-a', 'conversation-a', [
          ImMember(
            id: 'contact-a',
            username: 'a',
            displayName: 'A',
            isOnline: false,
            lastSeenAt: seen,
          ),
        ]);
        expect(
          (await migrated.readConversationMembers(
            'account-a',
            'conversation-a',
          )).single.lastSeenAt,
          seen,
        );
      } finally {
        await migrated.close();
      }
      final check = await databaseFactoryFfi.openDatabase(path);
      expect(await check.getVersion(), 15);
      expect(
        (await check.query('im_outbox')).single['client_message_id'],
        'migration-pending',
      );
      await check.close();
    },
  );

  test('bootstrap and messages stay isolated by terminal account', () async {
    await store.replaceBootstrap('account-a', _bootstrap('a', unread: 3));
    await store.replaceBootstrap('account-b', _bootstrap('b', unread: 1));

    final first = await store.readBootstrap('account-a');
    final second = await store.readBootstrap('account-b');

    expect(first?.currentMember.username, 'a');
    expect(first?.conversations.single.unreadCount, 3);
    expect(first?.conversations.single.unreadMentionSequences, [8, 11]);
    expect(second?.currentMember.username, 'b');
    expect(second?.conversations.single.unreadCount, 1);
  });

  test(
    'bootstrap cache preserves permissions and message capabilities',
    () async {
      final bootstrap = ImBootstrap(
        currentMember: const ImMember(
          id: 'member-a',
          username: 'a',
          displayName: 'A',
          isOnline: true,
        ),
        contacts: const [],
        conversations: const [],
        permissions: const ImPermissionSnapshot(
          createGroup: true,
          editMessage: true,
          invite: true,
        ),
        config: const ImClientConfig(
          message: ImMessageConfig(
            reply: false,
            forward: true,
            mentionMember: false,
            mentionAll: true,
          ),
        ),
      );

      await store.replaceBootstrap('account-a', bootstrap);
      final cached = await store.readBootstrap('account-a');

      expect(cached?.permissions.createGroup, isTrue);
      expect(cached?.permissions.editMessage, isTrue);
      expect(cached?.permissions.invite, isTrue);
      expect(cached?.config.message.reply, isFalse);
      expect(cached?.config.message.forward, isTrue);
      expect(cached?.config.message.mentionMember, isFalse);
      expect(cached?.config.message.mentionAll, isTrue);
    },
  );

  test('department directory cache preserves hierarchy per account', () async {
    const departments = [
      ImDepartment(
        id: 'root',
        name: '研发中心',
        code: 'RD',
        parentId: '',
        sortOrder: 1,
      ),
      ImDepartment(
        id: 'child',
        name: '移动产品组',
        code: 'RD-MOBILE',
        parentId: 'root',
        sortOrder: 2,
      ),
    ];

    await store.writeDepartments('account-a', departments);

    final cached = await store.readDepartments('account-a');
    expect(cached, hasLength(2));
    expect(cached.last.parentId, 'root');
    expect(cached.last.code, 'RD-MOBILE');
    expect(await store.readDepartments('account-b'), isEmpty);
  });

  test('outbox persists failed sends and reconciles by client id', () async {
    const clientMessageId = 'client-1';
    await store.enqueueText(
      accountId: 'account-a',
      senderId: 'member-a',
      conversationId: 'conversation-a',
      clientMessageId: clientMessageId,
      content: 'pending body',
    );

    final due = await store.dueOutbox('account-a');
    expect(due, hasLength(1));
    expect(
      (await store.readMessages(
        'account-a',
        'conversation-a',
      )).single.localStatus,
      ImLocalMessageStatus.pending,
    );

    await store.markOutboxSent(
      'account-a',
      clientMessageId,
      ImMessage(
        id: 'server-message',
        conversationId: 'conversation-a',
        sequence: 7,
        senderId: 'member-a',
        clientMessageId: clientMessageId,
        content: 'pending body',
        kind: 'text',
        createdAt: DateTime.utc(2026, 8, 17),
      ),
    );

    expect(await store.dueOutbox('account-a'), isEmpty);
    final messages = await store.readMessages('account-a', 'conversation-a');
    expect(messages, hasLength(1));
    expect(messages.single.id, 'server-message');
    expect(messages.single.sequence, 7);
    expect(messages.single.localStatus, ImLocalMessageStatus.sent);
  });

  test('manual retry makes a failed outbox message immediately due', () async {
    const clientMessageId = 'client-retry';
    await store.enqueueText(
      accountId: 'account-a',
      senderId: 'member-a',
      conversationId: 'conversation-a',
      clientMessageId: clientMessageId,
      content: 'retry body',
    );
    final queued = (await store.dueOutbox('account-a')).single;
    await store.markOutboxFailed('account-a', queued, 'offline');

    expect(await store.dueOutbox('account-a'), isEmpty);
    expect(
      (await store.readMessages(
        'account-a',
        'conversation-a',
      )).single.localStatus,
      ImLocalMessageStatus.failed,
    );

    await store.retryOutboxNow('account-a', clientMessageId);

    expect(await store.dueOutbox('account-a'), hasLength(1));
    expect(
      (await store.readMessages(
        'account-a',
        'conversation-a',
      )).single.localStatus,
      ImLocalMessageStatus.pending,
    );
  });

  test(
    'transient outbox failure remains queued and visually pending',
    () async {
      const clientMessageId = 'client-offline';
      await store.enqueueText(
        accountId: 'account-a',
        senderId: 'member-a',
        conversationId: 'conversation-a',
        clientMessageId: clientMessageId,
        content: 'offline body',
      );
      final queued = (await store.dueOutbox('account-a')).single;

      await store.markOutboxFailed(
        'account-a',
        queued,
        'network unavailable',
        retryScheduled: true,
      );

      expect(await store.dueOutbox('account-a'), isEmpty);
      final message = (await store.readMessages(
        'account-a',
        'conversation-a',
      )).single;
      expect(message.localStatus, ImLocalMessageStatus.pending);
      expect(message.lastError, 'network unavailable');
    },
  );

  test('outbox backoff blocks newer messages to preserve FIFO order', () async {
    for (final item in const [
      (id: 'client-first', content: 'first'),
      (id: 'client-second', content: 'second'),
    ]) {
      await store.enqueueText(
        accountId: 'account-a',
        senderId: 'member-a',
        conversationId: 'conversation-a',
        clientMessageId: item.id,
        content: item.content,
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final initial = await store.dueOutbox('account-a');
    expect(initial.map((item) => item.clientMessageId), [
      'client-first',
      'client-second',
    ]);

    await store.markOutboxFailed(
      'account-a',
      initial.first,
      'network unavailable',
      retryScheduled: true,
    );

    expect(await store.dueOutbox('account-a'), isEmpty);
    await store.retryOutboxNow('account-a', 'client-first');
    expect(
      (await store.dueOutbox('account-a')).map((item) => item.clientMessageId),
      ['client-first', 'client-second'],
    );
  });

  test(
    'outbox backoff is isolated by conversation before applying limit',
    () async {
      for (var index = 0; index < 55; index++) {
        await store.enqueueText(
          accountId: 'account-a',
          senderId: 'member-a',
          conversationId: 'conversation-a',
          clientMessageId: 'blocked-$index',
          content: 'queued',
        );
      }
      final first = (await store.dueOutbox('account-a')).first;
      await store.markOutboxFailed(
        'account-a',
        first,
        'HTTP 503',
        retryScheduled: true,
      );
      await store.enqueueText(
        accountId: 'account-a',
        senderId: 'member-a',
        conversationId: 'conversation-b',
        clientMessageId: 'independent',
        content: 'other conversation',
      );
      expect(
        (await store.dueOutbox('account-a'))
            .map((item) => item.clientMessageId),
        ['independent'],
      );
      expect(await store.dueOutbox('account-b'), isEmpty);
      // Retrying a later item cannot overtake its own conversation's head.
      await store.retryOutboxNow('account-a', 'blocked-54');
      expect(
        (await store.dueOutbox('account-a'))
            .map((item) => item.clientMessageId),
        ['independent'],
      );
    },
  );

  test('AES-GCM cache payloads are account bound and authenticated', () async {
    final cipher = AesGcmImCacheCipher(
      (_) async => List<int>.generate(32, (index) => index),
    );
    final protected = await cipher.protect('account-a', 'sensitive message');

    expect(protected, startsWith('enc:v1:'));
    expect(protected, isNot(contains('sensitive message')));
    expect(await cipher.reveal('account-a', protected), 'sensitive message');
    await expectLater(
      cipher.reveal('account-b', protected),
      throwsA(isA<StateError>()),
    );
  });

  test('sensitive IM payload columns are encrypted at rest', () async {
    final directory = await Directory.systemTemp.createTemp('hexing-im-enc-');
    final databasePath = '${directory.path}${Platform.pathSeparator}im.db';
    final cipher = AesGcmImCacheCipher(
      (_) async => List<int>.generate(32, (index) => 255 - index),
    );
    final encryptedStore = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => databasePath,
      cipher: cipher,
    );
    try {
      await encryptedStore.replaceBootstrap(
        'account-a',
        _bootstrap('a', unread: 1),
      );
      await encryptedStore.writeGroupProfile(
        'account-a',
        const ImGroupProfile(
          conversationId: 'conversation-a',
          title: 'Operations',
          introduction: 'private introduction',
          notice: 'private notice',
        ),
      );
      await encryptedStore.enqueueText(
        accountId: 'account-a',
        senderId: 'member-a',
        conversationId: 'conversation-a',
        clientMessageId: 'encrypted-client',
        content: 'private message body',
      );
    } finally {
      await encryptedStore.close();
    }

    final raw = await databaseFactoryFfi.openDatabase(databasePath);
    try {
      final conversation = (await raw.query(
        'im_conversations',
        columns: ['preview'],
      )).single;
      final message = (await raw.query(
        'im_messages',
        columns: ['content'],
      )).single;
      final outbox = (await raw.query(
        'im_outbox',
        columns: ['content'],
      )).single;
      final profile = (await raw.query(
        'im_group_profiles',
        columns: ['introduction', 'notice'],
      )).single;
      for (final value in [
        conversation['preview'],
        message['content'],
        outbox['content'],
        profile['introduction'],
        profile['notice'],
      ]) {
        expect(value, isA<String>());
        expect(value as String, startsWith('enc:v1:'));
      }
      expect(message['content'], isNot(contains('private message body')));
      expect(
        await cipher.reveal('account-a', conversation['preview'] as String),
        'Preview a',
      );
      expect(await raw.getVersion(), 15);
    } finally {
      await raw.close();
    }

    final reopened = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => databasePath,
      cipher: cipher,
    );
    try {
      expect(
        (await reopened.readBootstrap('account-a'))
            ?.conversations
            .single
            .preview,
        'private message body',
      );
      expect(
        (await reopened.readBootstrap('account-a'))
            ?.conversations.single.localPreviewStatus,
        ImLocalMessageStatus.pending,
      );
      expect(
        (await reopened.readMessages(
          'account-a',
          'conversation-a',
        )).single.content,
        'private message body',
      );
      expect(
        (await reopened.dueOutbox('account-a')).single.content,
        'private message body',
      );
      expect(
        (await reopened.readGroupProfile(
          'account-a',
          'conversation-a',
        ))?.notice,
        'private notice',
      );
    } finally {
      await reopened.close();
      await directory.delete(recursive: true);
    }
  });

  test('queued media metadata is encrypted at rest', () async {
    final directory = await Directory.systemTemp.createTemp(
      'im-media-metadata-',
    );
    final databasePath = '${directory.path}${Platform.pathSeparator}im.db';
    final cipher = AesGcmImCacheCipher(
      (_) async => List<int>.generate(32, (index) => index + 1),
    );
    final secureStore = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => databasePath,
      cipher: cipher,
    );
    const token = 'opaque-media-token';
    try {
      await secureStore.enqueueImages(
        accountId: 'account-a',
        senderId: 'member-a',
        conversationId: 'conversation-a',
        clientMessageId: 'client-image-1',
        files: const [
          ImOutboxStoredFile(
            token: token,
            role: 'image',
            fileName: 'private-image.jpg',
            contentType: 'image/jpeg',
            length: 12,
            sha256: 'digest',
          ),
        ],
      );
      await secureStore.close();

      final raw = await databaseFactoryFfi.openDatabase(databasePath);
      final encrypted =
          (await raw.query(
                'im_outbox',
                columns: ['media_files_json'],
              )).single['media_files_json']
              as String;
      expect(encrypted, startsWith('enc:v1:'));
      expect(encrypted, isNot(contains(token)));
      expect(encrypted, isNot(contains('private-image.jpg')));
      await raw.close();

      final reopened = ImLocalStore(
        factory: databaseFactoryFfi,
        pathResolver: () async => databasePath,
        cipher: cipher,
      );
      final item = (await reopened.dueOutbox('account-a')).single;
      expect(item.mediaFiles.single.token, token);
      expect(item.mediaFiles.single.fileName, 'private-image.jpg');
      await reopened.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('existing plaintext payloads migrate in place on secure open', () async {
    final directory = await Directory.systemTemp.createTemp('hexing-im-plain-');
    final databasePath = '${directory.path}${Platform.pathSeparator}im.db';
    final plainStore = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => databasePath,
    );
    await plainStore.enqueueText(
      accountId: 'account-a',
      senderId: 'member-a',
      conversationId: 'conversation-a',
      clientMessageId: 'legacy-client',
      content: 'legacy plaintext',
    );
    await plainStore.close();

    final secureStore = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => databasePath,
      cipher: AesGcmImCacheCipher(
        (_) async => List<int>.generate(32, (index) => index + 1),
      ),
    );
    try {
      expect(
        (await secureStore.dueOutbox('account-a')).single.content,
        'legacy plaintext',
      );
    } finally {
      await secureStore.close();
    }

    final raw = await databaseFactoryFfi.openDatabase(databasePath);
    try {
      final message =
          (await raw.query(
                'im_messages',
                columns: ['content'],
              )).single['content']
              as String;
      final outbox =
          (await raw.query('im_outbox', columns: ['content'])).single['content']
              as String;
      expect(message, startsWith('enc:v1:'));
      expect(outbox, startsWith('enc:v1:'));
      expect(message, isNot(contains('legacy plaintext')));
      expect(outbox, isNot(contains('legacy plaintext')));
    } finally {
      await raw.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'conversation details are cached per account and conversation',
    () async {
      const member = ImMember(
        id: 'member-detail',
        username: 'term.detail',
        displayName: '详情用户',
        isOnline: true,
        departmentName: '研发部',
        isOrganizationManager: true,
      );
      const profile = ImGroupProfile(
        conversationId: 'conversation-a',
        title: '研发协作群',
        notice: '真实群公告',
        groupNo: 'GROUP-A',
        currentUserRole: 'owner',
      );

      await store.replaceConversationMembers('account-a', 'conversation-a', [
        member,
      ]);
      await store.writeGroupProfile('account-a', profile);

      final members = await store.readConversationMembers(
        'account-a',
        'conversation-a',
      );
      final cachedProfile = await store.readGroupProfile(
        'account-a',
        'conversation-a',
      );
      expect(members.single.displayName, '详情用户');
      expect(members.single.isOrganizationManager, isTrue);
      expect(cachedProfile?.notice, '真实群公告');
      expect(cachedProfile?.currentUserRole, 'owner');
      expect(
        await store.readConversationMembers('account-b', 'conversation-a'),
        isEmpty,
      );
      expect(
        await store.readGroupProfile('account-b', 'conversation-a'),
        isNull,
      );
    },
  );

  test(
    'paged conversation members merge without dropping cached members',
    () async {
      const first = ImMember(
        id: 'member-first',
        username: 'first',
        displayName: '首批成员',
        isOnline: false,
      );
      const second = ImMember(
        id: 'member-second',
        username: 'second',
        displayName: '分页成员',
        isOnline: true,
        avatarKey: 'person',
      );
      await store.replaceConversationMembers('account-a', 'conversation-a', [
        first,
      ]);

      await store.mergeConversationMembers(
        'account-a',
        'conversation-a',
        const [second],
        positionOffset: 50,
      );

      final members = await store.readConversationMembers(
        'account-a',
        'conversation-a',
      );
      expect(members.map((item) => item.id), ['member-first', 'member-second']);
      expect(members.last.avatarKey, 'person');
    },
  );

  test('existing version 1 member cache upgrades through current schema', () async {
    final directory = await Directory.systemTemp.createTemp('hexing-im-v1-');
    final databasePath = '${directory.path}${Platform.pathSeparator}im.db';
    final versionOne = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
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
            is_current INTEGER NOT NULL,
            is_contact INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (account_id, id)
          )
        ''');
          // The original fixture omitted the messages table entirely. Include
          // its base columns so the later message-index migration is exercised.
          await database.execute('''
            CREATE TABLE im_messages (
              account_id TEXT NOT NULL, id TEXT NOT NULL,
              conversation_id TEXT NOT NULL, sequence INTEGER NOT NULL,
              sender_id TEXT NOT NULL, client_message_id TEXT NOT NULL,
              content TEXT NOT NULL, kind TEXT NOT NULL, created_at TEXT,
              recalled_at TEXT, local_status TEXT NOT NULL, last_error TEXT NOT NULL,
              is_deleted INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL,
              PRIMARY KEY (account_id, id)
            )
          ''');
        },
      ),
    );
    await versionOne.insert('im_members', {
      'account_id': 'account-a',
      'id': 'member-a',
      'username': 'term.a',
      'display_name': 'A',
      'is_online': 1,
      'avatar_key': '',
      'avatar_data_url': '',
      'department_id': '',
      'department_name': '',
      'is_current': 1,
      'is_contact': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await versionOne.close();

    final upgraded = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => databasePath,
    );
    try {
      await upgraded.replaceConversationMembers(
        'account-a',
        'conversation-a',
        const [
          ImMember(
            id: 'member-a',
            username: 'term.a',
            displayName: 'A',
            isOnline: true,
          ),
        ],
      );
      expect(
        await upgraded.readConversationMembers('account-a', 'conversation-a'),
        hasLength(1),
      );
    } finally {
      await upgraded.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'attachment and contact card metadata survive cache roundtrip',
    () async {
      const card = ImContactCard(
        memberId: 'member-card',
        username: 'term.card',
        displayName: '联系人卡片',
        departmentName: '研发部',
        isOrganizationManager: true,
      );
      await store.mergeMessages('account-a', 'conversation-a', [
        ImMessage(
          id: 'file-message',
          conversationId: 'conversation-a',
          sequence: 20,
          senderId: 'member-a',
          content: 'report.pdf',
          kind: 'file',
          attachmentName: 'report.pdf',
          attachmentSize: 2048,
          attachmentContentType: 'application/pdf',
          attachmentSha256: 'sha256-value',
          createdAt: DateTime.utc(2026, 8, 17),
        ),
        ImMessage(
          id: 'contact-message',
          conversationId: 'conversation-a',
          sequence: 21,
          senderId: 'member-a',
          content: '联系人卡片',
          kind: 'contact',
          contactCard: card,
          createdAt: DateTime.utc(2026, 8, 17),
        ),
        ImMessage(
          id: 'image-message',
          conversationId: 'conversation-a',
          sequence: 22,
          senderId: 'member-a',
          content: '图片',
          kind: 'image',
          images: const [
            ImMessageImage(
              id: 'image-1',
              fileName: 'device.png',
              size: 4096,
              contentType: 'image/png',
              sha256: 'image-sha256',
            ),
          ],
          createdAt: DateTime.utc(2026, 8, 17),
        ),
        ImMessage(
          id: 'audio-message',
          conversationId: 'conversation-a',
          sequence: 23,
          senderId: 'member-a',
          content: '',
          kind: 'audio',
          attachments: const [
            ImMessageAttachment(
              id: 'media-1',
              type: 'audio',
              fileName: 'notice.wav',
              contentType: 'audio/wav',
              size: 8192,
              sha256: 'media-sha256',
              durationSeconds: 2.5,
            ),
          ],
          createdAt: DateTime.utc(2026, 8, 17),
        ),
      ]);

      final messages = await store.readMessages('account-a', 'conversation-a');
      expect(messages, hasLength(4));
      expect(messages.first.attachmentName, 'report.pdf');
      expect(messages.first.attachmentSize, 2048);
      expect(messages.first.attachmentContentType, 'application/pdf');
      expect(messages.first.attachmentSha256, 'sha256-value');
      expect(messages[1].contactCard?.displayName, '联系人卡片');
      expect(messages[1].contactCard?.departmentName, '研发部');
      expect(messages[1].contactCard?.isOrganizationManager, isTrue);
      expect(messages[2].images.single.fileName, 'device.png');
      expect(messages[2].images.single.contentType, 'image/png');
      expect(messages.last.attachments.single.fileName, 'notice.wav');
      expect(messages.last.attachments.single.durationSeconds, 2.5);
    },
  );

  test(
    'message window reads only the newest requested rows in order',
    () async {
      await store.mergeMessages(
        'account-a',
        'conversation-a',
        List.generate(
          200,
          (index) => ImMessage(
            id: 'message-${index + 1}',
            conversationId: 'conversation-a',
            sequence: index + 1,
            senderId: 'member-a',
            content: '消息 ${index + 1}',
            kind: 'text',
            createdAt: DateTime.utc(2026, 8, 31).add(Duration(seconds: index)),
          ),
        ),
      );

      final window = await store.readMessages(
        'account-a',
        'conversation-a',
        limit: 80,
      );

      expect(window, hasLength(80));
      expect(window.first.sequence, 121);
      expect(window.last.sequence, 200);
    },
  );

  test(
    'event projection is idempotent and advances cursor transactionally',
    () async {
      final created = ImSyncEvent(
        sequence: 11,
        id: 'event-created',
        type: 'message.created',
        payloadJson: jsonEncode({
          'Id': 'message-11',
          'ConversationId': 'conversation-a',
          'Sequence': 11,
          'SenderId': 'member-b',
          'ClientMessageId': 'remote-client-11',
          'Content': 'original',
          'Kind': 'text',
          'CreatedAt': '2026-08-17T00:00:00Z',
        }),
        createdAt: DateTime.utc(2026, 8, 17),
      );
      final edited = ImSyncEvent(
        sequence: 12,
        id: 'event-edited',
        type: 'message.edited',
        payloadJson: jsonEncode({
          'Id': 'message-11',
          'ConversationId': 'conversation-a',
          'Detail': {'NewContent': 'edited'},
        }),
        createdAt: DateTime.utc(2026, 8, 17),
      );

      await store.applySyncBatch(
        accountId: 'account-a',
        deviceId: 'mobile-device-a',
        events: [created, edited],
        bootstrap: _bootstrap('a', unread: 1),
      );
      await store.applySyncBatch(
        accountId: 'account-a',
        deviceId: 'mobile-device-a',
        events: [created, edited],
        bootstrap: _bootstrap('a', unread: 1),
      );

      final messages = await store.readMessages('account-a', 'conversation-a');
      expect(messages, hasLength(1));
      expect(messages.single.content, 'edited');
      expect(await store.lastEventSequence('account-a', 'mobile-device-a'), 12);
      expect(
        await store.lastAckedEventSequence('account-a', 'mobile-device-a'),
        0,
      );
      await store.markEventsAcked('account-a', 'mobile-device-a', 12);
      expect(
        await store.lastAckedEventSequence('account-a', 'mobile-device-a'),
        12,
      );
    },
  );

  test(
    'cached bootstrap event advances preview unread and mention transactionally',
    () async {
      await store.replaceBootstrap(
        'account-a',
        ImBootstrap(
          currentMember: const ImMember(
            id: 'member-a',
            username: 'a',
            displayName: 'A',
            isOnline: true,
          ),
          contacts: const [],
          conversations: [
            ImConversation(
              id: 'conversation-a',
              type: 'Direct',
              title: 'Conversation a',
              preview: 'old preview',
              updatedAt: DateTime.utc(2026, 9, 6, 4),
              unreadCount: 0,
              lastMessageSequence: 65,
              lastReadSequence: 65,
            ),
          ],
        ),
      );
      final created = ImSyncEvent(
        sequence: 100,
        id: 'event-created-66',
        type: 'message.created',
        payloadJson: jsonEncode({
          'Id': 'message-66',
          'ConversationId': 'conversation-a',
          'Sequence': 66,
          'SenderId': 'member-b',
          'ClientMessageId': 'remote-client-66',
          'Content': 'new preview',
          'Kind': 'text',
          'CreatedAt': '2026-09-06T04:01:00Z',
          'Mentions': [
            {
              'MentionedMemberId': 'member-a',
              'DisplayName': 'A',
              'IsMentionAll': false,
            },
          ],
        }),
        createdAt: DateTime.utc(2026, 9, 6, 4, 1),
      );

      for (var replay = 0; replay < 2; replay++) {
        await store.applySyncBatch(
          accountId: 'account-a',
          deviceId: 'mobile-device-a',
          events: [created],
          bootstrap: _bootstrap('a', unread: 0),
          replaceBootstrap: false,
        );
      }

      final conversation = (await store.readBootstrap('account-a'))!
          .conversations
          .single;
      expect(conversation.lastMessageSequence, 66);
      expect(conversation.preview, 'new preview');
      expect(conversation.unreadCount, 1);
      expect(conversation.unreadMentionSequences, [66]);
      expect(
        await store.lastEventSequence('account-a', 'mobile-device-a'),
        100,
      );

      final ownDesktopCreated = ImSyncEvent(
        sequence: 101,
        id: 'event-created-67',
        type: 'message.created',
        payloadJson: jsonEncode({
          'Id': 'message-67',
          'ConversationId': 'conversation-a',
          'Sequence': 67,
          'SenderId': 'member-a',
          'ClientMessageId': 'desktop-client-67',
          'Content': 'same account desktop message',
          'Kind': 'text',
          'CreatedAt': '2026-09-06T04:02:00Z',
        }),
        createdAt: DateTime.utc(2026, 9, 6, 4, 2),
      );
      await store.applySyncBatch(
        accountId: 'account-a',
        deviceId: 'mobile-device-a',
        events: [ownDesktopCreated],
        bootstrap: _bootstrap('a', unread: 0),
        replaceBootstrap: false,
      );

      final afterDesktopEcho = (await store.readBootstrap('account-a'))!
          .conversations
          .single;
      expect(afterDesktopEcho.lastMessageSequence, 67);
      expect(afterDesktopEcho.preview, 'same account desktop message');
      expect(afterDesktopEcho.unreadCount, 1);
      expect(afterDesktopEcho.unreadMentionSequences, [66]);
    },
  );

  test('event cursors are isolated by account and mobile device', () async {
    final event = ImSyncEvent(
      sequence: 31,
      id: 'event-device-a',
      type: 'presence.changed',
      payloadJson: jsonEncode({'conversationId': 'conversation-a'}),
      createdAt: DateTime.utc(2026, 9, 1),
    );
    await store.applySyncBatch(
      accountId: 'account-a',
      deviceId: 'mobile-device-a',
      events: [event],
      bootstrap: _bootstrap('a', unread: 0),
    );

    expect(await store.lastEventSequence('account-a', 'mobile-device-a'), 31);
    expect(await store.lastEventSequence('account-a', 'mobile-device-b'), 0);
    expect(await store.lastEventSequence('account-b', 'mobile-device-a'), 0);
  });

  test(
    'own conversation.read event persists max read state idempotently',
    () async {
      ImSyncEvent messageEvent(int eventSequence, int messageSequence) =>
          ImSyncEvent(
            sequence: eventSequence,
            id: 'event-message-$messageSequence',
            type: 'message.created',
            payloadJson: jsonEncode({
              'Id': 'message-$messageSequence',
              'ConversationId': 'conversation-a',
              'Sequence': messageSequence,
              'SenderId': 'member-b',
              'ClientMessageId': 'remote-$messageSequence',
              'Content': 'message $messageSequence',
              'Kind': 'text',
            }),
            createdAt: DateTime.utc(2026, 9, 1),
          );

      final readEvent = ImSyncEvent(
        sequence: 43,
        id: 'event-read-10',
        type: 'conversation.read',
        payloadJson: jsonEncode({
          'ConversationId': 'conversation-a',
          'ReaderId': 'member-a',
          'Sequence': 10,
        }),
        createdAt: DateTime.utc(2026, 9, 1),
      );
      await store.applySyncBatch(
        accountId: 'account-a',
        deviceId: 'mobile-device-a',
        events: [messageEvent(41, 10), messageEvent(42, 11), readEvent],
        bootstrap: _bootstrap('a', unread: 2),
      );
      await store.applySyncBatch(
        accountId: 'account-a',
        deviceId: 'mobile-device-a',
        events: [readEvent],
        bootstrap: _bootstrap('a', unread: 2),
      );

      final conversation = (await store.readBootstrap('account-a'))!
          .conversations
          .single;
      expect(conversation.lastReadSequence, 10);
      expect(conversation.unreadCount, 1);
      expect(conversation.unreadMentionSequences, [11]);
    },
  );
}

ImBootstrap _bootstrap(String suffix, {required int unread}) => ImBootstrap(
  currentMember: ImMember(
    id: 'member-$suffix',
    username: suffix,
    displayName: suffix.toUpperCase(),
    isOnline: true,
  ),
  contacts: [
    ImMember(
      id: 'contact-$suffix',
      username: 'contact-$suffix',
      displayName: 'Contact $suffix',
      isOnline: false,
    ),
  ],
  conversations: [
    ImConversation(
      id: 'conversation-$suffix',
      type: 'Direct',
      title: 'Conversation $suffix',
      preview: 'Preview $suffix',
      updatedAt: DateTime.utc(2026, 8, 17),
      unreadCount: unread,
      lastMessageSequence: 11,
      unreadMentionSequences: const [8, 11],
    ),
  ],
);
