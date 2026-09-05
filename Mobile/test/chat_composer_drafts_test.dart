import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/chat_composer_drafts.dart';

import 'support/chat_composer_fixture.dart';

final _scope = NotifierProvider<_Scope, String>(_Scope.new);

class _Scope extends Notifier<String> {
  @override
  String build() => 'me';
  void change(String value) => state = value;
}

UnstoredChatDraft _draft(String text) => UnstoredChatDraft(
  content: text,
  mentionedMemberIds: ['member'],
  mentionAll: false,
  replyTo: null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unstored drafts are distinct, retry deduplicated and conversation scoped',
    () {
      final container = ProviderContainer(
        overrides: [
          collaborationAccountScopeProvider.overrideWith(
            (ref) => ref.watch(_scope),
          ),
        ],
      );
      addTearDown(container.dispose);
      final drafts = container.read(unstoredChatDraftsProvider.notifier);
      final generation = drafts.generation;
      final a = _draft('same');
      final b = _draft('same');
      drafts.retain('one', a, generation);
      drafts.retain('one', a, generation);
      drafts.retain('one', b, generation);
      drafts.retain('two', _draft('other'), generation);
      expect(container.read(unstoredChatDraftsProvider)['one']!.length, 2);
      drafts.remove('one', a, generation);
      expect(
        container.read(unstoredChatDraftsProvider)['one']!.single,
        same(b),
      );
      expect(container.read(unstoredChatDraftsProvider)['two']!.length, 1);
    },
  );

  for (final transition in ['other', '']) {
    test(
      'unstored drafts clear on scope change and reject late completion: $transition',
      () async {
        final container = ProviderContainer(
          overrides: [
            collaborationAccountScopeProvider.overrideWith(
              (ref) => ref.watch(_scope),
            ),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          unstoredChatDraftsProvider,
          (_, _) {},
        );
        addTearDown(subscription.close);
        final drafts = container.read(unstoredChatDraftsProvider.notifier);
        final generation = drafts.generation;
        final original = _draft('old');
        drafts.retain('one', original, generation);
        container.read(_scope.notifier).change(transition);
        await container.pump();
        expect(container.read(unstoredChatDraftsProvider), isEmpty);
        drafts.retain('one', original, generation);
        expect(container.read(unstoredChatDraftsProvider), isEmpty);
        container.read(_scope.notifier).change('me');
        await container.pump();
        drafts.retain('one', original, generation);
        expect(container.read(unstoredChatDraftsProvider), isEmpty);
      },
    );
  }

  test('disposed draft store safely ignores late failed write', () {
    final container = ProviderContainer(
      overrides: [collaborationAccountScopeProvider.overrideWithValue('me')],
    );
    final drafts = container.read(unstoredChatDraftsProvider.notifier);
    final generation = drafts.generation;
    container.dispose();
    expect(
      () => drafts.retain('one', _draft('late'), generation),
      returnsNormally,
    );
  });

  test(
    'repository rejects UI from another account before local enqueue',
    () async {
      final fixture = await ChatComposerFixture.create();
      addTearDown(fixture.store.close);
      await expectLater(
        fixture.repository.send(
          'ops',
          'wrong account',
          expectedAccountId: 'old',
        ),
        throwsA(isA<SessionChangedException>()),
      );
      expect(await fixture.store.dueOutbox('me'), isEmpty);
    },
  );

  test(
    'failed transaction rolls back message and retry keeps stable client id',
    () async {
      final fixture = await ChatComposerFixture.create();
      addTearDown(fixture.store.close);
      final draft = _draft('stable retry');
      fixture.cipher.hold(failure: true);
      final operation = fixture.repository.send(
        'ops',
        draft.content,
        clientMessageId: draft.clientMessageId,
      );
      final assertion = expectLater(operation, throwsStateError);
      await fixture.cipher.entered.future;
      fixture.cipher.release();
      await assertion;
      expect(await fixture.store.dueOutbox('me'), isEmpty);
      expect(await fixture.store.readMessages('me', 'ops'), isEmpty);
      await fixture.repository.send(
        'ops',
        draft.content,
        clientMessageId: draft.clientMessageId,
      );
      final queued = await fixture.store.dueOutbox('me');
      expect(queued.single.clientMessageId, draft.clientMessageId);
      expect(
        (await fixture.store.readMessages('me', 'ops')).single.clientMessageId,
        draft.clientMessageId,
      );
    },
  );
}
