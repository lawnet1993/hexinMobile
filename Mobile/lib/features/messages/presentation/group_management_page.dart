import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

class GroupManagementPage extends ConsumerStatefulWidget {
  const GroupManagementPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<GroupManagementPage> createState() =>
      _GroupManagementPageState();
}

class _GroupManagementPageState extends ConsumerState<GroupManagementPage> {
  final _pageScrollController = ScrollController();
  int _tab = 0;
  bool _loading = true;
  String? _error;
  ImGroupManagementCapabilities _capabilities =
      const ImGroupManagementCapabilities();
  ImGroupProfile? _profile;
  List<ImMember> _managers = const [];
  List<ImMutedGroupMember> _muted = const [];
  List<ImGroupJoinRequest> _requests = const [];
  List<ImGroupNotice> _notices = const [];
  int _mutedPage = 1;
  int _mutedTotal = 0;
  int _managersPage = 1;
  int _managersTotal = 0;
  int _requestsPage = 1;
  int _requestsTotal = 0;
  int _noticesPage = 1;
  int _noticesTotal = 0;
  bool _loadingMore = false;
  bool _autoLoadScheduled = false;
  bool _autoLoadRetryBlocked = false;
  bool _pagingExhausted = false;
  bool _pagingError = false;
  int _paginationGeneration = 0;
  bool _deletingHistory = false;
  String _historyDeletionStatus = '';

  @override
  void initState() {
    super.initState();
    _pageScrollController.addListener(_onPageScroll);
    _load();
  }

  @override
  void dispose() {
    _pageScrollController
      ..removeListener(_onPageScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _resetPagination(jumpToTop: false);
    });
    try {
      final values = await Future.wait<Object?>([
        ref.read(imGroupManagementCapabilitiesLoaderProvider)(
          widget.conversationId,
        ),
        ref.read(imGroupManagersPageLoaderProvider)(widget.conversationId),
        ref.read(imGroupMutedMembersPageLoaderProvider)(widget.conversationId),
        ref.read(imGroupJoinRequestsPageLoaderProvider)(widget.conversationId),
        ref.read(imGroupNoticesPageLoaderProvider)(widget.conversationId),
        ref.read(imGroupProfileRefresherProvider)(widget.conversationId),
      ]);
      if (!mounted) return;
      final managers = values[1] as ImGroupManagementPage<ImMember>;
      final muted = values[2] as ImGroupManagementPage<ImMutedGroupMember>;
      final requests = values[3] as ImGroupManagementPage<ImGroupJoinRequest>;
      final notices = values[4] as ImGroupManagementPage<ImGroupNotice>;
      setState(() {
        _capabilities = values[0] as ImGroupManagementCapabilities;
        _managers = managers.items;
        _managersPage = managers.page;
        _managersTotal = managers.total;
        _muted = muted.items;
        _mutedPage = muted.page;
        _mutedTotal = muted.total;
        _requests = requests.items;
        _requestsPage = requests.page;
        _requestsTotal = requests.total;
        _notices = notices.items;
        _noticesPage = notices.page;
        _noticesTotal = notices.total;
        _profile = values[5] as ImGroupProfile?;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore ||
        _autoLoadRetryBlocked ||
        _pagingExhausted ||
        !_hasMoreForTab(_tab)) {
      return;
    }
    final requestedTab = _tab;
    final generation = _paginationGeneration;
    setState(() {
      _loadingMore = true;
      _pagingError = false;
    });
    try {
      if (requestedTab == 0) {
        final previousPage = _mutedPage;
        final previousLength = _muted.length;
        final result = await ref.read(imGroupMutedMembersPageLoaderProvider)(
          widget.conversationId,
          page: previousPage + 1,
        );
        if (!_acceptPageResult(requestedTab, generation)) return;
        final merged = _mergeByKey(
          _muted,
          result.items,
          (item) => item.member.id,
        );
        setState(() {
          _muted = merged;
          _mutedPage = result.page;
          _mutedTotal = result.total;
          _pagingExhausted =
              result.page <= previousPage || merged.length == previousLength;
        });
      } else if (requestedTab == 1) {
        final previousPage = _requestsPage;
        final previousLength = _requests.length;
        final result = await ref.read(imGroupJoinRequestsPageLoaderProvider)(
          widget.conversationId,
          page: previousPage + 1,
        );
        if (!_acceptPageResult(requestedTab, generation)) return;
        final merged = _mergeByKey(_requests, result.items, (item) => item.id);
        setState(() {
          _requests = merged;
          _requestsPage = result.page;
          _requestsTotal = result.total;
          _pagingExhausted =
              result.page <= previousPage || merged.length == previousLength;
        });
      } else if (requestedTab == 2) {
        final previousPage = _managersPage;
        final previousLength = _managers.length;
        final result = await ref.read(imGroupManagersPageLoaderProvider)(
          widget.conversationId,
          page: previousPage + 1,
        );
        if (!_acceptPageResult(requestedTab, generation)) return;
        final merged = _mergeByKey(_managers, result.items, (item) => item.id);
        setState(() {
          _managers = merged;
          _managersPage = result.page;
          _managersTotal = result.total;
          _pagingExhausted =
              result.page <= previousPage || merged.length == previousLength;
        });
      } else if (requestedTab == 3) {
        final previousPage = _noticesPage;
        final previousLength = _notices.length;
        final result = await ref.read(imGroupNoticesPageLoaderProvider)(
          widget.conversationId,
          page: previousPage + 1,
        );
        if (!_acceptPageResult(requestedTab, generation)) return;
        final merged = _mergeByKey(_notices, result.items, (item) => item.id);
        setState(() {
          _notices = merged;
          _noticesPage = result.page;
          _noticesTotal = result.total;
          _pagingExhausted =
              result.page <= previousPage || merged.length == previousLength;
        });
      }
    } catch (error) {
      if (!mounted ||
          _tab != requestedTab ||
          _paginationGeneration != generation) {
        return;
      }
      _autoLoadRetryBlocked = true;
      setState(() => _pagingError = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('继续加载失败：$error')));
    } finally {
      if (_acceptPageResult(requestedTab, generation)) {
        setState(() => _loadingMore = false);
      }
    }
  }

  bool _acceptPageResult(int requestedTab, int generation) =>
      mounted && _tab == requestedTab && _paginationGeneration == generation;

  bool _hasMoreForTab(int tab) => switch (tab) {
    0 => _muted.length < _mutedTotal,
    1 => _requests.length < _requestsTotal,
    2 => _managers.length < _managersTotal,
    3 => _notices.length < _noticesTotal,
    _ => false,
  };

  int _loadedCountForTab(int tab) => switch (tab) {
    0 => _muted.length,
    1 => _requests.length,
    2 => _managers.length,
    3 => _notices.length,
    _ => 0,
  };

  int _totalForTab(int tab) => switch (tab) {
    0 => _mutedTotal,
    1 => _requestsTotal,
    2 => _managersTotal,
    3 => _noticesTotal,
    _ => 0,
  };

  void _resetPagination({bool jumpToTop = true}) {
    _paginationGeneration += 1;
    _loadingMore = false;
    _autoLoadScheduled = false;
    _autoLoadRetryBlocked = false;
    _pagingExhausted = false;
    _pagingError = false;
    if (!jumpToTop) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageScrollController.hasClients) return;
      _pageScrollController.jumpTo(0);
    });
  }

  void _changeTab(int tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _resetPagination();
    });
  }

  void _onPageScroll() {
    if (_autoLoadRetryBlocked ||
        !_pageScrollController.hasClients ||
        _pageScrollController.position.extentAfter > 240) {
      return;
    }
    unawaited(_loadMore());
  }

  bool _handlePageGesture(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        _autoLoadRetryBlocked) {
      setState(() {
        _autoLoadRetryBlocked = false;
        _pagingError = false;
      });
    }
    return false;
  }

  void _scheduleAutoLoad() {
    if (!_hasMoreForTab(_tab) ||
        _pagingExhausted ||
        _loadingMore ||
        _autoLoadRetryBlocked ||
        _autoLoadScheduled) {
      return;
    }
    _autoLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLoadScheduled = false;
      if (!mounted || !_pageScrollController.hasClients) return;
      if (_pageScrollController.position.extentAfter <= 240) {
        unawaited(_loadMore());
      }
    });
  }

  void _retryLoadMore() {
    setState(() {
      _autoLoadRetryBlocked = false;
      _pagingError = false;
    });
    unawaited(_loadMore());
  }

  Future<void> _deleteAllHistory() async {
    final profile = _profile;
    if (profile == null || _deletingHistory) return;
    final draft = await showMobileDestructiveVerificationSheet(
      context,
      title: '删除所有人的聊天记录',
      message: '服务器消息、附件、收藏、已读和提及记录将异步删除，所有成员都无法恢复。',
      requiredPhrase: profile.title,
      reasonLabel: '删除原因',
      confirmationLabel: '输入群名确认',
      actionLabel: '确认删除',
    );
    if (draft == null || !mounted) return;
    setState(() {
      _deletingHistory = true;
      _historyDeletionStatus = '正在删除服务器群历史…';
    });
    try {
      final job = await ref
          .read(imRepositoryProvider)
          .deleteAllGroupHistory(
            widget.conversationId,
            confirmation: draft.confirmation,
            reason: draft.reason,
          );
      if (!mounted) return;
      if (job.isCompleted) {
        ref.invalidate(conversationMessagesProvider(widget.conversationId));
        setState(
          () => _historyDeletionStatus =
              '删除完成，共删除 ${job.deletedMessageCount} 条群消息',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 ${job.deletedMessageCount} 条群消息')),
        );
      } else if (job.isFailed) {
        final detail = job.errorMessage.trim().isEmpty
            ? '后台删除失败'
            : job.errorMessage;
        setState(() => _historyDeletionStatus = '删除失败：$detail');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$detail')));
      } else {
        const detail = '任务仍在后台处理，可稍后重新进入查看';
        setState(() => _historyDeletionStatus = detail);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(detail)));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _historyDeletionStatus = '删除失败：$error');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _deletingHistory = false);
    }
  }

  Future<void> _unmute(ImMutedGroupMember item) async {
    try {
      await ref
          .read(imRepositoryProvider)
          .updateGroupMemberMute(widget.conversationId, item.member.id, null);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('解除禁言失败：$error')));
      }
    }
  }

  Future<void> _handle(ImGroupJoinRequest item, bool accept) async {
    try {
      await ref
          .read(imRepositoryProvider)
          .handleGroupJoinRequest(widget.conversationId, item.id, accept);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('入群申请处理失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F6F8),
    appBar: AppBar(title: const Text('群管理')),
    body: Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(
            children: [
              _Tab(
                label: '禁言 $_mutedTotal',
                selected: _tab == 0,
                onTap: () => _changeTab(0),
              ),
              _Tab(
                label: '入群 $_requestsTotal',
                selected: _tab == 1,
                onTap: () => _changeTab(1),
              ),
              _Tab(
                label: '管理员 $_managersTotal',
                selected: _tab == 2,
                onTap: () => _changeTab(2),
              ),
              _Tab(
                label: '记录 $_noticesTotal',
                selected: _tab == 3,
                onTap: () => _changeTab(3),
              ),
              _Tab(
                label: '高级',
                selected: _tab == 4,
                onTap: () => _changeTab(4),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '群管理加载失败',
                  description: _error,
                  onRetry: _load,
                )
              : RefreshIndicator(onRefresh: _load, child: _content()),
        ),
      ],
    ),
  );

  Widget _content() {
    if (_tab == 0) {
      if (_muted.isEmpty) return _pagedEmpty('暂无禁言成员');
      final hasMore = _hasMoreForTab(0) && !_pagingExhausted;
      _scheduleAutoLoad();
      return _withPaging(
        ListView.separated(
          key: const Key('group-management-page-scroll-0'),
          controller: _pageScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _muted.length + (hasMore || _pagingError ? 1 : 0),
          separatorBuilder: (_, _) =>
              const Divider(height: 1, indent: 58, color: AppColors.border),
          itemBuilder: (_, index) {
            if (index == _muted.length) {
              return _AutoPageFooter(
                loaded: _muted.length,
                total: _mutedTotal,
                loading: _loadingMore,
                error: _pagingError,
                onRetry: _retryLoadMore,
              );
            }
            final item = _muted[index];
            return ListTile(
              dense: true,
              leading: InitialAvatar(
                name: item.member.displayName,
                radius: 17,
                online: item.member.isOnline,
                avatarKey: item.member.avatarKey,
                avatarDataUrl: item.member.avatarDataUrl,
              ),
              title: Text(
                item.member.displayName,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                item.mutedUntil == null
                    ? '持续禁言'
                    : '至 ${DateFormat('MM-dd HH:mm').format(item.mutedUntil!.toLocal())}',
                style: const TextStyle(fontSize: 10.5),
              ),
              trailing: _capabilities.canMuteMembers
                  ? TextButton(
                      onPressed: () => _unmute(item),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('解除'),
                    )
                  : null,
            );
          },
        ),
      );
    }
    if (_tab == 1) {
      if (_requests.isEmpty) return _pagedEmpty('暂无待审核申请');
      final hasMore = _hasMoreForTab(1) && !_pagingExhausted;
      _scheduleAutoLoad();
      return _withPaging(
        ListView.separated(
          key: const Key('group-management-page-scroll-1'),
          controller: _pageScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _requests.length + (hasMore || _pagingError ? 1 : 0),
          separatorBuilder: (_, _) =>
              const Divider(height: 1, indent: 58, color: AppColors.border),
          itemBuilder: (_, index) {
            if (index == _requests.length) {
              return _AutoPageFooter(
                loaded: _requests.length,
                total: _requestsTotal,
                loading: _loadingMore,
                error: _pagingError,
                onRetry: _retryLoadMore,
              );
            }
            final item = _requests[index];
            return ListTile(
              dense: true,
              leading: InitialAvatar(name: item.applicantName, radius: 17),
              title: Text(
                item.applicantName,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                item.createdAt == null
                    ? item.status
                    : DateFormat('MM-dd HH:mm')
                          .format(item.createdAt!.toLocal()),
                style: const TextStyle(fontSize: 10.5),
              ),
              trailing: _capabilities.canReviewJoinRequests
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => _handle(item, false),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('拒绝'),
                        ),
                        FilledButton(
                          onPressed: () => _handle(item, true),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(52, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('通过'),
                        ),
                      ],
                    )
                  : null,
            );
          },
        ),
      );
    }
    if (_tab == 2) {
      if (_managers.isEmpty) return _pagedEmpty('暂无群管理员');
      final hasMore = _hasMoreForTab(2) && !_pagingExhausted;
      _scheduleAutoLoad();
      return _withPaging(
        ListView.separated(
          key: const Key('group-management-page-scroll-2'),
          controller: _pageScrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _managers.length + (hasMore || _pagingError ? 1 : 0),
          separatorBuilder: (_, _) =>
              const Divider(height: 1, indent: 58, color: AppColors.border),
          itemBuilder: (_, index) {
            if (index == _managers.length) {
              return _AutoPageFooter(
                loaded: _managers.length,
                total: _managersTotal,
                loading: _loadingMore,
                error: _pagingError,
                onRetry: _retryLoadMore,
              );
            }
            final item = _managers[index];
            final isOwner = item.groupRole.toLowerCase() == 'owner';
            return ListTile(
              dense: true,
              leading: InitialAvatar(
                name: item.displayName,
                radius: 17,
                online: item.isOnline,
                avatarKey: item.avatarKey,
                avatarDataUrl: item.avatarDataUrl,
              ),
              title: Text(
                item.displayName,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                item.username,
                style: const TextStyle(fontSize: 10.5),
              ),
              trailing: Text(
                isOwner ? '群主' : '管理员',
                style: TextStyle(
                  fontSize: 11,
                  color: isOwner ? AppColors.primary : AppColors.secondaryText,
                ),
              ),
            );
          },
        ),
      );
    }
    if (_tab == 4) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
        children: [
          const Text(
            '危险操作',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_capabilities.canDeleteAllHistory)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MobileSurface(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.delete_sweep_outlined,
                      color: Colors.red,
                    ),
                    title: const Text('删除所有人的聊天记录'),
                    subtitle: const Text('删除服务器群历史，所有成员均不可恢复'),
                    trailing: _deletingHistory
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: _deletingHistory ? null : _deleteAllHistory,
                  ),
                ),
                if (_historyDeletionStatus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Text(
                      _historyDeletionStatus,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ),
              ],
            )
          else
            const _EmptyList(label: '当前账号没有高级群管理权限'),
        ],
      );
    }
    if (_notices.isEmpty) return _pagedEmpty('暂无群操作记录');
    final hasMore = _hasMoreForTab(3) && !_pagingExhausted;
    _scheduleAutoLoad();
    return _withPaging(
      ListView.separated(
        key: const Key('group-management-page-scroll-3'),
        controller: _pageScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _notices.length + (hasMore || _pagingError ? 1 : 0),
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 18, color: AppColors.border),
        itemBuilder: (_, index) {
          if (index == _notices.length) {
            return _AutoPageFooter(
              loaded: _notices.length,
              total: _noticesTotal,
              loading: _loadingMore,
              error: _pagingError,
              onRetry: _retryLoadMore,
            );
          }
          final item = _notices[index];
          return ListTile(
            dense: true,
            leading: const Icon(
              Icons.history_rounded,
              size: 19,
              color: AppColors.primary,
            ),
            title: Text(
              item.actorName.isEmpty
                  ? _noticeLabel(item.type)
                  : '${item.actorName} · ${_noticeLabel(item.type)}',
              style: const TextStyle(fontSize: 13),
            ),
            trailing: item.createdAt == null
                ? null
                : Text(
                    DateFormat('MM-dd HH:mm').format(item.createdAt!.toLocal()),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _withPaging(Widget child) => NotificationListener<ScrollNotification>(
    onNotification: _handlePageGesture,
    child: child,
  );

  Widget _pagedEmpty(String label) {
    final hasMore = _hasMoreForTab(_tab) && !_pagingExhausted;
    if (!hasMore && !_pagingError) return _EmptyList(label: label);
    _scheduleAutoLoad();
    return _withPaging(
      ListView(
        key: ValueKey('group-management-page-scroll-$_tab'),
        controller: _pageScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 280,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
          ),
          _AutoPageFooter(
            loaded: _loadedCountForTab(_tab),
            total: _totalForTab(_tab),
            loading: _loadingMore,
            error: _pagingError,
            onRetry: _retryLoadMore,
          ),
        ],
      ),
    );
  }
}

List<T> _mergeByKey<T>(
  List<T> current,
  List<T> incoming,
  String Function(T item) keyOf,
) {
  final merged = <String, T>{for (final item in current) keyOf(item): item};
  for (final item in incoming) {
    merged[keyOf(item)] = item;
  }
  return merged.values.toList(growable: false);
}

class _AutoPageFooter extends StatelessWidget {
  const _AutoPageFooter({
    required this.loaded,
    required this.total,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final int loaded;
  final int total;
  final bool loading;
  final bool error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const Key('group-management-page-footer'),
    height: 44,
    child: Center(
      child: error
          ? TextButton(onPressed: onRetry, child: const Text('重新加载'))
          : loading
          ? const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              '继续上滑 · $loaded/$total',
              style: const TextStyle(color: AppColors.weakText, fontSize: 12),
            ),
    ),
  );
}

String _noticeLabel(String type) => switch (type.toLowerCase()) {
  'group.created' => '创建了群聊',
  'group.member.muted' => '禁言了群成员',
  'group.member.unmuted' => '解除了群成员禁言',
  'group.member.joined' => '成员加入群聊',
  'group.member.removed' => '移出了群成员',
  'group.notice.updated' => '更新了群公告',
  'group.profile.updated' => '更新了群资料',
  _ => type,
};

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F1FF) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.secondaryText,
          ),
        ),
      ),
    ),
  );
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      SizedBox(
        height: 280,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
        ),
      ),
    ],
  );
}
