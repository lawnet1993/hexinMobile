import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

String? notificationTargetRoute(OaNotification item) {
  final targetId = item.targetId.trim();
  switch (item.targetKind.trim()) {
    case 'im_conversation':
      if (targetId.isEmpty) return null;
      return '/chat/${Uri.encodeComponent(targetId)}';
    case 'im_friend_requests':
      return '/contacts?mode=requests';
    case 'oa_approval':
      final approvalId = targetId.isNotEmpty ? targetId : item.requestId.trim();
      if (approvalId.isEmpty) return null;
      return '/approval/${Uri.encodeComponent(approvalId)}';
    default:
      final approvalId = item.requestId.trim();
      if (approvalId.isEmpty) return null;
      return '/approval/${Uri.encodeComponent(approvalId)}';
  }
}

List<OaNotification> buildMobileNotificationFeed({
  required List<OaNotification> oaNotifications,
  required List<ImConversation> conversations,
  required List<ImFriendApplication> friendApplications,
}) {
  final conversationNotifications = conversations
      .where(
        (item) =>
            item.isSupported &&
            (item.lastMessageSequence > 0 ||
                item.unreadCount > 0 ||
                item.preview.trim().isNotEmpty),
      )
      .map(
        (item) => OaNotification(
          id: 'im-conversation:${item.id}',
          requestId: '',
          category: item.isGroup ? 'im_group' : 'im_direct',
          type: item.isGroup ? 'im.group.message' : 'im.direct.message',
          title: item.title,
          body: item.unreadCount > 0
              ? '${item.unreadCount} 条未读${item.preview.trim().isEmpty ? '' : ' · ${item.preview.trim()}'}'
              : item.preview,
          importance: item.unreadCount > 0 ? 'important' : 'normal',
          action: 'view',
          isRead: item.unreadCount == 0,
          readAt: null,
          createdAt: item.updatedAt,
          targetKind: 'im_conversation',
          targetId: item.id,
        ),
      );
  final pendingApplications = friendApplications
      .where(
        (item) =>
            item.direction.trim().toLowerCase() == 'incoming' &&
            item.status.trim().toLowerCase() == 'pending',
      )
      .toList();
  pendingApplications.sort(
    (left, right) => (right.createdAt ?? DateTime(0)).compareTo(
      left.createdAt ?? DateTime(0),
    ),
  );
  final normalizedOa = oaNotifications.map(
    (item) => OaNotification(
      id: item.id,
      requestId: item.requestId,
      category: item.category,
      type: item.type,
      title: item.title,
      body: item.body,
      importance: item.importance,
      action: item.action,
      isRead: item.isRead,
      readAt: item.readAt,
      createdAt: item.createdAt,
      targetKind: item.targetKind.trim().isEmpty
          ? 'oa_approval'
          : item.targetKind,
      targetId: item.targetId.trim().isEmpty ? item.requestId : item.targetId,
    ),
  );
  final result = <OaNotification>[
    ...normalizedOa,
    ...conversationNotifications,
    if (pendingApplications.isNotEmpty)
      OaNotification(
        id: 'im-friend-requests',
        requestId: '',
        category: 'im',
        type: 'im.friend.requested',
        title: '好友申请',
        body:
            '${pendingApplications.length} 个待处理申请 · ${pendingApplications.first.applicant.displayName}',
        importance: 'action_required',
        action: 'review',
        isRead: false,
        readAt: null,
        createdAt: pendingApplications.first.createdAt,
        targetKind: 'im_friend_requests',
        targetId: 'requests',
      ),
  ];
  result.sort(
    (left, right) => (right.createdAt ?? DateTime(0)).compareTo(
      left.createdAt ?? DateTime(0),
    ),
  );
  return result;
}

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key, this.initialSection = 0});

  final int initialSection;

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  bool _unreadOnly = false;
  late int _section;
  bool _markingAll = false;
  bool _loadingMore = false;
  bool _paginationStarted = false;
  bool _hasMore = false;
  String? _nextCursor;
  final List<OaNotification> _additionalNotifications = [];
  String? _handlingApplicationId;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection.clamp(0, 2);
  }

  @override
  void didUpdateWidget(covariant NotificationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _section = widget.initialSection.clamp(0, 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allNotificationKey = (cursor: null as String?, unreadOnly: false);
    final unreadNotificationKey = (cursor: null as String?, unreadOnly: true);
    final allNotifications = ref.watch(
      oaNotificationPageProvider(allNotificationKey),
    );
    final unreadNotifications = ref.watch(
      oaNotificationPageProvider(unreadNotificationKey),
    );
    final notificationKey = _unreadOnly
        ? unreadNotificationKey
        : allNotificationKey;
    final value = _unreadOnly ? unreadNotifications : allNotifications;
    final bootstrap = ref.watch(oaBootstrapProvider);
    final imBootstrap = ref.watch(imBootstrapProvider);
    final applications = ref.watch(pendingFriendApplicationsProvider);
    final conversations = imBootstrap.value?.conversations ?? const [];
    final friendApplications = applications.value ?? const [];
    final allProjected = buildMobileNotificationFeed(
      oaNotifications: allNotifications.value?.items ?? const [],
      conversations: conversations,
      friendApplications: friendApplications,
    );
    final unreadProjected = buildMobileNotificationFeed(
      oaNotifications: unreadNotifications.value?.items ?? const [],
      conversations: imBootstrap.value?.conversations ?? const [],
      friendApplications: applications.value ?? const [],
    );
    final allCount = allProjected.length;
    final unreadCount = unreadProjected.where((item) => !item.isRead).length;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        title: Text(switch (_section) {
          1 => '公司公告',
          2 => '好友申请',
          _ => '通知中心',
        }),
        actions: [
          if (_section == 0 && unreadCount > 0)
            IconButton(
              tooltip: '全部标为已读',
              onPressed: _markingAll ? null : _markAllRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _refreshCurrent,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _section == 2
          ? applications.when(
              loading: () => const ModuleLoadingState(label: '正在加载好友申请'),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: '好友申请加载失败',
                description: error.toString(),
                onRetry: () =>
                    ref.invalidate(pendingFriendApplicationsProvider),
              ),
              data: (items) => items.isEmpty
                  ? const EmptyState(
                      icon: Icons.person_add_alt_1_outlined,
                      title: '暂无好友申请',
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.refresh(pendingFriendApplicationsProvider.future),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 62,
                          color: Color(0xFFF0F2F5),
                        ),
                        itemBuilder: (context, index) {
                          final application = items[index];
                          final handling =
                              _handlingApplicationId == application.id;
                          return ListTile(
                            dense: true,
                            leading: InitialAvatar(
                              name: application.applicant.displayName,
                              radius: 19,
                              avatarDataUrl:
                                  application.applicant.avatarDataUrl,
                            ),
                            title: Text(application.applicant.displayName),
                            subtitle: Text(
                              application.greeting.isEmpty
                                  ? application.applicant.username
                                  : application.greeting,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  style: _compactActionStyle,
                                  onPressed: handling
                                      ? null
                                      : () => _handleApplication(
                                          application,
                                          false,
                                        ),
                                  child: const Text('拒绝'),
                                ),
                                FilledButton(
                                  style: _compactActionStyle,
                                  onPressed: handling
                                      ? null
                                      : () => _handleApplication(
                                          application,
                                          true,
                                        ),
                                  child: Text(handling ? '处理中…' : '接受'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            )
          : _section == 1
          ? bootstrap.when(
              loading: () => const ModuleLoadingState(label: '正在加载公告'),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: '公告加载失败',
                description: error.toString(),
                onRetry: () => ref.invalidate(oaBootstrapProvider),
              ),
              data: (data) => data.announcements.isEmpty
                  ? const EmptyState(
                      icon: Icons.campaign_outlined,
                      title: '暂无公告',
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await ref.read(oaRepositoryProvider).refreshBootstrap();
                        ref.invalidate(oaBootstrapProvider);
                      },
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: data.announcements.length,
                        separatorBuilder: (_, _) => const Divider(
                          height: 1,
                          indent: 62,
                          color: Color(0xFFF0F2F5),
                        ),
                        itemBuilder: (context, index) =>
                            _AnnouncementItem(item: data.announcements[index]),
                      ),
                    ),
            )
          : Column(
              children: [
                Container(
                  key: const Key('notification-filter-row'),
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFF0F2F5)),
                    ),
                  ),
                  child: Row(
                    children: [
                      _NotificationFilterButton(
                        label: '全部',
                        count: allCount,
                        selected: !_unreadOnly,
                        onTap: () {
                          setState(() {
                            _unreadOnly = false;
                            _resetPagination();
                          });
                        },
                      ),
                      const SizedBox(width: 22),
                      _NotificationFilterButton(
                        label: '未读',
                        count: unreadCount,
                        selected: _unreadOnly,
                        onTap: () {
                          setState(() {
                            _unreadOnly = true;
                            _resetPagination();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: value.when(
                    loading: () => const ModuleLoadingState(label: '正在加载通知'),
                    error: (error, _) => EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: '通知加载失败',
                      description: error.toString(),
                      onRetry: () => ref.invalidate(
                        oaNotificationPageProvider(notificationKey),
                      ),
                    ),
                    data: (page) {
                      final oaItems = <OaNotification>[
                        ...page.items,
                        ..._additionalNotifications,
                      ];
                      final items =
                          buildMobileNotificationFeed(
                                oaNotifications: oaItems,
                                conversations:
                                    imBootstrap.value?.conversations ??
                                    const [],
                                friendApplications:
                                    applications.value ?? const [],
                              )
                              .where((item) => !_unreadOnly || !item.isRead)
                              .toList()
                            ..sort(
                              (left, right) => (right.createdAt ?? DateTime(0))
                                  .compareTo(left.createdAt ?? DateTime(0)),
                            );
                      if (items.isEmpty) {
                        return EmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: _unreadOnly ? '暂无未读通知' : '暂无通知',
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: _refreshNotifications,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount:
                              items.length +
                              ((_paginationStarted ? _hasMore : page.hasMore)
                                  ? 1
                                  : 0),
                          separatorBuilder: (context, index) =>
                              index >= items.length - 1
                              ? const SizedBox.shrink()
                              : const Divider(
                                  height: 1,
                                  indent: 62,
                                  color: Color(0xFFF0F2F5),
                                ),
                          itemBuilder: (context, index) {
                            if (index == items.length) {
                              return Center(
                                child: TextButton(
                                  onPressed: _loadingMore
                                      ? null
                                      : () => _loadMore(page),
                                  child: Text(_loadingMore ? '加载中…' : '加载更多'),
                                ),
                              );
                            }
                            return _NotificationItem(
                              item: items[index],
                              onTap: () => _open(items[index]),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  ButtonStyle get _compactActionStyle => const ButtonStyle(
    visualDensity: VisualDensity(horizontal: -3, vertical: -3),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: WidgetStatePropertyAll(Size(48, 30)),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
    textStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
  );

  Future<void> _refreshCurrent() async {
    if (_section == 2) {
      ref.invalidate(pendingFriendApplicationsProvider);
      return;
    }
    if (_section == 1) {
      await ref.read(oaRepositoryProvider).refreshBootstrap();
      ref.invalidate(oaBootstrapProvider);
      return;
    }
    await _refreshNotifications();
  }

  Future<void> _refreshNotifications() async {
    try {
      await ref.read(oaRepositoryProvider).refreshNotifications();
      _resetPagination();
      ref.invalidate(oaNotificationPageProvider);
      ref.invalidate(imBootstrapProvider);
      ref.invalidate(pendingFriendApplicationsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刷新失败，继续显示本机通知：$error')));
      }
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      final conversations =
          ref.read(imBootstrapProvider).value?.conversations ?? const [];
      await Future.wait<void>([
        ref.read(oaRepositoryProvider).markAllNotificationsRead(),
        ...conversations
            .where(
              (item) => item.unreadCount > 0 && item.lastMessageSequence > 0,
            )
            .map(
              (item) => ref
                  .read(imRepositoryProvider)
                  .markRead(item.id, item.lastMessageSequence),
            ),
      ]);
      ref.invalidate(oaNotificationsProvider);
      ref.invalidate(oaNotificationPageProvider);
      ref.invalidate(oaBootstrapProvider);
      ref.invalidate(imBootstrapProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('标记失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _resetPagination() {
    _additionalNotifications.clear();
    _paginationStarted = false;
    _hasMore = false;
    _nextCursor = null;
  }

  Future<void> _loadMore(OaNotificationPage firstPage) async {
    if (_loadingMore) return;
    final cursor = _paginationStarted ? _nextCursor : firstPage.nextCursor;
    final hasMore = _paginationStarted ? _hasMore : firstPage.hasMore;
    if (!hasMore || cursor == null || cursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final next = await ref
          .read(oaRepositoryProvider)
          .notificationPage(cursor: cursor, unreadOnly: _unreadOnly);
      if (!mounted) return;
      final knownIds = <String>{
        ...firstPage.items.map((item) => item.id),
        ..._additionalNotifications.map((item) => item.id),
      };
      setState(() {
        _additionalNotifications.addAll(
          next.items.where((item) => knownIds.add(item.id)),
        );
        _paginationStarted = true;
        _nextCursor = next.nextCursor;
        _hasMore = next.hasMore;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _handleApplication(
    ImFriendApplication application,
    bool accept,
  ) async {
    setState(() => _handlingApplicationId = application.id);
    try {
      await ref
          .read(imRepositoryProvider)
          .handleFriendApplication(application.id, accept);
      ref.invalidate(pendingFriendApplicationsProvider);
      ref.invalidate(imBootstrapProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(accept ? '已添加为联系人' : '已拒绝申请')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('处理失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _handlingApplicationId = null);
    }
  }

  Future<void> _open(OaNotification item) async {
    if (!item.isRead) {
      try {
        if (item.targetKind == 'im_conversation') {
          final conversations = ref
              .read(imBootstrapProvider)
              .value
              ?.conversations;
          final conversation = conversations
              ?.where((candidate) => candidate.id == item.targetId)
              .firstOrNull;
          if (conversation != null && conversation.lastMessageSequence > 0) {
            await ref
                .read(imRepositoryProvider)
                .markRead(conversation.id, conversation.lastMessageSequence);
            ref.invalidate(imBootstrapProvider);
          }
        } else if (item.targetKind != 'im_friend_requests') {
          await ref.read(oaRepositoryProvider).markNotificationRead(item.id);
          ref.invalidate(oaNotificationsProvider);
          ref.invalidate(oaNotificationPageProvider);
          ref.invalidate(oaBootstrapProvider);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('通知状态同步失败：$error')));
        }
      }
    }
    if (!mounted) return;
    final route = notificationTargetRoute(item);
    if (route == null) return;
    if (route.startsWith('/contacts')) {
      context.go(route);
    } else {
      context.push(route);
    }
  }
}

class _AnnouncementItem extends StatelessWidget {
  const _AnnouncementItem({required this.item});

  final OaAnnouncement item;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minTileHeight: 60,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    leading: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E8),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Icon(
        Icons.campaign_outlined,
        size: 19,
        color: Color(0xFFE87918),
      ),
    ),
    title: Text(
      item.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      item.content,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
    ),
  );
}

class _NotificationFilterButton extends StatelessWidget {
  const _NotificationFilterButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('notification-filter-$label'),
    onTap: onTap,
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            width: 2,
            color: selected ? AppColors.primary : Colors.transparent,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primary : AppColors.secondaryText,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              color: selected ? AppColors.primary : AppColors.weakText,
            ),
          ),
        ],
      ),
    ),
  );
}

class _NotificationItem extends StatelessWidget {
  const _NotificationItem({required this.item, required this.onTap});

  final OaNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _importanceColor(item.importance);
    final kind = _notificationKind(item);
    return InkWell(
      key: Key('notification-row-${item.id}'),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        color: item.isRead
            ? Colors.white
            : AppColors.primary.withValues(alpha: .045),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(_notificationIcon(item), size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: item.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (kind != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          kind,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 62,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.createdAt != null)
                    Text(
                      _compactTime(item.createdAt!),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.weakText,
                      ),
                    ),
                  if (!item.isRead) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _compactTime(DateTime value) {
  final now = DateTime.now();
  final sameDay =
      now.year == value.year &&
      now.month == value.month &&
      now.day == value.day;
  return DateFormat(sameDay ? 'HH:mm' : 'MM-dd').format(value);
}

String? _notificationKind(OaNotification item) {
  if (item.targetKind != 'im_conversation') return null;
  return item.type == 'im.group.message' || item.category == 'im_group'
      ? '群聊'
      : item.type == 'im.direct.message' || item.category == 'im_direct'
      ? '单聊'
      : '消息';
}

IconData _notificationIcon(OaNotification item) {
  if (item.targetKind == 'im_friend_requests') {
    return Icons.person_add_alt_1_outlined;
  }
  if (item.targetKind == 'im_conversation') {
    return item.type == 'im.group.message' || item.category == 'im_group'
        ? Icons.groups_outlined
        : item.type == 'im.direct.message' || item.category == 'im_direct'
        ? Icons.person_outline_rounded
        : Icons.chat_bubble_outline_rounded;
  }
  if (item.action == 'review' || item.requestId.isNotEmpty) {
    return Icons.assignment_ind_outlined;
  }
  return Icons.notifications_active_outlined;
}

Color _importanceColor(String importance) => switch (importance.toLowerCase()) {
  'high' || 'urgent' => AppColors.error,
  'low' => AppColors.secondaryText,
  _ => AppColors.primary,
};
