import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';
import 'approval_request_page.dart';

class ApprovalDetailPage extends ConsumerStatefulWidget {
  const ApprovalDetailPage({super.key, required this.approvalId});

  final String approvalId;

  @override
  ConsumerState<ApprovalDetailPage> createState() => _ApprovalDetailPageState();
}

class _ApprovalDetailPageState extends ConsumerState<ApprovalDetailPage> {
  bool _submitting = false;
  bool _ccReadAttempted = false;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(oaApprovalRequestProvider(widget.approvalId));
    return value.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: const Text('审批详情')),
        body: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '审批详情加载失败',
          description: _errorMessage(error),
          onRetry: () =>
              ref.invalidate(oaApprovalRequestProvider(widget.approvalId)),
        ),
      ),
      data: _buildDetail,
    );
  }

  Widget _buildDetail(OaApprovalRequest request) {
    _markUnreadCopyAfterOpen(request);
    final task = request.operableTask;
    final oaBootstrap = ref.watch(oaBootstrapProvider).value;
    final applicationCatalog = ref.watch(oaApplicationCatalogProvider).value;
    final imBootstrap = ref.watch(imBootstrapProvider).value;
    final members = imBootstrap?.contacts ?? const [];
    final membersById = <String, ImMember>{
      if (imBootstrap != null)
        imBootstrap.currentMember.id: imBootstrap.currentMember,
      for (final member in members) member.id: member,
    };
    final canApprove =
        task != null && request.allowedActions.contains('approve');
    final canReject = task != null && request.allowedActions.contains('reject');
    final secondaryActions = <String>[
      for (final action in const [
        'transfer',
        'add_sign',
        'return',
        'remind',
        'withdraw',
      ])
        if (request.allowedActions.contains(action)) action,
    ];
    final canResubmit = _canResubmit(
      request,
      currentMemberId: oaBootstrap?.currentMemberId ?? '',
    );
    final resubmitTarget = canResubmit
        ? _resolveResubmitTarget(request, oaBootstrap, applicationCatalog)
        : null;
    final hasReviewActions =
        canApprove || canReject || secondaryActions.isNotEmpty;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('审批详情')),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref
              .read(oaRepositoryProvider)
              .refreshApprovalRequest(widget.approvalId);
          ref.invalidate(oaApprovalRequestProvider(widget.approvalId));
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          children: [
            MobileSurface(
              padding: const EdgeInsets.all(12),
              child: _RequestHeader(
                request: request,
                member: membersById[request.requesterId],
              ),
            ),
            const SizedBox(height: 8),
            MobileSurface(
              key: const Key('approval-request-content'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('申请内容'),
                  const SizedBox(height: 5),
                  ..._formRows(request)
                      .map((item) => _DetailRow(item.label, item.value)),
                  if (request.attachments.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    const _SectionTitle('附件'),
                    const SizedBox(height: 4),
                    ...request.attachments.map(
                      (attachment) => _AttachmentRow(
                        attachment,
                        onTap: () => _openAttachment(attachment),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            MobileSurface(
              key: const Key('approval-progress-surface'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('审批进度'),
                  const SizedBox(height: 8),
                  _SubmissionTimelineItem(
                    request: request,
                    member: membersById[request.requesterId],
                    last: request.tasks.isEmpty,
                  ),
                  ...request.tasks.indexed.map(
                    (entry) => _TimelineItem(
                      task: entry.$2,
                      member: membersById[entry.$2.assigneeId],
                      last: entry.$1 == request.tasks.length - 1,
                    ),
                  ),
                  if (request.actions.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    const _SectionTitle('处理记录'),
                    const SizedBox(height: 4),
                    ...request.actions.map(_ActionRow.new),
                  ],
                ],
              ),
            ),
            if (request.ccs.isNotEmpty) ...[
              const SizedBox(height: 8),
              MobileSurface(
                key: const Key('approval-copy-surface'),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('抄送人'),
                    const SizedBox(height: 7),
                    _ApprovalCopies(copies: request.ccs),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: canResubmit
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: FilledButton.icon(
                  key: const Key('approval-resubmit'),
                  onPressed: () => _startAgain(request, resubmitTarget),
                  style: _compactApprovalButtonStyle(),
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('再次发起'),
                ),
              ),
            )
          : hasReviewActions
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    if (secondaryActions.isNotEmpty) ...[
                      Tooltip(
                        message: '更多操作',
                        child: OutlinedButton.icon(
                          key: const Key('approval-more-actions'),
                          onPressed: _submitting
                              ? null
                              : () async {
                                  final action =
                                      await _showSecondaryActionsSheet(
                                        context,
                                        secondaryActions,
                                      );
                                  if (action == null || !mounted) return;
                                  await _runSecondaryAction(
                                    request,
                                    task,
                                    action,
                                    members,
                                  );
                                },
                          style: _compactApprovalButtonStyle().copyWith(
                            minimumSize: const WidgetStatePropertyAll(
                              Size(80, 42),
                            ),
                          ),
                          icon: const Icon(Icons.more_horiz_rounded, size: 18),
                          label: const Text('更多'),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (canReject)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => _review(request, task, false),
                          style: _compactApprovalButtonStyle(),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          label: const Text('驳回'),
                        ),
                      ),
                    if (canReject && canApprove) const SizedBox(width: 8),
                    if (canApprove)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => _review(request, task, true),
                          icon: _submitting
                              ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 18),
                          style: _compactApprovalButtonStyle(),
                          label: const Text('同意'),
                        ),
                      ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  void _startAgain(
    OaApprovalRequest request,
    ({String applicationKey, String templateId})? target,
  ) {
    if (target == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前应用没有可用的审批流程')));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ApprovalRequestPage(
          applicationKey: target.applicationKey,
          templateId: target.templateId,
          initialTitle: request.title,
          initialFormData: _resubmissionData(request),
        ),
      ),
    );
  }

  void _markUnreadCopyAfterOpen(OaApprovalRequest request) {
    if (_ccReadAttempted) return;
    final currentMemberId = ref
        .watch(oaBootstrapProvider)
        .value
        ?.currentMemberId;
    if (currentMemberId == null || currentMemberId.isEmpty) return;
    final unreadCopy = request.ccs.any(
      (item) => item.memberId == currentMemberId && !item.isRead,
    );
    if (!unreadCopy) return;
    _ccReadAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(markApprovalCcReadActionProvider)(widget.approvalId);
        if (!mounted) return;
        ref.invalidate(oaApprovalRequestProvider(widget.approvalId));
        ref.invalidate(oaBootstrapProvider);
        ref.invalidate(oaNotificationsProvider);
        ref.invalidate(oaNotificationPageProvider);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('抄送已读状态将在联网后同步')));
      }
    });
  }

  Future<void> _openAttachment(OaApprovalAttachment attachment) async {
    try {
      if (attachment.isPreviewableImage) {
        final bytes = await ref
            .read(oaRepositoryProvider)
            .downloadAttachmentPreview(attachment.id);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierColor: Colors.black87,
          builder: (context) => Dialog.fullscreen(
            backgroundColor: Colors.black,
            child: SafeArea(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Center(child: Image.memory(bytes)),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        return;
      }
      final bytes = await ref
          .read(oaRepositoryProvider)
          .downloadAttachment(attachment.id);
      final directory = await getTemporaryDirectory();
      final target = File(
        path.join(directory.path, path.basename(attachment.fileName)),
      );
      await target.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(target.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('附件打开失败：$error')));
      }
    }
  }

  Future<void> _runSecondaryAction(
    OaApprovalRequest request,
    OaApprovalTask? task,
    String action,
    List<ImMember> members,
  ) async {
    Future<OaApprovalRequest>? operation;
    if (action == 'transfer' || action == 'add_sign') {
      if (task == null) return;
      final member = await _showMemberPicker(
        context,
        action == 'transfer' ? '选择转交人' : '选择加签人',
        members.where((item) => item.id != task.assigneeId).toList(),
      );
      if (member == null || !mounted) return;
      if (action == 'transfer') {
        final reason = await _showReasonSheet(context, title: '转交原因');
        if (reason == null) return;
        operation = ref
            .read(oaRepositoryProvider)
            .transferApproval(
              requestId: request.id,
              task: task,
              newAssigneeId: member.id,
              reason: reason,
            );
      } else {
        final mode = await _showAddSignMode(context);
        if (mode == null || !mounted) return;
        final comment = await _showReasonSheet(
          context,
          title: '加签说明',
          required: false,
        );
        if (comment == null) return;
        operation = ref
            .read(oaRepositoryProvider)
            .addSignApproval(
              requestId: request.id,
              task: task,
              addedAssigneeId: member.id,
              mode: mode,
              comment: comment,
            );
      }
    } else if (action == 'return') {
      if (task == null) return;
      final reason = await _showReasonSheet(context, title: '退回原因');
      if (reason == null) return;
      operation = ref
          .read(oaRepositoryProvider)
          .returnApproval(requestId: request.id, task: task, reason: reason);
    } else if (action == 'withdraw') {
      final reason = await _showReasonSheet(context, title: '撤回原因');
      if (reason == null) return;
      operation = ref
          .read(oaRepositoryProvider)
          .withdrawApproval(requestId: request.id, reason: reason);
    } else if (action == 'remind') {
      final comment = await _showReasonSheet(
        context,
        title: '催办留言',
        required: false,
      );
      if (comment == null) return;
      operation = ref
          .read(oaRepositoryProvider)
          .remindApproval(requestId: request.id, comment: comment);
    }
    if (operation == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      await operation;
      _invalidateRequest(request.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${_actionLabel(action)}成功')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _invalidateRequest(String requestId) {
    ref.invalidate(oaApprovalRequestProvider(requestId));
    ref.invalidate(oaBootstrapProvider);
    ref.invalidate(oaNotificationsProvider);
    ref.invalidate(oaNotificationPageProvider);
  }

  Future<void> _review(
    OaApprovalRequest request,
    OaApprovalTask task,
    bool approve,
  ) async {
    final draft = await _showReviewSheet(context, approve);
    if (draft == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      final updatedRequest = await ref
          .read(oaRepositoryProvider)
          .reviewApproval(
            requestId: request.id,
            taskId: task.id,
            expectedTaskVersion: task.version,
            decision: approve ? 'approved' : 'rejected',
            comment: draft.comment,
          );
      _invalidateRequest(request.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approvalReviewSuccessMessage(
                approved: approve,
                requestStatus: updatedRequest.status,
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _RequestHeader extends StatelessWidget {
  const _RequestHeader({required this.request, this.member});

  final OaApprovalRequest request;
  final ImMember? member;

  @override
  Widget build(BuildContext context) {
    final status = _statusPresentation(request.status);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InitialAvatar(
          name: request.requesterName.isEmpty ? '申请人' : request.requesterName,
          radius: 21,
          avatarDataUrl: member?.avatarDataUrl ?? '',
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.title.isEmpty ? request.templateName : request.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                [
                  if (request.requesterName.isNotEmpty) request.requesterName,
                  if (request.requesterDepartmentName.isNotEmpty)
                    request.requesterDepartmentName,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  _requestNumber(request),
                  if (request.createdAt != null)
                    DateFormat('yyyy-MM-dd HH:mm').format(request.createdAt!),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.weakText,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: status.color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            child: Text(
              status.label,
              style: TextStyle(fontSize: 12.5, color: status.color),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
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
            value.isEmpty ? '-' : value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    ),
  );
}

class _AttachmentRow extends ConsumerWidget {
  const _AttachmentRow(this.attachment, {required this.onTap});

  final OaApprovalAttachment attachment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: attachment.isPreviewableImage
                ? ref
                      .watch(oaAttachmentThumbnailProvider(attachment.id))
                      .when(
                        data: (bytes) => ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(bytes, fit: BoxFit.cover),
                        ),
                        loading: () => const Center(
                          child: SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ),
                        error: (_, _) => const Icon(
                          Icons.image_outlined,
                          color: AppColors.primary,
                          size: 24,
                        ),
                      )
                : const Icon(
                    Icons.insert_drive_file_outlined,
                    color: AppColors.primary,
                    size: 25,
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_fileSize(attachment.size)} · ${attachment.isPreviewableImage ? '点击预览' : '点击打开'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.secondaryText,
          ),
        ],
      ),
    ),
  );
}

class _SubmissionTimelineItem extends StatelessWidget {
  const _SubmissionTimelineItem({
    required this.request,
    required this.last,
    this.member,
  });

  final OaApprovalRequest request;
  final bool last;
  final ImMember? member;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          child: Column(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 18,
              ),
              if (!last)
                Expanded(child: Container(width: 1, color: AppColors.border)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        InitialAvatar(
          name: request.requesterName.isEmpty ? '申请人' : request.requesterName,
          radius: 17,
          avatarDataUrl: member?.avatarDataUrl ?? '',
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '提交申请',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    request.requesterName.isEmpty
                        ? '申请人'
                        : request.requesterName,
                    if (request.requesterDepartmentName.isNotEmpty)
                      request.requesterDepartmentName,
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ),
        Text(
          request.createdAt == null
              ? ''
              : DateFormat('MM-dd HH:mm').format(request.createdAt!),
          style: const TextStyle(fontSize: 11, color: AppColors.secondaryText),
        ),
      ],
    ),
  );
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.task, required this.last, this.member});

  final OaApprovalTask task;
  final bool last;
  final ImMember? member;

  @override
  Widget build(BuildContext context) {
    final status = task.status.toLowerCase();
    final completed = status == 'approved' || status == 'completed';
    final rejected = status == 'rejected';
    final canceled = status == 'canceled' || status == 'cancelled';
    final active = task.canOperate || status == 'pending';
    final actorDetails = _approvalTaskActorDetails(task, member);
    final color = rejected
        ? AppColors.error
        : completed
        ? AppColors.success
        : active
        ? AppColors.primary
        : AppColors.weakText;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Icon(
                  rejected
                      ? Icons.cancel_rounded
                      : completed
                      ? Icons.check_circle_rounded
                      : canceled
                      ? Icons.remove_circle_outline_rounded
                      : active
                      ? Icons.radio_button_checked_rounded
                      : Icons.schedule_rounded,
                  color: color,
                  size: 18,
                ),
                if (!last)
                  Expanded(child: Container(width: 1, color: AppColors.border)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          InitialAvatar(
            name: actorDetails.isEmpty ? task.nodeName : actorDetails.first,
            radius: 17,
            avatarDataUrl: member?.avatarDataUrl ?? '',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.nodeName.isEmpty ? '审批节点' : task.nodeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _taskStatusLabel(task),
                        style: TextStyle(fontSize: 12, color: color),
                      ),
                      if (task.completedAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MM-dd HH:mm').format(task.completedAt!),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    actorDetails.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.25,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  if (task.comment.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.comment,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                  if (task.status.toLowerCase() == 'pending' &&
                      task.dueAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        '截止 ${DateFormat('MM-dd HH:mm').format(task.dueAt!)}',
                        if (task.timeoutAction.isNotEmpty)
                          '超时${_timeoutActionLabel(task.timeoutAction)}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                  if (task.timeoutLastError.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      task.timeoutLastError,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow(this.action);

  final OaApprovalAction action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                action.actorName.isEmpty ? '系统' : action.actorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (action.occurredAt != null)
              Text(
                DateFormat('MM-dd HH:mm').format(action.occurredAt!),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.secondaryText,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          [
            _actionLabel(action.action),
            if (action.comment.isNotEmpty) action.comment,
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
        ),
      ],
    ),
  );
}

class _ApprovalCopies extends StatelessWidget {
  const _ApprovalCopies({required this.copies});

  final List<OaApprovalCc> copies;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: copies.map((copy) {
      final color = copy.isRead ? AppColors.success : AppColors.secondaryText;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            '${copy.memberName.isEmpty ? '抄送人' : copy.memberName} · ${copy.isRead ? '已读' : '未读'}',
            style: TextStyle(fontSize: 12.5, color: color),
          ),
        ),
      );
    }).toList(),
  );
}

Future<_ReviewDraft?> _showReviewSheet(
  BuildContext context,
  bool approve,
) async {
  final controller = TextEditingController();
  String? validationMessage;
  final result = await showModalBottomSheet<_ReviewDraft>(
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
                approve ? '同意审批' : '驳回审批',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: !approve,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: approve ? '处理意见（选填）' : '驳回原因',
                  errorText: validationMessage,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  final comment = controller.text.trim();
                  if (!approve && comment.isEmpty) {
                    setSheetState(() => validationMessage = '请填写驳回原因');
                    return;
                  }
                  Navigator.pop(context, _ReviewDraft(comment));
                },
                child: Text(approve ? '确认同意' : '确认驳回'),
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
  await disposeRouteTextController(controller);
  return result;
}

Future<ImMember?> _showMemberPicker(
  BuildContext context,
  String title,
  List<ImMember> members,
) async {
  final searchController = TextEditingController();
  var query = '';
  final result = await showModalBottomSheet<ImMember>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) {
        final filtered = members.where((member) {
          final keyword = query.toLowerCase();
          return keyword.isEmpty ||
              member.displayName.toLowerCase().contains(keyword) ||
              member.username.toLowerCase().contains(keyword) ||
              member.departmentName.toLowerCase().contains(keyword);
        }).toList();
        final listHeight = filtered.isEmpty
            ? 96.0
            : (filtered.length * 58.0).clamp(58.0, 290.0);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              0,
              18,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: 108 + listHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    autofocus: false,
                    decoration: const InputDecoration(
                      hintText: '搜索姓名、账号或部门',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) =>
                        setSheetState(() => query = value.trim()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? const EmptyState(
                            icon: Icons.person_search_outlined,
                            title: '没有可选成员',
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final member = filtered[index];
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                minVerticalPadding: 4,
                                visualDensity: VisualDensity.compact,
                                leading: InitialAvatar(
                                  name: member.displayName,
                                  radius: 18,
                                  avatarDataUrl: member.avatarDataUrl,
                                ),
                                title: Text(member.displayName),
                                subtitle: Text(
                                  [member.username, member.departmentName]
                                      .where((value) => value.isNotEmpty)
                                      .join(' · '),
                                ),
                                onTap: () => Navigator.pop(context, member),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  await disposeRouteTextController(searchController);
  return result;
}

Future<String?> _showReasonSheet(
  BuildContext context, {
  required String title,
  bool required = true,
}) async {
  final controller = TextEditingController();
  String? errorText;
  final result = await showModalBottomSheet<String>(
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
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: required ? title : '$title（选填）',
                  errorText: errorText,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (required && value.isEmpty) {
                    setSheetState(() => errorText = '请填写$title');
                    return;
                  }
                  Navigator.pop(context, value);
                },
                child: const Text('确认'),
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
  await disposeRouteTextController(controller);
  return result;
}

Future<String?> _showAddSignMode(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.vertical_align_top_rounded),
              title: const Text('前加签'),
              subtitle: const Text('新增人员先处理，之后回到当前节点'),
              onTap: () => Navigator.pop(context, 'before'),
            ),
            ListTile(
              leading: const Icon(Icons.vertical_align_bottom_rounded),
              title: const Text('后加签'),
              subtitle: const Text('当前节点处理后，由新增人员继续处理'),
              onTap: () => Navigator.pop(context, 'after'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

Future<String?> _showSecondaryActionsSheet(
  BuildContext context,
  List<String> actions,
) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Text(
              '更多操作',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final action in actions)
                SizedBox(
                  width: 64,
                  child: _SecondaryActionItem(
                    action: action,
                    onTap: () => Navigator.pop(context, action),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  ),
);

class _SecondaryActionItem extends StatelessWidget {
  const _SecondaryActionItem({required this.action, required this.onTap});

  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (action) {
      'withdraw' => AppColors.error,
      'return' => AppColors.warning,
      _ => AppColors.primary,
    };
    return Semantics(
      button: true,
      label: _actionLabel(action),
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_actionIcon(action), size: 20, color: color),
                ),
                const SizedBox(height: 5),
                Text(
                  _actionLabel(action),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

List<_FieldValue> _formRows(OaApprovalRequest request) {
  final data = _jsonObject(request.formDataJson);
  final schema = _jsonObject(request.formSchemaSnapshotJson);
  final fields = schema['fields'];
  final rows = <_FieldValue>[];
  if (fields is List) {
    for (final raw in fields.whereType<Map>()) {
      final field = raw.cast<String, Object?>();
      final key = (field['id'] ?? field['key'] ?? field['name'])
          ?.toString()
          .trim();
      if (key == null || key.isEmpty || !data.containsKey(key)) continue;
      final type = field['type']?.toString().toLowerCase();
      if (type == 'attachment' || type == 'file') continue;
      final label = (field['label'] ?? field['title'] ?? key).toString();
      rows.add(
        _FieldValue(label, _displayValue(data['${key}__display'] ?? data[key])),
      );
    }
  }
  if (rows.isNotEmpty) return rows;
  return data.entries
      .where(
        (entry) =>
            !entry.key.endsWith('__display') &&
            !entry.key.startsWith('_') &&
            !_isAttachmentValue(entry.value),
      )
      .map(
        (entry) => _FieldValue(
          entry.key,
          _displayValue(data['${entry.key}__display'] ?? entry.value),
        ),
      )
      .toList();
}

bool _isAttachmentValue(Object? value) {
  final items = value is List ? value : [value];
  return items.isNotEmpty &&
      items.every(
        (item) =>
            item is Map &&
            item['id'] != null &&
            item['fileName'] != null &&
            item['contentType'] != null,
      );
}

Map<String, Object?> _jsonObject(String source) {
  if (source.trim().isEmpty) return const {};
  try {
    final value = jsonDecode(source);
    return value is Map ? value.cast<String, Object?>() : const {};
  } on FormatException {
    return const {};
  }
}

bool _canResubmit(
  OaApprovalRequest request, {
  required String currentMemberId,
}) {
  final terminal = switch (request.status.toLowerCase()) {
    'rejected' ||
    'withdrawn' ||
    'terminated' ||
    'canceled' ||
    'cancelled' => true,
    _ => false,
  };
  return terminal &&
      currentMemberId.isNotEmpty &&
      request.requesterId == currentMemberId;
}

({String applicationKey, String templateId})? _resolveResubmitTarget(
  OaApprovalRequest request,
  OaBootstrap? bootstrap,
  OaApplicationCatalog? catalog,
) {
  if (bootstrap == null || request.applicationKey.isEmpty) return null;
  final catalogItem = catalog?.items
      .where((item) => item.applicationKey == request.applicationKey)
      .firstOrNull;
  final configuredTemplateId = catalogItem?.approvalTemplateId?.trim() ?? '';
  if (configuredTemplateId.isNotEmpty &&
      bootstrap.templates.any((item) => item.id == configuredTemplateId)) {
    return (
      applicationKey: request.applicationKey,
      templateId: configuredTemplateId,
    );
  }
  final matchingTemplate = bootstrap.templates
      .where(
        (item) =>
            item.name == request.templateName &&
            (request.templateCategory.isEmpty ||
                item.category == request.templateCategory),
      )
      .firstOrNull;
  if (matchingTemplate == null) return null;
  return (
    applicationKey: request.applicationKey,
    templateId: matchingTemplate.id,
  );
}

Map<String, Object?> _resubmissionData(OaApprovalRequest request) {
  final data = Map<String, Object?>.of(_jsonObject(request.formDataJson));
  final schema = _jsonObject(request.formSchemaSnapshotJson);
  final attachmentFields = <String>{};
  final fields = schema['fields'];
  if (fields is List) {
    for (final raw in fields.whereType<Map>()) {
      final field = raw.cast<String, Object?>();
      final type = field['type']?.toString().toLowerCase();
      if (type != 'attachment' && type != 'file') continue;
      final id = (field['id'] ?? field['key'] ?? field['name'])
          ?.toString()
          .trim();
      if (id != null && id.isNotEmpty) attachmentFields.add(id);
    }
  }
  data.removeWhere((key, value) {
    if (key.startsWith('_') || _isAttachmentValue(value)) return true;
    return attachmentFields.any(
      (fieldId) => key == fieldId || key == '${fieldId}__display',
    );
  });
  return data;
}

ButtonStyle _compactApprovalButtonStyle() => const ButtonStyle(
  minimumSize: WidgetStatePropertyAll(Size.fromHeight(42)),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 14)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

String _requestNumber(OaApprovalRequest request) {
  final createdAt = request.createdAt;
  final day = createdAt == null
      ? '00000000'
      : DateFormat('yyyyMMdd').format(createdAt);
  final compactId = request.id.replaceAll('-', '').toUpperCase();
  final suffix = compactId.length <= 6 ? compactId : compactId.substring(0, 6);
  return 'OA-$day-$suffix';
}

String _displayValue(Object? value) {
  if (value == null) return '-';
  if (value is bool) return value ? '是' : '否';
  if (value is List) return value.map(_displayValue).join('、');
  if (value is Map) return value.values.map(_displayValue).join('、');
  final text = value.toString().trim();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}').hasMatch(text)) {
    final dateTime = DateTime.tryParse(text);
    if (dateTime != null) {
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime.toLocal());
    }
  }
  return text;
}

({String label, Color color}) _statusPresentation(String status) =>
    switch (status.toLowerCase()) {
      'approved' || 'completed' => (label: '已通过', color: AppColors.success),
      'rejected' => (label: '已驳回', color: AppColors.error),
      'withdrawn' => (label: '已撤回', color: AppColors.secondaryText),
      'terminated' ||
      'canceled' ||
      'cancelled' => (label: '已终止', color: AppColors.secondaryText),
      _ => (label: '审批中', color: AppColors.primary),
    };

String _taskStatusLabel(OaApprovalTask task) =>
    switch (task.status.toLowerCase()) {
      'approved' => '已同意',
      'rejected' => '已驳回',
      'completed' => '已完成',
      'canceled' || 'cancelled' => '已取消',
      'transferred' => '已转交',
      'returned' => '已退回',
      'waiting' => '等待中',
      _ when task.decision == 'auto_approved' => '自动同意',
      _ when task.decision == 'skipped' => '已跳过',
      _ => task.canOperate ? '待你处理' : '待处理',
    };

List<String> _approvalTaskActorDetails(OaApprovalTask task, ImMember? member) {
  final name = member?.displayName.trim().isNotEmpty == true
      ? member!.displayName.trim()
      : task.assigneeName.trim();
  return <String>[
    if (name.isNotEmpty) name,
    if (member?.username.trim().isNotEmpty == true) member!.username.trim(),
    if (member?.departmentName.trim().isNotEmpty == true)
      member!.departmentName.trim(),
  ];
}

String _timeoutActionLabel(String action) => switch (action.toLowerCase()) {
  'remind' => '催办',
  'transfer_to_manager' => '转交负责人',
  'transfer_to_role' => '转交岗位',
  'auto_reject' => '自动驳回',
  _ => action,
};

String approvalReviewSuccessMessage({
  required bool approved,
  required String requestStatus,
}) {
  if (!approved) return '审批已驳回';
  final terminal = switch (requestStatus.toLowerCase()) {
    'approved' || 'completed' => true,
    _ => false,
  };
  return terminal ? '审批已通过' : '当前节点已同意，审批继续流转';
}

String _actionLabel(String action) => switch (action.toLowerCase()) {
  'transfer' => '转交',
  'add_sign' => '加签',
  'return' => '退回',
  'remind' => '催办',
  'withdraw' => '撤回',
  'submitted' => '提交申请',
  'approved' => '同意',
  'rejected' => '驳回',
  'transferred' => '转交',
  'returned' => '退回',
  'withdrawn' => '撤回',
  'reminded' => '催办',
  _ => action,
};

IconData _actionIcon(String action) => switch (action) {
  'transfer' => Icons.forward_to_inbox_outlined,
  'add_sign' => Icons.person_add_alt_rounded,
  'return' => Icons.keyboard_return_rounded,
  'remind' => Icons.notifications_active_outlined,
  'withdraw' => Icons.undo_rounded,
  _ => Icons.more_horiz_rounded,
};

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      for (final key in const ['message', 'detail', 'title', 'error']) {
        final value = data[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) return value;
      }
    }
    final message = error.message?.trim() ?? '';
    if (message.isNotEmpty) return message;
  }
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  return message.isEmpty ? '操作失败，请稍后重试' : message;
}

final class _ReviewDraft {
  const _ReviewDraft(this.comment);

  final String comment;
}

final class _FieldValue {
  const _FieldValue(this.label, this.value);

  final String label;
  final String value;
}
