import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key, this.correctionMode = false});

  final bool correctionMode;

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  bool _punching = false;
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(oaAttendanceOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.correctionMode ? '补卡' : '考勤打卡'),
      ),
      body: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '考勤信息加载失败',
          description: _attendanceError(error),
          onRetry: () => ref.invalidate(oaAttendanceOverviewProvider),
        ),
        data: widget.correctionMode ? _buildCorrections : _buildPunch,
      ),
    );
  }

  Widget _buildPunch(OaAttendanceOverview overview) {
    final today = overview.today;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(oaAttendanceOverviewProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          MobileSurface(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  today?.isRestDay == true
                      ? '休息日'
                      : (today?.shiftName.isNotEmpty == true
                            ? today!.shiftName
                            : '今日考勤'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _scheduleText(today),
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 16),
                Text(
                  DateFormat('HH:mm:ss').format(_now),
                  style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 164,
                  height: 42,
                  child: FilledButton.icon(
                    onPressed: !overview.canPunch || _punching ? null : _punch,
                    icon: _punching
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            overview.canPunch
                                ? Icons.fingerprint_rounded
                                : Icons.check_circle_outline_rounded,
                          ),
                    label: Text(
                      overview.canPunch
                          ? _punchLabel(overview.nextPunchType)
                          : '今日打卡已完成',
                    ),
                  ),
                ),
                if (overview.punchMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    overview.punchMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _BehaviorPanel(),
          const SizedBox(height: 18),
          const _BehaviorHistory(),
          const SizedBox(height: 18),
          const _SectionTitle('最近打卡'),
          const SizedBox(height: 8),
          if (overview.recentRecords.isEmpty)
            const Text(
              '暂无打卡记录',
              style: TextStyle(color: AppColors.secondaryText),
            )
          else
            ...overview.recentRecords.map(_AttendanceRecordRow.new),
        ],
      ),
    );
  }

  Widget _buildCorrections(OaAttendanceOverview overview) {
    final exceptions = overview.exceptions
        .where((item) => item.status.toLowerCase() != 'resolved')
        .toList();
    return RefreshIndicator(
      onRefresh: () => ref.refresh(oaAttendanceOverviewProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '本月异常',
                  value: overview.monthExceptionCount.toString(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Metric(
                  label: '补卡次数',
                  value:
                      '${overview.monthPunchCorrectionCount}/${overview.monthlyPunchCorrectionLimit}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle('待处理异常'),
          const SizedBox(height: 8),
          if (exceptions.isEmpty)
            const EmptyState(
              icon: Icons.event_available_outlined,
              title: '暂无待补卡异常',
            )
          else
            ...exceptions.map(
              (item) => _ExceptionRow(
                item: item,
                onCorrect: () => _correct(item),
                onOpenRequest: item.resolutionApprovalRequestId == null
                    ? null
                    : () => context.push(
                        '/approval/${item.resolutionApprovalRequestId}',
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _punch() async {
    setState(() => _punching = true);
    try {
      final record = await ref.read(oaRepositoryProvider).punchAttendance();
      ref.invalidate(oaAttendanceOverviewProvider);
      ref.invalidate(oaBootstrapProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_punchLabel(record.type)}成功')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_attendanceError(error))));
      }
    } finally {
      if (mounted) setState(() => _punching = false);
    }
  }

  Future<void> _correct(OaAttendanceException exception) async {
    final draft = await _showCorrectionSheet(context, exception);
    if (draft == null || !mounted) return;
    try {
      await ref
          .read(oaRepositoryProvider)
          .correctAttendance(
            exceptionId: exception.id,
            correctionAt: draft.at,
            reason: draft.reason,
          );
      ref.invalidate(oaAttendanceOverviewProvider);
      ref.invalidate(oaBootstrapProvider);
      ref.invalidate(oaNotificationsProvider);
      ref.invalidate(oaNotificationPageProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('补卡申请已提交')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_attendanceError(error))));
      }
    }
  }
}

class _BehaviorPanel extends ConsumerStatefulWidget {
  const _BehaviorPanel();

  @override
  ConsumerState<_BehaviorPanel> createState() => _BehaviorPanelState();
}

class _BehaviorPanelState extends ConsumerState<_BehaviorPanel> {
  String _actionId = '';

  Future<void> _refresh() async {
    ref.invalidate(oaBehaviorDefinitionsProvider);
    ref.invalidate(oaActiveBehaviorSessionsProvider);
    ref.invalidate(oaBehaviorSessionHistoryProvider);
    await Future.wait([
      ref.read(oaBehaviorDefinitionsProvider.future),
      ref.read(oaActiveBehaviorSessionsProvider.future),
    ]);
  }

  Future<void> _toggle(
    OaBehaviorDefinition definition,
    OaBehaviorSession? active,
  ) async {
    setState(() => _actionId = active?.id ?? definition.id);
    try {
      final repository = ref.read(oaRepositoryProvider);
      if (active == null) {
        await repository.startBehavior(definition.id);
      } else {
        await repository.finishBehavior(active.id);
      }
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(active == null ? '已开始${definition.name}' : '已返回岗位'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_attendanceError(error))));
      }
    } finally {
      if (mounted) setState(() => _actionId = '');
    }
  }

  Future<void> _returnAll() async {
    setState(() => _actionId = 'return');
    try {
      await ref.read(oaRepositoryProvider).returnToPosition();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已返回岗位')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_attendanceError(error))));
      }
    } finally {
      if (mounted) setState(() => _actionId = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final definitions = ref.watch(oaBehaviorDefinitionsProvider);
    final sessions = ref.watch(oaActiveBehaviorSessionsProvider);
    if (definitions.isLoading || sessions.isLoading) {
      return const SizedBox(
        height: 42,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (definitions.hasError || sessions.hasError) {
      return InkWell(
        onTap: _refresh,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text('岗位状态加载失败，点击重试'),
        ),
      );
    }
    final items = definitions.value ?? const <OaBehaviorDefinition>[];
    final activeItems = sessions.value ?? const <OaBehaviorSession>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return MobileSurface(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _SectionTitle('岗位状态')),
              if (activeItems.isNotEmpty)
                TextButton(
                  onPressed: _actionId.isEmpty ? _returnAll : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('返回岗位'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((definition) {
              final active = activeItems
                  .where((item) => item.behaviorDefinitionId == definition.id)
                  .firstOrNull;
              final blocked =
                  active == null &&
                  activeItems.isNotEmpty &&
                  !definition.allowParallel;
              final busy =
                  _actionId == definition.id || _actionId == active?.id;
              return OutlinedButton.icon(
                onPressed: _actionId.isNotEmpty || blocked
                    ? null
                    : () => _toggle(definition, active),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: active == null
                      ? null
                      : AppColors.primary.withValues(alpha: .08),
                ),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        active == null
                            ? Icons.directions_walk_outlined
                            : Icons.location_on_outlined,
                        size: 17,
                      ),
                label: Text(
                  active == null ? definition.name : '${definition.name}中',
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _BehaviorHistory extends ConsumerWidget {
  const _BehaviorHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(oaBehaviorSessionHistoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('岗位记录'),
        const SizedBox(height: 8),
        value.when(
          loading: () => const SizedBox(
            height: 36,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, _) => InkWell(
            onTap: () => ref.invalidate(oaBehaviorSessionHistoryProvider),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('岗位记录加载失败，点击重试'),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const Text(
                '暂无岗位记录',
                style: TextStyle(color: AppColors.secondaryText),
              );
            }
            return MobileSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: items.take(8).map((item) {
                  final startedAt = item.startedAt;
                  final seconds =
                      item.durationSeconds ??
                      (startedAt == null
                          ? 0
                          : (item.endedAt ?? DateTime.now())
                                .difference(startedAt)
                                .inSeconds);
                  final status = item.endedAt == null
                      ? (item.isOvertime ? '进行中 · 已超时' : '进行中')
                      : (item.isOvertime ? '已结束 · 超时' : '已结束');
                  return ListTile(
                    dense: true,
                    minTileHeight: 48,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: Icon(
                      item.endedAt == null
                          ? Icons.directions_walk_rounded
                          : Icons.history_rounded,
                      size: 20,
                      color: item.isOvertime
                          ? Colors.orange.shade700
                          : AppColors.primary,
                    ),
                    title: Text(
                      item.behaviorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${startedAt == null ? '--' : DateFormat('MM-dd HH:mm').format(startedAt.toLocal())} · ${_durationText(seconds)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: item.isOvertime
                            ? Colors.orange.shade700
                            : AppColors.secondaryText,
                      ),
                    ),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }
}

String _durationText(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  if (hours > 0) return '$hours小时$minutes分钟';
  if (minutes > 0) return '$minutes分钟';
  return '${safe % 60}秒';
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.secondaryText)),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  );
}

class _AttendanceRecordRow extends StatelessWidget {
  const _AttendanceRecordRow(this.record);

  final OaAttendanceRecord record;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.access_time_rounded, color: AppColors.primary),
    title: Text(_punchLabel(record.type)),
    subtitle: Text(record.source.isEmpty ? '终端打卡' : record.source),
    trailing: Text(
      record.occurredAt == null
          ? '-'
          : DateFormat('MM-dd HH:mm').format(record.occurredAt!),
    ),
  );
}

class _ExceptionRow extends StatelessWidget {
  const _ExceptionRow({
    required this.item,
    required this.onCorrect,
    this.onOpenRequest,
  });

  final OaAttendanceException item;
  final VoidCallback onCorrect;
  final VoidCallback? onOpenRequest;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        const Icon(Icons.event_busy_outlined, color: AppColors.error),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _exceptionLabel(item.type),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                item.workDate,
                style: const TextStyle(color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
        if (onOpenRequest != null)
          TextButton(onPressed: onOpenRequest, child: const Text('查看申请'))
        else
          OutlinedButton(onPressed: onCorrect, child: const Text('补卡')),
      ],
    ),
  );
}

Future<_CorrectionDraft?> _showCorrectionSheet(
  BuildContext context,
  OaAttendanceException exception,
) async {
  DateTime selected = DateTime.tryParse(exception.workDate) ?? DateTime.now();
  final reason = TextEditingController();
  String? error;
  final result = await showModalBottomSheet<_CorrectionDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '补${_exceptionLabel(exception.type)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selected,
                    firstDate: selected.subtract(const Duration(days: 31)),
                    lastDate: DateTime.now(),
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(selected),
                  );
                  if (time == null) return;
                  setSheetState(() {
                    selected = DateTime(
                      date.year,
                      date.month,
                      date.day,
                      time.hour,
                      time.minute,
                    );
                  });
                },
                icon: const Icon(Icons.schedule_rounded),
                label: Text(DateFormat('yyyy-MM-dd HH:mm').format(selected)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: '补卡原因',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  if (reason.text.trim().isEmpty) {
                    setSheetState(() => error = '请填写补卡原因');
                    return;
                  }
                  Navigator.pop(
                    context,
                    _CorrectionDraft(selected, reason.text.trim()),
                  );
                },
                child: const Text('提交补卡'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await disposeRouteTextController(reason);
  return result;
}

String _scheduleText(OaPersonalScheduleDay? day) {
  if (day == null) return '今日未排班';
  if (day.isRestDay) return '休息日可按部门规则打卡';
  final start = day.expectedCheckInAt;
  final end = day.expectedCheckOutAt;
  if (start == null || end == null) return '班次时间待同步';
  return '${DateFormat('HH:mm').format(start)} - ${DateFormat('HH:mm').format(end)}';
}

String _punchLabel(String type) => switch (type.toLowerCase()) {
  'check_out' || 'checkout' => '下班打卡',
  _ => '上班打卡',
};

String _exceptionLabel(String type) => switch (type.toLowerCase()) {
  'missing_check_in' => '缺上班卡',
  'missing_check_out' => '缺下班卡',
  'late' => '迟到',
  'early_leave' => '早退',
  _ => '考勤异常',
};

String _attendanceError(Object error) {
  if (error is DioException && error.response?.data is Map) {
    final data = error.response!.data as Map;
    final message = data['message']?.toString() ?? '';
    if (message.trim().isNotEmpty) return message;
  }
  return error.toString().replaceFirst('Exception: ', '');
}

final class _CorrectionDraft {
  const _CorrectionDraft(this.at, this.reason);

  final DateTime at;
  final String reason;
}
