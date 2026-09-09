import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/application/oa_catalog_sync_coordinator.dart';
import '../../collaboration/domain/collaboration_models.dart';
import '../../auth/application/auth_controller.dart';
import 'approval_request_page.dart';

class ApprovalDetailPage extends ConsumerStatefulWidget {
  const ApprovalDetailPage({super.key, required this.approvalId});

  final String approvalId;

  @override
  ConsumerState<ApprovalDetailPage> createState() => _ApprovalDetailPageState();
}

final approvalDetailAutoRefreshProvider = Provider<bool>((ref) => true);
final approvalAttachmentTempDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) => getTemporaryDirectory);
final approvalAttachmentExternalOpenerProvider =
    Provider<Future<OpenResult> Function(String)>(
      (ref) =>
          (file) => OpenFilex.open(file),
    );

class _ApprovalDetailPageState extends ConsumerState<ApprovalDetailPage>
    with WidgetsBindingObserver {
  bool _submitting = false;
  bool _openingAttachment = false;
  String? _openingAttachmentId;
  double? _attachmentDownloadProgress;
  int _attachmentDownloadReceived = 0;
  CancelToken? _attachmentDownload;
  bool _interacting = false;
  bool _ccReadAttempted = false;
  bool _autoRefreshScheduled = false;
  Future<void>? _detailRefresh;
  Timer? _reconcileTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_cleanupStaleAttachmentHandoffs());
    _scheduleReconcile();
  }

  Future<void> _cleanupStaleAttachmentHandoffs() async {
    try {
      await cleanupStaleApprovalAttachmentHandoffs(
        await ref.read(approvalAttachmentTempDirectoryProvider)(),
      );
    } catch (_) {
      // Cache maintenance must never block approval details.
    }
  }

  @override
  void dispose() {
    _attachmentDownload?.cancel('approval-detail-closed');
    _reconcileTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileVisibleDetail();
    } else {
      _reconcileTimer?.cancel();
    }
  }

  void _scheduleReconcile() {
    _reconcileTimer?.cancel();
    if (!mounted || !ref.read(approvalDetailAutoRefreshProvider)) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _reconcileTimer = Timer(
      const Duration(seconds: 30),
      _reconcileVisibleDetail,
    );
  }

  void _reconcileVisibleDetail() {
    if (!mounted || !ref.read(approvalDetailAutoRefreshProvider)) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final request = ref
        .read(oaApprovalRequestProvider(widget.approvalId))
        .value;
    if (request != null &&
        const {
          'approved',
          'completed',
          'rejected',
          'withdrawn',
          'terminated',
          'canceled',
          'cancelled',
        }.contains(request.status.toLowerCase())) {
      return;
    }
    if (_submitting || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      _scheduleReconcile();
      return;
    }
    // Some deployments do not fan out later workflow events to an already
    // processed approver. Reconcile only this visible unfinished request, not
    // every list row. Event-driven refreshes reset the interval below.
    _refreshDetail(showFailure: false, background: true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(oaApprovalRevisionProvider(widget.approvalId), (before, after) {
      if (before == after) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshDetail(showFailure: false);
      });
    });
    final value = ref.watch(oaApprovalRequestProvider(widget.approvalId));
    final syncAvailability = ref.watch(oaSyncAvailabilityProvider);
    final autoRefresh = ref.watch(approvalDetailAutoRefreshProvider);
    if (autoRefresh &&
        syncAvailability == OaSyncAvailability.available &&
        !_autoRefreshScheduled) {
      _autoRefreshScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshDetail(showFailure: false);
      });
    }
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
      data: (request) => _buildDetail(request, syncAvailability),
    );
  }

  Widget _buildDetail(
    OaApprovalRequest request,
    OaSyncAvailability syncAvailability,
  ) {
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
    final taskGroups = _approvalTaskGroups(request.tasks);
    final actionsAvailable = syncAvailability == OaSyncAvailability.available;
    final canApprove =
        actionsAvailable &&
        task != null &&
        request.allowedActions.contains('approve');
    final canReject =
        actionsAvailable &&
        task != null &&
        request.allowedActions.contains('reject');
    final secondaryActions = <String>[
      if (actionsAvailable)
        for (final action in const [
          'transfer',
          'add_sign',
          'return',
          'remind',
          'withdraw',
        ])
          if (request.allowedActions.contains(action)) action,
    ];
    final canResubmit =
        actionsAvailable &&
        _canResubmit(
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
        onRefresh: () => _refreshDetail(showFailure: true),
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
            if (syncAvailability != OaSyncAvailability.available) ...[
              _ApprovalDetailSyncStrip(
                availability: syncAvailability,
                onRetry: () => _refreshDetail(showFailure: true),
              ),
              const SizedBox(height: 8),
            ],
            MobileSurface(
              key: const Key('approval-request-content'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('申请内容'),
                  const SizedBox(height: 5),
                  _DetailFields(_formRows(request)),
                  if (request.attachments.isNotEmpty) ...[
                    const SizedBox(height: 9),
                    const _SectionTitle('附件'),
                    const SizedBox(height: 4),
                    ...request.attachments.map(
                      (attachment) => _AttachmentRow(
                        attachment,
                        onTap: () => _openAttachment(attachment),
                        downloading: _openingAttachmentId == attachment.id,
                        progress: _openingAttachmentId == attachment.id
                            ? _attachmentDownloadProgress
                            : null,
                        receivedBytes: _openingAttachmentId == attachment.id
                            ? _attachmentDownloadReceived
                            : 0,
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
                  ...taskGroups.indexed.map(
                    (entry) => _TimelineTaskGroup(
                      group: entry.$2,
                      membersById: membersById,
                      last: entry.$1 == taskGroups.length - 1,
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
                child: Align(
                  alignment: Alignment.centerRight,
                  heightFactor: 1,
                  child: SizedBox(
                    width: 112,
                    child: FilledButton.icon(
                      key: const Key('approval-resubmit'),
                      onPressed: () => _startAgain(request, resubmitTarget),
                      style: _compactApprovalButtonStyle(),
                      icon: const Icon(Icons.replay_rounded, size: 16),
                      label: const Text('再次发起'),
                    ),
                  ),
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
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (secondaryActions.isNotEmpty) ...[
                      Tooltip(
                        message: '更多操作',
                        child: OutlinedButton.icon(
                          key: const Key('approval-more-actions'),
                          onPressed: _submitting || _interacting
                              ? null
                              : () => _chooseSecondaryAction(
                                  request,
                                  task,
                                  secondaryActions,
                                  members,
                                ),
                          style: _compactApprovalButtonStyle().copyWith(
                            minimumSize: const WidgetStatePropertyAll(
                              Size(80, 34),
                            ),
                          ),
                          icon: const Icon(Icons.more_horiz_rounded, size: 16),
                          label: const Text('更多'),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (canReject)
                      SizedBox(
                        width: 88,
                        child: OutlinedButton.icon(
                          onPressed: _submitting || _interacting
                              ? null
                              : () => _review(request, task, false),
                          style: _compactApprovalButtonStyle(),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('驳回'),
                        ),
                      ),
                    if (canReject && canApprove) const SizedBox(width: 8),
                    if (canApprove)
                      SizedBox(
                        width: 88,
                        child: FilledButton.icon(
                          onPressed: _submitting || _interacting
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
                              : const Icon(Icons.check_rounded, size: 16),
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

  Future<void> _refreshDetail({
    required bool showFailure,
    bool background = false,
  }) {
    return _detailRefresh ??=
        _refreshUntilCurrent(
          showFailure: showFailure,
          background: background,
        ).whenComplete(() {
          _detailRefresh = null;
          _scheduleReconcile();
        });
  }

  Future<void> _refreshUntilCurrent({
    required bool showFailure,
    required bool background,
  }) async {
    _autoRefreshScheduled = true;
    final account = ref.read(collaborationAccountScopeProvider);
    final controller = ref.read(oaSyncAvailabilityControllerProvider.notifier);
    // A routine consistency check must not flash a loading strip or disable
    // the current controls. A real failure still marks the snapshot stale.
    if (!background) controller.markConnecting();
    try {
      // Keep the existing content visible. If another event arrives during the
      // request, follow up once for the newest revision, never in parallel.
      while (mounted) {
        final revision = ref.read(
          oaApprovalRevisionProvider(widget.approvalId),
        );
        await ref.read(oaApprovalRequestRefresherProvider)(widget.approvalId);
        if (!mounted ||
            ref.read(collaborationAccountScopeProvider) != account) {
          return;
        }
        ref.invalidate(oaApprovalRequestProvider(widget.approvalId));
        if (revision ==
            ref.read(oaApprovalRevisionProvider(widget.approvalId))) {
          break;
        }
      }
      if (!mounted) return;
      controller.markAvailable();
    } on SessionChangedException {
      // A renewed login may be the same account; the old attempt must not
      // overwrite availability established by the new runtime.
      return;
    } catch (error) {
      if (!mounted || ref.read(collaborationAccountScopeProvider) != account) {
        return;
      }
      _autoRefreshScheduled = false;
      controller.markUnavailable();
      if (!mounted || !showFailure) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(mobileErrorText(error, fallback: '暂时无法同步审批详情')),
          ),
        );
    }
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
        ref.read(oaCatalogSyncCoordinatorProvider).catchUpAfterMutation();
        ref.invalidate(oaApprovalRequestProvider(widget.approvalId));
        ref.invalidate(oaBootstrapProvider);
        ref.invalidate(oaNotificationsProvider);
        ref.invalidate(oaNotificationPageProvider);
      } on SessionChangedException {
        return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('抄送已读状态将在联网后同步')));
      }
    });
  }

  Future<void> _openAttachment(OaApprovalAttachment attachment) async {
    if (_openingAttachment) return;
    final session = ref.read(authControllerProvider).value;
    if (session == null) return;
    final temporaryDirectory = ref.read(
      approvalAttachmentTempDirectoryProvider,
    );
    final openExternal = ref.read(approvalAttachmentExternalOpenerProvider);
    final cancel = _attachmentDownload = CancelToken();
    setState(() {
      _openingAttachment = true;
      _openingAttachmentId = attachment.id;
      _attachmentDownloadProgress = null;
      _attachmentDownloadReceived = 0;
    });
    Directory? downloadedDirectory;
    Directory? cacheDirectory;
    var downloadedThisAttempt = false;
    var handedOff = false;
    bool canOpen() =>
        !cancel.isCancelled &&
        _sameActionSession(session) &&
        ModalRoute.of(context)?.isCurrent == true;
    void reportProgress(int received, int total) {
      if (!mounted || !canOpen()) return;
      final next = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
      final previous = _attachmentDownloadProgress;
      final advancedEnough = next != null
          ? previous == null || next == 1 || next - previous >= 0.01
          : received == 0 ||
                received - _attachmentDownloadReceived >= 256 * 1024;
      if (!advancedEnough) return;
      setState(() {
        _attachmentDownloadProgress = next;
        _attachmentDownloadReceived = received;
      });
    }

    try {
      if (attachment.isPreviewableImage) {
        final bytes = await ref
            .read(oaRepositoryProvider)
            .downloadAttachmentPreview(
              attachment.id,
              expectedSession: session,
              cancelToken: cancel,
              onReceiveProgress: reportProgress,
            );
        if (!mounted || !canOpen()) return;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (context) => Consumer(
              builder: (context, ref, _) {
                final current = ref.watch(authControllerProvider).value;
                if (current?.isSameSession(session) != true) {
                  return Scaffold(
                    appBar: AppBar(title: const Text('附件预览')),
                    body: const Center(child: Text('登录状态已变化，请重新打开附件')),
                  );
                }
                return Scaffold(
                  backgroundColor: Colors.black,
                  body: SafeArea(
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
                );
              },
            ),
          ),
        );
        return;
      }
      if (!_isSupportedExternalAttachment(attachment.fileName)) {
        if (mounted && canOpen()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('暂不支持在移动端打开此格式，请在桌面端查看')),
          );
        }
        return;
      }
      final directory = await temporaryDirectory();
      if (!mounted || !canOpen()) return;
      final scope = sha256
          .convert(utf8.encode('${session.oaApiUrl}\n${session.userId}'))
          .toString();
      final accountDirectory = await Directory(
        path.join(directory.path, 'oa-attachments', scope),
      ).create(recursive: true);
      if (!mounted || !canOpen()) return;
      final safeName = path.basename(attachment.fileName);
      final cacheKey = sha256
          .convert(
            utf8.encode(
              '${attachment.id}\n$safeName\n${attachment.size}\n${attachment.sha256.trim().toLowerCase()}',
            ),
          )
          .toString();
      cacheDirectory = Directory(
        path.join(accountDirectory.path, 'cache-$cacheKey'),
      );
      var target = File(path.join(cacheDirectory.path, safeName));
      if (!await _isCompleteApprovalAttachment(
        target,
        attachment.size,
        attachment.sha256,
      )) {
        if (await cacheDirectory.exists()) {
          await cacheDirectory.delete(recursive: true);
        }
        downloadedDirectory = await accountDirectory.createTemp('download-');
        final partial = File(path.join(downloadedDirectory.path, safeName));
        await ref
            .read(oaRepositoryProvider)
            .downloadAttachmentToFile(
              attachment.id,
              partial.path,
              expectedSession: session,
              cancelToken: cancel,
              onReceiveProgress: reportProgress,
            );
        if (!mounted || !canOpen()) return;
        if (!await _isCompleteApprovalAttachment(
          partial,
          attachment.size,
          attachment.sha256,
        )) {
          throw const FileSystemException('附件完整性校验失败');
        }
        await cacheDirectory.create(recursive: true);
        target = await partial.rename(path.join(cacheDirectory.path, safeName));
        downloadedThisAttempt = true;
        try {
          await downloadedDirectory.delete(recursive: true);
          downloadedDirectory = null;
        } catch (_) {}
      }
      if (!mounted || !canOpen()) return;
      final result = await openExternal(target.path);
      handedOff = result.type == ResultType.done;
      if (result.type != ResultType.done && mounted && canOpen()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_externalAttachmentOpenFailure(result.type))),
        );
      }
    } on SessionChangedException {
      return;
    } catch (error) {
      if (mounted && canOpen()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mobileErrorText(error, fallback: '附件打开失败，请稍后重试')),
          ),
        );
      }
    } finally {
      _openingAttachment = false;
      if (identical(_attachmentDownload, cancel)) _attachmentDownload = null;
      if (mounted && _openingAttachmentId == attachment.id) {
        setState(() {
          _openingAttachmentId = null;
          _attachmentDownloadProgress = null;
          _attachmentDownloadReceived = 0;
        });
      }
      // Incomplete transfers never become cache entries. A freshly downloaded
      // file is also discarded if Android could not hand it to a viewer.
      if (downloadedDirectory != null) {
        try {
          await downloadedDirectory.delete(recursive: true);
        } catch (_) {}
      }
      if (!handedOff && downloadedThisAttempt && cacheDirectory != null) {
        try {
          await cacheDirectory.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  bool _sameActionSession(MobileSession? expected) {
    if (!mounted) return false;
    final current = ref.read(authControllerProvider).value;
    return expected == null
        ? current == null
        : current?.isSameSession(expected) == true;
  }

  bool _canContinueAction(
    MobileSession? expected,
    OaApprovalRequest original,
    OaApprovalTask? task,
    String action, {
    bool sending = false,
  }) {
    if (!mounted) return false;
    String? notice;
    if (!_sameActionSession(expected) ||
        (sending && expected == null && !AppEnvironment.demoMode)) {
      notice = '登录状态已更新，请重新打开审批';
    } else if (ref.read(oaSyncAvailabilityProvider) !=
        OaSyncAvailability.available) {
      notice = '当前连接不可用，请联网后重新操作';
    } else {
      final latest = ref.read(oaApprovalRequestProvider(original.id)).value;
      final sameTask =
          task == null ||
          latest?.tasks.any(
                (candidate) =>
                    candidate.id == task.id &&
                    candidate.version == task.version &&
                    candidate.assigneeId == task.assigneeId &&
                    candidate.canOperate,
              ) ==
              true;
      if (latest == null ||
          latest.id != original.id ||
          latest.requesterId != original.requesterId ||
          !latest.allowedActions.contains(action) ||
          !sameTask) {
        notice = '审批状态已更新，请重新确认';
      }
    }
    if (notice == null) return true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(notice)));
    return false;
  }

  Future<void> _chooseSecondaryAction(
    OaApprovalRequest request,
    OaApprovalTask? task,
    List<String> actions,
    List<ImMember> members,
  ) async {
    if (_interacting || _submitting) return;
    final session = ref.read(authControllerProvider).value;
    setState(() => _interacting = true);
    try {
      final action = await _showSecondaryActionsSheet(context, actions);
      if (action == null ||
          !mounted ||
          !_canContinueAction(
            session,
            request,
            const {'transfer', 'add_sign', 'return'}.contains(action)
                ? task
                : null,
            action,
          )) {
        return;
      }
      await _runSecondaryAction(request, task, action, members, session);
    } finally {
      if (mounted) setState(() => _interacting = false);
    }
  }

  Future<void> _runSecondaryAction(
    OaApprovalRequest request,
    OaApprovalTask? task,
    String action,
    List<ImMember> members,
    MobileSession? expectedSession,
  ) async {
    Future<OaApprovalRequest> Function()? operation;
    bool canContinue({bool sending = false}) => _canContinueAction(
      expectedSession,
      request,
      const {'transfer', 'add_sign', 'return'}.contains(action) ? task : null,
      action,
      sending: sending,
    );
    if (action == 'transfer' || action == 'add_sign') {
      if (task == null) return;
      final member = await _showMemberPicker(
        context,
        action == 'transfer' ? '选择转交人' : '选择加签人',
        members.where((item) => item.id != task.assigneeId).toList(),
      );
      if (member == null || !mounted || !canContinue()) return;
      if (action == 'transfer') {
        final reason = await _showReasonSheet(context, title: '转交原因');
        if (reason == null) return;
        operation = () => ref
            .read(oaRepositoryProvider)
            .transferApproval(
              requestId: request.id,
              task: task,
              newAssigneeId: member.id,
              reason: reason,
              expectedSession: expectedSession,
            );
      } else {
        final mode = await _showAddSignMode(context);
        if (mode == null || !mounted || !canContinue()) return;
        final comment = await _showReasonSheet(
          context,
          title: '加签说明',
          required: false,
        );
        if (comment == null) return;
        operation = () => ref
            .read(oaRepositoryProvider)
            .addSignApproval(
              requestId: request.id,
              task: task,
              addedAssigneeId: member.id,
              mode: mode,
              comment: comment,
              expectedSession: expectedSession,
            );
      }
    } else if (action == 'return') {
      if (task == null) return;
      final reason = await _showReasonSheet(context, title: '退回原因');
      if (reason == null) return;
      operation = () => ref
          .read(oaRepositoryProvider)
          .returnApproval(
            requestId: request.id,
            task: task,
            reason: reason,
            expectedSession: expectedSession,
          );
    } else if (action == 'withdraw') {
      final reason = await _showReasonSheet(context, title: '撤回原因');
      if (reason == null) return;
      operation = () => ref
          .read(oaRepositoryProvider)
          .withdrawApproval(
            requestId: request.id,
            reason: reason,
            expectedSession: expectedSession,
          );
    } else if (action == 'remind') {
      final comment = await _showReasonSheet(
        context,
        title: '催办留言',
        required: false,
      );
      if (comment == null) return;
      operation = () => ref
          .read(oaRepositoryProvider)
          .remindApproval(
            requestId: request.id,
            comment: comment,
            expectedSession: expectedSession,
          );
    }
    if (operation == null || !canContinue(sending: true)) return;
    setState(() => _submitting = true);
    try {
      await operation();
      if (!_sameActionSession(expectedSession)) return;
      _invalidateRequest(request.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${_actionLabel(action)}成功')));
      }
    } on SessionChangedException {
      return;
    } catch (error) {
      if (mounted && _sameActionSession(expectedSession)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _invalidateRequest(String requestId) {
    ref.read(oaCatalogSyncCoordinatorProvider).catchUpAfterMutation();
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
    if (_interacting || _submitting) return;
    final session = ref.read(authControllerProvider).value;
    setState(() => _interacting = true);
    try {
      final draft = await _showReviewSheet(context, approve);
      if (draft == null ||
          !mounted ||
          !_canContinueAction(
            session,
            request,
            task,
            approve ? 'approve' : 'reject',
            sending: true,
          )) {
        return;
      }
      setState(() => _submitting = true);
      final updatedRequest = await ref
          .read(oaRepositoryProvider)
          .reviewApproval(
            requestId: request.id,
            taskId: task.id,
            expectedTaskVersion: task.version,
            decision: approve ? 'approved' : 'rejected',
            comment: draft.comment,
            expectedSession: session,
          );
      if (!_sameActionSession(session)) return;
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
    } on SessionChangedException {
      return;
    } catch (error) {
      if (mounted && _sameActionSession(session)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_errorMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _interacting = false;
        });
      }
    }
  }
}

Future<void> cleanupStaleApprovalAttachmentHandoffs(
  Directory temporaryRoot, {
  DateTime? now,
  Duration maxAge = const Duration(hours: 24),
}) async {
  final root = Directory(path.join(temporaryRoot.path, 'oa-attachments'));
  if (!await root.exists()) return;
  final cutoff = (now ?? DateTime.now()).subtract(maxAge);
  await for (final account in root.list(followLinks: false)) {
    if (account is! Directory) continue;
    await for (final candidate in account.list(followLinks: false)) {
      final name = path.basename(candidate.path);
      if (candidate is! Directory ||
          !(name.startsWith('open-') ||
              name.startsWith('cache-') ||
              name.startsWith('download-'))) {
        continue;
      }
      try {
        if ((await _latestModified(candidate)).isBefore(cutoff)) {
          await candidate.delete(recursive: true);
        }
      } catch (_) {
        // The external viewer may still own the file. Retry on a later visit.
      }
    }
    try {
      if (await account.list(followLinks: false).isEmpty) {
        await account.delete();
      }
    } catch (_) {}
  }
  try {
    if (await root.list(followLinks: false).isEmpty) await root.delete();
  } catch (_) {}
}

Future<bool> _isCompleteApprovalAttachment(
  File file,
  int expectedSize,
  String expectedSha256,
) async {
  try {
    if (!await file.exists()) return false;
    final actualSize = await file.length();
    if (actualSize <= 0) return false;
    if (expectedSize > 0 && actualSize != expectedSize) return false;
    final normalizedDigest = expectedSha256.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedDigest)) return true;
    final actualDigest = await sha256.bind(file.openRead()).first;
    return actualDigest.toString() == normalizedDigest;
  } catch (_) {
    return false;
  }
}

Future<DateTime> _latestModified(Directory directory) async {
  DateTime? latest;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    final modified = (await entity.stat()).modified;
    if (latest == null || modified.isAfter(latest)) latest = modified;
  }
  return latest ?? (await directory.stat()).modified;
}

class _ApprovalDetailSyncStrip extends StatelessWidget {
  const _ApprovalDetailSyncStrip({
    required this.availability,
    required this.onRetry,
  });

  final OaSyncAvailability availability;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final connecting = availability == OaSyncAvailability.connecting;
    return Container(
      key: const Key('approval-detail-sync-strip'),
      height: 36,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            connecting ? Icons.sync_rounded : Icons.cloud_off_outlined,
            size: 17,
            color: AppColors.secondaryText,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              connecting ? '正在核对最新审批状态' : '当前显示本机审批快照',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
              ),
            ),
          ),
          if (!connecting)
            TextButton(
              key: const Key('approval-detail-sync-retry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: const Size(76, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('重新同步'),
            ),
        ],
      ),
    );
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
          avatarKey: member?.avatarKey ?? '',
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

class _DetailFields extends StatelessWidget {
  const _DetailFields(this.fields);

  final List<_FieldValue> fields;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style
          .merge(const TextStyle(fontSize: 13, color: AppColors.secondaryText));
      final labelLimit = (constraints.maxWidth * .4).clamp(84.0, 144.0);
      final widths = <double>[];
      var columnWidth = 84.0;
      for (final field in fields) {
        final painter = TextPainter(
          text: TextSpan(text: field.label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width.ceilToDouble();
        painter.dispose();
        widths.add(width);
        if (width + 12 <= labelLimit && width + 12 > columnWidth) {
          columnWidth = width + 12;
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < fields.length; i++)
            _DetailRow(
              fields[i].label,
              fields[i].value,
              multiline: fields[i].multiline,
              labelWidth: columnWidth,
              stackLabel: widths[i] + 12 > labelLimit,
            ),
        ],
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(
    this.label,
    this.value, {
    required this.labelWidth,
    required this.stackLabel,
    required this.multiline,
  });

  final String label;
  final String value;
  final double labelWidth;
  final bool stackLabel;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    final displayValue = value.isEmpty ? '-' : value;
    final isContinuousLongValue =
        !multiline &&
        displayValue.length >= 28 &&
        !RegExp(r'\s').hasMatch(displayValue);
    final valueText = Text(
      displayValue,
      key: ValueKey<String>('approval-detail-value-$label'),
      maxLines: isContinuousLongValue ? 1 : null,
      softWrap: !isContinuousLongValue,
      overflow: isContinuousLongValue ? TextOverflow.ellipsis : null,
      style: TextStyle(fontSize: isContinuousLongValue ? 13 : 14),
    );
    final labelText = Text(
      label,
      style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
    );
    final content = isContinuousLongValue && displayValue.length <= 48
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: valueText,
          )
        : valueText;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: stackLabel
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 4), content],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: labelText,
                  ),
                ),
                Expanded(child: content),
              ],
            ),
    );
  }
}

class _AttachmentRow extends ConsumerWidget {
  const _AttachmentRow(
    this.attachment, {
    required this.onTap,
    required this.downloading,
    this.progress,
    this.receivedBytes = 0,
  });

  final OaApprovalAttachment attachment;
  final VoidCallback onTap;
  final bool downloading;
  final double? progress;
  final int receivedBytes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requiresDesktop =
        !attachment.isPreviewableImage &&
        !_isSupportedExternalAttachment(attachment.fileName);
    final idleActionLabel = attachment.isPreviewableImage
        ? '点击预览'
        : requiresDesktop
        ? '请在桌面端查看'
        : '点击打开';
    return InkWell(
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
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.cover,
                              cacheWidth:
                                  (32 * MediaQuery.devicePixelRatioOf(context))
                                      .round()
                                      .clamp(32, 192),
                            ),
                          ),
                          loading: () => const Center(
                            child: SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                              ),
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
                    downloading
                        ? '${_fileSize(attachment.size)} · ${_downloadLabel(progress, receivedBytes)}'
                        : '${_fileSize(attachment.size)} · $idleActionLabel',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            if (downloading)
              SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(
                  key: ValueKey(
                    'oa-attachment-download-progress-${attachment.id}',
                  ),
                  value: progress,
                  strokeWidth: 2,
                ),
              )
            else if (requiresDesktop)
              const Icon(
                Icons.desktop_windows_outlined,
                size: 18,
                color: AppColors.secondaryText,
              )
            else
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
}

String _downloadLabel(double? progress, int receivedBytes) {
  if (progress != null) return '下载 ${(progress * 100).round()}%';
  if (receivedBytes > 0) return '已下载 ${_fileSize(receivedBytes)}';
  return '正在下载';
}

String _externalAttachmentOpenFailure(ResultType type) => switch (type) {
  ResultType.fileNotFound => '附件文件不存在，请重新下载',
  ResultType.noAppToOpen => '未找到可打开此格式的应用',
  ResultType.permissionDenied => '没有权限打开附件，请在系统设置中允许文件访问',
  ResultType.error => '附件打开失败，请稍后重试',
  ResultType.done => '',
};

bool _isSupportedExternalAttachment(String fileName) {
  final extension = path.extension(fileName).toLowerCase();
  return const {
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.csv',
    '.ppt',
    '.pptx',
    '.txt',
    '.md',
    '.json',
    '.xml',
    '.zip',
    '.rar',
    '.7z',
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.flac',
    '.mp4',
    '.mov',
    '.mkv',
    '.webm',
    '.avi',
  }.contains(extension);
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
          avatarKey: member?.avatarKey ?? '',
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
    final color = _approvalTaskStatusColor(task);
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
            avatarKey: member?.avatarKey ?? '',
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

final class _ApprovalTaskGroup {
  const _ApprovalTaskGroup(this.tasks);

  final List<OaApprovalTask> tasks;

  OaApprovalTask get first => tasks.first;
}

List<_ApprovalTaskGroup> _approvalTaskGroups(List<OaApprovalTask> tasks) {
  final groups = <_ApprovalTaskGroup>[];
  for (final task in tasks) {
    final nodeId = task.nodeId.trim();
    final previous = groups.isEmpty ? null : groups.last;
    final sameRuntimeNode =
        nodeId.isNotEmpty &&
        previous != null &&
        previous.first.nodeId.trim() == nodeId &&
        previous.first.stage == task.stage;
    if (sameRuntimeNode) {
      groups[groups.length - 1] = _ApprovalTaskGroup(
        List.unmodifiable([...previous.tasks, task]),
      );
    } else {
      groups.add(_ApprovalTaskGroup(List.unmodifiable([task])));
    }
  }
  return List.unmodifiable(groups);
}

class _TimelineTaskGroup extends StatelessWidget {
  const _TimelineTaskGroup({
    required this.group,
    required this.membersById,
    required this.last,
  });

  final _ApprovalTaskGroup group;
  final Map<String, ImMember> membersById;
  final bool last;

  @override
  Widget build(BuildContext context) {
    if (group.tasks.length == 1) {
      final task = group.first;
      return _TimelineItem(
        task: task,
        member: membersById[task.assigneeId],
        last: last,
      );
    }
    final tasks = group.tasks;
    final active = tasks.any(
      (task) => task.canOperate || task.status.toLowerCase() == 'pending',
    );
    final rejected = tasks.any(
      (task) => task.status.toLowerCase() == 'rejected',
    );
    final completed = tasks.every((task) {
      final status = task.status.toLowerCase();
      return status == 'approved' ||
          status == 'completed' ||
          status == 'canceled' ||
          status == 'cancelled';
    });
    final color = rejected
        ? AppColors.error
        : completed
        ? AppColors.success
        : active
        ? AppColors.primary
        : AppColors.weakText;
    final completionLabel = _approvalCompletionModeLabel(
      tasks
          .map((task) => task.completionMode)
          .firstWhere((value) => value.trim().isNotEmpty, orElse: () => ''),
    );
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
                          group.first.nodeName.isEmpty
                              ? '审批节点'
                              : group.first.nodeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2FF),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          completionLabel,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ...tasks.map((task) {
                    final member = membersById[task.assigneeId];
                    final actorDetails = _approvalTaskActorDetails(
                      task,
                      member,
                    );
                    final taskColor = _approvalTaskStatusColor(task);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          InitialAvatar(
                            name: actorDetails.isEmpty
                                ? task.nodeName
                                : actorDetails.first,
                            radius: 14,
                            avatarKey: member?.avatarKey ?? '',
                            avatarDataUrl: member?.avatarDataUrl ?? '',
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              actorDetails.join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                key: ValueKey<String>(
                                  'approval-task-status-${task.id}',
                                ),
                                _taskStatusLabel(task),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: taskColor,
                                ),
                              ),
                              if (task.completedAt != null)
                                Text(
                                  key: ValueKey<String>(
                                    'approval-task-completed-at-${task.id}',
                                  ),
                                  DateFormat('MM-dd HH:mm')
                                      .format(task.completedAt!),
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _approvalCompletionModeLabel(String value) {
  return switch (value.trim().toLowerCase()) {
    'all' || 'all_approve' || 'countersign' => '会签',
    'any' || 'any_approve' || 'or_sign' => '或签',
    'sequential' || 'serial' => '依次审批',
    'single' => '单人审批',
    _ => '多人审批',
  };
}

Color _approvalTaskStatusColor(OaApprovalTask task) {
  final status = task.status.toLowerCase();
  if (status == 'rejected') return AppColors.error;
  if (status == 'approved' || status == 'completed') {
    return AppColors.success;
  }
  if (task.canOperate || status == 'pending') return AppColors.primary;
  return AppColors.weakText;
}

class _ActionRow extends StatelessWidget {
  const _ActionRow(this.action);

  final OaApprovalAction action;

  @override
  Widget build(BuildContext context) {
    final actorName = action.actorName.trim();
    final comment = action.comment.trim();
    final actionLabel = _actionLabel(action.action);
    final occurredAt = action.occurredAt;
    final compactSystemEvent = actorName.isEmpty && comment.isEmpty;

    if (compactSystemEvent) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const SizedBox(
              width: 46,
              child: Text(
                '系统',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Text(
                actionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
            if (occurredAt != null) ...[
              const SizedBox(width: 6),
              Text(
                DateFormat('MM-dd HH:mm').format(occurredAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  actorName.isEmpty ? '系统' : actorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (occurredAt != null)
                Text(
                  DateFormat('MM-dd HH:mm').format(occurredAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryText,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [actionLabel, if (comment.isNotEmpty) comment].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
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
  final comment = await showMobileTextInputSheet(
    context,
    title: approve ? '同意审批' : '驳回审批',
    label: approve ? '处理意见（选填）' : '驳回原因',
    hintText: approve ? '请输入处理意见' : '请输入驳回原因',
    minLines: 2,
    maxLines: 4,
    actionLabel: approve ? '确认同意' : '确认驳回',
    autofocus: !approve,
    allowEmpty: approve,
    validator: (value) => !approve && value.isEmpty ? '请填写驳回原因' : null,
  );
  return comment == null ? null : _ReviewDraft(comment);
}

Future<ImMember?> _showMemberPicker(
  BuildContext context,
  String title,
  List<ImMember> members,
) async {
  final searchController = MobileSearchTextController(searchLabel: '搜索姓名或部门');
  var query = '';
  final result = await showModalBottomSheet<ImMember>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
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
            ? 72.0
            : (filtered.length * 52.0).clamp(52.0, 286.0);
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              12 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              key: const Key('approval-member-picker'),
              height: 108 + listHeight,
              child: Column(
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
                          title,
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
                  MobileSearchField(
                    key: const Key('approval-member-search'),
                    controller: searchController,
                    autofocus: false,
                    hintText: '搜索姓名或部门',
                    onChanged: (value) =>
                        setSheetState(() => query = value.trim()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Text(
                                  query.isEmpty ? '暂无可选成员' : '未找到匹配成员',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.secondaryText,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final member = filtered[index];
                              return ListTile(
                                minTileHeight: 50,
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                                leading: InitialAvatar(
                                  name: member.displayName,
                                  radius: 17,
                                  avatarKey: member.avatarKey,
                                  avatarDataUrl: member.avatarDataUrl,
                                ),
                                title: Text(
                                  member.displayName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  member.departmentName,
                                  style: const TextStyle(fontSize: 11),
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
}) => showMobileTextInputSheet(
  context,
  title: title,
  label: required ? title : '$title（选填）',
  hintText: '请输入$title',
  maxLength: 500,
  minLines: 2,
  maxLines: 4,
  actionLabel: '确认',
  allowEmpty: !required,
  validator: (value) => required && value.isEmpty ? '请填写$title' : null,
);

Future<String?> _showAddSignMode(BuildContext context) =>
    showMobileChoiceSheet<String>(
      context,
      title: '选择加签方式',
      options: const [
        MobileSheetOption(
          value: 'before',
          label: '前加签',
          subtitle: '新增人员先处理，之后回到当前节点',
          icon: Icons.vertical_align_top_rounded,
        ),
        MobileSheetOption(
          value: 'after',
          label: '后加签',
          subtitle: '当前节点处理后，由新增人员继续处理',
          icon: Icons.vertical_align_bottom_rounded,
        ),
      ],
    );

Future<String?> _showSecondaryActionsSheet(
  BuildContext context,
  List<String> actions,
) {
  if (actions.length <= 2) {
    return showMobileChoiceSheet<String>(
      context,
      title: '更多操作',
      options: [
        for (final action in actions)
          MobileSheetOption(
            value: action,
            label: _actionLabel(action),
            icon: _actionIcon(action),
            destructive: action == 'withdraw',
          ),
      ],
    );
  }
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
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
}

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
      if (_isHiddenFormField(request, field, key)) continue;
      final type = field['type']?.toString().toLowerCase();
      if (type == 'attachment' || type == 'file') continue;
      final label = (field['label'] ?? field['title'] ?? key).toString();
      final rawValue = data[key];
      final configuredDisplayValue = data['${key}__display'];
      final value =
          configuredDisplayValue != null &&
              !_isSchemaConfigurationValue(configuredDisplayValue, field)
          ? configuredDisplayValue
          : rawValue;
      rows.add(
        _FieldValue(
          label,
          _isSchemaConfigurationValue(value, field)
              ? '-'
              : _displayValue(value),
          multiline:
              const {'textarea', 'multiline', 'richtext'}.contains(type) ||
              field['multiline'] == true ||
              (field['rows'] is num && (field['rows'] as num) > 1),
        ),
      );
    }
  }
  if (rows.isNotEmpty) return rows;
  return data.entries
      .where(
        (entry) =>
            !entry.key.endsWith('__display') &&
            !entry.key.startsWith('_') &&
            !_isAttachmentValue(entry.value) &&
            !_isSchemaConfigurationValue(entry.value, const {}),
      )
      .map(
        (entry) => _FieldValue(
          entry.key,
          _displayValue(data['${entry.key}__display'] ?? entry.value),
        ),
      )
      .toList();
}

bool _isHiddenFormField(
  OaApprovalRequest request,
  Map<String, Object?> field,
  String key,
) {
  if (field['hidden'] == true || field['visible'] == false) return true;
  final applicationKey = request.applicationKey.trim().toLowerCase();
  final normalizedKey = key
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toLowerCase();
  // Attendance correction stores the selected exception as an internal UUID.
  // The desktop submission flow hides this technical reference as well; the
  // user-facing correction time and reason remain in the request snapshot.
  return applicationKey == 'attendance.punch_correction' &&
      const {'exceptionid', 'attendanceexceptionid'}.contains(normalizedKey);
}

bool _isSchemaConfigurationValue(Object? value, Map<String, Object?> field) {
  if (value is Map) {
    final keys = value.keys
        .map((item) => item.toString().toLowerCase())
        .toSet();
    return keys.intersection(const {
      'mode',
      'readonly',
      'unit',
      'calculation',
      'formula',
      'durationunit',
      'durationstartfieldid',
      'durationendfieldid',
      'autocalculate',
    }).isNotEmpty;
  }
  if (value is! String) return false;
  final fieldIsDerived =
      field['readOnly'] == true ||
      field['readonly'] == true ||
      field['calculation'] is Map ||
      field['durationUnit']?.toString().trim().isNotEmpty == true;
  if (field.isNotEmpty && !fieldIsDerived) return false;
  final parts = value
      .split(RegExp(r'[,，;；|、]'))
      .map((item) => item.replaceAll(RegExp(r'\s+'), '').trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
  if (parts.length < 2) return false;
  final knownParts = parts.every(
    (item) =>
        item == '自动计算' ||
        item == '只读' ||
        item.startsWith('单位') ||
        item.startsWith('公式'),
  );
  return knownParts && parts.any((item) => item == '自动计算' || item == '只读');
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

ButtonStyle _compactApprovalButtonStyle() => compactMobileActionStyle;

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
  'add_sign' || 'add_signed' => '加签',
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
  'service_queued' => '后续服务已排队',
  'service_succeeded' => '后续服务已完成',
  'service_failed' => '后续服务执行失败',
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
        if (value.isNotEmpty) {
          return mobileErrorText(Exception(value), fallback: '操作失败，请稍后重试');
        }
      }
    }
    final message = error.message?.trim() ?? '';
    if (message.isNotEmpty) {
      return mobileErrorText(Exception(message), fallback: '操作失败，请稍后重试');
    }
  }
  return mobileErrorText(error, fallback: '操作失败，请稍后重试');
}

final class _ReviewDraft {
  const _ReviewDraft(this.comment);

  final String comment;
}

final class _FieldValue {
  const _FieldValue(this.label, this.value, {this.multiline = false});

  final String label;
  final String value;
  final bool multiline;
}
