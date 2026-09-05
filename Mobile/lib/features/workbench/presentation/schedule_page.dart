import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/errors/mobile_error_text.dart';
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
    var message = mobileErrorText(error);
    if (error is DioException && error.response?.data is Map) {
      final serverMessage = (error.response!.data as Map)['message']
          ?.toString();
      if (serverMessage != null && serverMessage.trim().isNotEmpty) {
        message = mobileErrorText(Exception(serverMessage));
      }
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
          description: mobileErrorText(error),
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
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Padding(
          key: const Key('schedule-editor-sheet'),
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
                  Expanded(
                    child: Text(
                      item == null ? '新增待办' : '编辑待办',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
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
                '标题',
                style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: TextField(
                  key: const Key('schedule-title-input'),
                  controller: title,
                  autofocus: item == null,
                  maxLength: 160,
                  onChanged: (_) {
                    if (error != null) setSheetState(() => error = null);
                  },
                  decoration: InputDecoration(
                    hintText: '输入待办标题',
                    isDense: true,
                    counterText: '',
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
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 5),
                Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 11.5,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                '备注（可选）',
                style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 64,
                child: TextField(
                  key: const Key('schedule-description-input'),
                  controller: description,
                  minLines: 2,
                  maxLines: 2,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText: '补充备注',
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: .6),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
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
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: InkWell(
                        key: const Key('schedule-priority-select'),
                        borderRadius: BorderRadius.circular(8),
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
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: .6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _priorityLabel(priority),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                const Icon(
                                  Icons.expand_more_rounded,
                                  size: 18,
                                  color: AppColors.secondaryText,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: InkWell(
                        key: const Key('schedule-due-select'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () async {
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
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: .6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 16,
                                  color: AppColors.secondaryText,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    DateFormat('MM-dd HH:mm').format(dueAt),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
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
                    key: const Key('schedule-save-button'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(72, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
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
                ],
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
