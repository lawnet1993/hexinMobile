import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/config/app_environment.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('demo auxiliary actions update the visible preview state', () async {
    if (!AppEnvironment.demoMode) return;
    PreviewData.resetDemoDeviceSettings();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repository = container.read(imRepositoryProvider);

    expect(PreviewData.demoGroupMutedMembers, isNotEmpty);
    await repository.updateGroupMemberMute(
      'ops',
      PreviewData.demoGroupMutedMembers.single.member.id,
      null,
    );
    expect(PreviewData.demoGroupMutedMembers, isEmpty);

    expect(PreviewData.demoGroupJoinRequests, isNotEmpty);
    await repository.handleGroupJoinRequest(
      'ops',
      PreviewData.demoGroupJoinRequests.single.id,
      true,
    );
    expect(PreviewData.demoGroupJoinRequests, isEmpty);

    final notification = PreviewData.oaBootstrap.notifications.single;
    expect(notification.isRead, isFalse);
    await container
        .read(oaRepositoryProvider)
        .markNotificationRead(notification.id);
    expect(PreviewData.oaBootstrap.notifications.single.isRead, isTrue);

    final task = await repository.createAssistantTask(
      receiverMemberIds: const ['1', '2'],
      content: '演示群发状态验证',
    );
    expect(task.receiverCount, 2);
    await repository.cancelAssistantTask(task.id);
    expect(
      PreviewData.imAssistantTasks
          .firstWhere((item) => item.id == task.id)
          .status,
      'cancelled',
    );

    PreviewData.demoFriendRemarks.clear();
    final friendProfile = await repository.memberProfile('1');
    expect(friendProfile.remark, isEmpty);
    await repository.updateFriendRemark('1', '深圳负责人');
    expect((await repository.memberProfile('1')).remark, '深圳负责人');

    final oaRepository = container.read(oaRepositoryProvider);
    final todo = await oaRepository.createTodo(
      title: '模拟器个人待办验证',
      priority: 'high',
    );
    expect(todo.status, 'todo');
    expect(todo.createdById, PreviewData.oaBootstrap.currentMemberId);
    expect(
      PreviewData.oaBootstrap.todos
          .firstWhere((item) => item.id == todo.id)
          .title,
      '模拟器个人待办验证',
    );

    await oaRepository.updateTodo(todo.id, status: 'completed');
    expect(
      PreviewData.oaBootstrap.todos
          .firstWhere((item) => item.id == todo.id)
          .status,
      'completed',
    );

    final devices = await container.read(imDeviceAuthorizationsProvider.future);
    expect(devices, hasLength(2));
    expect(devices.first.deviceId, PreviewData.demoDeviceId);
    expect(devices.last.deviceName, 'Windows 桌面终端');

    await repository.revokeDeviceAuthorization(devices.last.deviceId);
    expect(
      (await repository.deviceAuthorizations()).last.isAuthorized,
      isFalse,
    );

    await repository.registerDeviceAuthorization(deviceName: 'Android 模拟器');
    expect(
      (await repository.deviceAuthorizations()).first.isAuthorized,
      isTrue,
    );

    expect((await repository.pushDevice())?.privacyMode, 'summary');
    await repository.registerPushDevice(
      platform: 'android',
      provider: 'fcm',
      token: 'demo-token-not-logged',
      privacyMode: 'detail',
    );
    expect((await repository.pushDevice())?.privacyMode, 'detail');
  });

  test('demo approval distinguishes intermediate and final approval', () async {
    if (!AppEnvironment.demoMode) return;
    final requests = PreviewData.oaBootstrap.approvalRequests;
    final notifications = PreviewData.oaBootstrap.notifications;
    final requestSnapshot = List.of(requests);
    final notificationSnapshot = List.of(notifications);
    addTearDown(() {
      requests
        ..clear()
        ..addAll(requestSnapshot);
      notifications
        ..clear()
        ..addAll(notificationSnapshot);
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final repository = container.read(oaRepositoryProvider);
    final initial = requests.firstWhere((item) => item.id == '1');
    expect(initial.operableTask?.id, 'task-2');
    expect(initial.tasks.last.status, 'waiting');

    final intermediate = await repository.reviewApproval(
      requestId: initial.id,
      taskId: 'task-2',
      expectedTaskVersion: 1,
      decision: 'approved',
      comment: '部门负责人同意',
    );
    expect(intermediate.status, 'submitted');
    expect(intermediate.operableTask?.id, 'task-3');
    expect(intermediate.tasks[1].status, 'approved');
    expect(intermediate.tasks[2].status, 'pending');
    expect(intermediate.allowedActions, containsAll(['approve', 'reject']));
    expect(notifications.single.isRead, isFalse);
    expect(notifications.single.body, contains('财务复核'));

    await expectLater(
      repository.reviewApproval(
        requestId: initial.id,
        taskId: 'task-2',
        expectedTaskVersion: 1,
        decision: 'approved',
        comment: '',
      ),
      throwsStateError,
    );

    final completed = await repository.reviewApproval(
      requestId: intermediate.id,
      taskId: 'task-3',
      expectedTaskVersion: 1,
      decision: 'approved',
      comment: '财务复核同意',
    );
    expect(completed.status, 'approved');
    expect(completed.operableTask, isNull);
    expect(completed.allowedActions, isEmpty);
    expect(completed.tasks.last.status, 'approved');
    expect(notifications.single.isRead, isTrue);
    expect(notifications.single.title, contains('已处理'));
  });

  test(
    'demo approval rejection cancels waiting work and closes the request',
    () async {
      if (!AppEnvironment.demoMode) return;
      final requests = PreviewData.oaBootstrap.approvalRequests;
      final notifications = PreviewData.oaBootstrap.notifications;
      final requestSnapshot = List.of(requests);
      final notificationSnapshot = List.of(notifications);
      addTearDown(() {
        requests
          ..clear()
          ..addAll(requestSnapshot);
        notifications
          ..clear()
          ..addAll(notificationSnapshot);
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final repository = container.read(oaRepositoryProvider);
      final initial = requests.firstWhere((item) => item.id == '1');

      await expectLater(
        repository.reviewApproval(
          requestId: initial.id,
          taskId: 'task-2',
          expectedTaskVersion: 1,
          decision: 'rejected',
          comment: '',
        ),
        throwsArgumentError,
      );
      expect(requests.firstWhere((item) => item.id == '1').status, 'submitted');

      final rejected = await repository.reviewApproval(
        requestId: initial.id,
        taskId: 'task-2',
        expectedTaskVersion: 1,
        decision: 'rejected',
        comment: '请补充工作交接说明',
      );
      expect(rejected.status, 'rejected');
      expect(rejected.operableTask, isNull);
      expect(rejected.allowedActions, isEmpty);
      expect(rejected.tasks[1].status, 'rejected');
      expect(rejected.tasks[1].comment, '请补充工作交接说明');
      expect(rejected.tasks[2].status, 'cancelled');
      expect(rejected.actions.last.action, 'rejected');
      expect(notifications.single.isRead, isTrue);
      expect(notifications.single.title, contains('已处理'));
      expect(notifications.single.body, contains('已驳回'));

      await expectLater(
        repository.reviewApproval(
          requestId: initial.id,
          taskId: 'task-2',
          expectedTaskVersion: 1,
          decision: 'rejected',
          comment: '再次驳回',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'demo approval transfer reassigns work without mixing assignees',
    () async {
      if (!AppEnvironment.demoMode) return;
      final requests = PreviewData.oaBootstrap.approvalRequests;
      final notifications = PreviewData.oaBootstrap.notifications;
      final requestSnapshot = List.of(requests);
      final notificationSnapshot = List.of(notifications);
      addTearDown(() {
        requests
          ..clear()
          ..addAll(requestSnapshot);
        notifications
          ..clear()
          ..addAll(notificationSnapshot);
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final repository = container.read(oaRepositoryProvider);
      final initial = requests.firstWhere((item) => item.id == '1');
      final task = initial.operableTask!;

      await expectLater(
        repository.transferApproval(
          requestId: initial.id,
          task: task,
          newAssigneeId: '2',
          reason: '',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.transferApproval(
          requestId: initial.id,
          task: task,
          newAssigneeId: PreviewData.oaBootstrap.currentMemberId,
          reason: '转交给自己',
        ),
        throwsArgumentError,
      );

      final transferred = await repository.transferApproval(
        requestId: initial.id,
        task: task,
        newAssigneeId: '2',
        reason: '请数据部门协助复核',
      );
      expect(transferred.status, 'submitted');
      expect(transferred.operableTask, isNull);
      expect(transferred.allowedActions, isEmpty);
      expect(transferred.tasks, hasLength(4));
      expect(transferred.tasks[1].status, 'transferred');
      expect(transferred.tasks[1].comment, '请数据部门协助复核');
      expect(transferred.tasks[2].status, 'pending');
      expect(transferred.tasks[2].assigneeId, '2');
      expect(transferred.tasks[2].assigneeName, '叶青');
      expect(transferred.tasks[2].canOperate, isFalse);
      expect(transferred.tasks[3].status, 'waiting');
      expect(transferred.actions.last.action, 'transferred');
      expect(transferred.actions.last.comment, contains('叶青'));
      expect(notifications.single.isRead, isTrue);
      expect(notifications.single.title, contains('已转交'));
      expect(notifications.single.body, contains('叶青'));

      await expectLater(
        repository.transferApproval(
          requestId: initial.id,
          task: task,
          newAssigneeId: '3',
          reason: '重复转交',
        ),
        throwsStateError,
      );
    },
  );
}
