import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  test('member page keeps server paging and real online state', () {
    final page = ImMemberPage.fromJson({
      'items': [
        {
          'id': 'member-1',
          'userName': 'term.member1',
          'displayName': '成员一',
          'isOnline': true,
          'departmentId': 'department-1',
          'departmentName': '测试部',
          'isOrganizationManager': false,
          'isFriend': true,
          'canStartDirect': true,
        },
      ],
      'page': 2,
      'pageSize': 50,
      'total': 123,
    });

    expect(page.page, 2);
    expect(page.pageSize, 50);
    expect(page.total, 123);
    expect(page.items.single.isOnline, isTrue);
  });

  test('group history deletion job exposes terminal server states', () {
    final completed = ImGroupHistoryDeletionJob.fromJson({
      'id': 'job-1',
      'conversationId': 'group-1',
      'status': 'completed',
      'deletedMessageCount': 12,
      'errorMessage': '',
      'createdAt': '2026-08-25T00:00:00Z',
      'updatedAt': '2026-08-25T00:00:01Z',
      'completedAt': '2026-08-25T00:00:01Z',
    });
    final failed = ImGroupHistoryDeletionJob.fromJson({
      'id': 'job-2',
      'conversationId': 'group-1',
      'status': 'failed',
      'deletedMessageCount': 0,
      'errorMessage': 'denied',
    });

    expect(completed.isCompleted, isTrue);
    expect(completed.isFailed, isFalse);
    expect(completed.deletedMessageCount, 12);
    expect(failed.isCompleted, isFalse);
    expect(failed.isFailed, isTrue);
    expect(failed.errorMessage, 'denied');
  });
}
