import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/notifications/presentation/notifications_page.dart';

void main() {
  test('notification targets are routed by the desktop target contract', () {
    expect(
      notificationTargetRoute(
        _notification(targetKind: 'im_conversation', targetId: ' group/研发 '),
      ),
      '/chat/group%2F%E7%A0%94%E5%8F%91',
    );
    expect(
      notificationTargetRoute(
        _notification(targetKind: 'im_friend_requests', targetId: 'requests'),
      ),
      '/contacts?mode=requests',
    );
    expect(
      notificationTargetRoute(
        _notification(
          requestId: 'request-fallback',
          targetKind: 'oa_approval',
          targetId: 'request-target',
        ),
      ),
      '/approval/request-target',
    );
    expect(
      notificationTargetRoute(_notification(requestId: 'request-legacy')),
      '/approval/request-legacy',
    );
    expect(
      notificationTargetRoute(
        _notification(
          category: 'attendance',
          type: 'attendance.exception.detected',
        ),
      ),
      '/attendance',
    );
    expect(
      notificationTargetRoute(
        _notification(
          category: 'attendance_exception',
          type: 'attendance.exception.detected',
          targetId: 'exception/2026-08-14',
        ),
      ),
      '/attendance?exceptionId=exception%2F2026-08-14',
    );
    expect(
      notificationTargetRoute(
        _notification(
          category: 'inspection',
          type: 'inspection.started',
          targetKind: 'oa_approval',
        ),
      ),
      '/punch?inspection=active',
    );
  });

  test('invalid conversation targets fail closed', () {
    expect(
      notificationTargetRoute(
        _notification(targetKind: 'im_conversation', targetId: '   '),
      ),
      isNull,
    );
  });

  test('notification feed keeps direct chat, group chat and OA distinct', () {
    final feed = buildMobileNotificationFeed(
      oaNotifications: [_notification(requestId: 'oa-1')],
      conversations: [
        ImConversation(
          id: 'direct-1',
          type: 'direct',
          title: '林川',
          preview: '收到',
          updatedAt: DateTime(2026, 8, 31, 10),
          unreadCount: 1,
          lastMessageSequence: 8,
        ),
        ImConversation(
          id: 'group-1',
          type: 'group',
          title: '外站工作群',
          preview: '请核对',
          updatedAt: DateTime(2026, 8, 31, 11),
          unreadCount: 2,
          lastMessageSequence: 9,
        ),
      ],
      friendApplications: const [],
    );

    expect(feed.map((item) => item.id), [
      'im-conversation:group-1',
      'im-conversation:direct-1',
      'notification-1',
    ]);
    expect(feed[0].type, 'im.group.message');
    expect(feed[1].type, 'im.direct.message');
    expect(feed[2].targetKind, isEmpty);
    expect(notificationKindLabel(feed[0]), '群聊');
    expect(notificationKindLabel(feed[1]), '单聊');
    expect(notificationKindLabel(feed[2]), '审批');
  });

  test(
    'application notification labels do not collapse into system notices',
    () {
      expect(
        notificationKindLabel(
          _notification(category: 'attendance', type: 'attendance.exception'),
        ),
        '考勤',
      );
      expect(
        notificationKindLabel(
          _notification(category: 'inspection', type: 'inspection.started'),
        ),
        '巡检',
      );
      expect(
        notificationKindLabel(
          _notification(category: 'security', type: 'security.risk.detected'),
        ),
        '安全',
      );
      expect(
        notificationKindLabel(
          _notification(category: 'announcement', type: 'announcement.created'),
        ),
        '公告',
      );
      expect(
        notificationKindLabel(
          _notification(category: 'other', type: 'business.event'),
        ),
        '应用',
      );
    },
  );

  test('notification feed deduplicates only the exact event identity', () {
    final feed = buildMobileNotificationFeed(
      oaNotifications: [
        _notification(id: 'inspection-1', category: 'inspection'),
        _notification(id: 'inspection-1', category: 'inspection'),
        _notification(id: 'inspection-2', category: 'inspection'),
      ],
      conversations: const [],
      friendApplications: const [],
    );

    expect(feed.map((item) => item.id), ['inspection-1', 'inspection-2']);
  });
}

OaNotification _notification({
  String id = 'notification-1',
  String requestId = '',
  String targetKind = '',
  String targetId = '',
  String category = 'approval',
  String type = 'test',
}) => OaNotification(
  id: id,
  requestId: requestId,
  category: category,
  type: type,
  title: '测试通知',
  body: '',
  importance: 'normal',
  action: 'view',
  isRead: true,
  readAt: null,
  createdAt: null,
  targetKind: targetKind,
  targetId: targetId,
);
