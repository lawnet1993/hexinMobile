import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  test('member profile preserves server friend remark', () {
    final profile = ImMemberProfile.fromJson({
      'id': 'member-1',
      'displayName': '张三',
      'nickname': '小张',
      'signature': '测试签名',
      'userName': 'zhangsan',
      'remark': '产品组张三',
    });

    expect(profile.nickname, '小张');
    expect(profile.signature, '测试签名');
    expect(profile.remark, '产品组张三');
  });

  test('group management payloads preserve capabilities and member state', () {
    final capabilities = ImGroupManagementCapabilities.fromJson({
      'canReviewJoinRequests': true,
      'canMuteMembers': true,
      'canDissolveGroup': false,
    });
    final muted = ImMutedGroupMember.fromJson({
      'member': {
        'id': 'member-2',
        'userName': 'lisi',
        'displayName': '李四',
        'isOnline': true,
      },
      'mutedUntil': '2026-08-26T08:00:00Z',
    });

    expect(capabilities.canReviewJoinRequests, isTrue);
    expect(capabilities.canMuteMembers, isTrue);
    expect(capabilities.canDissolveGroup, isFalse);
    expect(muted.member.displayName, '李四');
    expect(muted.mutedUntil, DateTime.utc(2026, 8, 26, 8).toLocal());
  });

  test('friend application parses desktop-compatible payload', () {
    final application = ImFriendApplication.fromJson({
      'id': 'application-1',
      'direction': 'incoming',
      'status': 'pending',
      'greeting': '你好',
      'createdAt': '2026-08-25T00:00:00Z',
      'applicant': {
        'id': 'member-1',
        'userName': 'qa.member',
        'displayName': '测试成员',
        'isOnline': true,
      },
      'target': {
        'id': 'member-2',
        'userName': 'qa.target',
        'displayName': '目标成员',
        'isOnline': false,
      },
    });

    expect(application.id, 'application-1');
    expect(application.direction, 'incoming');
    expect(application.status, 'pending');
    expect(application.applicant.username, 'qa.member');
    expect(application.target.displayName, '目标成员');
  });

  test('batch accept result parses desktop-compatible payload', () {
    final result = ImFriendApplicationBatchResult.fromJson({
      'processed': 4,
      'remaining': 2,
    });

    expect(result.processed, 4);
    expect(result.remaining, 2);
  });

  test('assistant task preserves desktop-compatible progress and state', () {
    final task = ImAssistantTask.fromJson({
      'id': 'task-1',
      'messageKind': 'text',
      'content': '设备维护通知',
      'attachmentJson': '',
      'status': 'running',
      'receiverCount': 8,
      'successCount': 5,
      'failureCount': 1,
      'createdAt': '2026-08-25T01:00:00Z',
      'updatedAt': '2026-08-25T01:01:00Z',
    });

    expect(task.content, '设备维护通知');
    expect(task.receiverCount, 8);
    expect(task.successCount, 5);
    expect(task.failureCount, 1);
    expect(task.canCancel, isTrue);
  });
}
