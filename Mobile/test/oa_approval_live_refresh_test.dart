import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_detail_page.dart';

void main() {
  for (final eventDriven in [true, false]) {
    testWidgets(
      'transferred task stays in history after ${eventDriven ? 'event' : 'fallback'} completion',
      (tester) async {
        var current = _transferredRequest('submitted');
        var refreshes = 0;
        final container = _container(() => current, (_) async {
          refreshes++;
          if (refreshes > 1) current = _transferredRequest('approved');
          return current;
        }, autoRefresh: true);
        addTearDown(container.dispose);
        await _pump(tester, container);
        expect(refreshes, 1);
        expect(find.text('审批中'), findsOneWidget);
        expect(find.text('已转交'), findsOneWidget);
        expect(find.text('同意'), findsNothing);
        expect(find.text('驳回'), findsNothing);

        if (eventDriven) {
          container.read(oaApprovalRevisionsProvider.notifier).changed({
            'approval-1',
          });
        } else {
          await tester.pump(const Duration(seconds: 30));
        }
        await tester.pumpAndSettle();
        expect(refreshes, 2);
        expect(find.text('已通过'), findsOneWidget);
        expect(find.text('已转交'), findsOneWidget);
        expect(find.text('已同意'), findsOneWidget);
        expect(find.text('同意'), findsNothing);
        expect(find.text('驳回'), findsNothing);
        await tester.pump(const Duration(minutes: 2));
        expect(refreshes, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      },
    );
  }

  testWidgets(
    'stale login detail failure does not mark the renewed session offline',
    (tester) async {
      final gate = Completer<OaApprovalRequest>();
      final container = _container(
        () => _request('submitted'),
        (_) => gate.future,
      );
      addTearDown(container.dispose);
      await _pump(tester, container);
      container.read(oaApprovalRevisionsProvider.notifier).changed({
        'approval-1',
      });
      await tester.pump();
      await tester.pump();
      // A renewed token can belong to the same account. Its successful sync
      // must not be overwritten by a pending failure from the old token.
      container
          .read(oaSyncAvailabilityControllerProvider.notifier)
          .markAvailable();
      gate.completeError(const SessionChangedException());
      await tester.pumpAndSettle();
      expect(
        container.read(oaSyncAvailabilityProvider),
        OaSyncAvailability.available,
      );
      expect(find.text('同意'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  test(
    'OA events identify affected requests without using notification IDs',
    () {
      final result = OaSyncPullResult.fromEvents([
        _event(8, '{"RequestId":"approval-1","Id":"notification-1"}'),
        _event(6, '{"requestId":"approval-1"}'),
        _event(9, '{"approvalRequestId":"approval-2"}'),
        _event(10, '{"ApprovalRequestId":" approval-3 "}'),
        _event(11, 'not json'),
        _event(12, '["approval-4"]'),
        _event(13, '{"Id":"unrelated","RequestId":null}'),
      ]);
      expect(result.changed, isTrue);
      expect(result.sequence, 13);
      expect(result.requestIds, {'approval-1', 'approval-2', 'approval-3'});
      expect(OaSyncPullResult.fromEvents([]).changed, isFalse);
    },
  );

  test(
    'approval revisions remain request-scoped and reset on account switch',
    () {
      final container = ProviderContainer(
        overrides: [
          collaborationAccountScopeProvider.overrideWith(
            (ref) => ref.watch(_accountProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(oaApprovalRevisionsProvider.notifier).changed({
        'approval-1',
      });
      expect(container.read(oaApprovalRevisionProvider('approval-1')), 1);
      expect(container.read(oaApprovalRevisionProvider('approval-2')), 0);
      container.read(_accountProvider.notifier).switchAccount();
      expect(container.read(oaApprovalRevisionProvider('approval-1')), 0);
    },
  );

  testWidgets('open detail refreshes only for its own remote changes', (
    tester,
  ) async {
    var current = _request('submitted');
    var refreshes = 0;
    final container = _container(() => current, (id) async {
      expect(id, 'approval-1');
      refreshes += 1;
      current = _request('approved');
      return current;
    });
    addTearDown(container.dispose);
    await _pump(tester, container);
    expect(find.text('同意'), findsOneWidget);
    container.read(oaApprovalRevisionsProvider.notifier).changed({'unrelated'});
    await tester.pumpAndSettle();
    expect(refreshes, 0);
    container.read(oaApprovalRevisionsProvider.notifier).changed({
      'approval-1',
    });
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.text('已通过'), findsOneWidget);
    expect(find.text('同意'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets(
    'updates during an active refresh coalesce into one trailing fetch',
    (tester) async {
      var current = _request('submitted');
      final gate = Completer<void>();
      var refreshes = 0;
      var active = 0;
      var maxActive = 0;
      final container = _container(() => current, (_) async {
        refreshes += 1;
        active += 1;
        if (active > maxActive) maxActive = active;
        if (refreshes == 1) await gate.future;
        current = _request(refreshes == 1 ? 'submitted' : 'withdrawn');
        active -= 1;
        return current;
      });
      addTearDown(container.dispose);
      await _pump(tester, container);
      final revisions = container.read(oaApprovalRevisionsProvider.notifier);
      revisions.changed({'approval-1'});
      await tester.pump();
      await tester.pump();
      expect(refreshes, 1);
      expect(find.text('AI-UAT-live-detail'), findsOneWidget);
      revisions.changed({'approval-1'});
      revisions.changed({'approval-1'});
      await tester.pump();
      expect(refreshes, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(refreshes, 2);
      expect(maxActive, 1);
      expect(find.text('已撤回'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  testWidgets('failed event refresh keeps cached detail and can recover', (
    tester,
  ) async {
    var current = _request('submitted');
    var refreshes = 0;
    final container = _container(() => current, (_) async {
      refreshes += 1;
      if (refreshes == 1) throw StateError('private-transport-error');
      current = _request('rejected');
      return current;
    });
    addTearDown(container.dispose);
    await _pump(tester, container);
    container.read(oaApprovalRevisionsProvider.notifier).changed({
      'approval-1',
    });
    await tester.pumpAndSettle();
    expect(find.text('AI-UAT-live-detail'), findsOneWidget);
    expect(find.text('审批中'), findsOneWidget);
    expect(find.textContaining('private-transport-error'), findsNothing);
    expect(find.text('同意'), findsNothing);
    container.read(oaApprovalRevisionsProvider.notifier).changed({
      'approval-1',
    });
    await tester.pumpAndSettle();
    expect(refreshes, 2);
    // The request header and the completed task both show their own status.
    expect(find.text('已驳回'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('an in-flight refresh can finish after leaving the detail', (
    tester,
  ) async {
    final gate = Completer<OaApprovalRequest>();
    final container = _container(
      () => _request('submitted'),
      (_) => gate.future,
    );
    addTearDown(container.dispose);
    await _pump(tester, container);
    container.read(oaApprovalRevisionsProvider.notifier).changed({
      'approval-1',
    });
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete(_request('approved'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    container.dispose();
  });
  testWidgets(
    'visible unfinished detail reconciles without an event then stops at terminal state',
    (tester) async {
      var current = _request('submitted');
      var refreshes = 0;
      final container = _container(() => current, (_) async {
        refreshes++;
        if (refreshes == 2) current = _request('withdrawn');
        return current;
      }, autoRefresh: true);
      await _pump(tester, container);
      expect(refreshes, 1);
      await tester.pump(const Duration(seconds: 29));
      expect(refreshes, 1);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(refreshes, 2);
      expect(find.text('已撤回'), findsOneWidget);
      expect(find.text('同意'), findsNothing);
      await tester.pump(const Duration(minutes: 2));
      expect(refreshes, 2);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  testWidgets(
    'background pauses reconciliation and foreground checks immediately',
    (tester) async {
      var current = _request('submitted');
      var refreshes = 0;
      final container = _container(() => current, (_) async {
        refreshes++;
        return current;
      }, autoRefresh: true);
      await _pump(tester, container);
      expect(refreshes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 2));
      expect(refreshes, 1);
      current = _request('withdrawn');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(refreshes, 2);
      expect(find.text('已撤回'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  testWidgets('covered detail performs no periodic requests', (tester) async {
    final current = _request('submitted');
    var refreshes = 0;
    final container = _container(() => current, (_) async {
      refreshes++;
      return current;
    }, autoRefresh: true);
    await _pump(tester, container);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('其他页面')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 2));
    expect(refreshes, 1);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(refreshes, 2);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets(
    'event refresh postpones fallback and routine check keeps controls visible',
    (tester) async {
      final current = _request('submitted');
      var refreshes = 0;
      final gate = Completer<OaApprovalRequest>();
      final container = _container(() => current, (_) async {
        refreshes++;
        return refreshes == 3 ? gate.future : current;
      }, autoRefresh: true);
      await _pump(tester, container);
      await tester.pump(const Duration(seconds: 20));
      container.read(oaApprovalRevisionsProvider.notifier).changed({
        'approval-1',
      });
      await tester.pumpAndSettle();
      expect(refreshes, 2);
      await tester.pump(const Duration(seconds: 29));
      expect(refreshes, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(refreshes, 3);
      expect(find.text('同意'), findsOneWidget);
      expect(
        container.read(oaSyncAvailabilityProvider),
        OaSyncAvailability.available,
      );
      await tester.pump(const Duration(seconds: 30));
      expect(refreshes, 3);
      gate.complete(current);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );

  testWidgets(
    'failed fallback preserves cached detail and retries without popup',
    (tester) async {
      var current = _request('submitted');
      var refreshes = 0;
      final container = _container(() => current, (_) async {
        refreshes++;
        if (refreshes == 2) throw StateError('sensitive internal response');
        if (refreshes == 3) current = _request('withdrawn');
        return current;
      }, autoRefresh: true);
      await _pump(tester, container);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(refreshes, 2);
      expect(find.text('AI-UAT-live-detail'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('sensitive'), findsNothing);
      expect(find.text('同意'), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(refreshes, 3);
      expect(find.text('已撤回'), findsOneWidget);
      expect(
        container.read(oaSyncAvailabilityProvider),
        OaSyncAvailability.available,
      );
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    },
  );
}

ProviderContainer _container(
  OaApprovalRequest Function() cached,
  OaApprovalRequestLoader refresh, {
  bool autoRefresh = false,
}) {
  final container = ProviderContainer(
    overrides: [
      collaborationAccountScopeProvider.overrideWithValue('member-1'),
      approvalDetailAutoRefreshProvider.overrideWithValue(autoRefresh),
      oaApprovalRequestLoaderProvider.overrideWithValue((_) async => cached()),
      oaApprovalRequestRefresherProvider.overrideWithValue(refresh),
      oaBootstrapProvider.overrideWith((ref) async => PreviewData.oaBootstrap),
      oaApplicationCatalogProvider.overrideWith(
        (ref) async => PreviewData.oaCatalog,
      ),
      imBootstrapProvider.overrideWith((ref) async => PreviewData.imBootstrap),
    ],
  );
  container.read(oaSyncAvailabilityControllerProvider.notifier).markAvailable();
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: ApprovalDetailPage(approvalId: 'approval-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

OaApprovalRequest _request(String status) => OaApprovalRequest.fromJson({
  'id': 'approval-1',
  'requesterId': 'member-1',
  'title': 'AI-UAT-live-detail',
  'formDataJson': '{}',
  'formSchemaSnapshotJson': '{}',
  'status': status,
  'requesterName': '测试发起人',
  'requesterDepartmentName': '测试部门',
  'createdAt': '2026-09-02T10:00:00Z',
  'updatedAt': '2026-09-02T10:11:00Z',
  'allowedActions': status == 'submitted' ? ['approve', 'reject'] : [],
  'tasks': [
    {
      'id': 'task-1',
      'nodeName': '测试会签',
      'assigneeId': 'member-1',
      'assigneeName': '测试审批人',
      'status': status == 'submitted' ? 'pending' : status,
      'canOperate': status == 'submitted',
    },
  ],
  'actions': [],
  'attachments': [],
  'ccs': [],
});

OaApprovalRequest _transferredRequest(String status) =>
    OaApprovalRequest.fromJson({
      'id': 'approval-1',
      'requesterId': 'member-1',
      'title': 'AI-UAT-live-detail',
      'formDataJson': '{}',
      'formSchemaSnapshotJson': '{}',
      'status': status,
      'requesterName': '测试发起人',
      'requesterDepartmentName': '测试部门',
      'createdAt': '2026-09-04T17:56:00Z',
      'allowedActions': <String>[],
      'tasks': [
        {
          'id': 'original-task',
          'nodeName': '部门负责人审批',
          'assigneeId': 'member-1',
          'assigneeName': '原处理人',
          'status': 'transferred',
          'canOperate': false,
        },
        {
          'id': 'transferred-task',
          'nodeName': '部门负责人审批',
          'assigneeId': 'member-2',
          'assigneeName': '跨部门处理人',
          'assigneeDepartmentName': '另一部门',
          'status': status == 'approved' ? 'approved' : 'pending',
          'canOperate': false,
        },
      ],
    });

OaSyncEvent _event(int sequence, String payload) => OaSyncEvent(
  id: 'event-$sequence',
  sequence: sequence,
  type: 'oa.notification.created',
  payloadJson: payload,
  createdAt: DateTime.utc(2026, 9, 2),
);

final _accountProvider = NotifierProvider<_Account, String>(_Account.new);

class _Account extends Notifier<String> {
  @override
  String build() => 'member-1';

  void switchAccount() => state = 'member-2';
}
