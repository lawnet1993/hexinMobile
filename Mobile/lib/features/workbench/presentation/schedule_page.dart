import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  String _actionId = '';

  Future<void> _refresh() async {
    await ref.read(oaRepositoryProvider).refreshBootstrap();
    ref.invalidate(oaBootstrapProvider);
  }

  Future<void> _create() async {
    final draft = await _showTodoSheet(context);
    if (draft == null || !mounted) return;
    setState(() => _actionId = 'create');
    try {
      await ref
          .read(oaRepositoryProvider)
          .createTodo(
            title: draft.title,
            description: draft.description,
            priority: draft.priority,
            dueAt: draft.dueAt,
          );
      ref.invalidate(oaBootstrapProvider);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _actionId = '');
    }
  }

  Future<void> _toggle(OaTodo item) async {
    setState(() => _actionId = item.id);
    try {
      await ref
          .read(oaRepositoryProvider)
          .updateTodo(
            item.id,
            status: item.status == 'completed' ? 'todo' : 'completed',
          );
      ref.invalidate(oaBootstrapProvider);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _actionId = '');
    }
  }

  Future<void> _edit(OaTodo item) async {
    final draft = await _showTodoSheet(context, item: item);
    if (draft == null || !mounted) return;
    setState(() => _actionId = item.id);
    try {
      await ref
          .read(oaRepositoryProvider)
          .updateTodo(
            item.id,
            title: draft.title,
            description: draft.description,
            priority: draft.priority,
            dueAt: draft.dueAt,
          );
      ref.invalidate(oaBootstrapProvider);
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _actionId = '');
    }
  }

  void _showError(Object error) {
    var message = error.toString().replaceFirst('Exception: ', '');
    if (error is DioException && error.response?.data is Map) {
      message = (error.response!.data as Map)['message']?.toString() ?? message;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(oaBootstrapProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('日程待办'),
        actions: [
          IconButton(
            tooltip: '新增待办',
            onPressed: _actionId.isEmpty ? _create : null,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.event_busy_outlined,
          title: '日程加载失败',
          description: error.toString(),
          onRetry: () => ref.invalidate(oaBootstrapProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: _refresh,
          child: data.todos.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 150),
                    EmptyState(
                      icon: Icons.event_available_outlined,
                      title: '暂无待办',
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    MobileSurface(
                      key: const Key('schedule-todo-list'),
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < data.todos.length;
                            index++
                          ) ...[
                            _ScheduleTodoRow(
                              key: Key(
                                'schedule-todo-row-${data.todos[index].id}',
                              ),
                              item: data.todos[index],
                              busy: _actionId == data.todos[index].id,
                              enabled: _actionId.isEmpty,
                              onToggle: () => _toggle(data.todos[index]),
                              onEdit: () => _edit(data.todos[index]),
                            ),
                            if (index < data.todos.length - 1)
                              const Divider(
                                height: 1,
                                indent: 48,
                                endIndent: 8,
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ScheduleTodoRow extends StatelessWidget {
  const _ScheduleTodoRow({
    super.key,
    required this.item,
    required this.busy,
    required this.enabled,
    required this.onToggle,
    required this.onEdit,
  });

  final OaTodo item;
  final bool busy;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final completed = item.status == 'completed';
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              tooltip: completed ? '恢复待办' : '标记完成',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onPressed: enabled ? onToggle : null,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      completed
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 22,
                      color: completed ? AppColors.success : AppColors.primary,
                    ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    decoration: completed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _subtitle(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    height: 1.15,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          SizedBox.square(
            dimension: 40,
            child: IconButton(
              tooltip: '编辑',
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onPressed: enabled ? onEdit : null,
              icon: const Icon(Icons.edit_outlined, size: 17),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

String _subtitle(OaTodo item) {
  final parts = <String>[_priorityLabel(item.priority)];
  if (item.dueAt != null) {
    parts.add(DateFormat('MM-dd HH:mm').format(item.dueAt!));
  }
  if (item.description.trim().isNotEmpty) parts.add(item.description.trim());
  return parts.join(' · ');
}

Future<_TodoDraft?> _showTodoSheet(BuildContext context, {OaTodo? item}) async {
  final title = TextEditingController(text: item?.title ?? '');
  final description = TextEditingController(text: item?.description ?? '');
  var priority = item?.priority.isNotEmpty == true ? item!.priority : 'normal';
  var dueAt = item?.dueAt ?? DateTime.now().add(const Duration(hours: 1));
  String? error;
  final result = await showModalBottomSheet<_TodoDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            14 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item == null ? '新增待办' : '编辑待办',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: title,
                autofocus: item == null,
                maxLength: 160,
                decoration: InputDecoration(
                  labelText: '标题',
                  isDense: true,
                  counterText: '',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  isDense: true,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('schedule-priority-select'),
                      onTap: () async {
                        final selected = await showMobileChoiceSheet<String>(
                          context,
                          title: '优先级',
                          selectedValue: priority,
                          options: const [
                            MobileSheetOption(value: 'low', label: '低'),
                            MobileSheetOption(value: 'normal', label: '普通'),
                            MobileSheetOption(value: 'high', label: '高'),
                            MobileSheetOption(value: 'urgent', label: '紧急'),
                          ],
                        );
                        if (selected == null) return;
                        setSheetState(() => priority = selected);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '优先级',
                          suffixIcon: Icon(Icons.expand_more_rounded, size: 20),
                        ),
                        child: Text(_priorityLabel(priority)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final date = await showMobileDatePickerSheet(
                          context,
                          initialDate: dueAt,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 3650),
                          ),
                        );
                        if (date == null || !context.mounted) return;
                        final time = await showMobileTimePickerSheet(
                          context,
                          initialTime: TimeOfDay.fromDateTime(dueAt),
                        );
                        if (time == null) return;
                        setSheetState(
                          () => dueAt = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          ),
                        );
                      },
                      icon: const Icon(Icons.schedule_rounded, size: 17),
                      label: Text(DateFormat('MM-dd HH:mm').format(dueAt)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: FilledButton(
                  onPressed: () {
                    if (title.text.trim().isEmpty) {
                      setSheetState(() => error = '请输入标题');
                      return;
                    }
                    Navigator.pop(
                      context,
                      _TodoDraft(
                        title.text.trim(),
                        description.text.trim(),
                        priority,
                        dueAt,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await Future.wait([
    disposeRouteTextController(title),
    disposeRouteTextController(description),
  ]);
  return result;
}

String _priorityLabel(String value) => switch (value) {
  'urgent' => '紧急',
  'high' => '高优先级',
  'low' => '低优先级',
  _ => '普通',
};

final class _TodoDraft {
  const _TodoDraft(this.title, this.description, this.priority, this.dueAt);
  final String title;
  final String description;
  final String priority;
  final DateTime dueAt;
}
