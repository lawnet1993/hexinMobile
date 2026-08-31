import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  test('group management page preserves paging metadata and item models', () {
    final page = ImGroupManagementPage<ImGroupJoinRequest>.fromJson({
      'items': [
        {
          'id': 'request-1',
          'applicantMemberId': 'member-1',
          'applicantName': '张三',
          'status': 'pending',
        },
      ],
      'page': 1,
      'pageSize': 50,
      'total': 51,
    }, ImGroupJoinRequest.fromJson);

    expect(page.items.single.id, 'request-1');
    expect(page.items.single.applicantName, '张三');
    expect(page.page, 1);
    expect(page.pageSize, 50);
    expect(page.total, 51);
    expect(page.hasMore, isTrue);
  });

  test('last group management page does not advertise more data', () {
    final page = ImGroupManagementPage<ImGroupNotice>.fromJson({
      'items': const <Object?>[],
      'page': 2,
      'pageSize': 50,
      'total': 51,
    }, ImGroupNotice.fromJson);

    expect(page.hasMore, isFalse);
  });
}
