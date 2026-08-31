import 'dart:async';

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
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';

void main() {
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
    expect(find.text('统一处理任务与审批'), findsOneWidget);
    expect(find.text('待我处理'), findsOneWidget);
    expect(find.text('抄送我的'), findsOneWidget);
    expect(find.text('草稿箱'), findsOneWidget);
    expect(find.text('待同步'), findsOneWidget);
    expect(tester.getRect(find.text('待同步')).right, lessThan(390));
    expect(find.text('搜索事项、申请编号或发起人'), findsOneWidget);
    expect(find.byType(NetworkIndicator), findsNothing);
    expect(find.text('个人待办'), findsNothing);
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    expect(find.text('新建待办'), findsOneWidget);
    expect(find.text('新建申请'), findsOneWidget);
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
      lastError: '申请表单校验失败，请检查必填项',
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

    await tester.tap(find.text('待同步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需修改后重提'), findsOneWidget);
    await tester.tap(find.byTooltip('同步操作'));
    await tester.pumpAndSettle();
    expect(find.text('修改后重提'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('放弃记录'), findsOneWidget);
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
    expect(find.text('请款金额'), findsOneWidget);
    expect(find.text('请款事由'), findsOneWidget);
    expect(find.text('附件'), findsOneWidget);
    expect(find.text('0 / 20'), findsOneWidget);
    expect(find.text('请款凭证.pdf'), findsNothing);
    final amount = tester.widget<TextFormField>(
      find.byType(TextFormField).at(1),
    );
    final reason = tester.widget<TextFormField>(
      find.byType(TextFormField).at(2),
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
      tasks: const [],
      actions: [
        OaApprovalAction(
          actorName: '很长的审批处理人员姓名',
          action: 'submitted',
          comment: '提交申请',
          occurredAt: DateTime(2026, 8, 25, 5, 46),
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
    final actor = tester.widget<Text>(find.text('很长的审批处理人员姓名'));
    expect(actor.maxLines, 1);
    expect(actor.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

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
    expect(tester.takeException(), isNull);
  });

  testWidgets('dynamic approval request renders server schema fields', (
    tester,
  ) async {
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
      ],
    );

    expect(find.text('请假申请'), findsOneWidget);
    expect(find.text('林晨'), findsOneWidget);
    expect(find.text('上海运营部'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
    expect(find.text('请假类型'), findsOneWidget);
    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('结束时间'), findsOneWidget);
    expect(find.text('请假事由'), findsOneWidget);
    expect(find.text('查看审批流程'), findsOneWidget);
    expect(find.text('提交申请'), findsOneWidget);
    expect(find.textContaining('/120'), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('approval-form-surface'))).height,
      lessThanOrEqualTo(400),
    );
    expect(
      tester.getSize(find.byKey(const Key('approval-workflow-button'))).height,
      40,
    );
    expect(
      tester.getSize(find.byKey(const Key('approval-draft-button'))).height,
      42,
    );
    expect(
      tester.getSize(find.byKey(const Key('approval-submit-button'))).height,
      42,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('workflow preview keeps desktop metadata in a compact sheet', (
    tester,
  ) async {
    await _pump(
      tester,
      ApprovalWorkflowPreviewSheet(
        preview: PreviewData.workflowPreview(
          PreviewData.oaBootstrap.templates.first,
        ),
      ),
      overrides: const [],
    );

    expect(find.text('审批流程'), findsOneWidget);
    expect(find.text('上海运营部 · v1'), findsOneWidget);
    expect(find.text('部门负责人审批'), findsOneWidget);
    expect(find.text('审批 · 冯逸、江敏 · 深圳运营部 · 会签'), findsOneWidget);
    expect(find.text('人事复核'), findsOneWidget);
    expect(find.text('审批 · 叶青、周宁 · 人事部 · 或签'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification center shows unread approval notification', (
    tester,
  ) async {
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
            items: PreviewData.oaBootstrap.notifications,
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
    expect(
      tester.getSize(find.byKey(const Key('notification-filter-row'))).height,
      lessThanOrEqualTo(52),
    );
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
    expect(find.text('浅色'), findsWidgets);
    expect(find.text('深色'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    expect(find.text('简体中文'), findsOneWidget);
    await tester.tap(find.text('简体中文'));
    await tester.pumpAndSettle();
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

    expect(find.text('当前设备未注册推送服务'), findsOneWidget);
    expect(find.text('打开应用后会自动同步消息和 OA 通知'), findsOneWidget);
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

    expect(find.text('当前设备未注册推送服务'), findsOneWidget);

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
    expect(find.text('当前设备未注册推送服务'), findsNothing);
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
    expect(find.text('搜索姓名、账号或部门'), findsOneWidget);
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
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
    }
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
    await tester.binding.handlePopRoute();
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
