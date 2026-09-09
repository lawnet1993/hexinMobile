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

final class MobileDestructiveVerificationResult {
  const MobileDestructiveVerificationResult({
    required this.reason,
    required this.confirmation,
  });

  final String reason;
  final String confirmation;
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
  FocusManager.instance.primaryFocus?.unfocus();
  final searchController = MobileSearchTextController(
    searchLabel: searchHint,
  );
  var query = '';
  final result = await showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
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
  FocusManager.instance.primaryFocus?.unfocus();
  final selected = selectedValues.toSet();
  final searchController = MobileSearchTextController(
    searchLabel: searchHint,
  );
  var query = '';
  final result = await showModalBottomSheet<List<T>>(
    context: context,
    useRootNavigator: true,
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
                        style: compactMobileActionStyle,
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
  useRootNavigator: true,
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
              style: compactMobileActionStyle,
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<String?> showMobileTextInputSheet(
  BuildContext context, {
  required String title,
  String subtitle = '',
  String initialValue = '',
  String label = '',
  String hintText = '',
  int? maxLength,
  int minLines = 1,
  int maxLines = 1,
  String actionLabel = '保存',
  bool autofocus = true,
  bool allowEmpty = true,
  String? Function(String value)? validator,
}) async {
  final controller = TextEditingController(text: initialValue);
  String? errorText;
  final result = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        top: false,
        child: Padding(
          key: const Key('mobile-text-input-sheet'),
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          key: const Key('mobile-sheet-title'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (label.isNotEmpty) ...[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              SizedBox(
                height: maxLines == 1 ? 36 : null,
                child: TextField(
                  key: const Key('mobile-text-input-field'),
                  controller: controller,
                  autofocus: autofocus,
                  maxLength: maxLength,
                  minLines: minLines,
                  maxLines: maxLines,
                  textInputAction: maxLines == 1
                      ? TextInputAction.done
                      : TextInputAction.newline,
                  decoration: InputDecoration(
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
                    hintText: hintText.isEmpty ? null : hintText,
                    counterText: maxLength == null ? null : '',
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
                  onSubmitted: maxLines == 1
                      ? (_) => _submitMobileTextInput(
                          sheetContext,
                          controller.text,
                          allowEmpty: allowEmpty,
                          validator: validator,
                          setError: (value) =>
                              setSheetState(() => errorText = value),
                        )
                      : null,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(60, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('mobile-text-input-submit'),
                    style: compactMobileActionStyle,
                    onPressed: () => _submitMobileTextInput(
                      sheetContext,
                      controller.text,
                      allowEmpty: allowEmpty,
                      validator: validator,
                      setError: (value) =>
                          setSheetState(() => errorText = value),
                    ),
                    child: Text(actionLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await disposeRouteTextController(controller);
  return result;
}

Future<MobileDestructiveVerificationResult?>
showMobileDestructiveVerificationSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String requiredPhrase,
  String reasonLabel = '操作原因',
  String confirmationLabel = '输入名称确认',
  String actionLabel = '确认操作',
}) async {
  final reasonController = TextEditingController();
  final confirmationController = TextEditingController();
  var reason = '';
  var confirmation = '';
  final result =
      await showModalBottomSheet<MobileDestructiveVerificationResult>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: false,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            final canSubmit =
                reason.trim().isNotEmpty &&
                confirmation.trim() == requiredPhrase;
            return SafeArea(
              top: false,
              child: Padding(
                key: const Key('mobile-destructive-verification-sheet'),
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  12 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SingleChildScrollView(
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
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded, size: 19),
                          ),
                        ],
                      ),
                      Text(
                        message,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(reasonLabel, style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 6),
                      TextField(
                        key: const Key('mobile-destructive-reason'),
                        controller: reasonController,
                        autofocus: true,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 3,
                        decoration: _compactSheetInputDecoration(
                          context,
                          hintText: '请填写$reasonLabel',
                        ),
                        onChanged: (value) =>
                            setSheetState(() => reason = value),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$confirmationLabel：$requiredPhrase',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 36,
                        child: TextField(
                          key: const Key('mobile-destructive-confirmation'),
                          controller: confirmationController,
                          textInputAction: TextInputAction.done,
                          decoration: _compactSheetInputDecoration(
                            context,
                            hintText: requiredPhrase,
                          ),
                          onChanged: (value) =>
                              setSheetState(() => confirmation = value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(60, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => Navigator.pop(sheetContext),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const Key('mobile-destructive-submit'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(88, 36),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AppColors.error,
                            ),
                            onPressed: canSubmit
                                ? () => Navigator.pop(
                                    sheetContext,
                                    MobileDestructiveVerificationResult(
                                      reason: reason.trim(),
                                      confirmation: confirmation.trim(),
                                    ),
                                  )
                                : null,
                            child: Text(actionLabel),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
  await disposeRouteTextController(reasonController);
  await disposeRouteTextController(confirmationController);
  return result;
}

InputDecoration _compactSheetInputDecoration(
  BuildContext context, {
  required String hintText,
}) => InputDecoration(
  isDense: true,
  filled: true,
  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest
      .withValues(alpha: .6),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  hintText: hintText,
  counterText: '',
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
);

void _submitMobileTextInput(
  BuildContext context,
  String rawValue, {
  required bool allowEmpty,
  required String? Function(String value)? validator,
  required ValueChanged<String?> setError,
}) {
  final value = rawValue.trim();
  final error = !allowEmpty && value.isEmpty ? '请填写内容' : validator?.call(value);
  if (error != null) {
    setError(error);
    return;
  }
  Navigator.pop(context, value);
}

Future<bool?> showMobileConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  bool destructive = false,
}) => showModalBottomSheet<bool>(
  context: context,
  useRootNavigator: true,
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
                  style: compactMobileActionStyle,
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: compactMobileActionStyle.copyWith(
                    backgroundColor: destructive
                        ? const WidgetStatePropertyAll(AppColors.error)
                        : null,
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
  // A picker replaces text entry. Clear the route's focus history so closing
  // it cannot reopen the keyboard from the previously edited form field.
  FocusManager.instance.primaryFocus?.unfocus();
  var selected = initialDate;
  return showModalBottomSheet<DateTime>(
    context: context,
    useRootNavigator: true,
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
  FocusManager.instance.primaryFocus?.unfocus();
  var start = initialDateRange?.start;
  var end = initialDateRange?.end;
  final initialDate = start ?? DateTime.now();
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    useRootNavigator: true,
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
  FocusManager.instance.primaryFocus?.unfocus();
  var hour = initialTime.hour;
  var minute = initialTime.minute;
  final hourController = FixedExtentScrollController(initialItem: hour);
  final minuteController = FixedExtentScrollController(initialItem: minute);
  final result = await showModalBottomSheet<TimeOfDay>(
    context: context,
    useRootNavigator: true,
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
          style: compactMobileActionStyle,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: compactMobileActionStyle,
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
