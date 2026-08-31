import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
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
  String _search = '';
  String _itemType = '';
  String _applicationKey = '';
  String _status = '';
  int _recentDays = 0;
  List<OaApprovalRequest>? _loadedApprovals;
  String? _nextCursor;
  bool? _hasMore;
  bool _loadingMore = false;
  String _todoActionId = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(oaBootstrapProvider);
    final catalog = ref.watch(oaApplicationCatalogProvider).value;
    final drafts = ref.watch(oaDraftsProvider).value ?? const [];
    final outbox = ref.watch(oaOutboxProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        toolbarHeight: 58,
        titleSpacing: 14,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '待办',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 2),
            Text(
              '统一处理任务与审批',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: '新建',
            enabled: _todoActionId.isEmpty,
            icon: const Icon(Icons.add_rounded, size: 21),
            onSelected: (value) {
              if (value == 'todo') {
                _createTodo();
              } else if (value == 'approval') {
                context.push('/apps');
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'todo',
                height: 40,
                child: Row(
                  children: [
                    Icon(Icons.checklist_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('新建待办'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'approval',
                height: 40,
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('新建申请'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: value.when(
        loading: () => const ModuleLoadingState(label: '正在加载待办'),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '待办加载失败',
          description: error.toString(),
          onRetry: () => ref.invalidate(oaBootstrapProvider),
        ),
        data: (data) {
          final approvals = _loadedApprovals ?? data.approvalRequests;
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
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: MobileSurface(
              child: Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
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
                  ),
                  const Divider(height: 1),
                  if (_tab < 4)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 38,
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: '搜索事项、申请编号或发起人',
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 18,
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
                                ),
                                onChanged: _updateSearch,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox.square(
                            dimension: 38,
                            child: IconButton(
                              tooltip: '筛选',
                              style: IconButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: const Color(0xFFF1F4F8),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () =>
                                  _showFilters(catalog?.items ?? const []),
                              icon: Badge.count(
                                count: _activeFilterCount,
                                isLabelVisible: _activeFilterCount > 0,
                                backgroundColor: AppColors.primary,
                                child: const Icon(Icons.tune_rounded, size: 19),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: _tab == 4
                        ? _DraftList(items: drafts)
                        : _tab == 5
                        ? _OutboxList(items: outbox)
                        : items.isEmpty && todoItems.isEmpty
                        ? _EmptyApprovalList(
                            searching: _search.isNotEmpty,
                            hasMore: _hasMore ?? data.approvalRequestsHasMore,
                            loading: _loadingMore,
                            onLoadMore: () => _loadMore(data),
                          )
                        : RefreshIndicator(
                            onRefresh: () async {
                              await ref
                                  .read(oaRepositoryProvider)
                                  .refreshBootstrap();
                              if (mounted) {
                                setState(() {
                                  _loadedApprovals = null;
                                  _nextCursor = null;
                                  _hasMore = null;
                                });
                              }
                              ref.invalidate(oaBootstrapProvider);
                            },
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                              itemCount:
                                  todoItems.length +
                                  items.length +
                                  ((_hasMore ?? data.approvalRequestsHasMore)
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
                                final approvalIndex = index - todoItems.length;
                                if (approvalIndex == items.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Center(
                                      child: TextButton.icon(
                                        onPressed: _loadingMore
                                            ? null
                                            : () => _loadMore(data),
                                        icon: _loadingMore
                                            ? const SizedBox.square(
                                                dimension: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.expand_more_rounded,
                                              ),
                                        label: Text(
                                          _loadingMore ? '加载中' : '加载更多',
                                        ),
                                      ),
                                    ),
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _changeTab(int value) {
    setState(() {
      _tab = value;
      _loadedApprovals = null;
      _nextCursor = null;
      _hasMore = null;
    });
  }

  void _updateSearch(String value) {
    setState(() {
      _search = value;
      _loadedApprovals = null;
      _nextCursor = null;
      _hasMore = null;
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建失败：${error.toString()}')));
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新失败：${error.toString()}')));
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
                items: const [
                  DropdownMenuItem(value: '', child: Text('全部类型')),
                  DropdownMenuItem(value: 'todo', child: Text('任务')),
                  DropdownMenuItem(value: 'approval', child: Text('审批')),
                ],
                onChanged: (value) =>
                    setSheetState(() => itemType = value ?? ''),
              ),
              const SizedBox(height: 8),
              _CompactFilterField<String>(
                key: const Key('approval-filter-application'),
                label: '审批应用',
                value: applicationKey,
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部应用')),
                  ...applications.map(
                    (item) => DropdownMenuItem(
                      value: item.applicationKey,
                      child: Text(item.name),
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
                items: _statusOptions.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
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
                items: const [
                  DropdownMenuItem(value: 0, child: Text('全部时间')),
                  DropdownMenuItem(value: 1, child: Text('今天')),
                  DropdownMenuItem(value: 7, child: Text('近 7 天')),
                  DropdownMenuItem(value: 30, child: Text('近 30 天')),
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
      _loadedApprovals = null;
      _nextCursor = null;
      _hasMore = null;
    });
  }

  Future<void> _loadMore(OaBootstrap data) async {
    if (_loadingMore || !(_hasMore ?? data.approvalRequestsHasMore)) return;
    final cursor = _nextCursor ?? data.approvalRequestsNextCursor;
    if (cursor == null || cursor.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(oaRepositoryProvider)
          .approvalRequestsPage(
            cursor: cursor,
            view: const ['pending', 'initiated', 'cc', 'completed'][_tab],
            search: _search,
            applicationKey: _applicationKey,
            status: _status,
            from: _filterFrom,
          );
      final byId = <String, OaApprovalRequest>{
        for (final item in _loadedApprovals ?? data.approvalRequests)
          item.id: item,
        for (final item in page.items) item.id: item,
      };
      if (mounted) {
        setState(() {
          _loadedApprovals = byId.values.toList();
          _nextCursor = page.nextCursor;
          _hasMore = page.hasMore;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载更多失败：${error.toString()}')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
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

bool _isTodoCompleted(String status) => const {
  'approved',
  'rejected',
  'withdrawn',
  'terminated',
  'completed',
  'canceled',
  'cancelled',
}.contains(status.toLowerCase());

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
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          14 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '新建待办',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: TextField(
                key: const Key('todo-title-input'),
                autofocus: true,
                maxLength: 160,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: '待办内容',
                  counterText: '',
                  errorText: errorText,
                ),
                onChanged: (value) => title = value,
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
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'normal', label: Text('普通')),
                ButtonSegment(value: 'high', label: Text('高')),
                ButtonSegment(value: 'urgent', label: Text('紧急')),
              ],
              selected: {priority},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity(vertical: -2),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (values) =>
                  setSheetState(() => priority = values.single),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: FilledButton(
                key: const Key('todo-create-button'),
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
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Container(
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
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              isExpanded: true,
              icon: const Icon(Icons.expand_more_rounded, size: 20),
              style: const TextStyle(fontSize: 14, color: AppColors.text),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    ),
  );
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
    required this.hasMore,
    required this.loading,
    required this.onLoadMore,
  });

  final bool searching;
  final bool hasMore;
  final bool loading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      EmptyState(
        icon: searching ? Icons.search_off_rounded : Icons.fact_check_outlined,
        title: searching ? '当前记录中没有匹配项' : '暂无审批事项',
      ),
      if (hasMore)
        TextButton.icon(
          onPressed: loading ? null : onLoadMore,
          icon: loading
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more_rounded),
          label: Text(loading ? '继续查找' : '加载更多记录'),
        ),
    ],
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
    final width = switch (label.characters.length) {
      >= 4 => 58.0,
      3 => 50.0,
      _ => 42.0,
    };
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: selected
                ? const Border(
                    bottom: BorderSide(color: AppColors.primary, width: 3),
                  )
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: selected
                        ? AppColors.primary
                        : AppColors.secondaryText,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (badge != null && badge! > 0)
                Positioned(
                  top: 3,
                  right: 2,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge! > 99 ? '99+' : '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
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
          final validationFailed = failed && _isValidationOutboxError(item);
          final editable = failed && _canEditFailedOutbox(item);
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
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
            subtitle: Text(
              failed
                  ? '${validationFailed ? (editable ? '需修改后重提 · ' : '需重新发起 · ') : ''}${_outboxErrorText(item.lastError)}'
                  : '网络恢复后自动同步 · 已尝试 ${item.attempts} 次',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: failed
                ? PopupMenuButton<String>(
                    tooltip: '同步操作',
                    icon: const Icon(Icons.more_horiz_rounded, size: 22),
                    onSelected: (action) async {
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
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('申请内容需要修改'),
                            content: const Text(
                              '这条旧记录无法还原完整表单，请从对应审批应用重新发起。旧记录会继续保留，确认新申请已提交后再放弃即可。',
                            ),
                            actions: [
                              FilledButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('知道了'),
                              ),
                            ],
                          ),
                        );
                      } else if (action == 'retry') {
                        await ref
                            .read(oaRepositoryProvider)
                            .retryOutbox(item.id);
                      } else if (action == 'discard') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('放弃待同步申请？'),
                            content: Text(
                              '将从本机删除“${title.isEmpty ? '待同步审批申请' : title}”的失败记录，服务端不会收到该申请。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('确认放弃'),
                              ),
                            ],
                          ),
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
                    itemBuilder: (context) => [
                      if (editable)
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined, size: 20),
                            title: Text('修改后重提'),
                          ),
                        )
                      else if (validationFailed)
                        const PopupMenuItem(
                          value: 'details',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.info_outline_rounded, size: 20),
                            title: Text('处理说明'),
                          ),
                        )
                      else
                        const PopupMenuItem(
                          value: 'retry',
                          child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.refresh_rounded, size: 20),
                            title: Text('重试'),
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'discard',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                            color: AppColors.error,
                          ),
                          title: Text(
                            '放弃记录',
                            style: TextStyle(color: AppColors.error),
                          ),
                        ),
                      ),
                    ],
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
  if (normalized.toLowerCase().contains('approval form validation failed')) {
    return '申请表单校验失败，请检查必填项';
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
              SizedBox.square(
                dimension: 32,
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(7),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Checkbox(
                        value: completed,
                        onChanged: (_) => onToggle(),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: priorityColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  completed ? Icons.task_alt_rounded : Icons.checklist_rounded,
                  size: 18,
                  color: completed ? AppColors.success : priorityColor,
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
        padding: const EdgeInsets.symmetric(vertical: 10),
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
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  updatedAt == null
                      ? '-'
                      : DateFormat('MM-dd HH:mm').format(updatedAt),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.label,
                  style: TextStyle(fontSize: 12, color: status.color),
                ),
              ],
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.secondaryText,
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
