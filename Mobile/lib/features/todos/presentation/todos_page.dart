import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/data/oa_local_store.dart';
import '../../collaboration/domain/collaboration_models.dart';
import 'approval_request_page.dart';

class TodosPage extends ConsumerStatefulWidget {
  const TodosPage({super.key});

  @override
  ConsumerState<TodosPage> createState() => _TodosPageState();
}

class _TodosPageState extends ConsumerState<TodosPage> {
  int _tab = 0;
  final _searchController = TextEditingController();
  final _approvalScrollController = ScrollController();
  String _search = '';
  String _itemType = '';
  String _applicationKey = '';
  String _status = '';
  int _recentDays = 0;
  List<OaApprovalRequest>? _loadedApprovals;
  String? _nextCursor;
  bool? _hasMore;
  bool _loadingMore = false;
  bool _autoLoadScheduled = false;
  bool _autoLoadRetryBlocked = false;
  bool _pagingExhausted = false;
  bool _pagingError = false;
  int _paginationGeneration = 0;
  OaBootstrap? _visibleBootstrap;
  String _todoActionId = '';

  @override
  void initState() {
    super.initState();
    _approvalScrollController.addListener(_onApprovalScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _approvalScrollController
      ..removeListener(_onApprovalScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(oaBootstrapProvider);
    final catalog = ref.watch(oaApplicationCatalogProvider).value;
    final drafts = ref.watch(oaDraftsProvider).value ?? const [];
    final outbox = ref.watch(oaOutboxProvider).value ?? const [];
    final syncAvailability = ref.watch(oaSyncAvailabilityProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        centerTitle: false,
        toolbarHeight: 50,
        titleSpacing: 14,
        title: const Text(
          '待办',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '新建',
            style: compactHeaderIconButtonStyle,
            icon: const Icon(Icons.add_rounded, size: 21),
            onPressed: _todoActionId.isNotEmpty
                ? null
                : () async {
                    final value = await showMobileChoiceSheet<String>(
                      context,
                      title: '新建',
                      options: const [
                        MobileSheetOption(
                          value: 'todo',
                          label: '新建待办',
                          icon: Icons.checklist_rounded,
                        ),
                        MobileSheetOption(
                          value: 'approval',
                          label: '新建申请',
                          icon: Icons.description_outlined,
                        ),
                      ],
                    );
                    if (!context.mounted || value == null) return;
                    if (value == 'todo') {
                      _createTodo();
                    } else if (value == 'approval') {
                      context.push('/apps');
                    }
                  },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: value.when(
        loading: () => const ModuleLoadingState(label: '正在加载待办'),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '待办加载失败',
          description: mobileErrorText(error),
          onRetry: () => ref.invalidate(oaBootstrapProvider),
        ),
        data: (data) {
          _visibleBootstrap = data;
          final approvals = _loadedApprovals ?? data.approvalRequests;
          final syncConnecting =
              syncAvailability == OaSyncAvailability.connecting;
          final syncUnavailable =
              syncAvailability == OaSyncAvailability.unavailable;
          final pendingCount =
              data.todos
                  .where((item) => !_isTodoCompleted(item.status))
                  .length +
              approvals.where((item) => item.operableTask != null).length;
          final items = _tab < 4
              ? _itemsForTab(data, approvals)
              : const <OaApprovalRequest>[];
          final todoItems = _tab < 4 ? _todosForTab(data) : const <OaTodo>[];
          final unreadCcCount = approvals
              .expand((item) => item.ccs)
              .where(
                (item) => item.memberId == data.currentMemberId && !item.isRead,
              )
              .length;
          if (_tab < 4) _scheduleAutoLoad(data);
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Material(
              key: const Key('todos-flat-content'),
              type: MaterialType.transparency,
              child: Column(
                children: [
                  SizedBox(
                    height: 40,
                    child: _ScrollableTabStrip(
                      children: [
                        _Tab(
                          label: '待我处理',
                          badge: pendingCount,
                          selected: _tab == 0,
                          onTap: () => _changeTab(0),
                        ),
                        _Tab(
                          label: '我发起的',
                          selected: _tab == 1,
                          onTap: () => _changeTab(1),
                        ),
                        _Tab(
                          label: '抄送我的',
                          badge: unreadCcCount,
                          selected: _tab == 2,
                          onTap: () => _changeTab(2),
                        ),
                        _Tab(
                          label: '已完成',
                          selected: _tab == 3,
                          onTap: () => _changeTab(3),
                        ),
                        _Tab(
                          label: '草稿箱',
                          badge: drafts.length,
                          selected: _tab == 4,
                          onTap: () => _changeTab(4),
                        ),
                        _Tab(
                          label: '待同步',
                          badge: outbox
                              .where((item) => item.state != 'completed')
                              .length,
                          selected: _tab == 5,
                          onTap: () => _changeTab(5),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE8EBF0)),
                  if (_tab < 4)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 34,
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: '搜索事项或申请编号',
                                  hintStyle: const TextStyle(
                                    color: AppColors.weakText,
                                    fontSize: 14,
                                  ),
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xFFF5F7FA),
                                  contentPadding: EdgeInsets.zero,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 18,
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 40,
                                    minHeight: 34,
                                  ),
                                  suffixIcon: _search.isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: '清除搜索',
                                          onPressed: () {
                                            _searchController.clear();
                                            _updateSearch('');
                                          },
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                        ),
                                  suffixIconConstraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 34,
                                  ),
                                ),
                                onChanged: _updateSearch,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox.square(
                            key: const Key('approval-filter-button'),
                            dimension: 40,
                            child: IconButton(
                              tooltip: '筛选',
                              style: IconButton.styleFrom(
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () =>
                                  _showFilters(catalog?.items ?? const []),
                              icon: Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F7FA),
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                child: Badge.count(
                                  count: _activeFilterCount,
                                  isLabelVisible: _activeFilterCount > 0,
                                  backgroundColor: AppColors.primary,
                                  child: const Icon(
                                    Icons.tune_rounded,
                                    size: 17,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_tab < 4 &&
                      syncAvailability != OaSyncAvailability.available)
                    _ApprovalSyncBar(
                      availability: syncAvailability,
                      onRetry: _refreshApprovals,
                    ),
                  Expanded(
                    child: _tab == 4
                        ? _DraftList(items: drafts)
                        : _tab == 5
                        ? _OutboxList(items: outbox)
                        : items.isEmpty && todoItems.isEmpty
                        ? RefreshIndicator(
                            onRefresh: _refreshApprovals,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _handleApprovalGesture,
                              child: CustomScrollView(
                                key: const Key('approval-empty-scroll'),
                                controller: _approvalScrollController,
                                physics: const AlwaysScrollableScrollPhysics(),
                                slivers: [
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _EmptyApprovalList(
                                      searching: _search.isNotEmpty,
                                      connecting: syncConnecting,
                                      offline: syncUnavailable,
                                      hasMore: _effectiveHasMore(data),
                                      loading: _loadingMore,
                                      error: _pagingError,
                                      onRetry: () => _retryLoadMore(data),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _refreshApprovals,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _handleApprovalGesture,
                              child: ListView.separated(
                                key: const Key('approval-page-scroll'),
                                controller: _approvalScrollController,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
                                itemCount:
                                    todoItems.length +
                                    items.length +
                                    (_effectiveHasMore(data) || _pagingError
                                        ? 1
                                        : 0),
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  if (index < todoItems.length) {
                                    final item = todoItems[index];
                                    return _PersonalTodoItem(
                                      item: item,
                                      busy: _todoActionId == item.id,
                                      onToggle: () => _toggleTodo(item),
                                    );
                                  }
                                  final approvalIndex =
                                      index - todoItems.length;
                                  if (approvalIndex == items.length) {
                                    return _ApprovalPageFooter(
                                      loadedCount: approvals.length,
                                      loading: _loadingMore,
                                      error: _pagingError,
                                      onRetry: () => _retryLoadMore(data),
                                    );
                                  }
                                  return _ApprovalItem(
                                    item: items[approvalIndex],
                                    currentMemberId: data.currentMemberId,
                                    color:
                                        _colors[approvalIndex % _colors.length],
                                  );
                                },
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _effectiveHasMore(OaBootstrap data) =>
      !_pagingExhausted && (_hasMore ?? data.approvalRequestsHasMore);

  void _resetPagination() {
    _paginationGeneration += 1;
    _loadedApprovals = null;
    _nextCursor = null;
    _hasMore = null;
    _loadingMore = false;
    _autoLoadScheduled = false;
    _autoLoadRetryBlocked = false;
    _pagingExhausted = false;
    _pagingError = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_approvalScrollController.hasClients) return;
      _approvalScrollController.jumpTo(0);
    });
  }

  void _onApprovalScroll() {
    if (_tab >= 4 ||
        _autoLoadRetryBlocked ||
        !_approvalScrollController.hasClients ||
        _approvalScrollController.position.extentAfter > 240) {
      return;
    }
    final data = _visibleBootstrap;
    if (data != null) unawaited(_loadMore(data));
  }

  bool _handleApprovalGesture(ScrollNotification notification) {
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

  void _scheduleAutoLoad(OaBootstrap data) {
    if (!_effectiveHasMore(data) ||
        _loadingMore ||
        _autoLoadScheduled ||
        _autoLoadRetryBlocked) {
      return;
    }
    _autoLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLoadScheduled = false;
      if (!mounted || _tab >= 4 || !_approvalScrollController.hasClients) {
        return;
      }
      if (_approvalScrollController.position.extentAfter <= 240) {
        unawaited(_loadMore(data));
      }
    });
  }

  Future<void> _refreshApprovals() async {
    ref.read(oaSyncAvailabilityControllerProvider.notifier).markConnecting();
    try {
      await ref.read(oaRepositoryProvider).refreshBootstrap();
      ref.read(oaSyncAvailabilityControllerProvider.notifier).markAvailable();
      if (!mounted) return;
      setState(_resetPagination);
      ref.invalidate(oaBootstrapProvider);
    } catch (error) {
      ref.read(oaSyncAvailabilityControllerProvider.notifier).markUnavailable();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('同步失败', error))),
        );
      }
    }
  }

  void _retryLoadMore(OaBootstrap data) {
    setState(() {
      _autoLoadRetryBlocked = false;
      _pagingError = false;
    });
    unawaited(_loadMore(data));
  }

  void _changeTab(int value) {
    setState(() {
      _tab = value;
      _resetPagination();
    });
  }

  void _updateSearch(String value) {
    setState(() {
      _search = value;
      _resetPagination();
    });
  }

  Future<void> _createTodo() async {
    final draft = await _showCreateTodoSheet(context);
    if (draft == null || !mounted) return;
    setState(() => _todoActionId = 'create');
    try {
      await ref
          .read(oaRepositoryProvider)
          .createTodo(title: draft.title, priority: draft.priority);
      ref.invalidate(oaBootstrapProvider);
      if (mounted) {
        setState(() => _tab = 0);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('待办已创建')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('创建失败', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _todoActionId = '');
    }
  }

  Future<void> _toggleTodo(OaTodo item) async {
    setState(() => _todoActionId = item.id);
    try {
      await ref
          .read(oaRepositoryProvider)
          .updateTodo(
            item.id,
            status: _isTodoCompleted(item.status) ? 'todo' : 'completed',
          );
      ref.invalidate(oaBootstrapProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('更新失败', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _todoActionId = '');
    }
  }

  int get _activeFilterCount =>
      (_itemType.isEmpty ? 0 : 1) +
      (_applicationKey.isEmpty ? 0 : 1) +
      (_status.isEmpty ? 0 : 1) +
      (_recentDays == 0 ? 0 : 1);

  Future<void> _showFilters(List<OaApplicationCatalogItem> applications) async {
    var itemType = _itemType;
    var applicationKey = _applicationKey;
    var status = _status;
    var recentDays = _recentDays;
    final result = await showModalBottomSheet<_ApprovalFilters>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            12,
            18,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '筛选',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _CompactFilterField<String>(
                key: const Key('approval-filter-item-type'),
                label: '事项类型',
                value: itemType,
                options: const [
                  MobileSheetOption(value: '', label: '全部类型'),
                  MobileSheetOption(value: 'todo', label: '任务'),
                  MobileSheetOption(value: 'approval', label: '审批'),
                ],
                onChanged: (value) =>
                    setSheetState(() => itemType = value ?? ''),
              ),
              const SizedBox(height: 8),
              _CompactFilterField<String>(
                key: const Key('approval-filter-application'),
                label: '审批应用',
                value: applicationKey,
                options: [
                  const MobileSheetOption(value: '', label: '全部应用'),
                  ...applications.map(
                    (item) => MobileSheetOption(
                      value: item.applicationKey,
                      label: item.name,
                    ),
                  ),
                ],
                onChanged: (value) =>
                    setSheetState(() => applicationKey = value ?? ''),
              ),
              const SizedBox(height: 8),
              _CompactFilterField<String>(
                key: const Key('approval-filter-status'),
                label: '审批状态',
                value: status,
                options: _statusOptions.entries
                    .map(
                      (entry) => MobileSheetOption(
                        value: entry.key,
                        label: entry.value,
                      ),
                    )
                    .toList(),
                onChanged: (value) => setSheetState(() => status = value ?? ''),
              ),
              const SizedBox(height: 8),
              _CompactFilterField<int>(
                key: const Key('approval-filter-updated-at'),
                label: '时间范围',
                value: recentDays,
                options: const [
                  MobileSheetOption(value: 0, label: '全部时间'),
                  MobileSheetOption(value: 1, label: '今天'),
                  MobileSheetOption(value: 7, label: '近 7 天'),
                  MobileSheetOption(value: 30, label: '近 30 天'),
                ],
                onChanged: (value) =>
                    setSheetState(() => recentDays = value ?? 0),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(64, 40)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () =>
                        Navigator.pop(context, const _ApprovalFilters()),
                    child: const Text('重置'),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: const ButtonStyle(
                      minimumSize: WidgetStatePropertyAll(Size(84, 40)),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.pop(
                      context,
                      _ApprovalFilters(
                        itemType: itemType,
                        applicationKey: applicationKey,
                        status: status,
                        recentDays: recentDays,
                      ),
                    ),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _itemType = result.itemType;
      _applicationKey = result.applicationKey;
      _status = result.status;
      _recentDays = result.recentDays;
      _resetPagination();
    });
  }

  Future<void> _loadMore(OaBootstrap data) async {
    if (_loadingMore ||
        _autoLoadRetryBlocked ||
        !_effectiveHasMore(data) ||
        _tab >= 4) {
      return;
    }
    final cursor = _nextCursor ?? data.approvalRequestsNextCursor;
    if (cursor == null || cursor.isEmpty) {
      setState(() {
        _hasMore = false;
        _pagingExhausted = true;
      });
      return;
    }
    final generation = _paginationGeneration;
    final pageKey = (
      cursor: cursor as String?,
      view: const ['pending', 'initiated', 'cc', 'completed'][_tab],
      search: _search,
      applicationKey: _applicationKey,
      status: _status,
      from: _filterFrom,
    );
    setState(() {
      _loadingMore = true;
      _pagingError = false;
    });
    try {
      final page = await ref.read(
        oaApprovalRequestsPageProvider(pageKey).future,
      );
      if (!mounted || generation != _paginationGeneration) return;
      final byId = <String, OaApprovalRequest>{
        for (final item in _loadedApprovals ?? data.approvalRequests)
          item.id: item,
        for (final item in page.items) item.id: item,
      };
      final cursorAdvanced =
          page.nextCursor != null &&
          page.nextCursor!.isNotEmpty &&
          page.nextCursor != cursor;
      final hasMore = page.hasMore && cursorAdvanced;
      setState(() {
        _loadedApprovals = byId.values.toList();
        _nextCursor = page.nextCursor;
        _hasMore = hasMore;
        _pagingExhausted = page.hasMore && !cursorAdvanced;
        _autoLoadRetryBlocked = false;
        _pagingError = false;
      });
    } catch (error) {
      if (mounted && generation == _paginationGeneration) {
        _autoLoadRetryBlocked = true;
        setState(() => _pagingError = true);
        ref.invalidate(oaApprovalRequestsPageProvider(pageKey));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('加载更多失败', error))),
        );
      }
    } finally {
      if (mounted && generation == _paginationGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  List<OaApprovalRequest> _itemsForTab(
    OaBootstrap data,
    List<OaApprovalRequest> approvals,
  ) {
    if (_itemType == 'todo') return const [];
    final items = switch (_tab) {
      0 => approvals.where((item) => item.operableTask != null).toList(),
      1 =>
        approvals
            .where((item) => item.requesterId == data.currentMemberId)
            .toList(),
      2 =>
        approvals
            .where(
              (item) =>
                  item.ccs.any((cc) => cc.memberId == data.currentMemberId),
            )
            .toList(),
      _ =>
        approvals
            .where(
              (item) =>
                  item.status.toLowerCase() != 'submitted' ||
                  item.tasks.any(
                    (task) =>
                        task.assigneeId == data.currentMemberId &&
                        task.completedAt != null,
                  ),
            )
            .toList(),
    };
    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      items.removeWhere(
        (item) => ![
          item.id,
          item.title,
          item.templateName,
          item.requesterName,
          item.requesterDepartmentName,
        ].any((value) => value.toLowerCase().contains(query)),
      );
    }
    if (_applicationKey.isNotEmpty) {
      items.removeWhere((item) => item.applicationKey != _applicationKey);
    }
    if (_status.isNotEmpty) {
      if (_status == 'pending') {
        items.removeWhere(
          (item) =>
              item.operableTask == null &&
              item.status.toLowerCase() != 'submitted',
        );
      } else {
        items.removeWhere(
          (item) => item.status.toLowerCase() != _status.toLowerCase(),
        );
      }
    }
    final filterFrom = _filterFrom;
    if (filterFrom != null) {
      items.removeWhere(
        (item) => (item.updatedAt ?? item.createdAt ?? DateTime(0)).isBefore(
          filterFrom,
        ),
      );
    }
    items.sort(
      (left, right) => (right.updatedAt ?? right.createdAt ?? DateTime(0))
          .compareTo(left.updatedAt ?? left.createdAt ?? DateTime(0)),
    );
    return items;
  }

  List<OaTodo> _todosForTab(OaBootstrap data) {
    if (_tab == 2 || _itemType == 'approval' || _applicationKey.isNotEmpty) {
      return const [];
    }
    final items = switch (_tab) {
      0 => data.todos.where((item) => !_isTodoCompleted(item.status)).toList(),
      1 =>
        data.todos
            .where((item) => item.createdById == data.currentMemberId)
            .toList(),
      _ => data.todos.where((item) => _isTodoCompleted(item.status)).toList(),
    };
    final query = _search.trim().toLowerCase();
    if (query.isNotEmpty) {
      items.removeWhere(
        (item) => ![
          item.title,
          item.description,
          _todoPriorityLabel(item.priority),
        ].any((value) => value.toLowerCase().contains(query)),
      );
    }
    if (_status.isNotEmpty) {
      if (_status == 'pending') {
        items.removeWhere((item) => _isTodoCompleted(item.status));
      } else if (_status == 'completed') {
        items.removeWhere((item) => !_isTodoCompleted(item.status));
      } else {
        items.clear();
      }
    }
    final filterFrom = _filterFrom;
    if (filterFrom != null) {
      items.removeWhere(
        (item) =>
            (item.updatedAt ?? item.createdAt ?? item.dueAt ?? DateTime(0))
                .isBefore(filterFrom),
      );
    }
    items.sort(
      (left, right) =>
          (right.updatedAt ?? right.createdAt ?? right.dueAt ?? DateTime(0))
              .compareTo(
                left.updatedAt ?? left.createdAt ?? left.dueAt ?? DateTime(0),
              ),
    );
    return items;
  }

  DateTime? get _filterFrom {
    if (_recentDays == 0) return null;
    final now = DateTime.now();
    if (_recentDays == 1) return DateTime(now.year, now.month, now.day);
    return now.subtract(Duration(days: _recentDays));
  }
}

const _statusOptions = <String, String>{
  '': '全部状态',
  'pending': '待处理',
  'submitted': '审批中',
  'approved': '已通过',
  'rejected': '已驳回',
  'completed': '已完成',
  'withdrawn': '已撤回',
  'terminated': '已终止',
};

bool _isTodoCompleted(String status) => isTerminalTodoStatus(status);

String _todoPriorityLabel(String priority) => switch (priority.toLowerCase()) {
  'urgent' => '紧急',
  'high' => '高优先级',
  'low' => '低优先级',
  _ => '普通',
};

Color _todoPriorityColor(String priority) => switch (priority.toLowerCase()) {
  'urgent' => AppColors.error,
  'high' => const Color(0xFFFF7A00),
  'low' => AppColors.secondaryText,
  _ => AppColors.primary,
};

Future<_TodoCreateDraft?> _showCreateTodoSheet(BuildContext context) {
  var title = '';
  var priority = 'normal';
  String? errorText;
  return showModalBottomSheet<_TodoCreateDraft>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        key: const Key('todo-create-sheet'),
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '新建待办',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '待办内容',
              style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: TextField(
                key: const Key('todo-title-input'),
                autofocus: true,
                maxLength: 160,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: '待办内容',
                  counterText: '',
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  border: const OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide.none,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                onChanged: (value) {
                  title = value;
                  if (errorText != null) {
                    setSheetState(() => errorText = null);
                  }
                },
                onSubmitted: (value) {
                  final normalizedTitle = value.trim();
                  if (normalizedTitle.isEmpty) {
                    setSheetState(() => errorText = '请输入待办内容');
                    return;
                  }
                  Navigator.pop(
                    context,
                    _TodoCreateDraft(
                      title: normalizedTitle,
                      priority: priority,
                    ),
                  );
                },
              ),
            ),
            if (errorText != null) ...[
              const SizedBox(height: 5),
              Text(
                errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 11.5,
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              '优先级',
              style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'normal', label: Text('普通')),
                  ButtonSegment(value: 'high', label: Text('高')),
                  ButtonSegment(value: 'urgent', label: Text('紧急')),
                ],
                selected: {priority},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity(vertical: -3),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: WidgetStatePropertyAll(Size(0, 34)),
                ),
                onSelectionChanged: (values) =>
                    setSheetState(() => priority = values.single),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(60, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('todo-create-button'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    final normalizedTitle = title.trim();
                    if (normalizedTitle.isEmpty) {
                      setSheetState(() => errorText = '请输入待办内容');
                      return;
                    }
                    Navigator.pop(
                      context,
                      _TodoCreateDraft(
                        title: normalizedTitle,
                        priority: priority,
                      ),
                    );
                  },
                  child: const Text('创建'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

final class _TodoCreateDraft {
  const _TodoCreateDraft({required this.title, required this.priority});

  final String title;
  final String priority;
}

class _CompactFilterField<T> extends StatelessWidget {
  const _CompactFilterField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<MobileSheetOption<T>> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.where((option) => option.value == value);
    final valueLabel = selected.isEmpty ? '请选择' : selected.first.label;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final result = await showMobileChoiceSheet<T>(
          context,
          title: label,
          options: options,
          selectedValue: value,
        );
        if (result != null) onChanged(result);
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
            Expanded(
              child: Text(
                valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: AppColors.text),
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

final class _ApprovalFilters {
  const _ApprovalFilters({
    this.itemType = '',
    this.applicationKey = '',
    this.status = '',
    this.recentDays = 0,
  });

  final String itemType;
  final String applicationKey;
  final String status;
  final int recentDays;
}

const _colors = [
  AppColors.error,
  Color(0xFFFF7A00),
  AppColors.primary,
  Color(0xFF7356C8),
  AppColors.success,
];

class _EmptyApprovalList extends StatelessWidget {
  const _EmptyApprovalList({
    required this.searching,
    required this.connecting,
    required this.offline,
    required this.hasMore,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool searching;
  final bool connecting;
  final bool offline;
  final bool hasMore;
  final bool loading;
  final bool error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final title = searching
        ? '当前记录中没有匹配项'
        : connecting
        ? '正在同步审批'
        : offline
        ? '本机暂无审批记录'
        : '暂无审批事项';
    return Align(
      alignment: const Alignment(0, -0.34),
      child: Semantics(
        container: true,
        label: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFF3F6FA),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                searching
                    ? Icons.search_off_rounded
                    : connecting
                    ? Icons.sync_rounded
                    : Icons.fact_check_outlined,
                size: 24,
                color: AppColors.weakText,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 14,
              ),
            ),
            if (error) ...[
              const SizedBox(height: 6),
              TextButton(onPressed: onRetry, child: const Text('重新加载')),
            ] else if (hasMore && loading) ...[
              const SizedBox(height: 10),
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ApprovalSyncBar extends StatelessWidget {
  const _ApprovalSyncBar({required this.availability, required this.onRetry});

  final OaSyncAvailability availability;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final connecting = availability == OaSyncAvailability.connecting;
    return Semantics(
      container: true,
      label: connecting ? '正在同步审批' : '审批同步中断，当前显示本机记录',
      child: ExcludeSemantics(
        child: SizedBox(
          key: Key(
            connecting
                ? 'approval-connecting-sync-bar'
                : 'approval-offline-sync-bar',
          ),
          height: 32,
          child: Row(
            children: [
              const SizedBox(width: 4),
              Icon(
                connecting ? Icons.sync_rounded : Icons.cloud_off_outlined,
                size: 15,
                color: AppColors.secondaryText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  connecting ? '正在同步审批' : '当前显示本机记录',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
              if (connecting)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '同步中',
                    style: TextStyle(fontSize: 11.5, color: AppColors.weakText),
                  ),
                )
              else
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('重新同步', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalPageFooter extends StatelessWidget {
  const _ApprovalPageFooter({
    required this.loadedCount,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final int loadedCount;
  final bool loading;
  final bool error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('approval-page-footer'),
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: error
          ? TextButton(onPressed: onRetry, child: const Text('重新加载'))
          : loading
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              '继续上滑 · 已载入 $loadedCount 条',
              style: const TextStyle(color: AppColors.weakText, fontSize: 12),
            ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final int? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visibleBadge = badge != null && badge! > 0;
    return Semantics(
      button: true,
      selected: selected,
      label: visibleBadge ? '$label，$badge 条' : label,
      child: ConstrainedBox(
        key: ValueKey('todo-tab-target-$label'),
        // Keep the label and badge compact while giving the tab a reliable
        // touch target. The extra vertical space also separates the text from
        // the active underline without increasing either visual element.
        constraints: const BoxConstraints(minWidth: 64, minHeight: 40),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        key: ValueKey('todo-tab-label-$label'),
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: selected
                              ? AppColors.primary
                              : AppColors.secondaryText,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (visibleBadge) ...[
                        const SizedBox(width: 2),
                        Container(
                          key: ValueKey('todo-tab-badge-$label'),
                          constraints: const BoxConstraints(minWidth: 13),
                          height: 13,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary
                                : const Color(0xFFE9EEF6),
                            borderRadius: BorderRadius.circular(6.5),
                          ),
                          child: Text(
                            badge! > 99 ? '99+' : '$badge',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : AppColors.secondaryText,
                              fontSize: 8.5,
                              height: 1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 0,
                  child: Container(
                    key: ValueKey('todo-tab-indicator-$label'),
                    height: 2,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollableTabStrip extends StatefulWidget {
  const _ScrollableTabStrip({required this.children});

  final List<Widget> children;

  @override
  State<_ScrollableTabStrip> createState() => _ScrollableTabStripState();
}

class _ScrollableTabStripState extends State<_ScrollableTabStrip> {
  final _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_refreshEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshEdges());
  }

  @override
  void didUpdateWidget(covariant _ScrollableTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshEdges());
  }

  void _refreshEdges() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final canScrollLeft = position.pixels > position.minScrollExtent + .5;
    final canScrollRight = position.pixels < position.maxScrollExtent - .5;
    if (_canScrollLeft == canScrollLeft && _canScrollRight == canScrollRight) {
      return;
    }
    setState(() {
      _canScrollLeft = canScrollLeft;
      _canScrollRight = canScrollRight;
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_refreshEdges)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      SingleChildScrollView(
        key: const Key('todo-tab-strip'),
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(children: widget.children),
      ),
      if (_canScrollLeft)
        const Positioned.fill(
          right: null,
          child: _TabEdgeFade(key: Key('todo-tabs-left-fade'), left: true),
        ),
      if (_canScrollRight)
        const Positioned.fill(
          left: null,
          child: _TabEdgeFade(key: Key('todo-tabs-right-fade'), left: false),
        ),
    ],
  );
}

class _TabEdgeFade extends StatelessWidget {
  const _TabEdgeFade({super.key, required this.left});

  final bool left;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 22,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: left ? Alignment.centerLeft : Alignment.centerRight,
          end: left ? Alignment.centerRight : Alignment.centerLeft,
          colors: [
            Theme.of(context).colorScheme.surface,
            Theme.of(context).colorScheme.surface.withValues(alpha: 0),
          ],
        ),
      ),
    ),
  );
}

class _DraftList extends ConsumerWidget {
  const _DraftList({required this.items});

  final List<OaApprovalDraft> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const EmptyState(icon: Icons.drafts_outlined, title: '暂无草稿');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          leading: const Icon(
            Icons.edit_note_rounded,
            color: AppColors.primary,
          ),
          title: Text(
            item.title.isEmpty ? '未命名草稿' : item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            DateFormat('MM-dd HH:mm').format(item.updatedAt.toLocal()),
          ),
          trailing: IconButton(
            tooltip: '删除草稿',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              await ref.read(oaRepositoryProvider).deleteDraft(item.id);
              ref.invalidate(oaDraftsProvider);
            },
          ),
          onTap: () => context.push(
            '/apply/${item.applicationKey}?templateId=${item.templateId}',
          ),
        );
      },
    );
  }
}

class _OutboxList extends ConsumerWidget {
  const _OutboxList({required this.items});

  final List<OaOutboxItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.cloud_done_outlined,
        title: '没有待同步申请',
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(oaRepositoryProvider).flushOutbox();
        ref.invalidate(oaOutboxProvider);
        ref.invalidate(oaBootstrapProvider);
      },
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = items[index];
          final title = item.payload['title']?.toString().trim() ?? '';
          final failed = item.state == 'failed';
          final hasError = item.lastError.trim().isNotEmpty;
          final validationFailed = failed && _isValidationOutboxError(item);
          final editable = failed && _canEditFailedOutbox(item);
          final statusLabel = validationFailed
              ? (editable ? '修改后重提' : '需重新发起')
              : failed
              ? '同步失败'
              : '待自动同步';
          final updatedAt = DateFormat('MM-dd HH:mm')
              .format(item.updatedAt.toLocal());
          return ListTile(
            key: ValueKey<String>('outbox-item-${item.id}'),
            contentPadding: const EdgeInsets.symmetric(vertical: 2),
            minVerticalPadding: 6,
            visualDensity: const VisualDensity(vertical: -1),
            leading: Icon(
              failed
                  ? Icons.error_outline_rounded
                  : Icons.cloud_upload_outlined,
              color: failed ? AppColors.error : AppColors.primary,
            ),
            title: Text(
              title.isEmpty ? '待同步审批申请' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$statusLabel · ${item.attempts} 次',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: failed ? AppColors.error : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      updatedAt,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
                if (hasError)
                  Text(
                    _outboxErrorText(item.lastError),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryText,
                    ),
                  ),
              ],
            ),
            trailing: failed || hasError
                ? IconButton(
                    tooltip: '同步操作',
                    icon: const Icon(Icons.more_horiz_rounded, size: 22),
                    onPressed: () async {
                      final action = await showMobileChoiceSheet<String>(
                        context,
                        title: '同步操作',
                        options: [
                          if (editable)
                            const MobileSheetOption(
                              value: 'edit',
                              label: '修改后重提',
                              icon: Icons.edit_outlined,
                            )
                          else if (validationFailed)
                            const MobileSheetOption(
                              value: 'details',
                              label: '处理说明',
                              icon: Icons.info_outline_rounded,
                            )
                          else
                            const MobileSheetOption(
                              value: 'retry',
                              label: '重试',
                              icon: Icons.refresh_rounded,
                            ),
                          MobileSheetOption(
                            value: 'error-details',
                            label: failed ? '查看失败原因' : '查看同步原因',
                            icon: Icons.error_outline_rounded,
                          ),
                          if (failed)
                            const MobileSheetOption(
                              value: 'discard',
                              label: '放弃记录',
                              icon: Icons.delete_outline_rounded,
                              destructive: true,
                            ),
                        ],
                      );
                      if (!context.mounted || action == null) return;
                      if (action == 'edit') {
                        final editData = _outboxEditData(item);
                        if (editData == null) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ApprovalRequestPage(
                              applicationKey: editData.applicationKey,
                              templateId: editData.templateId,
                              initialTitle: editData.title,
                              initialFormData: editData.formData,
                              initialAttachments: editData.attachments,
                              initialAttachmentIds: editData.attachmentIds,
                              initialAttachmentBindings:
                                  editData.attachmentBindings,
                              sourceOutboxId: item.id,
                            ),
                          ),
                        );
                      } else if (action == 'details') {
                        await showMobileMessageSheet(
                          context,
                          title: '申请内容需要修改',
                          message: '这条旧记录无法还原完整表单，请从对应审批应用重新发起。旧记录会继续保留，确认新申请已提交后再放弃即可。',
                        );
                      } else if (action == 'retry') {
                        await ref
                            .read(oaRepositoryProvider)
                            .retryOutbox(item.id);
                      } else if (action == 'error-details') {
                        await showMobileMessageSheet(
                          context,
                          title: failed ? '失败原因' : '暂未同步',
                          message: _outboxErrorText(item.lastError),
                        );
                      } else if (action == 'discard') {
                        final confirmed = await showMobileConfirmSheet(
                          context,
                          title: '放弃待同步申请？',
                          message:
                              '将从本机删除“${title.isEmpty ? '待同步审批申请' : title}”的失败记录，服务端不会收到该申请。',
                          confirmLabel: '确认放弃',
                          destructive: true,
                        );
                        if (confirmed != true) return;
                        await ref
                            .read(oaRepositoryProvider)
                            .discardOutbox(item.id);
                      } else {
                        return;
                      }
                      ref.invalidate(oaOutboxProvider);
                      ref.invalidate(oaBootstrapProvider);
                    },
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

bool _canEditFailedOutbox(OaOutboxItem item) {
  if (item.commandType != 'submit-approval') return false;
  if (!_isValidationOutboxError(item)) return false;
  return _outboxEditData(item) != null;
}

bool _isValidationOutboxError(OaOutboxItem item) {
  final error = item.lastError.toLowerCase();
  return error.contains('校验') ||
      error.contains('必填') ||
      error.contains('validation failed');
}

({
  String applicationKey,
  String templateId,
  String title,
  Map<String, Object?> formData,
  List<OaLocalAttachment> attachments,
  List<String> attachmentIds,
  List<Map<String, Object?>> attachmentBindings,
})?
_outboxEditData(OaOutboxItem item) {
  final applicationKey = item.payload['applicationKey']?.toString() ?? '';
  final templateId = item.payload['templateId']?.toString() ?? '';
  if (applicationKey.isEmpty || templateId.isEmpty) return null;
  try {
    final rawFormData = item.payload['formDataJson'];
    final decoded = rawFormData is String
        ? jsonDecode(rawFormData)
        : rawFormData;
    if (decoded is! Map) return null;
    final formData = decoded.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final rawAttachments = item.payload['pendingAttachments'];
    final attachments =
        (rawAttachments is List ? rawAttachments : const <Object?>[])
            .whereType<Map>()
            .map(
              (value) => OaLocalAttachment.fromJson(
                value.map((key, value) => MapEntry(key.toString(), value)),
              ),
            )
            .toList();
    final attachmentIds =
        (item.payload['attachmentIds'] is List
                ? item.payload['attachmentIds'] as List
                : const <Object?>[])
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty)
            .toList();
    final attachmentBindings =
        (item.payload['attachmentBindings'] is List
                ? item.payload['attachmentBindings'] as List
                : const <Object?>[])
            .whereType<Map>()
            .map(
              (value) =>
                  value.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList();
    return (
      applicationKey: applicationKey,
      templateId: templateId,
      title: item.payload['title']?.toString() ?? '',
      formData: formData,
      attachments: attachments,
      attachmentIds: attachmentIds,
      attachmentBindings: attachmentBindings,
    );
  } catch (_) {
    return null;
  }
}

String _outboxErrorText(String error) {
  final normalized = error.trim();
  if (normalized.isEmpty) return '同步失败，请检查申请内容';
  // Older queued records can contain raw transport messages. Do not surface
  // request URLs, credentials or stack traces when exposing their diagnosis.
  if (RegExp(
    r'https?://|/api/|token|cookie|authorization|stack trace|requestoptions',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return '同步暂未完成，请稍后重试';
  }
  if (normalized.toLowerCase().contains('approval form validation failed')) {
    return normalized.replaceFirst(
      RegExp('approval form validation failed\\.?', caseSensitive: false),
      '申请表单校验失败',
    );
  }
  return normalized;
}

class _PersonalTodoItem extends StatelessWidget {
  const _PersonalTodoItem({
    required this.item,
    required this.busy,
    required this.onToggle,
  });

  final OaTodo item;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final completed = _isTodoCompleted(item.status);
    final priorityColor = _todoPriorityColor(item.priority);
    final details = <String>[
      _todoPriorityLabel(item.priority),
      if (item.description.trim().isNotEmpty) item.description.trim(),
    ];
    return Semantics(
      button: true,
      label: '${item.title}，${completed ? '已完成' : '待处理'}',
      child: InkWell(
        onTap: busy ? null : onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Container(
                  key: ValueKey('todo-toggle-${item.id}'),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (completed ? AppColors.success : priorityColor)
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(11),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Checkbox(
                          value: completed,
                          onChanged: (_) => onToggle(),
                          activeColor: AppColors.success,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: completed ? AppColors.secondaryText : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: completed
                            ? AppColors.secondaryText
                            : priorityColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.dueAt == null
                        ? '个人待办'
                        : DateFormat('MM-dd HH:mm')
                              .format(item.dueAt!.toLocal()),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    completed ? '已完成' : '待处理',
                    style: TextStyle(
                      fontSize: 12,
                      color: completed
                          ? AppColors.secondaryText
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalItem extends ConsumerWidget {
  const _ApprovalItem({
    required this.item,
    required this.currentMemberId,
    required this.color,
  });

  final OaApprovalRequest item;
  final String currentMemberId;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatedAt = item.updatedAt ?? item.createdAt;
    final unreadCc = item.ccs.any(
      (cc) => cc.memberId == currentMemberId && !cc.isRead,
    );
    final delegatedFor = _delegatedAssigneeName(item, currentMemberId);
    final metadata = [
      _approvalNumber(item),
      item.requesterName,
      item.requesterDepartmentName,
      if (delegatedFor.isNotEmpty) '代$delegatedFor处理',
    ].where((value) => value.isNotEmpty).join(' · ');
    final status = _approvalStatusPresentation(
      item.status,
      item.operableTask != null,
    );
    return InkWell(
      onTap: () async {
        if (unreadCc) {
          try {
            await ref.read(markApprovalCcReadActionProvider)(item.id);
            ref.invalidate(oaBootstrapProvider);
            ref.invalidate(oaNotificationsProvider);
            ref.invalidate(oaNotificationPageProvider);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已打开审批，抄送已读状态将在联网后同步')),
              );
            }
          }
        }
        if (context.mounted) context.push('/approval/${item.id}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.description_outlined, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty ? item.templateName : item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                      if (unreadCc) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            '抄送未读',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                      if (updatedAt != null) ...[
                        const SizedBox(width: 7),
                        Text(
                          DateFormat('MM-dd HH:mm').format(updatedAt),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.weakText,
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: status.color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          status.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: status.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _approvalNumber(OaApprovalRequest request) {
  final value = request.id.replaceAll('-', '').trim().toUpperCase();
  final token = value.length > 6 ? value.substring(0, 6) : value;
  final day = request.createdAt == null
      ? '00000000'
      : DateFormat('yyyyMMdd').format(request.createdAt!);
  return 'OA-$day-$token';
}

String _delegatedAssigneeName(
  OaApprovalRequest request,
  String currentMemberId,
) {
  for (final task in request.tasks) {
    if (task.status.toLowerCase() == 'pending' &&
        task.canOperate &&
        task.assigneeId.isNotEmpty &&
        task.assigneeId != currentMemberId) {
      return task.assigneeName;
    }
  }
  return '';
}

({String label, Color color}) _approvalStatusPresentation(
  String status,
  bool canOperate,
) {
  if (canOperate) return (label: '待处理', color: AppColors.primary);
  return switch (status.toLowerCase()) {
    'approved' || 'completed' => (label: '已通过', color: AppColors.success),
    'rejected' => (label: '已驳回', color: AppColors.error),
    'withdrawn' => (label: '已撤回', color: AppColors.secondaryText),
    'terminated' ||
    'canceled' ||
    'cancelled' => (label: '已终止', color: AppColors.secondaryText),
    _ => (label: '审批中', color: AppColors.primary),
  };
}
