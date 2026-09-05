import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_request_page.dart';

final _account = NotifierProvider<_Account, String>(_Account.new);

class _Account extends Notifier<String> {
  @override
  String build() => 'account-a';
  void change(String value) => state = value;
}

final _template = OaApprovalTemplate(
  id: '1',
  name: '请假申请',
  category: '考勤',
  iconKey: 'file',
  workflowKey: 'leave',
  version: 1,
  formSchemaJson:
      '{"fields":[{"id":"reason","type":"text","label":"事由","required":true}]}',
);

class _SaveCall {
  _SaveCall(this.id, this.data);
  final String? id;
  final Map<String, Object?> data;
  final completion = Completer<OaApprovalDraft>();
  void succeed() => completion.complete(
    OaApprovalDraft(
      id: id ?? 'first-draft',
      applicationKey: 'attendance.leave',
      templateId: '1',
      workflowKey: 'leave',
      title: '测试',
      formData: data,
      updatedAt: DateTime(2026, 9, 2),
      attachments: const [],
    ),
  );
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  List<_SaveCall> calls, {
  VoidCallback? onSubmit,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collaborationAccountScopeProvider.overrideWith(
          (ref) => ref.watch(_account),
        ),
        oaBootstrapProvider.overrideWith(
          (ref) async => OaBootstrap(
            currentMemberId: 'a',
            displayName: '测试',
            todos: const [],
            announcements: const [],
            templates: [_template],
          ),
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        imDepartmentsProvider.overrideWith((ref) async => const []),
        oaDraftLoaderProvider.overrideWithValue((_) async => null),
        oaDraftSaverProvider.overrideWithValue(({
          String? id,
          required String applicationKey,
          required OaApprovalTemplate template,
          required String title,
          required Map<String, Object?> formData,
          required List<OaLocalAttachment> attachments,
        }) {
          final call = _SaveCall(id, Map.of(formData));
          calls.add(call);
          return call.completion.future;
        }),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
        if (onSubmit != null)
          oaRepositoryProvider.overrideWith((ref) {
            onSubmit();
            throw StateError('test submission unavailable');
          }),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ApprovalRequestPage(
                    applicationKey: 'attendance.leave',
                    templateId: '1',
                  ),
                ),
              ),
              child: const Text('打开表单'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开表单'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(ApprovalRequestPage)),
  );
}

Future<void> _edit(WidgetTester tester, String value) async {
  await tester.enterText(find.byType(TextFormField), value);
  await tester.pump(const Duration(milliseconds: 650));
}

void main() {
  testWidgets('account switch stops a queued follow-up draft write', (
    tester,
  ) async {
    final calls = <_SaveCall>[];
    final container = await _open(tester, calls);
    await _edit(tester, 'AI-UAT-account-a');
    expect(calls.first.id, isNotNull);
    await tester.enterText(find.byType(TextFormField), 'AI-UAT-later-edit');
    container.read(_account.notifier).change('account-b');
    await tester.pump();
    calls.first.succeed();
    await tester.pump(const Duration(seconds: 1));
    expect(calls.length, 1);
    expect(find.text('草稿已保存'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('autosave serializes edits and cannot mark a newer value saved', (
    tester,
  ) async {
    final calls = <_SaveCall>[];
    await _open(tester, calls);
    await _edit(tester, 'AI-UAT-first');
    expect(calls.length, 1);
    await _edit(tester, 'AI-UAT-latest');
    expect(
      calls.length,
      1,
      reason: 'the first disk write must settle before the next starts',
    );
    calls.first.succeed();
    await tester.pump();
    expect(calls.length, 2);
    expect(calls.last.data['reason'], 'AI-UAT-latest');
    expect(calls.last.id, calls.first.id);
    expect(find.text('草稿已保存'), findsNothing);
    expect(find.text('保存中'), findsOneWidget);
    calls.last.succeed();
    await tester.pumpAndSettle();
    expect(find.text('草稿已保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'back waits for the latest autosave and does not start duplicate writes',
    (tester) async {
      final calls = <_SaveCall>[];
      await _open(tester, calls);
      await _edit(tester, 'AI-UAT-first');
      await tester.enterText(find.byType(TextFormField), 'AI-UAT-back-latest');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(ApprovalRequestPage), findsOneWidget);
      expect(calls.length, 1);
      calls.first.succeed();
      await tester.pump();
      expect(calls.length, 2);
      expect(calls.last.data['reason'], 'AI-UAT-back-latest');
      calls.last.succeed();
      await tester.pumpAndSettle();
      expect(find.byType(ApprovalRequestPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed back save keeps input and exposes a retryable status', (
    tester,
  ) async {
    final calls = <_SaveCall>[];
    await _open(tester, calls);
    await _edit(tester, 'AI-UAT-failure');
    calls.first.completion.completeError(StateError('disk unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('保存失败'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    calls.last.completion.completeError(StateError('disk unavailable'));
    await tester.pumpAndSettle();
    expect(find.byType(ApprovalRequestPage), findsOneWidget);
    expect(find.text('草稿未保存，请重试'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approval-draft-button')));
    await tester.pump();
    expect(
      calls.last.id,
      calls.first.id,
      reason: 'retry must retain the same draft identity',
    );
    expect(calls.last.data['reason'], 'AI-UAT-failure');
    calls.last.succeed();
    await tester.pumpAndSettle();
    expect(find.text('保存失败'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'submit waits for in-flight draft and ignores a duplicate press and back',
    (tester) async {
      final calls = <_SaveCall>[];
      var submits = 0;
      await _open(tester, calls, onSubmit: () => submits++);
      await _edit(tester, 'AI-UAT-submit');
      final submit = tester
          .widget<FilledButton>(find.byKey(const Key('approval-submit-button')))
          .onPressed!;
      submit();
      submit();
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        submits,
        0,
        reason: 'do not submit then let the old save resurrect a deleted draft',
      );
      expect(find.byType(ApprovalRequestPage), findsOneWidget);
      expect(calls.length, 1);
      calls.first.succeed();
      await tester.pumpAndSettle();
      expect(submits, 1);
      expect(find.byType(ApprovalRequestPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'disposed page does not continue saving or invalidate providers',
    (tester) async {
      final calls = <_SaveCall>[];
      await _open(tester, calls);
      await _edit(tester, 'AI-UAT-old');
      await tester.enterText(find.byType(TextFormField), 'AI-UAT-new');
      await tester.pumpWidget(const SizedBox.shrink());
      calls.first.succeed();
      await tester.pumpAndSettle();
      expect(calls.length, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
