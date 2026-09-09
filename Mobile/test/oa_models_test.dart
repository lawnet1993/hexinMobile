import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  test('OA bootstrap parses approval tasks, actions and notifications', () {
    final bootstrap = OaBootstrap.fromJson({
      'currentMember': {'id': 'member-1', 'displayName': '林晨'},
      'todos': <Object?>[],
      'announcements': <Object?>[],
      'approvalTemplates': [
        {
          'id': 'template-1',
          'name': '请假审批',
          'category': '考勤',
          'iconKey': 'leave',
          'workflowKey': 'attendance.leave',
          'version': 4,
          'formSchemaJson':
              '{"fields":[{"id":"reason","label":"请假事由","type":"textarea"}]}',
        },
      ],
      'approvalRequests': [
        {
          'id': 'request-1',
          'requesterId': 'member-2',
          'title': '请假审批',
          'formDataJson': '{"days":1}',
          'formSchemaSnapshotJson': '{"fields":[]}',
          'status': 'submitted',
          'createdAt': '2026-08-22T08:00:00Z',
          'updatedAt': '2026-08-22T08:01:00Z',
          'requesterName': '小美',
          'requesterDepartmentName': '运营部',
          'templateName': '请假审批',
          'templateCategory': '考勤',
          'applicationKey': 'attendance.leave',
          'allowedActions': ['approve', 'reject'],
          'tasks': [
            {
              'id': 'task-1',
              'nodeName': '部门负责人审批',
              'assigneeId': 'member-1',
              'assigneeName': '林晨',
              'status': 'pending',
              'version': 3,
              'decision': '',
              'comment': '',
              'canOperate': true,
              'createdAt': '2026-08-22T08:00:00Z',
              'completedAt': null,
            },
          ],
          'actions': [
            {
              'actorName': '小美',
              'action': 'submitted',
              'comment': '提交申请',
              'occurredAt': '2026-08-22T08:00:00Z',
            },
          ],
          'attachments': [
            {
              'id': 'attachment-1',
              'fileName': '交接清单.pdf',
              'contentType': 'application/pdf',
              'size': 2048,
            },
          ],
        },
      ],
      'notifications': [
        {
          'id': 'notification-1',
          'requestId': 'request-1',
          'category': 'approval',
          'type': 'approval.task.created',
          'title': '审批待处理',
          'body': '小美提交的请假审批等待你处理',
          'importance': 'high',
          'action': 'review',
          'isRead': false,
          'readAt': null,
          'createdAt': '2026-08-22T08:01:00Z',
          'targetKind': 'im_conversation',
          'targetId': 'conversation-1',
        },
      ],
    });

    expect(bootstrap.currentMemberId, 'member-1');
    expect(bootstrap.templates.single.workflowKey, 'attendance.leave');
    expect(bootstrap.templates.single.version, 4);
    expect(bootstrap.templates.single.formSchemaJson, contains('reason'));
    expect(bootstrap.approvalRequests, hasLength(1));
    expect(bootstrap.approvalRequests.single.operableTask?.version, 3);
    expect(
      bootstrap.approvalRequests.single.applicationKey,
      'attendance.leave',
    );
    expect(
      bootstrap.approvalRequests.single.allowedActions,
      containsAll(['approve', 'reject']),
    );
    expect(
      bootstrap.approvalRequests.single.actions.single.action,
      'submitted',
    );
    expect(
      bootstrap.approvalRequests.single.attachments.single.fileName,
      '交接清单.pdf',
    );
    expect(bootstrap.notifications.single.requestId, 'request-1');
    expect(bootstrap.notifications.single.isRead, isFalse);
    expect(bootstrap.notifications.single.targetKind, 'im_conversation');
    expect(bootstrap.notifications.single.targetId, 'conversation-1');
    expect(
      bootstrap.notifications.single.toJson()['targetId'],
      'conversation-1',
    );
  });

  test('attendance overview keeps punch and correction policy state', () {
    final overview = OaAttendanceOverview.fromJson({
      'today': {
        'workDate': '2026-08-22',
        'isRestDay': true,
        'shiftName': '',
        'expectedCheckInAt': null,
        'expectedCheckOutAt': null,
        'result': null,
      },
      'nextPunchType': 'check_in',
      'canPunch': true,
      'punchMessage': '休息日允许打卡',
      'monthExceptionCount': 1,
      'requirePunchCorrectionApproval': true,
      'monthlyPunchCorrectionLimit': 3,
      'monthPunchCorrectionCount': 1,
      'exceptions': [
        {
          'id': 'exception-1',
          'workDate': '2026-08-21',
          'type': 'missing_check_out',
          'status': 'pending',
          'resolutionApprovalRequestId': null,
        },
      ],
      'recentRecords': [
        {
          'id': 'record-1',
          'type': 'check_in',
          'occurredAt': '2026-08-22T01:00:00Z',
          'source': 'terminal',
          'periodIndex': 0,
        },
      ],
    });

    expect(overview.today?.isRestDay, isTrue);
    expect(overview.canPunch, isTrue);
    expect(overview.requirePunchCorrectionApproval, isTrue);
    expect(overview.exceptions.single.type, 'missing_check_out');
    expect(overview.recentRecords.single.type, 'check_in');
  });

  test('workflow preview parses resolved actors and countersign mode', () {
    final preview = OaWorkflowPreview.fromJson({
      'templateId': 'template-1',
      'templateName': '请款审批',
      'workflowKey': 'finance.payment',
      'templateVersion': 3,
      'requesterDepartmentName': '运营部',
      'isResolved': true,
      'nodes': [
        {
          'stage': 1,
          'nodeId': 'manager',
          'nodeName': '部门负责人审批',
          'nodeType': 'approval',
          'isResolved': true,
          'completionMode': 'all',
          'actors': [
            {
              'memberId': 'member-1',
              'displayName': '林晨',
              'userName': 'test05',
              'departmentName': '运营部',
            },
          ],
        },
      ],
    });

    expect(preview.isResolved, isTrue);
    expect(preview.nodes.single.nodeName, '部门负责人审批');
    expect(preview.nodes.single.actors.single.displayName, '林晨');
    expect(preview.nodes.single.completionMode, 'all');
  });

  test('approval task parses node completion semantics when supplied', () {
    final task = OaApprovalTask.fromJson({
      'id': 'task-1',
      'nodeId': 'finance-review',
      'nodeName': '财务复核',
      'nodeType': 'approval',
      'stage': 2,
      'completionMode': 'any',
      'assigneeId': 'member-1',
      'assigneeName': '测试审批人',
      'status': 'pending',
      'version': 1,
      'decision': '',
      'comment': '',
      'canOperate': true,
    });

    expect(task.nodeId, 'finance-review');
    expect(task.nodeType, 'approval');
    expect(task.completionMode, 'any');
  });

  test('approval cursor page and bootstrap paging metadata parse', () {
    final page = OaApprovalRequestPage.fromJson({
      'items': <Object?>[],
      'nextCursor': 'cursor-2',
      'hasMore': true,
    });
    final bootstrap = OaBootstrap.fromJson({
      'currentMember': {'id': 'member-1', 'displayName': '林晨'},
      'todos': <Object?>[],
      'announcements': <Object?>[],
      'approvalTemplates': <Object?>[],
      'approvalRequests': <Object?>[],
      'approvalRequestsNextCursor': 'cursor-1',
      'approvalRequestsHasMore': true,
      'notifications': <Object?>[],
    });

    expect(page.nextCursor, 'cursor-2');
    expect(page.hasMore, isTrue);
    expect(bootstrap.approvalRequestsNextCursor, 'cursor-1');
    expect(bootstrap.approvalRequestsHasMore, isTrue);
  });
}
