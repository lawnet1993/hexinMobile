import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'mobile_primitives.dart';

final class MobileSheetOption<T> {
  const MobileSheetOption({
    required this.value,
    required this.label,
    this.subtitle = '',
    this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final String subtitle;
  final IconData? icon;
  final bool destructive;
}

Future<T?> showMobileChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<MobileSheetOption<T>> options,
  T? selectedValue,
  bool searchable = false,
  String searchHint = '搜索',
  String emptyText = '暂无可选项',
}) async {
  final searchController = TextEditingController();
  var query = '';
  final result = await showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final keyword = query.trim().toLowerCase();
        final filtered = options.where((option) {
          if (keyword.isEmpty) return true;
          return option.label.toLowerCase().contains(keyword) ||
              option.subtitle.toLowerCase().contains(keyword);
        }).toList();
        final height = math.min(
          MediaQuery.sizeOf(context).height * .78,
          72.0 + (searchable ? 52 : 0) + math.max(1, filtered.length) * 52.0,
        );
        return SafeArea(
          top: false,
          child: SizedBox(
            key: const Key('mobile-choice-sheet'),
            height: height,
            child: Column(
              children: [
                _SheetHeader(title: title),
                if (searchable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: MobileSearchField(
                      controller: searchController,
                      autofocus: options.length > 12,
                      hintText: searchHint,
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            emptyText,
                            style: const TextStyle(
                              color: AppColors.secondaryText,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final option = filtered[index];
                            final selected = option.value == selectedValue;
                            final color = option.destructive
                                ? AppColors.error
                                : AppColors.text;
                            return ListTile(
                              minTileHeight: 48,
                              dense: true,
                              leading: option.icon == null
                                  ? null
                                  : Icon(option.icon, size: 20, color: color),
                              title: Text(
                                option.label,
                                style: TextStyle(fontSize: 15, color: color),
                              ),
                              subtitle: option.subtitle.isEmpty
                                  ? null
                                  : Text(
                                      option.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5),
                                    ),
                              trailing: selected
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 20,
                                      color: AppColors.primary,
                                    )
                                  : null,
                              onTap: () =>
                                  Navigator.pop(sheetContext, option.value),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  await disposeRouteTextController(searchController);
  return result;
}

Future<List<T>?> showMobileMultiChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<MobileSheetOption<T>> options,
  required Iterable<T> selectedValues,
  bool searchable = false,
  String searchHint = '搜索',
}) async {
  final selected = selectedValues.toSet();
  final searchController = TextEditingController();
  var query = '';
  final result = await showModalBottomSheet<List<T>>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final keyword = query.trim().toLowerCase();
        final filtered = options.where((option) {
          if (keyword.isEmpty) return true;
          return option.label.toLowerCase().contains(keyword) ||
              option.subtitle.toLowerCase().contains(keyword);
        }).toList();
        return SafeArea(
          top: false,
          child: SizedBox(
            key: const Key('mobile-multi-choice-sheet'),
            height: MediaQuery.sizeOf(context).height * .78,
            child: Column(
              children: [
                _SheetHeader(title: title),
                if (searchable)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: MobileSearchField(
                      controller: searchController,
                      hintText: searchHint,
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final option = filtered[index];
                      final checked = selected.contains(option.value);
                      return CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.trailing,
                        title: Text(option.label),
                        subtitle: option.subtitle.isEmpty
                            ? null
                            : Text(option.subtitle),
                        value: checked,
                        onChanged: (_) => setSheetState(() {
                          checked
                              ? selected.remove(option.value)
                              : selected.add(option.value);
                        }),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setSheetState(selected.clear),
                        child: const Text('清空'),
                      ),
                      const Spacer(),
                      FilledButton(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(92, 40)),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () =>
                            Navigator.pop(sheetContext, selected.toList()),
                        child: Text('确定（${selected.length}）'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  await disposeRouteTextController(searchController);
  return result;
}

Future<void> showMobileMessageSheet(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = '知道了',
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    top: false,
    child: Padding(
      key: const Key('mobile-message-sheet'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.secondaryText,
            ),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(88, 40)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<bool?> showMobileConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool destructive = false,
}) => showModalBottomSheet<bool>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isDismissible: true,
  builder: (sheetContext) => PopScope(
    canPop: true,
    child: SafeArea(
      top: false,
      child: Padding(
        key: const Key('mobile-confirm-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: destructive ? AppColors.error : null,
                  ),
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: Text(confirmLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ),
);

Future<DateTime?> showMobileDatePickerSheet(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '选择日期',
}) {
  var selected = initialDate;
  return showModalBottomSheet<DateTime>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        top: false,
        child: Column(
          key: const Key('mobile-date-picker-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHeader(title: title),
            CalendarDatePicker(
              initialDate: initialDate,
              firstDate: firstDate,
              lastDate: lastDate,
              onDateChanged: (date) => setSheetState(() => selected = date),
            ),
            _SheetActions(
              onConfirm: () => Navigator.pop(sheetContext, selected),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<DateTimeRange?> showMobileDateRangePickerSheet(
  BuildContext context, {
  DateTimeRange? initialDateRange,
  required DateTime firstDate,
  required DateTime lastDate,
  String title = '选择日期范围',
}) {
  var start = initialDateRange?.start;
  var end = initialDateRange?.end;
  final initialDate = start ?? DateTime.now();
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        top: false,
        child: Column(
          key: const Key('mobile-date-range-picker-sheet'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHeader(title: title),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _DateValue(
                      label: '开始',
                      value: start,
                      active: start == null || end != null,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward_rounded, size: 18),
                  ),
                  Expanded(
                    child: _DateValue(
                      label: '结束',
                      value: end,
                      active: start != null && end == null,
                    ),
                  ),
                ],
              ),
            ),
            CalendarDatePicker(
              initialDate: initialDate.isBefore(firstDate)
                  ? firstDate
                  : initialDate.isAfter(lastDate)
                  ? lastDate
                  : initialDate,
              firstDate: firstDate,
              lastDate: lastDate,
              onDateChanged: (date) => setSheetState(() {
                if (start == null || end != null) {
                  start = date;
                  end = null;
                } else if (date.isBefore(start!)) {
                  end = start;
                  start = date;
                } else {
                  end = date;
                }
              }),
            ),
            _SheetActions(
              onConfirm: start == null || end == null
                  ? null
                  : () => Navigator.pop(
                      sheetContext,
                      DateTimeRange(start: start!, end: end!),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<TimeOfDay?> showMobileTimePickerSheet(
  BuildContext context, {
  required TimeOfDay initialTime,
  String title = '选择时间',
}) async {
  var hour = initialTime.hour;
  var minute = initialTime.minute;
  final hourController = FixedExtentScrollController(initialItem: hour);
  final minuteController = FixedExtentScrollController(initialItem: minute);
  final result = await showModalBottomSheet<TimeOfDay>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Column(
        key: const Key('mobile-time-picker-sheet'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(title: title),
          SizedBox(
            height: 156,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _NumberWheel(
                  controller: hourController,
                  count: 24,
                  semanticsLabel: '小时',
                  onChanged: (value) => hour = value,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    ':',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                ),
                _NumberWheel(
                  controller: minuteController,
                  count: 60,
                  semanticsLabel: '分钟',
                  onChanged: (value) => minute = value,
                ),
              ],
            ),
          ),
          _SheetActions(
            onConfirm: () => Navigator.pop(
              sheetContext,
              TimeOfDay(hour: hour, minute: minute),
            ),
          ),
        ],
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 320));
  hourController.dispose();
  minuteController.dispose();
  return result;
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 0, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            key: const Key('mobile-sheet-title'),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, size: 21),
        ),
      ],
    ),
  );
}

class _SheetActions extends StatelessWidget {
  const _SheetActions({required this.onConfirm});

  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(88, 40)),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: onConfirm,
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

class _DateValue extends StatelessWidget {
  const _DateValue({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final DateTime? value;
  final bool active;

  @override
  Widget build(BuildContext context) => Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.centerLeft,
    decoration: BoxDecoration(
      color: active ? const Color(0xFFEAF2FF) : const Color(0xFFF3F5F8),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$label  ${value == null ? '请选择' : _dateText(value!)}',
      style: TextStyle(
        fontSize: 13.5,
        color: value == null ? AppColors.secondaryText : AppColors.text,
      ),
    ),
  );
}

class _NumberWheel extends StatelessWidget {
  const _NumberWheel({
    required this.controller,
    required this.count,
    required this.semanticsLabel,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int count;
  final String semanticsLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 78,
    child: Semantics(
      label: semanticsLabel,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: 42,
        physics: const FixedExtentScrollPhysics(),
        diameterRatio: 1.35,
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: count,
          builder: (context, index) => Center(
            child: Text(
              index.toString().padLeft(2, '0'),
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),
      ),
    ),
  );
}

String _dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
