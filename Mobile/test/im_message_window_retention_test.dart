import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_message_window_retention.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/chat_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'paging 510 messages retains only the latest window for hot reopen',
    () async {
      final loads = <int>[];
      final container = ProviderContainer.test(
        overrides: [
          collaborationAccountScopeProvider.overrideWithValue('test-account'),
          conversationMessageWindowLoaderProvider.overrideWithValue((
            id, {
            take,
          }) async {
            loads.add(take!);
            return List.generate(take, (index) => _message(id, index + 1));
          }),
        ],
      );
      addTearDown(container.dispose);
      final keys = [
        80,
        160,
        240,
        320,
        400,
        480,
        510,
      ].map((take) => (conversationId: 'test-group', take: take)).toList();
      for (final key in keys) {
        final subscription = container.listen(
          conversationMessageWindowProvider(key),
          (_, _) {},
        );
        await container.read(conversationMessageWindowProvider(key).future);
        subscription.close();
        await container.pump();
      }
      final retained = keys
          .where(
            (key) => container.exists(conversationMessageWindowProvider(key)),
          )
          .toList();
      expect(retained.map((key) => key.take), [510]);
      final reopened = container.listen(
        conversationMessageWindowProvider(keys.last),
        (_, _) {},
      );
      await container.read(conversationMessageWindowProvider(keys.last).future);
      expect(loads, [
        80,
        160,
        240,
        320,
        400,
        480,
        510,
      ], reason: 'hot reopen must not query again');
      container.invalidate(conversationMessageRevisionProvider('test-group'));
      await container.pump();
      await container.read(conversationMessageWindowProvider(keys.last).future);
      expect(loads, [80, 160, 240, 320, 400, 480, 510, 510]);
      reopened.close();
    },
  );

  test('superseded but actively watched window is not destroyed', () async {
    final container = _container();
    addTearDown(container.dispose);
    const oldKey = (conversationId: 'group', take: 80);
    const newKey = (conversationId: 'group', take: 160);
    final old = container.listen(
      conversationMessageWindowProvider(oldKey),
      (_, _) {},
    );
    await container.read(conversationMessageWindowProvider(oldKey).future);
    final current = container.listen(
      conversationMessageWindowProvider(newKey),
      (_, _) {},
    );
    await container.read(conversationMessageWindowProvider(newKey).future);
    await container.pump();
    expect(
      container
          .read(conversationMessageWindowProvider(oldKey))
          .requireValue
          .length,
      80,
    );
    expect(container.read(imMessageWindowRetentionProvider).messageCount, 160);
    old.close();
    await container.pump();
    expect(
      container.exists(conversationMessageWindowProvider(oldKey)),
      isFalse,
    );
    expect(container.exists(conversationMessageWindowProvider(newKey)), isTrue);
    current.close();
  });

  test('window LRU drops old chats but keeps a resumed chat hot', () async {
    final retention = ImMessageWindowRetention(maxWindows: 2);
    final container = _container(retention: retention);
    addTearDown(() {
      container.dispose();
      retention.dispose();
    });
    for (final id in ['a', 'b', 'a', 'c']) {
      await _openAndClose(container, id, 80);
    }
    expect(retention.windowCount, 2);
    expect(
      container.exists(
        conversationMessageWindowProvider((conversationId: 'a', take: 80)),
      ),
      isTrue,
    );
    expect(
      container.exists(
        conversationMessageWindowProvider((conversationId: 'b', take: 80)),
      ),
      isFalse,
    );
    expect(
      container.exists(
        conversationMessageWindowProvider((conversationId: 'c', take: 80)),
      ),
      isTrue,
    );
  });

  test(
    'message budget evicts dormant data without truncating active history',
    () async {
      final retention = ImMessageWindowRetention(maxMessages: 150);
      final container = _container(retention: retention);
      addTearDown(() {
        container.dispose();
        retention.dispose();
      });
      await _openAndClose(container, 'a', 80);
      await _openAndClose(container, 'b', 80);
      expect(retention.messageCount, 80);
      expect(
        container.exists(
          conversationMessageWindowProvider((conversationId: 'a', take: 80)),
        ),
        isFalse,
      );
      const key = (conversationId: 'large', take: 5000);
      final active = container.listen(
        conversationMessageWindowProvider(key),
        (_, _) {},
      );
      final messages = await container.read(
        conversationMessageWindowProvider(key).future,
      );
      await container.pump();
      expect(
        messages.length,
        5000,
        reason: 'cache budget is not a history limit',
      );
      expect(container.exists(conversationMessageWindowProvider(key)), isTrue);
      expect(retention.messageCount, lessThanOrEqualTo(150));
      active.close();
      await container.pump();
      expect(container.exists(conversationMessageWindowProvider(key)), isFalse);
    },
  );

  test(
    'late old window completion cannot replace the newer retained window',
    () async {
      final pending = Completer<List<ImMessage>>();
      final container = _container(
        loader: (id, {take}) async => take == 80
            ? pending.future
            : List.generate(take!, (i) => _message(id, i + 1)),
      );
      addTearDown(container.dispose);
      const oldKey = (conversationId: 'group', take: 80);
      final old = container.listen(
        conversationMessageWindowProvider(oldKey),
        (_, _) {},
      );
      final oldFuture = container.read(
        conversationMessageWindowProvider(oldKey).future,
      );
      await _openAndClose(container, 'group', 160);
      pending.complete(List.generate(80, (i) => _message('group', i + 1)));
      await oldFuture;
      old.close();
      await container.pump();
      final retained = container.read(imMessageWindowRetentionProvider);
      expect(retained.windowCount, 1);
      expect(retained.messageCount, 160);
    },
  );

  test('failed windows are released and reopen retries instead of caching the error', () async {
    var loads = 0;
    final container = _container(
      loader: (id, {take}) async {
        if (++loads == 1) throw StateError('test-only unavailable');
        return [_message(id, 1)];
      },
    );
    addTearDown(container.dispose);
    const key = (conversationId: 'retry', take: 80);
    final failed = container.listen(
      conversationMessageWindowProvider(key),
      (_, _) {},
    );
    await expectLater(
      container.read(conversationMessageWindowProvider(key).future),
      throwsStateError,
    );
    failed.close();
    await container.pump();
    expect(container.exists(conversationMessageWindowProvider(key)), isFalse);
    await _openAndClose(container, 'retry', 80);
    expect(loads, 2);
  });

  test(
    'account changes clear retained windows and expanded-window metadata',
    () async {
      final container = ProviderContainer.test(
        overrides: [
          collaborationAccountScopeProvider.overrideWith(
            (ref) => ref.watch(_accountProvider),
          ),
          conversationMessageWindowLoaderProvider.overrideWithValue(
            (id, {take}) async => [_message(id, 1)],
          ),
        ],
      );
      addTearDown(container.dispose);
      await _openAndClose(container, 'shared-group', 160);
      final oldRetention = container.read(imMessageWindowRetentionProvider);
      container
          .read(conversationMessageWindowMemoryProvider)
          .remember('shared-group', take: 160, hasOlder: false);
      container.read(_accountProvider.notifier).change('account-b');
      await container.pump();
      final newRetention = container.read(imMessageWindowRetentionProvider);
      expect(identical(oldRetention, newRetention), isFalse);
      expect(oldRetention.windowCount, 0);
      final metadata = container
          .read(conversationMessageWindowMemoryProvider)
          .restore('shared-group');
      expect(metadata.take, 80);
      expect(metadata.hasOlder, isTrue);
    },
  );

  testWidgets('TTL only runs while idle and resumes reset its deadline', (
    tester,
  ) async {
    var closes = 0;
    final retention = ImMessageWindowRetention(
      retention: const Duration(minutes: 30),
    );
    final lease = retention.acquire('group', () => closes++);
    lease.loaded(80);
    await tester.pump(const Duration(hours: 1));
    expect(closes, 0, reason: 'active window cannot expire');
    lease.idle();
    await tester.pump(const Duration(minutes: 29));
    lease.resume();
    await tester.pump(const Duration(minutes: 2));
    expect(closes, 0);
    lease.idle();
    await tester.pump(const Duration(minutes: 30));
    expect(closes, 1);
    lease.release();
    retention.dispose();
    expect(closes, 1);
  });
}

final _accountProvider = NotifierProvider<_Account, String>(_Account.new);

class _Account extends Notifier<String> {
  @override
  String build() => 'account-a';
  void change(String account) => state = account;
}

ProviderContainer _container({
  ImMessageWindowRetention? retention,
  ConversationMessageWindowLoader? loader,
}) => ProviderContainer.test(
  overrides: [
    collaborationAccountScopeProvider.overrideWithValue('test-account'),
    if (retention != null)
      imMessageWindowRetentionProvider.overrideWithValue(retention),
    conversationMessageWindowLoaderProvider.overrideWithValue(
      loader ??
          (id, {take}) async =>
              List.generate(take!, (i) => _message(id, i + 1)),
    ),
  ],
);

Future<void> _openAndClose(
  ProviderContainer container,
  String id,
  int take,
) async {
  final provider = conversationMessageWindowProvider((
    conversationId: id,
    take: take,
  ));
  final subscription = container.listen(provider, (_, _) {});
  await container.read(provider.future);
  subscription.close();
  await container.pump();
}

ImMessage _message(String conversationId, int sequence) => ImMessage(
  id: 'message-$sequence',
  conversationId: conversationId,
  sequence: sequence,
  senderId: 'sender',
  content: 'Synthetic message $sequence',
  kind: 'text',
  createdAt: DateTime.utc(2026, 9, 3, 0, 0, sequence),
);
