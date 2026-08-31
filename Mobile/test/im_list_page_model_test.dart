import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  test('通用分页模型保留桌面端分页字段并判断是否还有数据', () {
    final page = ImListPage<ImAssistantTask>.fromJson({
      'items': [
        {
          'id': 'task-1',
          'content': '测试任务',
          'status': 'completed',
          'receiverCount': 2,
          'successCount': 2,
          'failureCount': 0,
        },
      ],
      'page': 1,
      'pageSize': 50,
      'total': 51,
    }, ImAssistantTask.fromJson);

    expect(page.items.single.id, 'task-1');
    expect(page.page, 1);
    expect(page.pageSize, 50);
    expect(page.total, 51);
    expect(page.hasMore, isTrue);
  });

  test('缺少分页元数据时使用请求页作为回退', () {
    final page = ImListPage<ImAssistantTask>.fromJson(
      const {'items': <Object?>[]},
      ImAssistantTask.fromJson,
      fallbackPage: 3,
      fallbackPageSize: 20,
    );

    expect(page.page, 3);
    expect(page.pageSize, 20);
    expect(page.total, 40);
    expect(page.hasMore, isFalse);
  });
}
