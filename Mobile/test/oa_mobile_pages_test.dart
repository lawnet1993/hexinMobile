import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/notifications/mobile_push_registration.dart';
import 'package:hexing_terminal_mobile/core/updates/client_update_repository.dart';
import 'package:hexing_terminal_mobile/features/attendance/presentation/attendance_page.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/settings_pages.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_detail_page.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_request_page.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/todos_page.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/schedule_page.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_bottom_sheets.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';
import 'package:intl/intl.dart';

void main() {
  testWidgets('mobile confirmation, text input and time selection use sheets', (
    tester,
  ) async {
    String? textResult;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showMobileConfirmSheet(
                    context,
                    title: '确认操作',
                    message: '测试确认内容',
                  ),
                  child: const Text('打开确认'),
                ),
                TextButton(
                  onPressed: () async {
                    textResult = await showMobileTextInputSheet(
                      context,
                      title: '编辑内容',
                      initialValue: '原内容',
                      allowEmpty: false,
                    );
                  },
                  child: const Text('打开输入'),
                ),
                TextButton(
                  onPressed: () => showMobileTimePickerSheet(
                    context,
                    initialTime: const TimeOfDay(hour: 9, minute: 30),
                  ),
                  child: const Text('打开时间'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开确认'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-confirm-sheet')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('打开输入'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-text-input-sheet')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('mobile-text-input-field'))).height,
      lessThanOrEqualTo(40),
    );
    await tester.enterText(
      find.byKey(const Key('mobile-text-input-field')),
      '新内容',
    );
    await tester.tap(find.byKey(const Key('mobile-text-input-submit')));
    await tester.pumpAndSettle();
    expect(textResult, '新内容');

    await tester.tap(find.text('打开时间'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-time-picker-sheet')), findsOneWidget);
    expect(find.byType(TimePickerDialog), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'destructive verification stays compact and requires exact text',
    (tester) async {
      Future<MobileDestructiveVerificationResult?>? pendingResult;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  pendingResult = showMobileDestructiveVerificationSheet(
                    context,
                    title: '删除所有人的聊天记录',
                    message: '所有成员都无法恢复。',
                    requiredPhrase: '测试群',
                    reasonLabel: '删除原因',
                    actionLabel: '确认删除',
                  );
                },
                child: const Text('打开删除确认'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开删除确认'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mobile-destructive-verification-sheet')),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const Key('mobile-destructive-confirmation')))
            .height,
        lessThanOrEqualTo(40),
      );
      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('mobile-destructive-submit')),
      );
      expect(submit.onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('mobile-destructive-reason')),
        'AI-UAT 测试清理',
      );
      await tester.enterText(
        find.byKey(const Key('mobile-destructive-confirmation')),
        '错误群名',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('mobile-destructive-submit')),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('mobile-destructive-confirmation')),
        '测试群',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('mobile-destructive-submit')),
            )
            .onPressed,
        isNotNull,
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('mobile-destructive-submit')),
      );
      tester
          .widget<FilledButton>(
            find.byKey(const Key('mobile-destructive-submit')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      final result = await pendingResult;
      expect(result?.reason, 'AI-UAT 测试清理');
      expect(result?.confirmation, '测试群');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('mobile sheets cover the shell bottom navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: const SizedBox(
            key: Key('test-shell-bottom-nav'),
            height: 64,
          ),
          body: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showMobileChoiceSheet<String>(
                      context,
                      title: '操作',
                      options: const [
                        MobileSheetOption(value: 'one', label: '第一项'),
                      ],
                    ),
                    child: const Text('打开操作'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开操作'));
    await tester.pumpAndSettle();
    final sheetBottom = tester
        .getBottomRight(find.byKey(const Key('mobile-choice-sheet')))
        .dy;
    final navigationTop = tester
        .getTopLeft(find.byKey(const Key('test-shell-bottom-nav')))
        .dy;
    expect(sheetBottom, greaterThan(navigationTop));
    expect(sheetBottom, 844);
    expect(tester.takeException(), isNull);
  });

  testWidgets('todos page unifies personal todos with approval work', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pump(
      tester,
      const TodosPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        oaDraftsProvider.overrideWith((ref) async => const []),
        oaOutboxProvider.overrideWith((ref) async => const []),
      ],
    );

    expect(find.text('终端绑定申请'), findsOneWidget);
    expect(find.text('数据导出申请'), findsOneWidget);
    expect(find.textContaining('OA-20260813-1'), findsOneWidget);
    expect(find.byTooltip('新建'), findsOneWidget);
    expect(find.text('统一处理任务与审批'), findsNothing);
    expect(find.text('待我处理'), findsOneWidget);
    expect(find.text('抄送我的'), findsOneWidget);
    expect(find.text('草稿箱'), findsOneWidget);
    expect(find.text('待同步'), findsOneWidget);
    expect(
      tester.getRect(find.text('我发起的')).left -
          tester.getRect(find.text('待我处理')).left,
      closeTo(56, 2),
    );
    final tabStrip = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('todo-tab-strip')),
    );
    expect(tabStrip.controller!.position.maxScrollExtent, 0);
    expect(find.text('搜索事项或申请编号'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(TextField, '搜索事项或申请编号')).height,
      34,
    );
    expect(find.byType(NetworkIndicator), findsNothing);
    expect(find.text('个人待办'), findsNothing);
    final flatContent = tester.widget<Material>(
      find.byKey(const Key('todos-flat-content')),
    );
    expect(flatContent.type, MaterialType.transparency);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      Theme.of(tester.element(find.byType(Scaffold))).colorScheme.surface,
    );
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('新建待办'), findsOneWidget);
    expect(find.text('新建申请'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('新建待办'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('todo-create-sheet')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('todo-title-input'))).height,
      36,
    );
    expect(
      tester.getSize(find.byKey(const Key('todo-create-button'))).height,
      36,
    );
    expect(
      tester.getSize(find.byKey(const Key('todo-create-button'))).width,
      lessThan(120),
    );
    expect(find.byType(AlertDialog), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('todo-create-sheet')), findsNothing);
  });

  testWidgets('personal todo uses one compact completion control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final source = PreviewData.oaBootstrap;
    final personalTodo = OaTodo(
      id: 'personal-completed',
      title: '已完成个人待办',
      description: '验收记录',
      status: 'completed',
      priority: 'normal',
      dueAt: DateTime(2026, 9, 1, 12),
      createdById: source.currentMemberId,
    );
    final bootstrap = OaBootstrap(
      currentMemberId: source.currentMemberId,
      displayName: source.displayName,
      todos: [...source.todos, personalTodo],
      announcements: source.announcements,
      templates: source.templates,
      approvalRequests: source.approvalRequests,
      approvalRequestsNextCursor: source.approvalRequestsNextCursor,
      approvalRequestsHasMore: source.approvalRequestsHasMore,
      notifications: source.notifications,
    );
    await _pump(
      tester,
      const TodosPage(),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        oaDraftsProvider.overrideWith((ref) async => const []),
        oaOutboxProvider.overrideWith((ref) async => const []),
      ],
    );

    await tester.tap(find.text('我发起的'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('todo-toggle-personal-completed'));
    expect(toggle, findsOneWidget);
    expect(tester.getSize(toggle), const Size.square(40));
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.byIcon(Icons.task_alt_rounded), findsNothing);
    expect(find.byIcon(Icons.checklist_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approval list loads the next page while scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final base = PreviewData.oaBootstrap;
    final pending = base.approvalRequests.firstWhere(
      (item) => item.operableTask != null,
    );
    final firstPage = List.generate(
      20,
      (index) => _copyApproval(
        pending,
        id: 'approval-page-${index + 1}',
        title: '分页审批 ${index + 1}',
      ),
    );
    final bootstrap = OaBootstrap(
      currentMemberId: base.currentMemberId,
      displayName: base.displayName,
      todos: const [],
      announcements: base.announcements,
      templates: base.templates,
      approvalRequests: firstPage,
      approvalRequestsNextCursor: 'approval-cursor-2',
      approvalRequestsHasMore: true,
      notifications: base.notifications,
    );
    var secondPageCalls = 0;

    await _pump(
      tester,
      const TodosPage(),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApprovalRequestsPageProvider.overrideWith((ref, key) async {
          expect(key.cursor, 'approval-cursor-2');
          expect(key.view, 'pending');
          secondPageCalls += 1;
          return OaApprovalRequestPage(
            items: [
              _copyApproval(pending, id: 'approval-page-21', title: '自动载入的审批'),
            ],
            nextCursor: null,
            hasMore: false,
          );
        }),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        oaDraftsProvider.overrideWith((ref) async => const []),
        oaOutboxProvider.overrideWith((ref) async => const []),
      ],
    );

    expect(secondPageCalls, 0);
    expect(find.text('加载更多'), findsNothing);
    await tester.drag(
      find.byKey(const Key('approval-page-scroll')),
      const Offset(0, -2200),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('approval-page-scroll')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(secondPageCalls, 1);
    expect(find.text('自动载入的审批'), findsOneWidget);
    expect(find.byKey(const Key('approval-page-footer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty approval result fills the next page automatically', (
    tester,
  ) async {
    final base = PreviewData.oaBootstrap;
    final pending = base.approvalRequests.firstWhere(
      (item) => item.operableTask != null,
    );
    final bootstrap = OaBootstrap(
      currentMemberId: base.currentMemberId,
      displayName: base.displayName,
      todos: const [],
      announcements: base.announcements,
      templates: base.templates,
      approvalRequests: const [],
      approvalRequestsNextCursor: 'empty-cursor-2',
      approvalRequestsHasMore: true,
      notifications: base.notifications,
    );
    var secondPageCalls = 0;

    await _pump(
      tester,
      const TodosPage(),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApprovalRequestsPageProvider.overrideWith((ref, key) async {
          secondPageCalls += 1;
          return OaApprovalRequestPage(
            items: [
              _copyApproval(pending, id: 'empty-page-result', title: '空首屏自动补齐'),
            ],
            nextCursor: null,
            hasMore: false,
          );
        }),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        oaDraftsProvider.overrideWith((ref) async => const []),
        oaOutboxProvider.overrideWith((ref) async => const []),
      ],
    );

    expect(secondPageCalls, 1);
    expect(find.text('空首屏自动补齐'), findsOneWidget);
    expect(find.text('加载更多记录'), findsNothing);
    expect(find.text('加载更多'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validation-failed outbox asks for editing instead of retry', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 31, 8);
    final failedItem = OaOutboxItem(
      id: 'outbox-validation-1',
      idempotencyKey: 'request-validation-1',
      commandType: 'submit-approval',
      payload: const {
        'applicationKey': 'leave',
        'templateId': 'template-leave',
        'title': 'AI-UAT-请假审批',
        'formDataJson': '{"reason":""}',
        'attachmentIds': <Object?>[],
        'pendingAttachments': <Object?>[],
      },
      state: 'failed',
      attempts: 1,
      nextRetryAt: now,
      lastError: 'Approval form validation failed.\n请选择请假类型。\n请填写请假事由。',
      createdAt: now,
      updatedAt: now,
    );
    await _pump(
      tester,
      const TodosPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        oaDraftsProvider.overrideWith((ref) async => const []),
        oaOutboxProvider.overrideWith((ref) async => [failedItem]),
      ],
    );

    await tester.ensureVisible(find.text('待同步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待同步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('修改后重提 · 1 次'), findsOneWidget);
    expect(
      find.text(DateFormat('MM-dd HH:mm').format(now.toLocal())),
      findsOneWidget,
    );
    expect(find.textContaining('申请表单校验失败'), findsOneWidget);
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('outbox-item-outbox-validation-1'),
            ),
          )
          .height,
      lessThanOrEqualTo(78),
    );
    await tester.tap(find.byTooltip('同步操作'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('修改后重提'), findsOneWidget);
    expect(find.text('查看失败原因'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('放弃记录'), findsOneWidget);
    await tester.tap(find.text('查看失败原因'));
    await tester.pumpAndSettle();
    expect(find.text('失败原因'), findsOneWidget);
    expect(find.textContaining('请选择请假类型。'), findsWidgets);
    expect(find.textContaining('请填写请假事由。'), findsWidgets);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('todo counts stay inline with compact tab labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final now = DateTime.utc(2026, 8, 31, 8);
    final item = OaOutboxItem(
      id: 'outbox-inline-badge',
      idempotencyKey: 'request-inline-badge',
      commandType: 'submit-approval',
      payload: const <String, Object?>{},
      state: 'pending',
      attempts: 0,
      nextRetryAt: now,
      lastError: '',
      createdAt: now,
      updatedAt: now,
    );
    await _pump(
      tester,
      const TodosPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        oaDraftsProvider.overrideWith((ref) async => const []),
        oaOutboxProvider.overrideWith((ref) async => [item]),
      ],
    );

    expect(find.byKey(const Key('todo-tabs-right-fade')), findsNothing);
    expect(find.byKey(const Key('todo-tabs-left-fade')), findsNothing);
    final tabStrip = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('todo-tab-strip')),
    );
    expect(tabStrip.controller!.position.maxScrollExtent, 0);
    final label = tester.getRect(find.text('待同步'));
    final badge = tester.getRect(
      find.byKey(const ValueKey('todo-tab-badge-待同步')),
    );
    expect((label.center.dy - badge.center.dy).abs(), lessThan(1));
    expect(label.right, lessThan(390));
    expect(find.bySemanticsLabel('待同步，1 条'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approval filters use compact rows and apply item type', (
    tester,
  ) async {
    await _pump(
      tester,
      const TodosPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        oaDraftsProvider.overrideWith((ref) async => const []),
        oaOutboxProvider.overrideWith((ref) async => const []),
      ],
    );

    await tester.tap(find.byTooltip('筛选'));
    await tester.pumpAndSettle();
    for (final key in const [
      'approval-filter-item-type',
      'approval-filter-application',
      'approval-filter-status',
      'approval-filter-updated-at',
    ]) {
      expect(tester.getSize(find.byKey(Key(key))).height, 44);
    }
    expect(tester.getSize(find.widgetWithText(FilledButton, '确定')).height, 40);

    await tester.tap(find.byKey(const Key('approval-filter-updated-at')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('近 7 天'), findsOneWidget);
    expect(find.text('近 30 天'), findsOneWidget);
    expect(find.text('最近 90 天'), findsNothing);
    await tester.tap(find.text('全部时间').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approval-filter-item-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('审批').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await tester.pumpAndSettle();
    expect(find.text('终端绑定申请'), findsNothing);
    expect(find.text('林晨的请假申请'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initiated approvals keep the desktop withdrawn state', (
    tester,
  ) async {
    await _pump(
      tester,
      const TodosPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        oaDraftsProvider.overrideWith((ref) async => const []),
        oaOutboxProvider.overrideWith((ref) async => const []),
      ],
    );

    await tester.tap(find.text('我发起的'));
    await tester.pumpAndSettle();

    expect(find.text('分级请款审批'), findsOneWidget);
    expect(find.text('已撤回'), findsOneWidget);
    expect(find.text('08-24 13:54'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminal approval can be started again with safe prefill', (
    tester,
  ) async {
    final request = PreviewData.oaBootstrap.approvalRequests.last;
    await _pump(
      tester,
      ApprovalDetailPage(approvalId: request.id),
      overrides: [
        oaApprovalRequestProvider(request.id)
            .overrideWith((ref) async => request),
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
      ],
    );

    expect(find.text('审批详情'), findsOneWidget);
    expect(find.text('分级请款审批'), findsOneWidget);
    expect(find.text('已撤回'), findsOneWidget);
    expect(find.byKey(const Key('approval-resubmit')), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(FilledButton, '再次发起')).height,
      42,
    );

    await tester.tap(find.byKey(const Key('approval-resubmit')));
    await tester.pumpAndSettle();

    expect(find.text('分级请款审批'), findsWidgets);
    expect(find.text('请款金额 *'), findsOneWidget);
    expect(find.text('请款事由 *'), findsOneWidget);
    expect(find.text('附件'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);
    expect(find.text('请款凭证.pdf'), findsNothing);
    final amount = tester.widget<TextFormField>(
      find.byType(TextFormField).at(0),
    );
    final reason = tester.widget<TextFormField>(
      find.byType(TextFormField).at(1),
    );
    expect(amount.initialValue, '4999');
    expect(reason.initialValue, '测试环境请款');
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminal approval resubmit stays owner-only', (tester) async {
    final source = PreviewData.oaBootstrap.approvalRequests.last;
    final request = _copyApproval(
      source,
      id: 'other-member-withdrawn',
      title: source.title,
      requesterId: 'another-member',
      status: 'withdrawn',
      allowedActions: const [],
      tasks: const [],
    );
    await _pump(
      tester,
      ApprovalDetailPage(approvalId: request.id),
      overrides: [
        oaApprovalRequestProvider(request.id)
            .overrideWith((ref) async => request),
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
      ],
    );

    expect(find.text('已撤回'), findsOneWidget);
    expect(find.byKey(const Key('approval-resubmit')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approval detail formats server dates and compact action rows', (
    tester,
  ) async {
    final source = PreviewData.oaBootstrap.approvalRequests.first;
    final request = OaApprovalRequest(
      id: 'real-device-format',
      requesterId: source.requesterId,
      title: '真机请假审批',
      formDataJson: '{"startAt":"2026-08-25T05:29:00.000","endAt":"2026-08-26T05:30:00.000"}',
      formSchemaSnapshotJson: '{"fields":[{"id":"startAt","label":"开始时间","type":"datetime"},{"id":"endAt","label":"结束时间","type":"datetime"}]}',
      status: 'submitted',
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
      requesterName: source.requesterName,
      requesterDepartmentName: source.requesterDepartmentName,
      templateName: source.templateName,
      templateCategory: source.templateCategory,
      allowedActions: const [],
      tasks: [
        OaApprovalTask(
          id: 'compact-comment-task',
          nodeName: '部门负责人审批',
          assigneeId: 'compact-reviewer',
          assigneeName: '测试-管理员测试',
          status: 'approved',
          version: 1,
          decision: 'approved',
          comment: 'REAL_DEVICE_ACCEPTANCE_APPROVED_LONG_COMMENT',
          canOperate: false,
          createdAt: DateTime(2026, 8, 25, 5, 40),
          completedAt: DateTime(2026, 8, 25, 5, 46),
        ),
      ],
      actions: [
        OaApprovalAction(
          actorName: '很长的审批处理人员姓名',
          action: 'submitted',
          comment: '提交申请',
          occurredAt: DateTime(2026, 8, 25, 5, 46),
        ),
        OaApprovalAction(
          actorName: '',
          action: 'service_queued',
          comment: '',
          occurredAt: DateTime(2026, 8, 25, 5, 47),
        ),
        OaApprovalAction(
          actorName: '',
          action: 'service_succeeded',
          comment: '',
          occurredAt: DateTime(2026, 8, 25, 5, 48),
        ),
      ],
      attachments: const [],
    );
    await _pump(
      tester,
      ApprovalDetailPage(approvalId: request.id),
      overrides: [
        oaApprovalRequestProvider(request.id)
            .overrideWith((ref) async => request),
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
      ],
    );

    expect(find.text('2026-08-25 05:29'), findsOneWidget);
    expect(find.text('2026-08-26 05:30'), findsOneWidget);
    expect(find.textContaining('T05:29:00.000'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    final actor = tester.widget<Text>(find.text('很长的审批处理人员姓名'));
    expect(actor.maxLines, 1);
    expect(actor.overflow, TextOverflow.ellipsis);
    final taskComment = tester.widget<Text>(
      find.text('REAL_DEVICE_ACCEPTANCE_APPROVED_LONG_COMMENT'),
    );
    expect(taskComment.maxLines, 1);
    expect(taskComment.overflow, TextOverflow.ellipsis);
    expect(find.text('后续服务已排队'), findsOneWidget);
    expect(find.text('后续服务已完成'), findsOneWidget);
    expect(find.text('service_queued'), findsNothing);
    expect(find.text('service_succeeded'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'approval detail never exposes visual-form configuration as business data',
    (tester) async {
      final source = PreviewData.oaBootstrap.approvalRequests.first;
      final request = OaApprovalRequest(
        id: 'schema-config-detail',
        requesterId: source.requesterId,
        title: '请假审批',
        formDataJson: jsonEncode({
          'days': {'mode': '自动计算', 'readOnly': '只读', 'unit': '单位天'},
          'hours': '自动计算，只读，单位小时',
          'reason': '真实请假事由',
        }),
        formSchemaSnapshotJson: jsonEncode({
          'fields': [
            {
              'id': 'days',
              'label': '请假天数',
              'type': 'number',
              'readOnly': true,
              'unit': '天',
            },
            {
              'id': 'hours',
              'label': '请假小时',
              'type': 'number',
              'readOnly': true,
              'unit': '小时',
            },
            {'id': 'reason', 'label': '请假事由', 'type': 'text'},
          ],
        }),
        status: source.status,
        createdAt: source.createdAt,
        updatedAt: source.updatedAt,
        requesterName: source.requesterName,
        requesterDepartmentName: source.requesterDepartmentName,
        templateName: source.templateName,
        templateCategory: source.templateCategory,
        allowedActions: const [],
        tasks: const [],
        actions: const [],
        attachments: const [],
      );
      await _pump(
        tester,
        ApprovalDetailPage(approvalId: request.id),
        overrides: [
          oaApprovalRequestProvider(request.id)
              .overrideWith((ref) async => request),
          oaBootstrapProvider.overrideWith(
            (ref) async => PreviewData.oaBootstrap,
          ),
          oaApplicationCatalogProvider.overrideWith(
            (ref) async => PreviewData.oaCatalog,
          ),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
        ],
      );

      expect(find.text('请假天数'), findsOneWidget);
      expect(find.text('请假小时'), findsOneWidget);
      expect(find.text('真实请假事由'), findsOneWidget);
      expect(find.textContaining('自动计算'), findsNothing);
      expect(find.textContaining('只读'), findsNothing);
      expect(find.textContaining('单位天'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('approval list keeps number, delegation and terminal status', (
    tester,
  ) async {
    final base = PreviewData.oaBootstrap;
    final original = base.approvalRequests.first;
    final delegated = _copyApproval(
      original,
      id: '12345678-delegated',
      title: '跨部门请款审批',
      tasks: [
        OaApprovalTask(
          id: 'delegated-task',
          nodeName: '业务负责人审批',
          assigneeId: 'delegated-member',
          assigneeName: '顾宁',
          status: 'pending',
          version: 1,
          decision: '',
          comment: '',
          canOperate: true,
          createdAt: DateTime(2026, 8, 31, 9),
          completedAt: null,
        ),
      ],
    );
    final terminated = _copyApproval(
      original,
      id: '87654321-terminated',
      title: '已终止请款审批',
      status: 'terminated',
      allowedActions: const [],
      tasks: const [],
    );
    final bootstrap = OaBootstrap(
      currentMemberId: base.currentMemberId,
      displayName: base.displayName,
      todos: const [],
      announcements: base.announcements,
      templates: base.templates,
      approvalRequests: [delegated, terminated],
      notifications: base.notifications,
    );

    await _pump(
      tester,
      const TodosPage(),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        oaDraftsProvider.overrideWith((ref) async => const []),
        oaOutboxProvider.overrideWith((ref) async => const []),
      ],
    );

    expect(find.textContaining('OA-20260813-123456'), findsOneWidget);
    expect(find.textContaining('代顾宁处理'), findsOneWidget);
    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('已终止请款审批'), findsOneWidget);
    expect(find.textContaining('OA-20260813-876543'), findsOneWidget);
    expect(find.text('已终止'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('about page exposes a real manual update check', (tester) async {
    await _pump(
      tester,
      const AboutPage(),
      overrides: [
        clientUpdateInfoProvider.overrideWith(
          (ref) async => const ClientUpdateInfo(
            hasPublishedVersion: true,
            updateAvailable: true,
            isMandatory: false,
            releaseId: 'release-2',
            latestVersion: '1.0.2',
            packageUrl: 'https://example.test/mobile.apk',
            packageSize: 1024,
            releaseNotes: '安全更新',
          ),
        ),
      ],
    );

    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('点击检查'), findsOneWidget);
    await tester.tap(find.text('点击检查'));
    await tester.pumpAndSettle();
    expect(find.text('发现 v1.0.2'), findsOneWidget);
    await tester.tap(find.text('发现 v1.0.2'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-update-sheet')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('版本 v1.0.2'), findsOneWidget);
    expect(find.text('安全更新'), findsOneWidget);
    expect(find.byKey(const Key('client-update-close')), findsOneWidget);
    await tester.tap(find.byKey(const Key('client-update-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-update-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dynamic approval request renders server schema fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await _pump(
      tester,
      const ApprovalRequestPage(
        applicationKey: 'attendance.leave',
        templateId: '1',
      ),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
      ],
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('请假申请'), findsOneWidget);
    expect(find.text('林晨'), findsOneWidget);
    expect(find.text('上海运营部'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
    expect(find.text('申请标题'), findsNothing);
    expect(find.text('请假类型 *'), findsOneWidget);
    expect(find.text('开始时间 *'), findsOneWidget);
    expect(find.text('结束时间 *'), findsOneWidget);
    expect(find.text('请假事由 *'), findsOneWidget);
    expect(find.text('审批流程'), findsOneWidget);
    expect(find.text('部门负责人审批'), findsOneWidget);
    expect(find.text('人事复核'), findsOneWidget);
    expect(find.text('提交申请'), findsOneWidget);
    expect(find.textContaining('/120'), findsNothing);
    expect(find.byKey(const Key('approval-workflow-inline')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approval-workflow-node-0')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('approval-draft-button'))).height,
      42,
    );
    expect(
      tester.getSize(find.byKey(const Key('approval-draft-button'))).width,
      116,
    );
    expect(
      tester.getSize(find.byKey(const Key('approval-submit-button'))).height,
      42,
    );
    expect(
      tester.getSize(find.byKey(const Key('approval-submit-button'))).width,
      140,
    );

    final reasonField = find.byKey(const ValueKey('schema-reason'));
    await tester.ensureVisible(reasonField);
    await tester.tap(reasonField);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'A',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: reasonField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'AI-UAT',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();
    expect(find.text('AI-UAT'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: reasonField,
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('schema-leaveType-select')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('年假'));
    await tester.pumpAndSettle();
    expect(find.text('年假'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('schema-startAt-date')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-date-picker-sheet')), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('duration field uses backend schema without synthetic value', (
    tester,
  ) async {
    const durationTemplate = OaApprovalTemplate(
      id: 'duration-template',
      name: '请假审批',
      category: '考勤',
      iconKey: 'leave',
      workflowKey: 'attendance.leave',
      version: 1,
      formSchemaJson: '{"fields":[{"id":"startAt","label":"开始时间","type":"datetime","required":true},{"id":"endAt","label":"结束时间","type":"datetime","required":true},{"id":"duration","label":"请假天数","type":"number","required":true,"durationStartFieldId":"startAt","durationEndFieldId":"endAt","durationUnit":"days"}]}',
    );
    final bootstrap = OaBootstrap(
      currentMemberId: PreviewData.oaBootstrap.currentMemberId,
      displayName: PreviewData.oaBootstrap.displayName,
      todos: PreviewData.oaBootstrap.todos,
      announcements: PreviewData.oaBootstrap.announcements,
      templates: const [durationTemplate],
    );
    await _pump(
      tester,
      const ApprovalRequestPage(
        applicationKey: 'attendance.leave',
        templateId: 'duration-template',
      ),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('请假天数 *'), findsOneWidget);
    expect(find.text('根据起止时间自动计算自然日'), findsOneWidget);
    expect(find.text('自动计算'), findsNothing);
    expect(find.text('只读'), findsNothing);
    expect(find.textContaining('单位天'), findsNothing);
    expect(find.byIcon(Icons.calculate_outlined), findsNothing);
    final durationField = find.byKey(const ValueKey('schema-duration-'));
    final durationInput = tester.widget<TextField>(
      find.descendant(of: durationField, matching: find.byType(TextField)),
    );
    expect(durationInput.readOnly, isTrue);
    expect(durationInput.canRequestFocus, isFalse);
    expect(durationInput.decoration?.suffixText, '天');
    await tester.tap(durationField);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schema configuration objects never render as field values', (
    tester,
  ) async {
    const template = OaApprovalTemplate(
      id: 'readonly-number-template',
      name: '请假审批',
      category: '考勤',
      iconKey: 'leave',
      workflowKey: 'attendance.leave',
      version: 1,
      formSchemaJson: '{"fields":[{"id":"days","label":"请假天数","type":"number","readOnly":true,"unit":"天"}]}',
    );
    final bootstrap = OaBootstrap(
      currentMemberId: PreviewData.oaBootstrap.currentMemberId,
      displayName: PreviewData.oaBootstrap.displayName,
      todos: PreviewData.oaBootstrap.todos,
      announcements: PreviewData.oaBootstrap.announcements,
      templates: const [template],
    );
    await _pump(
      tester,
      const ApprovalRequestPage(
        applicationKey: 'attendance.leave',
        templateId: 'readonly-number-template',
        initialFormData: {
          'days': {'mode': '自动计算', 'readOnly': '只读', 'unit': '单位天'},
        },
      ),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('自动计算'), findsNothing);
    expect(find.textContaining('只读'), findsNothing);
    expect(find.textContaining('单位天'), findsNothing);
    final input = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('schema-days-')),
        matching: find.byType(TextField),
      ),
    );
    expect(input.controller?.text ?? '', isEmpty);
    expect(input.readOnly, isTrue);
    expect(input.decoration?.suffixText, '天');
  });

  testWidgets('serialized schema description never fills readonly input', (
    tester,
  ) async {
    const template = OaApprovalTemplate(
      id: 'readonly-text-template',
      name: '请假审批',
      category: '考勤',
      iconKey: 'leave',
      workflowKey: 'attendance.leave',
      version: 1,
      formSchemaJson: '{"fields":[{"id":"days","label":"请假天数","type":"number","readOnly":true,"unit":"天"}]}',
    );
    final bootstrap = OaBootstrap(
      currentMemberId: PreviewData.oaBootstrap.currentMemberId,
      displayName: PreviewData.oaBootstrap.displayName,
      todos: PreviewData.oaBootstrap.todos,
      announcements: PreviewData.oaBootstrap.announcements,
      templates: const [template],
    );
    await _pump(
      tester,
      const ApprovalRequestPage(
        applicationKey: 'attendance.leave',
        templateId: 'readonly-text-template',
        initialFormData: {'days': '自动计算，只读，单位天'},
      ),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('自动计算'), findsNothing);
    expect(find.textContaining('只读'), findsNothing);
    expect(find.textContaining('单位天'), findsNothing);
    final input = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('schema-days-')),
        matching: find.byType(TextField),
      ),
    );
    expect(input.controller?.text ?? '', isEmpty);
    expect(input.readOnly, isTrue);
    expect(input.decoration?.suffixText, '天');
  });

  testWidgets(
    'calculation fields use backend formula readonly unit and precision',
    (tester) async {
      const calculationTemplate = OaApprovalTemplate(
        id: 'calculation-template',
        name: '分级请款审批',
        category: '财务',
        iconKey: 'payment',
        workflowKey: 'finance.tiered-payment',
        version: 1,
        formSchemaJson:
            '{"fields":['
            '{"id":"original","label":"原始费用","type":"amount","required":true,"unit":"USDT"},'
            '{"id":"ratio","label":"结算比例","type":"number","required":true},'
            '{"id":"exchangeRate","label":"汇率","type":"number","required":true},'
            '{"id":"memberCount","label":"会员人数","type":"number","required":true},'
            '{"id":"amount","label":"请款金额","type":"amount","required":true,"readOnly":true,"unit":"USDT","calculation":{"version":1,"expression":"original * ratio / exchangeRate","scale":2,"roundingMode":"half_up"}},'
            '{"id":"cost","label":"成本","type":"amount","required":true,"readOnly":true,"unit":"CNY","calculation":{"version":1,"expression":"amount * exchangeRate / memberCount","scale":4,"roundingMode":"floor"}}'
            ']}',
      );
      final bootstrap = OaBootstrap(
        currentMemberId: PreviewData.oaBootstrap.currentMemberId,
        displayName: PreviewData.oaBootstrap.displayName,
        todos: PreviewData.oaBootstrap.todos,
        announcements: PreviewData.oaBootstrap.announcements,
        templates: const [calculationTemplate],
      );
      await _pump(
        tester,
        const ApprovalRequestPage(
          applicationKey: 'finance.tiered-payment',
          templateId: 'calculation-template',
        ),
        overrides: [
          oaBootstrapProvider.overrideWith((ref) async => bootstrap),
          oaApplicationCatalogProvider.overrideWith(
            (ref) async => PreviewData.oaCatalog,
          ),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          oaWorkflowPreviewLoaderProvider.overrideWithValue(
            ({
              required String applicationKey,
              required OaApprovalTemplate template,
              required Map<String, Object?> formData,
            }) async => PreviewData.workflowPreview(template),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('自动计算'), findsNothing);
      expect(find.textContaining('只读'), findsNothing);
      final amountBefore = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('schema-amount-')),
          matching: find.byType(TextField),
        ),
      );
      expect(amountBefore.readOnly, isTrue);
      expect(amountBefore.canRequestFocus, isFalse);
      expect(amountBefore.decoration?.suffixText, 'USDT');
      expect(amountBefore.decoration?.prefixText, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('schema-original')),
        '1000',
      );
      await tester.enterText(find.byKey(const ValueKey('schema-ratio')), '0.8');
      await tester.enterText(
        find.byKey(const ValueKey('schema-exchangeRate')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('schema-memberCount')),
        '4',
      );
      await tester.pumpAndSettle();

      final amount = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('schema-amount-400.00')),
          matching: find.byType(TextField),
        ),
      );
      final cost = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('schema-cost-200.0000')),
          matching: find.byType(TextField),
        ),
      );
      expect(amount.controller?.text, '400.00');
      expect(cost.controller?.text, '200.0000');
      expect(cost.decoration?.suffixText, 'CNY');
      expect(cost.readOnly, isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('schema-cost-200.0000')));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new request resolves backend schema defaults from requester', (
    tester,
  ) async {
    final before = DateTime.now();
    final requester = PreviewData.imBootstrap.currentMember;
    const defaultsTemplate = OaApprovalTemplate(
      id: 'defaults-template',
      name: '默认值审批',
      category: '测试',
      workflowKey: 'test.defaults',
      version: 3,
      formSchemaJson:
          '{"fields":['
          '{"id":"requester","label":"申请人","type":"person","defaultValueSource":"requester"},'
          '{"id":"department","label":"申请部门","type":"department","defaultValueSource":"requester_department"},'
          '{"id":"applyDate","label":"申请日期","type":"date","defaultValueSource":"today"},'
          '{"id":"sentAt","label":"发送时间","type":"datetime","defaultValueSource":"now"},'
          '{"id":"period","label":"日期范围","type":"dateRange","defaultValueSource":"today"},'
          '{"id":"fixedDate","label":"指定日期","type":"date","defaultValueSource":"fixed","defaultValue":"2026-09-01"}'
          ']}',
    );
    final bootstrap = OaBootstrap(
      currentMemberId: PreviewData.oaBootstrap.currentMemberId,
      displayName: PreviewData.oaBootstrap.displayName,
      todos: PreviewData.oaBootstrap.todos,
      announcements: PreviewData.oaBootstrap.announcements,
      templates: const [defaultsTemplate],
    );
    Map<String, Object?>? previewValues;
    await _pump(
      tester,
      const ApprovalRequestPage(
        applicationKey: 'test.defaults',
        templateId: 'defaults-template',
      ),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(({
          required String applicationKey,
          required OaApprovalTemplate template,
          required Map<String, Object?> formData,
        }) async {
          previewValues = Map<String, Object?>.from(formData);
          return PreviewData.workflowPreview(template);
        }),
      ],
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    final after = DateTime.now();
    expect(previewValues, isNotNull);
    expect(previewValues!['requester'], requester.id);
    expect(previewValues!['department'], requester.departmentId);
    final applyDate = DateTime.parse(previewValues!['applyDate']! as String);
    expect(
      DateUtils.dateOnly(applyDate),
      anyOf(DateUtils.dateOnly(before), DateUtils.dateOnly(after)),
    );
    final sentAt = DateTime.parse(previewValues!['sentAt']! as String);
    expect(
      sentAt.isBefore(before.subtract(const Duration(seconds: 2))),
      isFalse,
    );
    expect(sentAt.isAfter(after.add(const Duration(seconds: 2))), isFalse);
    expect(previewValues!['period'], [
      DateFormat('yyyy-MM-dd').format(applyDate),
      DateFormat('yyyy-MM-dd').format(applyDate),
    ]);
    expect(previewValues!['fixedDate'], '2026-09-01');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('schema-fixedDate-date')),
        matching: find.text('2026/09/01'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('text validation and attachment behavior follow backend schema', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const schemaTemplate = OaApprovalTemplate(
      id: 'validation-template',
      name: '字段规则审批',
      category: '测试',
      workflowKey: 'test.validation',
      version: 2,
      formSchemaJson:
          '{"fields":['
          '{"id":"address","label":"请款地址","type":"text","required":true,"validationFormat":"tron_address","minLength":34,"maxLength":34},'
          '{"id":"note","label":"备注","type":"textarea","required":true,"minLength":3,"maxLength":5},'
          '{"id":"proof","label":"证明附件","type":"attachment","required":true,"multiple":true,"maxCount":3,"imagePreview":false}'
          ']}',
    );
    final bootstrap = OaBootstrap(
      currentMemberId: PreviewData.oaBootstrap.currentMemberId,
      displayName: PreviewData.oaBootstrap.displayName,
      todos: PreviewData.oaBootstrap.todos,
      announcements: PreviewData.oaBootstrap.announcements,
      templates: const [schemaTemplate],
    );
    const attachments = [
      OaLocalAttachment(
        id: 'proof-1',
        fileName: 'proof-1.png',
        contentType: 'image/png',
        bytes: [1],
        formFieldId: 'proof',
      ),
      OaLocalAttachment(
        id: 'proof-2',
        fileName: 'proof-2.png',
        contentType: 'image/png',
        bytes: [2],
        formFieldId: 'proof',
      ),
      OaLocalAttachment(
        id: 'proof-3',
        fileName: 'proof-3.png',
        contentType: 'image/png',
        bytes: [3],
        formFieldId: 'proof',
      ),
    ];
    await _pump(
      tester,
      const ApprovalRequestPage(
        applicationKey: 'test.validation',
        templateId: 'validation-template',
        initialTitle: '已有表单',
        initialAttachments: attachments,
      ),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('schema-address')),
      'T000000000000000000000000000000000',
    );
    await tester.enterText(find.byKey(const ValueKey('schema-note')), 'ab');
    await tester.drag(find.byType(ListView).first, const Offset(0, -520));
    await tester.pumpAndSettle();

    expect(find.text('3 / 3'), findsOneWidget);
    for (final attachment in attachments) {
      final row = find.byKey(ValueKey('approval-attachment-${attachment.id}'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byType(Image)),
        findsNothing,
      );
    }
    await tester.tap(find.widgetWithText(OutlinedButton, '添加文件'));
    await tester.pumpAndSettle();
    expect(find.text('证明附件最多添加 3 个附件'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approval-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('请检查：请输入有效的 TRON 地址'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(find.text('请输入有效的 TRON 地址'), findsOneWidget);
    expect(find.text('备注至少输入 3 个字符'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('schema-note')), 'abcdef');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final submitButton = find.byKey(const Key('approval-submit-button'));
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pump();
    expect(find.text('备注最多输入 5 个字符'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workflow preview stays expanded with compact desktop metadata', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovalWorkflowInline(
        preview: PreviewData.workflowPreview(
          PreviewData.oaBootstrap.templates.first,
        ),
        loading: false,
        error: null,
        templateVersion: 1,
        onRetry: () {},
      ),
      overrides: const [],
    );

    expect(find.text('审批流程'), findsOneWidget);
    expect(find.text('上海运营部 · v1'), findsOneWidget);
    expect(find.text('部门负责人审批'), findsOneWidget);
    expect(find.text('审批 · 冯逸、江敏 · 深圳运营部 · 会签'), findsOneWidget);
    expect(find.text('人事复核'), findsOneWidget);
    expect(find.text('审批 · 叶青、周宁 · 人事部 · 或签'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restored draft shows a compact image row and real preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final sourceTemplate = PreviewData.oaBootstrap.templates.firstWhere(
      (item) => item.id == '3',
    );
    final template = OaApprovalTemplate(
      id: sourceTemplate.id,
      name: sourceTemplate.name,
      category: sourceTemplate.category,
      iconKey: sourceTemplate.iconKey,
      workflowKey: sourceTemplate.workflowKey,
      version: sourceTemplate.version,
      formSchemaJson: sourceTemplate.formSchemaJson.replaceFirst(
        '"type":"attachment"',
        '"type":"attachment","multiple":true,"maxCount":20,"imagePreview":true',
      ),
    );
    final bootstrap = OaBootstrap(
      currentMemberId: PreviewData.oaBootstrap.currentMemberId,
      displayName: PreviewData.oaBootstrap.displayName,
      todos: PreviewData.oaBootstrap.todos,
      announcements: PreviewData.oaBootstrap.announcements,
      templates: [template],
    );
    final attachment = OaLocalAttachment(
      id: 'draft-image',
      fileName: 'AI-UAT-请假凭证.png',
      contentType: 'image/png',
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
      formFieldId: 'proof',
    );
    final draft = OaApprovalDraft(
      id: 'draft-1',
      applicationKey: 'finance.tiered-payment',
      templateId: template.id,
      workflowKey: template.workflowKey,
      title: 'AI-UAT-草稿恢复',
      formData: const {'amount': 4999, 'reason': '测试环境草稿'},
      updatedAt: DateTime(2026, 8, 31, 16, 55),
      attachments: [attachment],
    );
    await _pump(
      tester,
      ApprovalRequestPage(
        applicationKey: draft.applicationKey,
        templateId: template.id,
      ),
      overrides: [
        oaBootstrapProvider.overrideWith((ref) async => bootstrap),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        oaDraftLoaderProvider.overrideWithValue((_) async => draft),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
      ],
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('已恢复上次草稿'), findsOneWidget);
    expect(find.text('08-31 16:55'), findsOneWidget);
    expect(find.text('申请标题'), findsNothing);
    expect(find.text('AI-UAT-草稿恢复'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('approval-draft-status'))).height,
      30,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -560));
    await tester.pumpAndSettle();
    expect(find.text('AI-UAT-请假凭证.png'), findsOneWidget);
    final attachmentRow = find.byKey(
      const ValueKey('approval-attachment-draft-image'),
    );
    expect(tester.getSize(attachmentRow).height, 54);
    await tester.tap(attachmentRow);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('approval-local-attachment-preview')),
      findsOneWidget,
    );
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('关闭附件预览'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('approval-local-attachment-preview')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid back saves the latest local draft before leaving', (
    tester,
  ) async {
    final template = PreviewData.oaBootstrap.templates.first;
    String? savedTitle;
    Map<String, Object?>? savedFormData;
    await _pump(
      tester,
      ApprovalRequestPage(
        applicationKey: 'attendance.leave',
        templateId: template.id,
      ),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        oaDraftLoaderProvider.overrideWithValue((_) async => null),
        oaDraftSaverProvider.overrideWithValue(({
          String? id,
          required String applicationKey,
          required OaApprovalTemplate template,
          required String title,
          required Map<String, Object?> formData,
          required List<OaLocalAttachment> attachments,
        }) async {
          savedTitle = title;
          savedFormData = Map<String, Object?>.from(formData);
          return OaApprovalDraft(
            id: id ?? 'saved-draft',
            applicationKey: applicationKey,
            templateId: template.id,
            workflowKey: template.workflowKey,
            title: title,
            formData: formData,
            updatedAt: DateTime(2026, 8, 31, 16, 56),
            attachments: attachments,
          );
        }),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(
          ({
            required String applicationKey,
            required OaApprovalTemplate template,
            required Map<String, Object?> formData,
          }) async => PreviewData.workflowPreview(template),
        ),
      ],
    );

    final reasonField = find.byType(TextFormField);
    expect(reasonField, findsOneWidget);
    await tester.enterText(reasonField, 'AI-UAT-快速返回草稿');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(savedTitle, '林晨的请假申请');
    expect(savedFormData?['reason'], 'AI-UAT-快速返回草稿');
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification center shows unread approval notification', (
    tester,
  ) async {
    final notifications = [
      ...PreviewData.oaBootstrap.notifications,
      OaNotification(
        id: 'notification-read',
        requestId: '1',
        category: 'approval',
        type: 'approval.completed',
        title: '请假审批已完成',
        body: '请假申请已完成',
        importance: 'normal',
        action: 'view',
        isRead: true,
        readAt: DateTime(2026, 8, 13, 10),
        createdAt: DateTime(2026, 8, 13, 9, 30),
      ),
    ];
    await _pump(
      tester,
      const NotificationsPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaNotificationsProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap.notifications,
        ),
        oaNotificationPageProvider.overrideWith(
          (ref, key) async => OaNotificationPage(
            items: notifications
                .where((item) => !key.unreadOnly || !item.isRead)
                .toList(),
            nextCursor: null,
            hasMore: false,
          ),
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        pendingFriendApplicationsProvider.overrideWith((ref) async => const []),
      ],
    );

    expect(find.text('通知中心'), findsOneWidget);
    expect(find.text('未读'), findsOneWidget);
    expect(find.text('请假审批待处理'), findsOneWidget);
    expect(find.byTooltip('全部标为已读'), findsOneWidget);
    expect(find.text('华南运营协作'), findsOneWidget);
    expect(find.text('群聊'), findsNWidgets(2));
    expect(find.text('唐泽'), findsOneWidget);
    expect(find.text('单聊'), findsOneWidget);
    final allFilter = find.byKey(const ValueKey('notification-filter-全部'));
    final unreadFilter = find.byKey(const ValueKey('notification-filter-未读'));
    expect(
      find.descendant(of: allFilter, matching: find.text('5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: unreadFilter, matching: find.text('3')),
      findsOneWidget,
    );
    await tester.tap(unreadFilter);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: allFilter, matching: find.text('5')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: unreadFilter, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('notification-filter-row'))).height,
      lessThanOrEqualTo(52),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification center loads the next page while scrolling', (
    tester,
  ) async {
    var secondPageCalls = 0;
    OaNotification notification(int index, {String? title}) => OaNotification(
      id: 'paged-notification-$index',
      requestId: 'approval-$index',
      category: 'approval',
      type: 'approval.updated',
      title: title ?? '分页通知 $index',
      body: '审批状态更新',
      importance: 'normal',
      action: 'view',
      isRead: true,
      readAt: DateTime(2026, 9, 1, 8),
      createdAt: DateTime(2026, 9, 1, 8).subtract(Duration(minutes: index)),
    );

    await _pump(
      tester,
      const NotificationsPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaNotificationPageProvider.overrideWith((ref, key) async {
          if (key.unreadOnly) {
            return const OaNotificationPage(
              items: [],
              nextCursor: null,
              hasMore: false,
            );
          }
          if (key.cursor == 'cursor-2') {
            secondPageCalls += 1;
            return OaNotificationPage(
              items: [notification(31, title: '第二页通知')],
              nextCursor: null,
              hasMore: false,
            );
          }
          return OaNotificationPage(
            items: List.generate(30, (index) => notification(index + 1)),
            nextCursor: 'cursor-2',
            hasMore: true,
          );
        }),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        pendingFriendApplicationsProvider.overrideWith((ref) async => const []),
      ],
    );

    expect(secondPageCalls, 0);
    expect(find.text('加载更多'), findsNothing);
    await tester.drag(find.byType(ListView).last, const Offset(0, -2200));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(secondPageCalls, 1);
    expect(find.text('第二页通知'), findsOneWidget);
    expect(find.byKey(const Key('notification-page-footer')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification center fills a short first page automatically', (
    tester,
  ) async {
    var secondPageCalls = 0;
    OaNotification notification(String id, String title) => OaNotification(
      id: id,
      requestId: id,
      category: 'approval',
      type: 'approval.updated',
      title: title,
      body: '审批状态更新',
      importance: 'normal',
      action: 'view',
      isRead: true,
      readAt: DateTime(2026, 9, 1, 8),
      createdAt: DateTime(2026, 9, 1, 8),
    );

    await _pump(
      tester,
      const NotificationsPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaNotificationPageProvider.overrideWith((ref, key) async {
          if (key.unreadOnly) {
            return const OaNotificationPage(
              items: [],
              nextCursor: null,
              hasMore: false,
            );
          }
          if (key.cursor == 'cursor-short-2') {
            secondPageCalls += 1;
            return OaNotificationPage(
              items: [notification('short-2', '自动补齐的通知')],
              nextCursor: null,
              hasMore: false,
            );
          }
          return OaNotificationPage(
            items: [notification('short-1', '首屏通知')],
            nextCursor: 'cursor-short-2',
            hasMore: true,
          );
        }),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        pendingFriendApplicationsProvider.overrideWith((ref) async => const []),
      ],
    );

    expect(secondPageCalls, 1);
    expect(find.text('首屏通知'), findsOneWidget);
    expect(find.text('自动补齐的通知'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification paging retries after a new upward gesture', (
    tester,
  ) async {
    var secondPageCalls = 0;
    OaNotification notification(int index, {String? title}) => OaNotification(
      id: 'retry-notification-$index',
      requestId: 'retry-approval-$index',
      category: 'approval',
      type: 'approval.updated',
      title: title ?? '重试分页通知 $index',
      body: '审批状态更新',
      importance: 'normal',
      action: 'view',
      isRead: true,
      readAt: DateTime(2026, 9, 1, 8),
      createdAt: DateTime(2026, 9, 1, 8).subtract(Duration(minutes: index)),
    );

    await _pump(
      tester,
      const NotificationsPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaNotificationPageProvider.overrideWith((ref, key) async {
          if (key.unreadOnly) {
            return const OaNotificationPage(
              items: [],
              nextCursor: null,
              hasMore: false,
            );
          }
          if (key.cursor == 'cursor-retry-2') {
            secondPageCalls += 1;
            if (secondPageCalls == 1) throw StateError('临时网络中断');
            return OaNotificationPage(
              items: [notification(31, title: '重试恢复的通知')],
              nextCursor: null,
              hasMore: false,
            );
          }
          return OaNotificationPage(
            items: List.generate(30, (index) => notification(index + 1)),
            nextCursor: 'cursor-retry-2',
            hasMore: true,
          );
        }),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        pendingFriendApplicationsProvider.overrideWith((ref) async => const []),
      ],
    );

    await tester.drag(find.byType(ListView).last, const Offset(0, -2200));
    await tester.pumpAndSettle();
    expect(secondPageCalls, 1);
    expect(find.text('重试恢复的通知'), findsNothing);
    expect(find.byKey(const Key('notification-page-footer')), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, 300));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(secondPageCalls, 2);
    expect(find.text('重试恢复的通知'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account language exposes the desktop-aligned choices', (
    tester,
  ) async {
    await _pump(
      tester,
      const AppearanceLanguagePage(),
      overrides: [
        imLanguagePreferenceProvider.overrideWith(
          (ref) async => ImLanguagePreference(
            language: 'zh-CN',
            updatedAt: DateTime(2026, 8, 25),
          ),
        ),
      ],
    );

    expect(find.text('浅色'), findsOneWidget);
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.text('浅色'), findsWidgets);
    expect(find.text('深色'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    expect(find.text('简体中文'), findsOneWidget);
    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.text('繁體中文'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification privacy uses a compact full-row action sheet', (
    tester,
  ) async {
    var device = ImPushDevice(
      deviceId: PreviewData.demoDeviceId,
      platform: 'android',
      provider: 'fcm',
      privacyMode: 'summary',
      isEnabled: true,
      lastPushEventSequence: 18,
      updatedAt: DateTime(2026, 8, 31, 9),
    );
    final registration = MobilePushRegistration.withCallbacks(
      const _TestPushTokenSource(),
      ({
        required platform,
        required provider,
        required token,
        privacyMode = 'summary',
      }) async {
        device = ImPushDevice(
          deviceId: device.deviceId,
          platform: platform,
          provider: provider,
          privacyMode: privacyMode,
          isEnabled: true,
          lastPushEventSequence: device.lastPushEventSequence,
          updatedAt: DateTime(2026, 8, 31, 9, 10),
        );
      },
      () async {},
    );

    await _pump(
      tester,
      const NotificationSettingsPage(),
      overrides: [
        imPushDeviceProvider.overrideWith((ref) async => device),
        mobilePushRuntimeTokenProvider.overrideWith(
          (ref) => Stream.value(
            const MobilePushToken(
              platform: 'android',
              provider: 'fcm',
              value: 'test-token',
            ),
          ),
        ),
        mobilePushRegistrationProvider.overrideWithValue(registration),
      ],
    );

    expect(find.text('已启用'), findsOneWidget);
    expect(find.text('android · fcm'), findsOneWidget);
    await tester.tap(find.text('锁屏内容'));
    await tester.pumpAndSettle();
    expect(find.text('显示消息详情'), findsOneWidget);
    expect(find.text('不显示内容'), findsOneWidget);

    await tester.tap(find.text('显示消息详情'));
    await tester.pumpAndSettle();
    expect(find.text('显示消息详情'), findsOneWidget);
    expect(find.text('推送设置已同步'), findsOneWidget);
    expect(device.privacyMode, 'detail');
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification settings exposes a missing native push channel', (
    tester,
  ) async {
    final staleServerRegistration = ImPushDevice(
      deviceId: PreviewData.demoDeviceId,
      platform: 'android',
      provider: 'fcm',
      privacyMode: 'summary',
      isEnabled: true,
      lastPushEventSequence: 18,
      updatedAt: DateTime(2026, 8, 31, 9),
    );
    await _pump(
      tester,
      const NotificationSettingsPage(),
      overrides: [
        imPushDeviceProvider.overrideWith(
          (ref) async => staleServerRegistration,
        ),
        mobilePushRuntimeTokenProvider.overrideWith(
          (ref) => Stream<MobilePushToken?>.value(null),
        ),
      ],
    );

    expect(find.text('离线推送'), findsOneWidget);
    expect(find.text('未注册'), findsOneWidget);
    expect(find.text('应用内同步'), findsOneWidget);
    expect(find.text('打开应用后同步'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('push-unavailable-status'))).height,
      lessThanOrEqualTo(64),
    );
    expect(find.bySemanticsLabel('离线推送未注册，应用内同步在打开应用后进行'), findsOneWidget);
    expect(find.text('已启用'), findsNothing);
    expect(find.text('android · fcm'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification settings updates when native push token arrives', (
    tester,
  ) async {
    final runtimeTokens = StreamController<MobilePushToken?>();
    addTearDown(runtimeTokens.close);
    final serverRegistration = ImPushDevice(
      deviceId: PreviewData.demoDeviceId,
      platform: 'android',
      provider: 'fcm',
      privacyMode: 'summary',
      isEnabled: true,
      lastPushEventSequence: 18,
      updatedAt: DateTime(2026, 8, 31, 9),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imPushDeviceProvider.overrideWith((ref) async => serverRegistration),
          mobilePushRuntimeTokenProvider.overrideWith(
            (ref) => runtimeTokens.stream,
          ),
        ],
        child: const MaterialApp(home: NotificationSettingsPage()),
      ),
    );
    runtimeTokens.add(null);
    await tester.pumpAndSettle();

    expect(find.text('离线推送'), findsOneWidget);
    expect(find.text('未注册'), findsOneWidget);

    runtimeTokens.add(
      const MobilePushToken(
        platform: 'android',
        provider: 'fcm',
        value: 'late-test-token',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已启用'), findsOneWidget);
    expect(find.text('android · fcm'), findsOneWidget);
    expect(find.text('离线推送'), findsNothing);
    expect(find.text('未注册'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification center projects pending friend applications', (
    tester,
  ) async {
    final applicant = PreviewData.imBootstrap.contacts.first;
    await _pump(
      tester,
      const NotificationsPage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaNotificationsProvider.overrideWith((ref) async => const []),
        oaNotificationPageProvider.overrideWith(
          (ref, key) async => const OaNotificationPage(
            items: [],
            nextCursor: null,
            hasMore: false,
          ),
        ),
        pendingFriendApplicationsProvider.overrideWith(
          (ref) async => [
            ImFriendApplication(
              id: 'application-1',
              applicant: applicant,
              target: PreviewData.imBootstrap.currentMember,
              direction: 'incoming',
              status: 'pending',
              greeting: '申请添加你为联系人',
              createdAt: DateTime(2026, 8, 25),
            ),
          ],
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
      ],
    );

    expect(find.text('好友申请'), findsOneWidget);
    expect(find.textContaining('1 个待处理申请'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('friend request entry opens a compact dedicated list', (
    tester,
  ) async {
    final applicant = PreviewData.imBootstrap.contacts.first;
    await _pump(
      tester,
      const NotificationsPage(initialSection: 2),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaNotificationPageProvider.overrideWith(
          (ref, key) async => const OaNotificationPage(
            items: [],
            nextCursor: null,
            hasMore: false,
          ),
        ),
        pendingFriendApplicationsProvider.overrideWith(
          (ref) async => [
            ImFriendApplication(
              id: 'application-1',
              applicant: applicant,
              target: PreviewData.imBootstrap.currentMember,
              direction: 'incoming',
              status: 'pending',
              greeting: '申请添加你为联系人',
              createdAt: DateTime(2026, 8, 25),
            ),
          ],
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
      ],
    );

    expect(find.text(applicant.displayName), findsOneWidget);
    expect(find.text('申请添加你为联系人'), findsOneWidget);
    expect(find.text('接受'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification center projects real OA announcements', (
    tester,
  ) async {
    await _pump(
      tester,
      const NotificationsPage(initialSection: 1),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaNotificationsProvider.overrideWith((ref) async => const []),
        oaNotificationPageProvider.overrideWith(
          (ref, key) async => const OaNotificationPage(
            items: [],
            nextCursor: null,
            hasMore: false,
          ),
        ),
        pendingFriendApplicationsProvider.overrideWith((ref) async => const []),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
      ],
    );

    expect(find.text('公司公告'), findsOneWidget);
    expect(
      find.text(PreviewData.oaBootstrap.announcements.first.title),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('announcement entry opens the announcement section directly', (
    tester,
  ) async {
    await _pump(
      tester,
      const NotificationsPage(initialSection: 1),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaNotificationPageProvider.overrideWith(
          (ref, key) async => const OaNotificationPage(
            items: [],
            nextCursor: null,
            hasMore: false,
          ),
        ),
        pendingFriendApplicationsProvider.overrideWith((ref) async => const []),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
      ],
    );

    expect(
      find.text(PreviewData.oaBootstrap.announcements.first.title),
      findsOneWidget,
    );
    expect(find.byTooltip('全部标为已读'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('approval detail exposes every server-allowed advanced action', (
    tester,
  ) async {
    final original = PreviewData.oaBootstrap.approvalRequests.first;
    final request = OaApprovalRequest(
      id: original.id,
      requesterId: original.requesterId,
      title: original.title,
      formDataJson: original.formDataJson,
      formSchemaSnapshotJson: original.formSchemaSnapshotJson,
      status: original.status,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
      requesterName: original.requesterName,
      requesterDepartmentName: original.requesterDepartmentName,
      templateName: original.templateName,
      templateCategory: original.templateCategory,
      allowedActions: const [
        'approve',
        'reject',
        'transfer',
        'add_sign',
        'return',
        'remind',
        'withdraw',
      ],
      tasks: original.tasks,
      actions: original.actions,
      attachments: original.attachments,
      ccs: original.ccs,
    );
    await _pump(
      tester,
      ApprovalDetailPage(approvalId: request.id),
      overrides: [
        oaApprovalRequestProvider(request.id)
            .overrideWith((ref) async => request),
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
      ],
    );

    final headerAvatar = tester
        .widgetList<InitialAvatar>(find.byType(InitialAvatar))
        .first;
    expect(headerAvatar.radius, 21);
    expect(find.text('林晨的请假申请'), findsOneWidget);
    expect(find.textContaining('OA-20260813-1'), findsOneWidget);
    expect(find.text('提交申请'), findsWidgets);
    expect(find.textContaining('截止 08-14 18:00'), findsOneWidget);
    expect(find.text('冯逸 · term.sz02 · 深圳运营部'), findsOneWidget);
    expect(find.text('已同意'), findsOneWidget);
    expect(find.text('林晨 · term.sh01 · 上海运营部'), findsNWidgets(2));
    expect(find.text('待你处理'), findsOneWidget);
    expect(find.text('财务复核'), findsOneWidget);
    expect(find.text('等待中'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('冯逸 · 已读'), findsOneWidget);
    expect(find.text('江敏 · 未读'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(OutlinedButton, '驳回')).height,
      42,
    );
    expect(tester.getSize(find.widgetWithText(FilledButton, '同意')).height, 42);
    expect(
      tester.getSize(find.byKey(const Key('approval-more-actions'))),
      const Size(80, 42),
    );
    expect(find.widgetWithText(OutlinedButton, '更多'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '驳回'));
    await tester.pumpAndSettle();
    expect(find.text('驳回审批'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('驳回审批'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('转交'), findsOneWidget);
    expect(find.text('加签'), findsOneWidget);
    expect(find.text('退回'), findsOneWidget);
    expect(find.text('催办'), findsOneWidget);
    expect(find.text('撤回'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('转交'));
    await tester.pumpAndSettle();
    expect(find.text('选择转交人'), findsOneWidget);
    expect(find.byKey(const Key('approval-member-picker')), findsOneWidget);
    expect(find.text('搜索姓名、账号或部门'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('approval-member-search'))).height,
      34,
    );
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(
      find.text(PreviewData.imBootstrap.contacts.first.displayName),
    );
    await tester.pumpAndSettle();
    expect(find.text('转交原因'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加签'));
    await tester.pumpAndSettle();
    expect(find.text('选择加签人'), findsOneWidget);
    await tester.tap(
      find.text(PreviewData.imBootstrap.contacts.first.displayName),
    );
    await tester.pumpAndSettle();
    expect(find.text('前加签'), findsOneWidget);
    expect(find.text('后加签'), findsOneWidget);
    await tester.tap(find.text('前加签'));
    await tester.pumpAndSettle();
    expect(find.text('加签说明'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    for (final entry in const [
      ('退回', '退回原因'),
      ('催办', '催办留言'),
      ('撤回', '撤回原因'),
    ]) {
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$1));
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsWidgets);
      expect(find.byKey(const Key('mobile-text-input-sheet')), findsOneWidget);
      final compactSubmitSize = tester.getSize(
        find.byKey(const Key('mobile-text-input-submit')),
      );
      expect(compactSubmitSize.height, lessThanOrEqualTo(36));
      expect(compactSubmitSize.width, lessThan(120));
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('single approval secondary action uses a compact choice sheet', (
    tester,
  ) async {
    final original = PreviewData.oaBootstrap.approvalRequests.first;
    final request = OaApprovalRequest(
      id: original.id,
      requesterId: original.requesterId,
      title: original.title,
      formDataJson: original.formDataJson,
      formSchemaSnapshotJson: original.formSchemaSnapshotJson,
      status: original.status,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
      requesterName: original.requesterName,
      requesterDepartmentName: original.requesterDepartmentName,
      templateName: original.templateName,
      templateCategory: original.templateCategory,
      allowedActions: const ['transfer'],
      tasks: original.tasks,
      actions: original.actions,
      attachments: original.attachments,
      ccs: original.ccs,
    );
    await _pump(
      tester,
      ApprovalDetailPage(approvalId: request.id),
      overrides: [
        oaApprovalRequestProvider(request.id)
            .overrideWith((ref) async => request),
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
      ],
    );

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mobile-choice-sheet')), findsOneWidget);
    expect(find.text('更多操作'), findsOneWidget);
    expect(find.text('转交'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('mobile-choice-sheet'))).height,
      lessThan(160),
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'approval review success copy distinguishes node and process completion',
    () {
      expect(
        approvalReviewSuccessMessage(
          approved: true,
          requestStatus: 'submitted',
        ),
        '当前节点已同意，审批继续流转',
      );
      expect(
        approvalReviewSuccessMessage(approved: true, requestStatus: 'approved'),
        '审批已通过',
      );
      expect(
        approvalReviewSuccessMessage(
          approved: false,
          requestStatus: 'rejected',
        ),
        '审批已驳回',
      );
    },
  );

  test('approval task keeps desktop timeout metadata', () {
    final task = OaApprovalTask.fromJson({
      'id': 'task-timeout',
      'nodeId': 'finance-review',
      'nodeName': '财务复核',
      'stage': 3,
      'assigneeId': 'member-1',
      'assigneeName': '苏敏',
      'status': 'pending',
      'version': 2,
      'decision': '',
      'comment': '',
      'canOperate': true,
      'createdAt': '2026-08-31T09:00:00Z',
      'dueAt': '2026-08-31T18:00:00Z',
      'timeoutAction': 'remind',
      'timeoutLastError': 'notification delayed',
    });

    expect(task.nodeId, 'finance-review');
    expect(task.stage, 3);
    expect(task.dueAt, isNotNull);
    expect(task.timeoutAction, 'remind');
    expect(task.timeoutLastError, 'notification delayed');
  });

  testWidgets('attendance pages render punch policy and correction limit', (
    tester,
  ) async {
    final overview = OaAttendanceOverview(
      today: const OaPersonalScheduleDay(
        workDate: '2026-08-22',
        isRestDay: true,
        shiftName: '',
        expectedCheckInAt: null,
        expectedCheckOutAt: null,
        status: 'pending',
      ),
      nextPunchType: 'check_in',
      canPunch: true,
      punchMessage: '休息日允许打卡',
      monthExceptionCount: 1,
      requirePunchCorrectionApproval: true,
      monthlyPunchCorrectionLimit: 3,
      monthPunchCorrectionCount: 1,
      exceptions: const [
        OaAttendanceException(
          id: 'exception-1',
          workDate: '2026-08-21',
          type: 'missing_check_out',
          status: 'pending',
          resolutionApprovalRequestId: null,
        ),
      ],
      recentRecords: const [],
    );

    await _pump(
      tester,
      const AttendancePage(),
      overrides: [
        oaAttendanceOverviewProvider.overrideWith((ref) async => overview),
      ],
    );
    expect(find.text('休息日'), findsOneWidget);
    expect(find.text('上班打卡'), findsOneWidget);
    expect(find.text('休息日允许打卡'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('attendance-punch-button'))),
      const Size(132, 40),
    );

    await _pump(
      tester,
      const AttendancePage(correctionMode: true),
      overrides: [
        oaAttendanceOverviewProvider.overrideWith((ref) async => overview),
      ],
    );
    expect(find.text('本月异常'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('缺下班卡'), findsOneWidget);
    expect(find.text('补卡'), findsWidgets);
    await tester.tap(find.widgetWithText(OutlinedButton, '补卡').first);
    await tester.pumpAndSettle();
    expect(find.text('补缺下班卡'), findsOneWidget);
    expect(
      find.byKey(const Key('attendance-correction-sheet')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const Key('attendance-correction-time')))
          .height,
      lessThanOrEqualTo(40),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('attendance-correction-submit')))
          .height,
      lessThanOrEqualTo(40),
    );
    expect(
      tester
          .getSize(find.byKey(const Key('attendance-correction-submit')))
          .width,
      lessThan(120),
    );
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('补缺下班卡'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule uses one compact list and closes its editor safely', (
    tester,
  ) async {
    await _pump(
      tester,
      const SchedulePage(),
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
      ],
    );

    expect(find.byKey(const Key('schedule-todo-list')), findsOneWidget);
    expect(find.text('终端绑定申请'), findsOneWidget);
    expect(find.text('数据导出申请'), findsOneWidget);
    expect(find.text('审计报告确认'), findsOneWidget);
    for (final item in PreviewData.oaBootstrap.todos) {
      expect(
        tester.getSize(find.byKey(Key('schedule-todo-row-${item.id}'))).height,
        58,
      );
    }

    await tester.tap(find.byTooltip('新增待办'));
    await tester.pumpAndSettle();
    expect(find.text('新增待办'), findsOneWidget);
    expect(find.byKey(const Key('schedule-editor-sheet')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('schedule-title-input'))).height,
      36,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('schedule-description-input')))
          .height,
      64,
    );
    expect(
      tester.getSize(find.byKey(const Key('schedule-priority-select'))).height,
      36,
    );
    expect(
      tester.getSize(find.byKey(const Key('schedule-due-select'))).height,
      36,
    );
    expect(
      tester.getSize(find.byKey(const Key('schedule-save-button'))).height,
      36,
    );
    expect(
      tester.getSize(find.byKey(const Key('schedule-save-button'))).width,
      lessThan(120),
    );
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byTooltip('关闭').last);
    await tester.pumpAndSettle();
    expect(find.text('新增待办'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

final class _TestPushTokenSource implements MobilePushTokenSource {
  const _TestPushTokenSource();

  @override
  Future<MobilePushToken?> currentToken() async => const MobilePushToken(
    platform: 'android',
    provider: 'fcm',
    value: 'test-token',
  );

  @override
  Future<String?> initialTargetRoute() async => null;

  @override
  Stream<String> get notificationClicks => const Stream.empty();

  @override
  Stream<MobilePushToken> get tokenChanges => const Stream.empty();
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

OaApprovalRequest _copyApproval(
  OaApprovalRequest source, {
  required String id,
  required String title,
  String? requesterId,
  String? status,
  List<String>? allowedActions,
  List<OaApprovalTask>? tasks,
}) => OaApprovalRequest(
  id: id,
  requesterId: requesterId ?? source.requesterId,
  title: title,
  formDataJson: source.formDataJson,
  formSchemaSnapshotJson: source.formSchemaSnapshotJson,
  status: status ?? source.status,
  createdAt: source.createdAt,
  updatedAt: source.updatedAt,
  requesterName: source.requesterName,
  requesterDepartmentName: source.requesterDepartmentName,
  templateName: source.templateName,
  templateCategory: source.templateCategory,
  applicationKey: source.applicationKey,
  conversationId: source.conversationId,
  allowedActions: allowedActions ?? source.allowedActions,
  tasks: tasks ?? source.tasks,
  actions: source.actions,
  attachments: source.attachments,
  ccs: source.ccs,
);
