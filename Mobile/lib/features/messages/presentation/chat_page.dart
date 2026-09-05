import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/media/mobile_image_compressor.dart';
import '../../../core/media/mobile_upload_policy.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/diagnostics/chat_open_diagnostics.dart';
import '../../../core/config/app_environment.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../../shared/widgets/visible_refresh_scheduler.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/data/im_presence_projection.dart';
import '../../collaboration/data/im_member_presence.dart';
import '../../collaboration/data/im_video_thumbnail.dart';
import '../../collaboration/domain/collaboration_models.dart';
import '../../collaboration/application/im_sync_coordinator.dart';
import 'conversation_detail_page.dart';
import 'chat_composer_drafts.dart';
import 'message_favorites_page.dart';
import 'messages_page.dart'
    show imConversationDisplayTitle, imDirectConversationPeer;

final conversationMessageWindowMemoryProvider =
    Provider<ConversationMessageWindowMemory>((ref) {
      ref.watch(collaborationAccountScopeProvider);
      return ConversationMessageWindowMemory();
    });
final conversationLatestReconcileCoordinatorProvider =
    Provider<ConversationLatestReconcileCoordinator>(
      (ref) => ConversationLatestReconcileCoordinator(),
    );

class ConversationMessageWindowMemory {
  static const initialTake = 80;
  static const _maximumConversations = 32;

  final LinkedHashMap<String, ConversationMessageWindowSnapshot> _windows =
      LinkedHashMap<String, ConversationMessageWindowSnapshot>();

  ConversationMessageWindowSnapshot restore(String conversationId) {
    final remembered = _windows.remove(conversationId);
    if (remembered == null) {
      return const ConversationMessageWindowSnapshot(
        take: initialTake,
        hasOlder: true,
      );
    }
    _windows[conversationId] = remembered;
    return remembered;
  }

  void remember(
    String conversationId, {
    required int take,
    required bool hasOlder,
  }) {
    _windows.remove(conversationId);
    _windows[conversationId] = ConversationMessageWindowSnapshot(
      take: take < initialTake ? initialTake : take,
      hasOlder: hasOlder,
    );
    while (_windows.length > _maximumConversations) {
      _windows.remove(_windows.keys.first);
    }
  }
}

class ConversationMessageWindowSnapshot {
  const ConversationMessageWindowSnapshot({
    required this.take,
    required this.hasOlder,
  });

  final int take;
  final bool hasOlder;
}

class ConversationLatestReconcileCoordinator {
  ConversationLatestReconcileCoordinator({
    DateTime Function()? now,
    this.minimumInterval = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now;

  static const _maximumConversations = 32;

  final DateTime Function() _now;
  final Duration minimumInterval;
  final LinkedHashMap<String, DateTime> _lastStarted =
      LinkedHashMap<String, DateTime>();
  final Map<String, Future<bool>> _inFlight = <String, Future<bool>>{};

  Future<bool> reconcile(
    String conversationId,
    ConversationLatestReconciler loader,
  ) {
    final active = _inFlight[conversationId];
    if (active != null) return active;
    final now = _now();
    final lastStarted = _lastStarted.remove(conversationId);
    if (lastStarted != null && now.difference(lastStarted) < minimumInterval) {
      _lastStarted[conversationId] = lastStarted;
      return Future<bool>.value(false);
    }
    _lastStarted[conversationId] = now;
    while (_lastStarted.length > _maximumConversations) {
      _lastStarted.remove(_lastStarted.keys.first);
    }
    final request = Future<bool>.sync(() => loader(conversationId));
    _inFlight[conversationId] = request;
    return request.whenComplete(() {
      if (identical(_inFlight[conversationId], request)) {
        _inFlight.remove(conversationId);
      }
    });
  }
}

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.conversationId,
    this.initialConversation,
    this.enablePresence = true,
    this.initialResourceTab = 0,
  });

  final String conversationId;
  final ImConversation? initialConversation;
  final bool enablePresence;
  final int initialResourceTab;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver {
  Future<void> Function()? _leavePresence;
  final _controller = TextEditingController();
  final _messageScrollController = ScrollController();
  final _messageViewportKey = GlobalKey();
  final Map<String, GlobalKey> _messageItemKeys = <String, GlobalKey>{};
  List<ImMessage> _renderedMessages = const <ImMessage>[];
  bool _visibleReadCheckScheduled = false;
  bool _sending = false;
  bool _sendingAttachment = false;
  bool _loadingReadReceipt = false;
  int _lastReadSequence = 0;
  bool _searching = false;
  String _query = '';
  final Set<String> _mentionedMemberIds = <String>{};
  bool _mentionAll = false;
  ImMessage? _replyTo;
  VisibleRefreshScheduler? _presenceRefreshScheduler;
  VisibleRefreshScheduler? _latestMessageRefreshScheduler;
  bool _routeVisible = false;
  bool _foreground = true;
  bool _reconcilingLatestMessages = false;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  int _messageTake = ConversationMessageWindowMemory.initialTake;
  bool _didInitialMessageScroll = false;
  bool _scrollToBottomAfterRefresh = false;
  ({double pixels, double maxExtent})? _historyAnchor;
  int _resourceTab = 0;
  AudioPlayer? _audioPlayer;
  StreamSubscription<PlayerState>? _audioStateSubscription;
  StreamSubscription<Duration>? _audioPositionSubscription;
  StreamSubscription<Duration?>? _audioDurationSubscription;
  String? _activeAudioAttachmentId;
  Duration _audioPosition = Duration.zero;
  Duration? _audioDuration;
  bool _audioLoading = false;
  bool _audioPlaying = false;
  ChatOpenDiagnostics? _openTrace;
  bool _initialWindowCached = false;
  bool _traceWindowResolved = false;
  bool _unreadInitialized = false;
  int? _firstUnreadSequence;
  int? _anchorEndSequence;
  int _latestSequence = 0;
  bool _positioningUnread = false;
  bool _unreadPositionScheduled = false;
  bool _unreadPositionFailed = false;
  int _unreadPositionPass = 0;
  bool _loadingNewer = false;
  double? _appendScrollOffset;
  bool _latestPositionScheduled = false;
  int _latestPositionPass = 0;
  String? _messageDataAccountScope;

  FutureProvider<List<ImMessage>> get _activeMessageProvider =>
      _anchorEndSequence == null
      ? conversationMessageWindowProvider(_messageWindowKey)
      : conversationAnchoredWindowProvider((
          conversationId: widget.conversationId,
          take: _messageTake,
          beforeSequence: _anchorEndSequence! + 1,
        ));

  void _configureUnread(ImConversation? conversation, {bool resolved = false}) {
    if (conversation != null) {
      final previousLatest = _latestSequence;
      _latestSequence = conversation.lastMessageSequence;
      if (conversation.lastReadSequence > _lastReadSequence) {
        _lastReadSequence = conversation.lastReadSequence;
        if (_unreadInitialized && _positioningUnread) {
          // A desktop read arriving during positioning supersedes the target.
          _unreadInitialized = false;
        }
      }
      if (_unreadInitialized &&
          !_positioningUnread &&
          _anchorEndSequence == previousLatest &&
          _latestSequence > previousLatest &&
          _messageScrollController.hasClients &&
          _messageScrollController.position.extentAfter < 72) {
        _anchorEndSequence = null;
      }
    }
    if (_unreadInitialized || (conversation == null && !resolved)) return;
    _unreadInitialized = true;
    final target = conversation?.firstUnreadSequence;
    if (target != null && target > 0 && target <= _latestSequence) {
      _firstUnreadSequence = target;
      _anchorEndSequence = (target + 39).clamp(target, _latestSequence);
      _messageTake = ConversationMessageWindowMemory.initialTake;
      _hasOlder = true;
      _positioningUnread = true;
      _didInitialMessageScroll = false;
      _unreadPositionPass = 0;
      _unreadPositionFailed = false;
    } else {
      _firstUnreadSequence = null;
      _anchorEndSequence = null;
      _positioningUnread = false;
      _unreadPositionFailed = false;
    }
  }

  ConversationMessageWindowKey get _messageWindowKey =>
      (conversationId: widget.conversationId, take: _messageTake);

  bool get _canObserveMessages => mounted && _routeVisible && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    final rememberedWindow = ref
        .read(conversationMessageWindowMemoryProvider)
        .restore(widget.conversationId);
    _messageTake = rememberedWindow.take;
    _hasOlder = rememberedWindow.hasOlder;
    _openTrace = ChatOpenDiagnostics.attach(widget.conversationId);
    _configureUnread(widget.initialConversation);
    if (_openTrace != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTrace?.mark(ChatOpenStage.routeFrame);
      });
    }
    _resourceTab = widget.initialResourceTab.clamp(0, 2);
    _messageScrollController.addListener(_handleMessageScroll);
    if (widget.enablePresence) {
      _leavePresence = ref.read(conversationPresenceLeaveActionProvider);
      _presenceRefreshScheduler = VisibleRefreshScheduler(
        _refreshPresence,
        interval: const Duration(seconds: 25),
      );
      _latestMessageRefreshScheduler = VisibleRefreshScheduler(
        _reconcileLatestMessages,
        interval: const Duration(seconds: 12),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _presenceRefreshScheduler?.setVisible(_routeVisible);
    _latestMessageRefreshScheduler?.setVisible(_routeVisible);
    _resumeMessageObservation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _resumeMessageObservation();
  }

  void _resumeMessageObservation() {
    if (!_canObserveMessages) return;
    if (_positioningUnread) {
      // A hidden-page result has no visible geometry. Resume positioning when
      // foreground/route visibility returns, even if no provider changes again.
      final current = ref.read(_activeMessageProvider).asData?.value;
      if (current != null) _handleMessageWindow(current);
    } else {
      _scheduleVisibleRead(_renderedMessages);
    }
  }

  Future<void> _reconcileLatestMessages() async {
    if (!_canObserveMessages || _reconcilingLatestMessages) return;
    _reconcilingLatestMessages = true;
    try {
      final changed = await ref
          .read(conversationLatestReconcileCoordinatorProvider)
          .reconcile(
            widget.conversationId,
            ref.read(conversationLatestReconcilerProvider),
          );
      if (!mounted || !changed) return;
      ref.invalidate(
        conversationMessageRevisionProvider(widget.conversationId),
      );
      ref.invalidate(imBootstrapProvider);
    } catch (_) {
      // Event sync remains the primary path; the next bounded reconciliation
      // retries same-account multi-device delivery without disturbing cache.
    } finally {
      _reconcilingLatestMessages = false;
    }
  }

  Future<void> _refreshPresence() async {
    if (!widget.enablePresence || !_canObserveMessages) return;
    try {
      await ref.read(conversationPresenceEnterActionProvider)(
        widget.conversationId,
      );
      if (_canObserveMessages) {
        final provider = conversationPresenceProvider(widget.conversationId);
        if (!ref.read(provider).isLoading) ref.invalidate(provider);
        await ref.read(provider.future);
      }
    } catch (_) {
      // The next heartbeat retries presence synchronization.
    }
  }

  @override
  void dispose() {
    _openTrace?.finish(ChatOpenEnd.routeClosed);
    WidgetsBinding.instance.removeObserver(this);
    _presenceRefreshScheduler?.dispose();
    _latestMessageRefreshScheduler?.dispose();
    _audioStateSubscription?.cancel();
    _audioPositionSubscription?.cancel();
    _audioDurationSubscription?.cancel();
    _audioPlayer?.dispose();
    _leavePresence?.call().ignore();
    _messageScrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleMessageScroll({
    bool upwardOverscroll = false,
    bool downwardOverscroll = false,
  }) {
    _scheduleVisibleRead(_renderedMessages);
    if (_didInitialMessageScroll &&
        !_positioningUnread &&
        _anchorEndSequence != null &&
        _resourceTab == 0 &&
        _query.isEmpty &&
        _messageScrollController.hasClients) {
      final position = _messageScrollController.position;
      if ((downwardOverscroll ||
              position.userScrollDirection == ScrollDirection.reverse) &&
          position.extentAfter <= 72) {
        if (_anchorEndSequence! < _latestSequence) {
          unawaited(_loadNewerMessages());
        } else if (!_loadingNewer) {
          setState(() => _anchorEndSequence = null);
        }
      }
    }
    if (!_didInitialMessageScroll ||
        _resourceTab != 0 ||
        _query.isNotEmpty ||
        _loadingOlder ||
        !_hasOlder ||
        !_messageScrollController.hasClients) {
      return;
    }
    final position = _messageScrollController.position;
    if ((upwardOverscroll ||
            position.userScrollDirection == ScrollDirection.forward) &&
        position.pixels <= position.minScrollExtent + 72) {
      unawaited(_loadOlderMessages());
    }
  }

  bool _handleMessageScrollNotification(ScrollNotification notification) {
    // On Android a drag at the clamped top changes no scroll pixels, so the
    // controller listener cannot retry a page that finished during that drag.
    // Only a real user gesture qualifies; layout/anchor jumps must not fetch.
    if (notification.depth == 0 &&
        notification is OverscrollNotification &&
        notification.dragDetails != null) {
      _handleMessageScroll(
        upwardOverscroll: notification.overscroll < 0,
        downwardOverscroll: notification.overscroll > 0,
      );
    }
    return false;
  }

  void _refreshConversationState({bool scrollToBottom = false}) {
    if (!mounted) return;
    if (scrollToBottom && _anchorEndSequence != null) _returnToLatest();
    _scrollToBottomAfterRefresh |= scrollToBottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(_activeMessageProvider);
      ref.invalidate(imBootstrapProvider);
    });
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || _loadingNewer || !_hasOlder) return;
    final expectedWindow = _activeMessageProvider;
    final account = ref.read(collaborationAccountScopeProvider);
    final position = _messageScrollController.hasClients
        ? _messageScrollController.position
        : null;
    final anchor = position == null
        ? null
        : (pixels: position.pixels, maxExtent: position.maxScrollExtent);
    setState(() => _loadingOlder = true);
    try {
      final current = ref.read(_activeMessageProvider).value;
      final sequenced = (current ?? const <ImMessage>[])
          .where((message) => message.sequence > 0)
          .toList(growable: false);
      final beforeSequence = sequenced.isEmpty
          ? null
          : sequenced
                .map((message) => message.sequence)
                .reduce((left, right) => left < right ? left : right);
      final older = await ref.read(conversationOlderMessageLoaderProvider)(
        widget.conversationId,
        beforeSequence: beforeSequence,
      );
      if (!mounted ||
          expectedWindow != _activeMessageProvider ||
          ref.read(collaborationAccountScopeProvider) != account) {
        return;
      }
      if (older.isNotEmpty) _historyAnchor = anchor;
      final nextTake = _messageTake + older.length;
      // A short local page may stop at a cache gap, not at the beginning of
      // server history. Keep the next upward gesture available in that case.
      final hasOlder =
          older.isNotEmpty && !older.any((message) => message.sequence == 1);
      setState(() {
        _hasOlder = hasOlder;
        _messageTake = nextTake;
      });
      if (_anchorEndSequence == null) {
        ref
            .read(conversationMessageWindowMemoryProvider)
            .remember(
              widget.conversationId,
              take: nextTake,
              hasOlder: hasOlder,
            );
      }
    } catch (_) {
      if (mounted &&
          expectedWindow == _activeMessageProvider &&
          ref.read(collaborationAccountScopeProvider) == account) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('历史消息加载失败，请稍后再次上滑')));
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  Future<void> _loadNewerMessages() async {
    final end = _anchorEndSequence;
    if (_loadingNewer ||
        _loadingOlder ||
        end == null ||
        end >= _latestSequence) {
      return;
    }
    final expectedWindow = _activeMessageProvider;
    final account = ref.read(collaborationAccountScopeProvider);
    final nextEnd = (end + 80).clamp(end, _latestSequence);
    final offset = _messageScrollController.hasClients
        ? _messageScrollController.offset
        : null;
    setState(() => _loadingNewer = true);
    try {
      final newer = await ref.read(conversationAnchoredWindowLoaderProvider)(
        widget.conversationId,
        take: 80,
        beforeSequence: nextEnd + 1,
      );
      if (!mounted ||
          expectedWindow != _activeMessageProvider ||
          ref.read(collaborationAccountScopeProvider) != account) {
        return;
      }
      if (!_positioningUnread) _appendScrollOffset = offset;
      setState(() {
        _anchorEndSequence = nextEnd;
        _messageTake += newer.where((item) => item.sequence > end).length;
      });
    } catch (_) {
      if (mounted &&
          expectedWindow == _activeMessageProvider &&
          ref.read(collaborationAccountScopeProvider) == account) {
        if (_positioningUnread) {
          setState(() => _unreadPositionFailed = true);
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('消息加载失败，请再次上滑重试')));
        }
      }
    } finally {
      if (mounted) setState(() => _loadingNewer = false);
    }
  }

  void _returnToLatest() {
    setState(() {
      _anchorEndSequence = null;
      _positioningUnread = false;
      _unreadPositionFailed = false;
      _firstUnreadSequence = null;
      _messageTake = ConversationMessageWindowMemory.initialTake;
      _hasOlder = true;
      _historyAnchor = null;
      _appendScrollOffset = null;
      _didInitialMessageScroll = false;
      _scrollToBottomAfterRefresh = true;
      _latestPositionPass = 0;
    });
  }

  void _scheduleUnreadPosition(List<ImMessage> items) {
    if (_unreadPositionScheduled ||
        _unreadPositionFailed ||
        !_canObserveMessages ||
        _resourceTab != 0 ||
        _query.isNotEmpty) {
      return;
    }
    _unreadPositionScheduled = true;
    final expectedWindow = _activeMessageProvider;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unreadPositionScheduled = false;
      if (!mounted ||
          !_positioningUnread ||
          !_canObserveMessages ||
          _resourceTab != 0 ||
          _query.isNotEmpty) {
        return;
      }
      if (expectedWindow != _activeMessageProvider) {
        final current = ref.read(_activeMessageProvider).asData?.value;
        if (current != null) _scheduleUnreadPosition(current);
        return;
      }
      final target = items
          .where((item) => item.sequence >= (_firstUnreadSequence ?? 0))
          .firstOrNull;
      if (target == null) {
        if ((_anchorEndSequence ?? 0) < _latestSequence) {
          unawaited(_loadNewerMessages());
        } else {
          _returnToLatest();
        }
        return;
      }
      if (!_messageScrollController.hasClients) return;
      final viewport = _messageViewportKey.currentContext?.findRenderObject();
      if (viewport is! RenderBox) return;
      final position = _messageScrollController.position;
      final targetBox = _messageItemKeys[target.id]?.currentContext
          ?.findRenderObject();
      double desired;
      if (targetBox is RenderBox && targetBox.attached) {
        final top = targetBox.localToGlobal(Offset.zero, ancestor: viewport).dy;
        desired = (position.pixels + top - 28).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((position.pixels - desired).abs() < 1) {
          setState(() {
            _positioningUnread = false;
            _didInitialMessageScroll = true;
          });
          _scheduleVisibleRead(items);
          return;
        }
      } else {
        final built = <({int index, double top, double height})>[];
        for (var index = 0; index < items.length; index++) {
          final box = _messageItemKeys[items[index].id]?.currentContext
              ?.findRenderObject();
          if (box is RenderBox && box.attached) {
            built.add((
              index: index,
              top: box.localToGlobal(Offset.zero, ancestor: viewport).dy,
              height: box.size.height,
            ));
          }
        }
        if (built.isEmpty) return;
        final targetIndex = items.indexOf(target);
        built.sort(
          (a, b) => (a.index - targetIndex).abs().compareTo(
            (b.index - targetIndex).abs(),
          ),
        );
        final nearest = built.first;
        final average =
            built.fold<double>(0, (sum, item) => sum + item.height) /
            built.length;
        desired =
            (position.pixels +
                    nearest.top +
                    (targetIndex - nearest.index) * (average + 6) -
                    28)
                .clamp(position.minScrollExtent, position.maxScrollExtent);
      }
      if (++_unreadPositionPass > 32) {
        setState(() => _unreadPositionFailed = true);
        return;
      }
      _messageScrollController.jumpTo(desired);
      _scheduleUnreadPosition(items);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleLatestPosition(List<ImMessage> items) {
    if (_latestPositionScheduled) return;
    _latestPositionScheduled = true;
    _didInitialMessageScroll = false;
    final expectedWindow = _activeMessageProvider;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _latestPositionScheduled = false;
      if (!mounted ||
          _positioningUnread ||
          expectedWindow != _activeMessageProvider ||
          !_messageScrollController.hasClients ||
          _resourceTab != 0 ||
          _query.isNotEmpty) {
        return;
      }
      final position = _messageScrollController.position;
      final last = items.isEmpty
          ? null
          : _messageItemKeys[items.last.id]?.currentContext?.findRenderObject();
      if ((position.extentAfter <= 1 &&
              (items.isEmpty || last?.attached == true)) ||
          _latestPositionPass >= 32) {
        _latestPositionPass = 0;
        _didInitialMessageScroll = true;
        _scheduleVisibleRead(items);
        return;
      }
      _latestPositionPass++;
      _messageScrollController.jumpTo(position.maxScrollExtent);
      _scheduleLatestPosition(items);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _retryMessage(ImMessage message) async {
    if (message.clientMessageId.isEmpty) return;
    await ref
        .read(imRepositoryProvider)
        .retryMessage(widget.conversationId, message.clientMessageId);
    _refreshConversationState(scrollToBottom: true);
    _wakeImSync();
  }

  void _wakeImSync() {
    final scope = ref.read(collaborationAccountScopeProvider);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted && ref.read(collaborationAccountScopeProvider) == scope) {
        ref.read(imSyncCoordinatorProvider).synchronizeNow();
      }
    });
  }

  Future<void> _send() async {
    final value = _controller.text.trim();
    if (value.isEmpty || _sending) return;
    final replyTo = _replyTo;
    final draft = UnstoredChatDraft(
      content: value,
      mentionedMemberIds: _mentionedMemberIds.toList(),
      mentionAll: _mentionAll,
      replyTo: replyTo == null
          ? null
          : ImMessageReply(
              messageId: replyTo.id,
              senderId: replyTo.senderId,
              content: replyTo.content,
              kind: replyTo.kind,
              createdAt: replyTo.createdAt,
              recalledAt: replyTo.recalledAt,
            ),
    );
    // Detach the submitted draft synchronously. A later local commit must not
    // clear text, mentions or replies entered for the next message.
    _controller.clear();
    _mentionedMemberIds.clear();
    _mentionAll = false;
    _replyTo = null;
    await _sendDraft(draft);
  }

  Future<void> _sendDraft(UnstoredChatDraft draft) async {
    if (_sending) return;
    final drafts = ref.read(unstoredChatDraftsProvider.notifier);
    final generation = drafts.generation;
    final account = ref.read(collaborationAccountScopeProvider);
    final conversationId = widget.conversationId;
    final repository = ref.read(imRepositoryProvider);
    bool ownsComposer() =>
        mounted &&
        drafts.isCurrent(generation) &&
        ref.read(collaborationAccountScopeProvider) == account &&
        widget.conversationId == conversationId;
    setState(() => _sending = true);
    try {
      final message = await repository.send(
        conversationId,
        draft.content,
        mentionedMemberIds: draft.mentionedMemberIds,
        mentionAll: draft.mentionAll,
        replyTo: draft.replyTo,
        clientMessageId: draft.clientMessageId,
        expectedAccountId: account.isEmpty ? null : account,
      );
      drafts.remove(conversationId, draft, generation);
      if (!ownsComposer()) return;
      _refreshConversationState(scrollToBottom: true);
      _wakeImSync();
      if (message.localStatus == ImLocalMessageStatus.failed && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('消息已保存，将在网络恢复后自动重试')));
      }
    } on SessionChangedException {
      // The old account must not restore a draft into the newly logged-in UI.
    } catch (error) {
      drafts.retain(conversationId, draft, generation);
      if (mounted && ownsComposer()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('发送失败', error))),
        );
      }
    } finally {
      if (ownsComposer()) setState(() => _sending = false);
    }
  }

  void _scheduleVisibleRead(List<ImMessage> items) {
    _renderedMessages = items;
    if (!_canObserveMessages ||
        !_unreadInitialized ||
        _positioningUnread ||
        !_didInitialMessageScroll ||
        _resourceTab != 0 ||
        _query.isNotEmpty) {
      return;
    }
    if (_visibleReadCheckScheduled) return;
    _visibleReadCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleReadCheckScheduled = false;
      if (mounted) unawaited(_markVisibleMessagesRead());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _markVisibleMessagesRead() async {
    // Layout can remain attached beneath routes, offstage or in the background.
    // Recheck at execution, not only when the post-frame callback was queued.
    if (!_canObserveMessages ||
        !_unreadInitialized ||
        _positioningUnread ||
        !_didInitialMessageScroll ||
        _resourceTab != 0 ||
        _query.isNotEmpty) {
      return;
    }
    final viewport = _messageViewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return;
    final viewportRect = Offset.zero & viewport.size;
    var sequence = 0;
    for (final item in _renderedMessages) {
      final renderObject = _messageItemKeys[item.id]?.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final origin = renderObject.localToGlobal(
        Offset.zero,
        ancestor: viewport,
      );
      final itemRect = origin & renderObject.size;
      final visibleHeight = itemRect.intersect(viewportRect).height;
      final threshold = renderObject.size.height.clamp(1, 24) / 2;
      if (visibleHeight >= threshold &&
          _didInitialMessageScroll &&
          identical(item, _renderedMessages.last)) {
        _openTrace?.mark(ChatOpenStage.latestMessageLaidOut);
      }
      if (visibleHeight >= threshold && item.sequence > sequence) {
        sequence = item.sequence;
      }
    }
    if (sequence <= _lastReadSequence) return;
    _lastReadSequence = sequence;
    try {
      await ref.read(conversationVisibleReadMarkerProvider)(
        widget.conversationId,
        sequence,
      );
      if (mounted) ref.invalidate(imBootstrapProvider);
    } catch (_) {
      _lastReadSequence = 0;
    }
  }

  void _handleMessageWindow(List<ImMessage> items) {
    if (!_unreadInitialized) return;
    if (_positioningUnread) {
      _scheduleUnreadPosition(items);
      return;
    }
    final nearBottom =
        !_messageScrollController.hasClients ||
        _messageScrollController.position.maxScrollExtent -
                _messageScrollController.position.pixels <
            120;
    final shouldScrollToBottom =
        !_didInitialMessageScroll || _scrollToBottomAfterRefresh || nearBottom;
    final expectedWindow = _activeMessageProvider;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          expectedWindow != _activeMessageProvider ||
          _positioningUnread ||
          !_messageScrollController.hasClients) {
        return;
      }
      final position = _messageScrollController.position;
      final appendOffset = _appendScrollOffset;
      if (appendOffset != null) {
        _appendScrollOffset = null;
        _messageScrollController.jumpTo(
          appendOffset.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
        _scheduleVisibleRead(items);
        return;
      }
      final anchor = _historyAnchor;
      if (anchor != null) {
        _historyAnchor = null;
        _didInitialMessageScroll = true;
        final target =
            anchor.pixels + position.maxScrollExtent - anchor.maxExtent;
        _messageScrollController.jumpTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
        );
        return;
      }
      if (!shouldScrollToBottom) return;
      _scrollToBottomAfterRefresh = false;
      _scheduleLatestPosition(items);
    });
  }

  Future<void> _showAttachmentMenu(ImBootstrap? bootstrap) async {
    if (_sendingAttachment) return;
    var isDirectConversation = false;
    if (bootstrap != null) {
      for (final item in bootstrap.conversations) {
        if (item.id == widget.conversationId) {
          isDirectConversation = item.isDirect;
          break;
        }
      }
    }
    final actions = <_AttachmentMenuAction>[
      const _AttachmentMenuAction('image', '图片', Icons.photo_outlined),
      const _AttachmentMenuAction('video', '视频', Icons.videocam_outlined),
      const _AttachmentMenuAction('audio', '音频', Icons.audio_file_outlined),
      const _AttachmentMenuAction(
        'file',
        '文件',
        Icons.insert_drive_file_outlined,
      ),
      _AttachmentMenuAction(
        'contact',
        '联系人',
        Icons.contact_page_outlined,
        enabled: bootstrap != null,
      ),
      if (isDirectConversation)
        const _AttachmentMenuAction('task', '创建任务', Icons.fact_check_outlined),
    ];
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '发送内容',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: actions.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisExtent: 72,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                ),
                itemBuilder: (context, index) {
                  final item = actions[index];
                  return _AttachmentActionTile(
                    action: item,
                    onTap: item.enabled
                        ? () => Navigator.pop(context, item.value)
                        : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'image') {
      await _pickAndSendImages();
    } else if (action == 'video' || action == 'audio') {
      await _pickAndSendMedia(action);
    } else if (action == 'file') {
      await _pickAndSendFile();
    } else if (action == 'contact' && bootstrap != null) {
      await _pickAndSendContact(bootstrap.contacts);
    } else if (action == 'task') {
      await _createSharedTask();
    }
  }

  Future<void> _pickAndSendMedia(String kind) async {
    final isVideo = kind == 'video';
    var sending = false;
    try {
      final selected = await withMobileFileAccess(
        () => FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: isVideo
              ? const ['mp4', 'm4v', 'webm', 'mov', 'mkv']
              : const ['mp3', 'm4a', 'wav', 'ogg', 'oga', 'flac'],
        ),
      );
      if (selected == null || !mounted) return;
      final length = await withMobileFileAccess(selected.length);
      validateMobileUploadSourceLength(
        isVideo ? MobileUploadKind.chatVideo : MobileUploadKind.chatAudio,
        length,
      );
      if (length <= 0) throw const MobileUploadAccessException();
      setState(() => _sendingAttachment = true);
      sending = true;
      final thumbnail = isVideo
          ? await createImVideoThumbnailFromPath(
              selected.path ?? selected.uri.toString(),
            )
          : null;
      await ref
          .read(imRepositoryProvider)
          .sendMediaStream(
            conversationId: widget.conversationId,
            kind: kind,
            fileName: selected.name,
            length: length,
            openRead: () =>
                withMobileFileStreamAccess(selected.readAsByteStream()),
            contentType: _contentType(
              path.extension(selected.name).replaceFirst('.', ''),
            ),
            coverBytes: thumbnail?.bytes,
            coverWidth: thumbnail?.width,
            coverHeight: thumbnail?.height,
          );
      _refreshConversationState(scrollToBottom: true);
      _wakeImSync();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mobileUploadErrorText('${isVideo ? '视频' : '音频'}发送失败', error),
            ),
          ),
        );
      }
    } finally {
      if (mounted && sending) setState(() => _sendingAttachment = false);
    }
  }

  Future<void> _pickAndSendImages() async {
    var sending = false;
    try {
      final selected = await withMobileFileAccess(
        () => FilePicker.pickFiles(type: FileType.image),
      );
      if (selected.isEmpty || !mounted) return;
      if (selected.length > 9) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('一次最多发送 9 张图片')));
        return;
      }
      setState(() => _sendingAttachment = true);
      sending = true;
      final files =
          <({String fileName, Uint8List bytes, String contentType})>[];
      for (final item in selected) {
        final length = await withMobileFileAccess(item.length);
        validateMobileUploadSourceLength(MobileUploadKind.chatImage, length);
        final bytes = await withMobileFileAccess(item.readAsBytes);
        if (bytes.isEmpty) throw const MobileUploadAccessException();
        final contentType = _contentType(
          path.extension(item.name).replaceFirst('.', ''),
        );
        final prepared = await ref
            .read(mobileImageCompressorProvider)
            .prepare(
              fileName: item.name,
              bytes: bytes,
              contentType: contentType,
              purpose: MobileImagePurpose.message,
            );
        files.add((
          fileName: prepared.fileName,
          bytes: prepared.bytes,
          contentType: prepared.contentType,
        ));
      }
      await ref
          .read(imRepositoryProvider)
          .sendImages(conversationId: widget.conversationId, files: files);
      _refreshConversationState(scrollToBottom: true);
      _wakeImSync();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileUploadErrorText('图片发送失败', error))),
        );
      }
    } finally {
      if (mounted && sending) setState(() => _sendingAttachment = false);
    }
  }

  Future<void> _pickAndSendFile() async {
    var sending = false;
    try {
      final selected = await withMobileFileAccess(FilePicker.pickFile);
      if (selected == null || !mounted) return;
      final length = await withMobileFileAccess(selected.length);
      validateMobileUploadSourceLength(MobileUploadKind.chatFile, length);
      if (length <= 0) throw const MobileUploadAccessException();
      setState(() => _sendingAttachment = true);
      sending = true;
      await ref
          .read(imRepositoryProvider)
          .sendAttachmentStream(
            conversationId: widget.conversationId,
            fileName: selected.name,
            length: length,
            openRead: () =>
                withMobileFileStreamAccess(selected.readAsByteStream()),
            contentType: _contentType(
              path.extension(selected.name).replaceFirst('.', ''),
            ),
          );
      _refreshConversationState(scrollToBottom: true);
      _wakeImSync();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileUploadErrorText('文件发送失败', error))),
        );
      }
    } finally {
      if (mounted && sending) setState(() => _sendingAttachment = false);
    }
  }

  Future<void> _pickAndSendContact(List<ImMember> contacts) async {
    final member = await showModalBottomSheet<ImMember>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => _ContactPickerSheet(contacts: contacts),
    );
    if (member == null || !mounted) return;
    setState(() => _sendingAttachment = true);
    try {
      await ref
          .read(imRepositoryProvider)
          .sendContactCard(widget.conversationId, member.id);
      _refreshConversationState(scrollToBottom: true);
      _wakeImSync();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('联系人分享失败', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  Future<void> _openAttachment(ImMessage message) async {
    try {
      final attachment = await ref
          .read(imRepositoryProvider)
          .downloadAttachment(message);
      final directory = await getTemporaryDirectory();
      final target = File(
        path.join(directory.path, path.basename(attachment.fileName)),
      );
      await target.writeAsBytes(attachment.bytes, flush: true);
      final result = await OpenFilex.open(target.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(result.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('附件打开失败', error))),
        );
      }
    }
  }

  Future<void> _openMediaAttachment(ImMessageAttachment attachment) async {
    try {
      final bytes = await ref
          .read(imRepositoryProvider)
          .downloadMediaAttachment(attachment.id);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('媒体打开失败', error))),
        );
      }
    }
  }

  Future<void> _toggleAudioAttachment(ImMessageAttachment attachment) async {
    if (_audioLoading) return;
    final player = _audioPlayer ??= AudioPlayer();
    _bindAudioPlayer(player);

    if (_activeAudioAttachmentId == attachment.id) {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
        unawaited(player.play());
      } else if (player.playing) {
        await player.pause();
      } else {
        unawaited(player.play());
      }
      return;
    }

    setState(() {
      _activeAudioAttachmentId = attachment.id;
      _audioPosition = Duration.zero;
      _audioDuration = attachment.durationSeconds == null
          ? null
          : Duration(
              milliseconds: (attachment.durationSeconds! * 1000).round(),
            );
      _audioLoading = true;
      _audioPlaying = false;
    });
    try {
      final bytes = await ref
          .read(imRepositoryProvider)
          .downloadMediaAttachment(attachment.id);
      final directory = await getTemporaryDirectory();
      final target = File(
        path.join(directory.path, path.basename(attachment.fileName)),
      );
      await target.writeAsBytes(bytes, flush: true);
      await player.stop();
      final duration = await player.setFilePath(target.path);
      if (!mounted || _activeAudioAttachmentId != attachment.id) return;
      setState(() {
        _audioDuration = duration ?? _audioDuration;
        _audioLoading = false;
      });
      unawaited(player.play());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _activeAudioAttachmentId = null;
        _audioLoading = false;
        _audioPlaying = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mobileActionErrorText('音频播放失败', error))),
      );
    }
  }

  void _bindAudioPlayer(AudioPlayer player) {
    if (_audioStateSubscription != null) return;
    _audioStateSubscription = player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _audioPlaying =
            state.playing && state.processingState != ProcessingState.completed;
        if (state.processingState == ProcessingState.completed &&
            _audioDuration != null) {
          _audioPosition = _audioDuration!;
        }
      });
    });
    _audioPositionSubscription = player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _audioPosition = position);
    });
    _audioDurationSubscription = player.durationStream.listen((duration) {
      if (!mounted || duration == null) return;
      setState(() => _audioDuration = duration);
    });
  }

  Future<void> _openConversationLink(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('无法打开链接');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mobileActionErrorText('链接打开失败', error))),
      );
    }
  }

  void _openConversationImage(ImMessage message) {
    if (message.images.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (_) => _ConversationImagePreview(message: message),
    );
  }

  Future<void> _showEmojiPicker() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ['😀', '😂', '😊', '👍', '👏', '🎉', '❤️', '收到']
                .map(
                  (item) => InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => Navigator.pop(context, item),
                    child: SizedBox.square(
                      dimension: 42,
                      child: Center(
                        child: Text(item, style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (emoji == null || !mounted) return;
    _controller.text += emoji;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  Future<void> _showMentionPicker(
    List<ImMember> members,
    int memberTotal,
    ImGroupProfile? profile,
    bool allowMentionAll,
  ) async {
    final choice = await showModalBottomSheet<Object?>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => _MentionPickerSheet(
        conversationId: widget.conversationId,
        members: members,
        memberTotal: memberTotal,
        allowMentionAll: (profile?.atEnabled ?? true) && allowMentionAll,
      ),
    );
    if (!mounted || choice is! _MentionChoice) return;
    if (choice.mentionAll) {
      setState(() {
        _mentionAll = true;
        _controller.text += '@全体 ';
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      });
      return;
    }
    final member = choice.member;
    if (member == null) return;
    setState(() {
      _mentionedMemberIds.add(member.id);
      _controller.text += '@${member.displayName} ';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  Future<void> _showMessageActions(
    ImMessage message,
    bool mine,
    bool isGroup,
    ImBootstrap? bootstrap,
  ) async {
    if (mine &&
        message.localStatus != ImLocalMessageStatus.sent &&
        message.clientMessageId.isNotEmpty) {
      final retry = await showMobileChoiceSheet<bool>(
        context,
        title: message.localStatus == ImLocalMessageStatus.failed
            ? '发送失败'
            : '等待发送',
        options: [
          MobileSheetOption(
            value: true,
            label: '立即重试',
            icon: Icons.refresh_rounded,
            subtitle: imOutboxStatusText(message),
          ),
        ],
      );
      if (retry == true && mounted) await _retryMessage(message);
      return;
    }
    if (message.id.isEmpty || message.id.startsWith('local-')) return;
    final permissions = bootstrap?.permissions ?? const ImPermissionSnapshot();
    final action = await showMobileChoiceSheet<String>(
      context,
      title: '消息操作',
      options: [
        if (bootstrap?.config.message.reply ?? true)
          const MobileSheetOption(
            value: 'reply',
            label: '回复',
            icon: Icons.reply_rounded,
          ),
        if (mine && permissions.editMessage && message.kind == 'text')
          const MobileSheetOption(
            value: 'edit',
            label: '编辑',
            icon: Icons.edit_outlined,
          ),
        if (mine && permissions.revokeMessage)
          const MobileSheetOption(
            value: 'revoke',
            label: '撤回',
            icon: Icons.undo_rounded,
          ),
        if (bootstrap?.config.message.forward ?? true)
          const MobileSheetOption(
            value: 'forward',
            label: '转发',
            icon: Icons.forward_rounded,
          ),
        const MobileSheetOption(
          value: 'favorite',
          label: '收藏',
          icon: Icons.bookmark_add_outlined,
        ),
        if (isGroup)
          const MobileSheetOption(
            value: 'pin',
            label: '设为群置顶',
            icon: Icons.push_pin_outlined,
          ),
        if (mine && permissions.readReceipt)
          const MobileSheetOption(
            value: 'receipt',
            label: '查看已读',
            icon: Icons.done_all_rounded,
          ),
        if (permissions.deleteMessage)
          const MobileSheetOption(
            value: 'delete',
            label: '删除',
            icon: Icons.delete_outline_rounded,
            destructive: true,
          ),
      ],
    );
    if (action == null || !mounted) return;
    try {
      switch (action) {
        case 'reply':
          setState(() => _replyTo = message);
        case 'edit':
          await _editMessage(message);
        case 'revoke':
          await ref
              .read(imRepositoryProvider)
              .revokeMessage(widget.conversationId, message.id);
          _refreshConversationState();
        case 'delete':
          await ref.read(imRepositoryProvider).deleteMessage(message.id);
          _refreshConversationState();
        case 'forward':
          await _forwardMessage(message, bootstrap?.conversations ?? const []);
        case 'favorite':
          await ref.read(imRepositoryProvider).addFavorite(message.id);
          ref.invalidate(imFavoritesProvider);
          ref.invalidate(imFavoritesPageProvider);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已收藏')));
          }
        case 'pin':
          await ref.read(imRepositoryProvider).pinMessage(message.id);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已设为群置顶')));
          }
        case 'receipt':
          await _showReadReceipts(message);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('操作失败', error))),
        );
      }
    }
  }

  Future<void> _editMessage(ImMessage message) async {
    final content = await showMobileTextInputSheet(
      context,
      title: '编辑消息',
      initialValue: message.content,
      maxLength: 2000,
      maxLines: 4,
      allowEmpty: false,
    );
    if (content == null || content.isEmpty || !mounted) return;
    await ref.read(imRepositoryProvider).editMessage(message.id, content);
    _refreshConversationState();
  }

  Future<void> _forwardMessage(
    ImMessage message,
    List<ImConversation> conversations,
  ) async {
    final targets = conversations
        .where((item) => item.id != widget.conversationId)
        .toList();
    final targetId = await showMobileChoiceSheet<String>(
      context,
      title: '转发到',
      searchable: targets.length > 8,
      searchHint: '搜索会话',
      emptyText: '暂无其他会话',
      options: [
        for (final target in targets)
          MobileSheetOption(
            value: target.id,
            label: target.title,
            subtitle: target.isGroup ? '群聊' : '单聊',
            icon: target.isGroup
                ? Icons.groups_outlined
                : Icons.person_outline_rounded,
          ),
      ],
    );
    if (targetId == null || !mounted) return;
    final target = targets.firstWhere((item) => item.id == targetId);
    await ref.read(imRepositoryProvider).forwardMessage(message.id, target.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已转发到 ${target.title}')));
    }
  }

  Future<void> _showReadReceipts(ImMessage message) async {
    if (_loadingReadReceipt) return;
    _loadingReadReceipt = true;
    late final ImMessageReadReceipt receipt;
    try {
      receipt = await ref.read(imMessageReadReceiptLoaderProvider)(message.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂时无法获取已读状态，请稍后重试')));
      }
      return;
    } finally {
      _loadingReadReceipt = false;
    }
    if (!mounted) return;
    ref.invalidate(conversationMessageRevisionProvider(widget.conversationId));
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final maxListHeight = MediaQuery.sizeOf(sheetContext).height * .45;
        final listHeight = (receipt.readers.length * 52.0)
            .clamp(52.0, maxListHeight)
            .toDouble();
        return SafeArea(
          top: false,
          child: Padding(
            key: const Key('message-read-receipts-sheet'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '已读 ${receipt.readCount}/${receipt.totalRecipientCount}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                if (receipt.readers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      '暂无已读成员',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    key: const Key('message-read-receipts-list'),
                    height: listHeight,
                    child: ListView.builder(
                      itemCount: receipt.readers.length,
                      itemExtent: 52,
                      itemBuilder: (context, index) {
                        final item = receipt.readers[index];
                        final name = item.displayName.isNotEmpty
                            ? item.displayName
                            : item.username;
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          minLeadingWidth: 34,
                          contentPadding: EdgeInsets.zero,
                          leading: InitialAvatar(
                            name: name,
                            radius: 15,
                            avatarKey: item.avatarKey,
                            avatarDataUrl: item.avatarDataUrl,
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: item.readAt == null
                              ? null
                              : Text(
                                  DateFormat('MM-dd HH:mm')
                                      .format(item.readAt!.toLocal()),
                                  style: const TextStyle(fontSize: 11),
                                ),
                        );
                      },
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('关闭'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _createSharedTask() async {
    var taskTitle = '';
    var priority = 'normal';
    final draft = await showModalBottomSheet<_SharedTaskDraft>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          key: const Key('shared-task-create-sheet'),
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
                      '新建共同任务',
                      style: TextStyle(
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
              const SizedBox(height: 4),
              const Text(
                '任务名称',
                style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 36,
                child: TextField(
                  key: const Key('shared-task-title-input'),
                  autofocus: true,
                  maxLength: 120,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: '输入任务名称',
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
                  onChanged: (value) => taskTitle = value,
                  onSubmitted: (_) {
                    final title = taskTitle.trim();
                    if (title.isNotEmpty) {
                      Navigator.pop(
                        sheetContext,
                        _SharedTaskDraft(title, priority),
                      );
                    }
                  },
                ),
              ),
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
                    ButtonSegment(value: 'low', label: Text('低')),
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
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('shared-task-create-button'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(72, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      final title = taskTitle.trim();
                      if (title.isNotEmpty) {
                        Navigator.pop(
                          sheetContext,
                          _SharedTaskDraft(title, priority),
                        );
                      }
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
    if (draft == null || !mounted) return;
    try {
      await ref
          .read(oaRepositoryProvider)
          .createTodo(
            title: draft.title,
            priority: draft.priority,
            conversationId: widget.conversationId,
          );
      ref.invalidate(oaBootstrapProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('共同任务已创建')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('任务创建失败', error))),
        );
      }
    }
  }

  Future<void> _openConversationDetail(
    ImConversation conversation,
    ImMember currentMember,
  ) async {
    final resourceTab = await Navigator.of(context).push<int>(
      MaterialPageRoute<int>(
        builder: (routeContext) => ConversationDetailPage(
          conversation: conversation,
          currentMember: currentMember,
          onOpenResource: (tab) => Navigator.of(routeContext).pop(tab),
        ),
      ),
    );
    if (!mounted || resourceTab == null) return;
    setState(() {
      _resourceTab = resourceTab;
      _searching = false;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final unstoredDrafts =
        ref.watch(unstoredChatDraftsProvider)[widget.conversationId] ??
        const <UnstoredChatDraft>[];
    ref.listen(collaborationAccountScopeProvider, (previous, next) {
      if (previous == next) return;
      setState(() {
        _controller.clear();
        _mentionedMemberIds.clear();
        _mentionAll = false;
        _replyTo = null;
        _sending = false;
      });
    });
    final bootstrapState = ref.watch(imBootstrapProvider);
    final bootstrap = bootstrapState.value;
    final oa = ref.watch(oaBootstrapProvider).value;
    final storedConversation = bootstrap?.conversations
        .where((item) => item.id == widget.conversationId)
        .firstOrNull;
    final syntheticDirectMember =
        widget.conversationId.startsWith('demo-direct-')
        ? bootstrap?.contacts
              .where(
                (item) =>
                    item.id ==
                    widget.conversationId.substring('demo-direct-'.length),
              )
              .firstOrNull
        : null;
    final conversation =
        storedConversation ??
        widget.initialConversation ??
        (syntheticDirectMember == null
            ? null
            : ImConversation(
                id: widget.conversationId,
                type: 'direct',
                title: syntheticDirectMember.displayName,
                preview: '',
                updatedAt: DateTime(0),
                unreadCount: 0,
              ));
    // A failed bootstrap is not evidence of an empty/read conversation. Keep
    // cached messages available, but wait for its cursor before marking reads.
    _configureUnread(conversation, resolved: bootstrapState.hasValue);
    if (_openTrace != null && !_traceWindowResolved && _unreadInitialized) {
      _initialWindowCached = ref.read(_activeMessageProvider).asData != null;
      _traceWindowResolved = true;
    }
    final messages = ref.watch(_activeMessageProvider);
    final accountScope = ref.watch(collaborationAccountScopeProvider);
    final retainMessageLayout = _messageDataAccountScope == accountScope;
    if (messages is AsyncData<List<ImMessage>>) {
      _messageDataAccountScope = accountScope;
    }
    final availableMessages = messages.asData?.value;
    if (availableMessages != null) {
      _openTrace?.snapshot(
        cached: _initialWindowCached,
        count: availableMessages.length,
      );
    }
    final resourceCount =
        messages.asData?.value.where(_isConversationResource).length ?? 0;
    final sharedTasks = (oa?.todos ?? const <OaTodo>[])
        .where(
          (item) =>
              item.conversationId == widget.conversationId &&
              item.status != 'completed' &&
              item.status != 'canceled',
        )
        .toList(growable: false);
    final groupMemberPage = conversation?.isGroup == true
        ? ref
              .watch(
                conversationMemberPageProvider((
                  conversationId: widget.conversationId,
                  page: 1,
                  pageSize: 50,
                  keyword: '',
                )),
              )
              .value
        : null;
    final cachedGroupMembers = conversation?.isGroup == true
        ? ref
              .watch(conversationCachedMembersProvider(widget.conversationId))
              .value
        : null;
    final directMembers = conversation?.isDirect == true
        ? ref.watch(conversationMembersProvider(widget.conversationId)).value
        : null;
    final members = conversation == null
        ? null
        : conversation.isGroup
        ? (groupMemberPage?.items.isNotEmpty ?? false)
              ? groupMemberPage!.items
              : cachedGroupMembers
        : directMembers;
    final memberTotal = conversation?.isGroup == true
        ? (groupMemberPage?.total ?? 0) > 0
              ? groupMemberPage!.total
              : cachedGroupMembers?.length ?? 0
        : members?.length ?? 0;
    final groupProfileState = conversation?.isGroup == true
        ? ref.watch(groupProfileProvider(widget.conversationId))
        : null;
    final groupProfile = groupProfileState?.value;
    final realtimeAvailable =
        ref.watch(imRealtimeAvailabilityProvider) ==
        ImRealtimeAvailability.available;
    final presenceState = widget.enablePresence
        ? ref.watch(conversationPresenceProvider(widget.conversationId))
        : null;
    final presence =
        presenceState?.isLoading == false && presenceState?.hasError == false
        ? presenceState?.value
        : null;
    final observation =
        ref.watch(
          imPresenceProjectionProvider.select(
            (values) => values[widget.conversationId],
          ),
        ) ??
        (presence == null ? null : ImPresenceObservation(presence));
    final authoritativePresence =
        realtimeAvailable && observation?.fresh == true
        ? observation?.value
        : null;
    final currentMember = bootstrap?.currentMember;
    final composerRestriction = _groupComposerRestriction(
      conversation: conversation,
      profile: groupProfile,
      profileLoadFailed: groupProfileState?.hasError ?? false,
      members: members,
      currentMemberId: currentMember?.id ?? '',
    );
    final composerEnabled = composerRestriction == null;
    final directMember = conversation?.isDirect == true
        ? imDirectConversationPeer(
            members ?? const <ImMember>[],
            currentMember?.id ?? '',
            conversation: conversation,
            contacts: bootstrap?.contacts ?? const <ImMember>[],
          )
        : null;
    final directTitle = conversation?.isDirect == true
        ? imConversationDisplayTitle(
            conversation!,
            members ?? const <ImMember>[],
            currentMember?.id ?? '',
            currentDisplayName: currentMember?.displayName ?? '',
            contacts: bootstrap?.contacts ?? const <ImMember>[],
          )
        : conversation?.title ?? '会话';
    final directPresence = resolveDirectPeerPresence(
      transportAvailable: realtimeAvailable,
      member: directMember,
      directoryMember: bootstrap?.contacts
          .where((member) => member.id == directMember?.id)
          .firstOrNull,
      observation: observation,
      memberObservation: ref.watch(
        imMemberPresenceProjectionProvider.select(
          (values) => values[directMember?.id],
        ),
      ),
      allowPreviewStatus: AppEnvironment.demoMode,
    );
    final String conversationStatusLabel;
    if (conversation == null) {
      conversationStatusLabel = '';
    } else if (conversation.isGroup) {
      if (memberTotal > 0) {
        conversationStatusLabel = authoritativePresence == null
            ? '$memberTotal 位成员'
            : '$memberTotal 位成员 · ${authoritativePresence.onlineMemberCount} 人在线';
      } else if ((authoritativePresence?.onlineMemberCount ?? 0) > 0) {
        conversationStatusLabel =
            '${authoritativePresence!.onlineMemberCount} 人在线';
      } else {
        conversationStatusLabel = '';
      }
    } else {
      conversationStatusLabel = _directPresenceLabel(directPresence);
    }
    final memberMap = <String, ImMember>{
      for (final member in <ImMember?>[
        currentMember,
        ...?bootstrap?.contacts,
        directMember,
        ...?members,
      ].nonNulls)
        member.id: member,
    };
    ref.listen(_activeMessageProvider, (_, next) {
      next.whenData(_handleMessageWindow);
    });
    // A hot reopen can already have AsyncData before this listener attaches.
    // Initialize from that snapshot too; waiting for another change leaves the
    // newly mounted list at its oldest row until a later synchronization.
    if (!_didInitialMessageScroll && _resourceTab == 0 && _query.isEmpty) {
      messages.whenData(_handleMessageWindow);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            if (conversation?.isGroup == true)
              const _GroupAvatar(size: 34)
            else
              InitialAvatar(
                name: directTitle,
                radius: 17,
                online: directPresence.online,
                avatarKey: directMember?.avatarKey ?? '',
                avatarDataUrl: directMember?.avatarDataUrl ?? '',
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    directTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (conversationStatusLabel.isNotEmpty)
                    Text(
                      conversationStatusLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '我的收藏',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MessageFavoritesPage(),
              ),
            ),
            icon: const Icon(Icons.bookmark_border_rounded),
          ),
          IconButton(
            tooltip: '搜索聊天记录',
            onPressed: () => setState(() {
              _resourceTab = 0;
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: conversation?.isGroup == true ? '群聊详情' : '个人资料',
            onPressed: conversation == null || currentMember == null
                ? null
                : () => _openConversationDetail(conversation, currentMember),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (conversation != null)
            _ChatResourceTabs(
              selectedIndex: _resourceTab,
              fileCount: resourceCount,
              taskCount: sharedTasks.length,
              showTasks: conversation.isDirect,
              onChanged: (value) => setState(() {
                _resourceTab = value;
                if (value != 0) {
                  _searching = false;
                  _query = '';
                }
              }),
            ),
          if (_searching && _resourceTab == 0)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                children: [
                  Expanded(
                    child: MobileSearchField(
                      key: const Key('chat-current-search'),
                      hintText: '搜索当前会话',
                      autofocus: true,
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox.square(
                    dimension: 34,
                    child: IconButton(
                      key: const Key('chat-current-search-close'),
                      tooltip: '关闭搜索',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      onPressed: () => setState(() {
                        _searching = false;
                        _query = '';
                      }),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ),
                ],
              ),
            ),
          if (_resourceTab == 0 &&
              conversation?.isGroup == true &&
              (groupProfile?.notice.trim().isNotEmpty ?? false))
            InkWell(
              onTap: currentMember == null
                  ? null
                  : () => _openConversationDetail(conversation!, currentMember),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 9,
                ),
                color: Colors.white,
                child: Row(
                  children: [
                    const Icon(
                      Icons.campaign_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        groupProfile!.notice,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.secondaryText,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                messages.when(
                  // A same-account event revision must not unmount the ListView.
                  // Doing so loses its geometry and mistakes reload for a new
                  // route, jumping an unread/history reader to the window's end.
                  // Never retain prior data while switching account scope.
                  skipLoadingOnReload: retainMessageLayout,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: '消息加载失败',
                    description: mobileErrorText(error),
                    onRetry: () => ref.invalidate(_activeMessageProvider),
                  ),
                  data: (items) {
                    if (_resourceTab == 1) {
                      return _ConversationFilesView(
                        messages: items,
                        onOpenFile: _openAttachment,
                        onOpenImage: _openConversationImage,
                        onOpenMedia: _openMediaAttachment,
                        onOpenLink: _openConversationLink,
                      );
                    }
                    if (_resourceTab == 2 && conversation?.isDirect == true) {
                      return _ConversationTasksView(
                        tasks: sharedTasks,
                        onCreate: _createSharedTask,
                        onViewAll: () => context.go('/todos'),
                      );
                    }
                    final query = _query.toLowerCase();
                    final visibleItems = query.isEmpty
                        ? items
                        : items
                              .where(
                                (item) =>
                                    item.content.toLowerCase().contains(query),
                              )
                              .toList();
                    final messageIndexes = <Key, int>{
                      for (var index = 0; index < visibleItems.length; index++)
                        ValueKey<String>('message:${visibleItems[index].id}'):
                            index,
                    };
                    final unreadIndex = _firstUnreadSequence == null
                        ? -1
                        : visibleItems.indexWhere(
                            (item) => item.sequence >= _firstUnreadSequence!,
                          );
                    _scheduleVisibleRead(visibleItems);
                    return visibleItems.isEmpty
                        ? query.isEmpty
                              ? const Center(
                                  child: Text(
                                    '发送第一条消息开始协作',
                                    key: Key('chat-empty-start'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                )
                              : const EmptyState(
                                  icon: Icons.search_off_rounded,
                                  title: '没有匹配的消息',
                                )
                        : KeyedSubtree(
                            key: _messageViewportKey,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: _handleMessageScrollNotification,
                              child: ListView.builder(
                                key: PageStorageKey<String>(
                                  'chat-messages:${widget.conversationId}',
                                ),
                                controller: _messageScrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  16,
                                  14,
                                  16,
                                ),
                                itemCount: visibleItems.length,
                                findChildIndexCallback: (key) =>
                                    messageIndexes[key],
                                itemBuilder: (context, index) {
                                  final item = visibleItems[index];
                                  final previous = index > 0
                                      ? visibleItems[index - 1]
                                      : null;
                                  final next = index + 1 < visibleItems.length
                                      ? visibleItems[index + 1]
                                      : null;
                                  final mine =
                                      item.senderId ==
                                      bootstrap?.currentMember.id;
                                  final startsIdentityGroup =
                                      !_messagesShareCompactCluster(
                                        previous,
                                        item,
                                      );
                                  final compactWithNext =
                                      _messagesShareCompactCluster(item, next);
                                  final showDateDivider =
                                      index == 0 ||
                                      !_messagesShareCalendarDay(
                                        previous,
                                        item,
                                      );
                                  return Column(
                                    key: ValueKey<String>('message:${item.id}'),
                                    children: [
                                      if (showDateDivider)
                                        Column(
                                          children: [
                                            if (index == 0 &&
                                                _query.isEmpty &&
                                                _loadingOlder)
                                              const Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: 10,
                                                ),
                                                child: SizedBox.square(
                                                  key: ValueKey<String>(
                                                    'older-messages-loading',
                                                  ),
                                                  dimension: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: DecoratedBox(
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFE8EEF6,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 9,
                                                        vertical: 3,
                                                      ),
                                                  child: Text(
                                                    _messageDayLabel(
                                                      item.createdAt,
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: AppColors
                                                          .secondaryText,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      if (index == unreadIndex)
                                        const Padding(
                                          key: Key('chat-first-unread-marker'),
                                          padding: EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          child: Text(
                                            '以下为未读消息',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppColors.secondaryText,
                                            ),
                                          ),
                                        ),
                                      KeyedSubtree(
                                        key: _messageItemKeys.putIfAbsent(
                                          item.id,
                                          GlobalKey.new,
                                        ),
                                        child: _MessageBubble(
                                          item: item,
                                          mine: mine,
                                          currentMemberName:
                                              bootstrap
                                                  ?.currentMember
                                                  .displayName ??
                                              '',
                                          currentMemberAvatarKey:
                                              bootstrap
                                                  ?.currentMember
                                                  .avatarKey ??
                                              '',
                                          currentMemberAvatarDataUrl:
                                              bootstrap
                                                  ?.currentMember
                                                  .avatarDataUrl ??
                                              '',
                                          sender: memberMap[item.senderId],
                                          showSenderName:
                                              conversation?.isGroup == true &&
                                              !mine &&
                                              startsIdentityGroup,
                                          reserveSenderAvatar: true,
                                          showSenderAvatar: startsIdentityGroup,
                                          compactWithNext: compactWithNext,
                                          onOpenAttachment: item.kind == 'file'
                                              ? () => _openAttachment(item)
                                              : item.kind == 'audio' &&
                                                    item.attachments.isNotEmpty
                                              ? () => _toggleAudioAttachment(
                                                  item.attachments.first,
                                                )
                                              : item.kind == 'video' &&
                                                    item.attachments.isNotEmpty
                                              ? () => _openMediaAttachment(
                                                  item.attachments.first,
                                                )
                                              : null,
                                          audioActive:
                                              item.kind == 'audio' &&
                                              item.attachments.isNotEmpty &&
                                              item.attachments.first.id ==
                                                  _activeAudioAttachmentId,
                                          audioLoading:
                                              item.kind == 'audio' &&
                                              item.attachments.isNotEmpty &&
                                              item.attachments.first.id ==
                                                  _activeAudioAttachmentId &&
                                              _audioLoading,
                                          audioPlaying:
                                              item.kind == 'audio' &&
                                              item.attachments.isNotEmpty &&
                                              item.attachments.first.id ==
                                                  _activeAudioAttachmentId &&
                                              _audioPlaying,
                                          audioPosition: _audioPosition,
                                          audioDuration: _audioDuration,
                                          onRetry:
                                              item.localStatus ==
                                                  ImLocalMessageStatus.failed
                                              ? () => _retryMessage(item)
                                              : null,
                                          showReadReceiptAction:
                                              item.localStatus ==
                                                  ImLocalMessageStatus.sent &&
                                              item.id.trim().isNotEmpty &&
                                              (bootstrap
                                                      ?.permissions
                                                      .readReceipt ??
                                                  false),
                                          onOpenReadReceipt: () =>
                                              _showReadReceipts(item),
                                          onLongPress: () =>
                                              _showMessageActions(
                                                item,
                                                item.senderId ==
                                                    bootstrap?.currentMember.id,
                                                conversation?.isGroup == true,
                                                bootstrap,
                                              ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          );
                  },
                ),
                if (_positioningUnread &&
                    !messages.hasError &&
                    _resourceTab == 0)
                  ColoredBox(
                    color: const Color(0xFFF7F8FA),
                    child: Center(
                      child: _unreadPositionFailed
                          ? TextButton(
                              onPressed: () {
                                setState(() {
                                  _unreadPositionFailed = false;
                                  _unreadPositionPass = 0;
                                });
                                _scheduleUnreadPosition(_renderedMessages);
                              },
                              child: const Text('重试定位未读消息'),
                            )
                          : const SizedBox.square(
                              key: Key('chat-unread-positioning'),
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                    ),
                  ),
                if (_anchorEndSequence != null &&
                    _resourceTab == 0 &&
                    _query.isEmpty)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: FilledButton.tonalIcon(
                      key: const Key('chat-return-latest'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _returnToLatest,
                      icon: _loadingNewer
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_downward_rounded, size: 16),
                      label: const Text('回到最新'),
                    ),
                  ),
              ],
            ),
          ),
          if (_resourceTab == 0 && unstoredDrafts.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 96),
              child: ListView.builder(
                key: const Key('chat-unstored-drafts'),
                shrinkWrap: true,
                itemCount: unstoredDrafts.length,
                itemBuilder: (context, index) {
                  final draft = unstoredDrafts[index];
                  return Container(
                    color: const Color(0xFFFFF5F3),
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: Color(0xFFB42318),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '未发送：${draft.content}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        IconButton(
                          tooltip: '重试未入库消息',
                          onPressed: _sending || !composerEnabled
                              ? null
                              : () => _sendDraft(draft),
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          if (_resourceTab == 0)
            SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (conversation?.isGroup == true &&
                        (groupProfile?.atEnabled ?? true) &&
                        (bootstrap?.config.message.mentionMember ?? true))
                      SizedBox.square(
                        dimension: 40,
                        child: IconButton(
                          tooltip: '提及成员',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: !composerEnabled || members == null
                              ? null
                              : () => _showMentionPicker(
                                  members,
                                  memberTotal,
                                  groupProfile,
                                  bootstrap?.config.message.mentionAll ?? false,
                                ),
                          icon: const Icon(
                            Icons.alternate_email_rounded,
                            size: 21,
                          ),
                        ),
                      ),
                    SizedBox.square(
                      dimension: 40,
                      child: IconButton(
                        tooltip: '附件',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        onPressed: !composerEnabled || _sendingAttachment
                            ? null
                            : () => _showAttachmentMenu(bootstrap),
                        icon: _sendingAttachment
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.attach_file_rounded, size: 21),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        key: const Key('chat-message-input-shell'),
                        constraints: const BoxConstraints(minHeight: 40),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F5F8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          key: const Key('chat-message-input'),
                          controller: _controller,
                          enabled: composerEnabled,
                          maxLines: 4,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText:
                                composerRestriction ??
                                (_replyTo == null ? '输入消息' : '回复消息'),
                            isDense: true,
                            filled: false,
                            contentPadding: const EdgeInsets.fromLTRB(
                              12,
                              8,
                              4,
                              8,
                            ),
                            prefixIcon: _replyTo == null
                                ? null
                                : const Icon(Icons.reply_rounded, size: 18),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 40,
                            ),
                            suffixIconConstraints:
                                const BoxConstraints.tightFor(
                                  width: 38,
                                  height: 38,
                                ),
                            suffixIcon: IconButton(
                              tooltip: '表情',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: composerEnabled
                                  ? _showEmojiPicker
                                  : null,
                              icon: const Icon(
                                Icons.sentiment_satisfied_alt_outlined,
                                size: 21,
                              ),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox.square(
                      dimension: 40,
                      child: IconButton.filled(
                        tooltip: '发送',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        onPressed: !composerEnabled || _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox.square(
                                dimension: 17,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 21),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final class _SharedTaskDraft {
  const _SharedTaskDraft(this.title, this.priority);

  final String title;
  final String priority;
}

final class _AttachmentMenuAction {
  const _AttachmentMenuAction(
    this.value,
    this.label,
    this.icon, {
    this.enabled = true,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool enabled;
}

class _AttachmentActionTile extends StatelessWidget {
  const _AttachmentActionTile({required this.action, required this.onTap});

  final _AttachmentMenuAction action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? AppColors.primary : AppColors.secondaryText;
    return SizedBox(
      key: ValueKey('chat-attachment-${action.value}'),
      height: 72,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: enabled
                    ? const Color(0xFFEAF2FF)
                    : const Color(0xFFF2F3F5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(action.icon, size: 20, color: color),
            ),
            const SizedBox(height: 5),
            Text(
              action.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12.5,
                color: enabled ? AppColors.text : AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isConversationFile(ImMessage item) =>
    item.kind == 'file' ||
    item.kind == 'audio' ||
    (item.attachmentName.trim().isNotEmpty &&
        !const {'image', 'video'}.contains(item.kind));

bool _isConversationMedia(ImMessage item) =>
    item.kind == 'image' || item.kind == 'video';

bool _isConversationLink(ImMessage item) => _messageLinks(item).isNotEmpty;

bool _isConversationResource(ImMessage item) =>
    _isConversationFile(item) ||
    _isConversationMedia(item) ||
    _isConversationLink(item);

List<Uri> _messageLinks(ImMessage item) {
  final matches = RegExp(
    r'https?://[^\s<>()]+',
    caseSensitive: false,
  ).allMatches(item.content);
  return matches
      .map((match) => match.group(0) ?? '')
      .map((value) => value.replaceFirst(RegExp(r'[，。；、,.!?]+$'), ''))
      .map(Uri.tryParse)
      .nonNulls
      .where((uri) => uri.hasScheme && uri.host.isNotEmpty)
      .toList(growable: false);
}

class _ChatResourceTabs extends StatelessWidget {
  const _ChatResourceTabs({
    required this.selectedIndex,
    required this.fileCount,
    required this.taskCount,
    required this.showTasks,
    required this.onChanged,
  });

  final int selectedIndex;
  final int fileCount;
  final int taskCount;
  final bool showTasks;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: SizedBox(
      height: 38,
      child: Row(
        children: [
          _ResourceTab(
            label: '聊天',
            selected: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _ResourceTab(
            label: fileCount == 0 ? '文件' : '文件 $fileCount',
            selected: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
          if (showTasks)
            _ResourceTab(
              label: taskCount == 0 ? '任务' : '任务 $taskCount',
              selected: selectedIndex == 2,
              onTap: () => onChanged(2),
            ),
        ],
      ),
    ),
  );
}

class _ResourceTab extends StatelessWidget {
  const _ResourceTab({
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
      key: ValueKey<String>('chat-resource-tab-$label'),
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primary : AppColors.secondaryText,
              ),
            ),
          ),
          if (selected)
            Positioned(
              left: 24,
              right: 24,
              bottom: 0,
              child: SizedBox(
                key: ValueKey<String>('chat-resource-tab-indicator-$label'),
                height: 2,
                child: const ColoredBox(color: AppColors.primary),
              ),
            ),
        ],
      ),
    ),
  );
}

enum _ConversationResourceType { file, media, link }

class _ConversationFilesView extends StatefulWidget {
  const _ConversationFilesView({
    required this.messages,
    required this.onOpenFile,
    required this.onOpenImage,
    required this.onOpenMedia,
    required this.onOpenLink,
  });

  final List<ImMessage> messages;
  final ValueChanged<ImMessage> onOpenFile;
  final ValueChanged<ImMessage> onOpenImage;
  final ValueChanged<ImMessageAttachment> onOpenMedia;
  final ValueChanged<Uri> onOpenLink;

  @override
  State<_ConversationFilesView> createState() => _ConversationFilesViewState();
}

class _ConversationFilesViewState extends State<_ConversationFilesView> {
  _ConversationResourceType _type = _ConversationResourceType.file;

  @override
  Widget build(BuildContext context) {
    final files = widget.messages.where(_isConversationFile).toList();
    final media = widget.messages.where(_isConversationMedia).toList();
    final links = [
      for (final message in widget.messages)
        for (final uri in _messageLinks(message)) (message: message, uri: uri),
    ];
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: SizedBox(
            height: 42,
            child: Row(
              children: [
                _ResourceCategoryTab(
                  label: '文件',
                  count: files.length,
                  selected: _type == _ConversationResourceType.file,
                  onTap: () =>
                      setState(() => _type = _ConversationResourceType.file),
                ),
                _ResourceCategoryTab(
                  label: '图片/视频',
                  count: media.length,
                  selected: _type == _ConversationResourceType.media,
                  onTap: () =>
                      setState(() => _type = _ConversationResourceType.media),
                ),
                _ResourceCategoryTab(
                  label: '链接',
                  count: links.length,
                  selected: _type == _ConversationResourceType.link,
                  onTap: () =>
                      setState(() => _type = _ConversationResourceType.link),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (_type) {
            _ConversationResourceType.file => _ConversationResourceList(
              items: files,
              emptyIcon: Icons.folder_open_outlined,
              emptyText: '暂无会话文件',
              iconOf: (item) => item.kind == 'audio'
                  ? Icons.graphic_eq_rounded
                  : Icons.description_outlined,
              nameOf: _conversationFileName,
              trailing: Icons.download_outlined,
              onTap: widget.onOpenFile,
            ),
            _ConversationResourceType.media => _ConversationResourceList(
              items: media,
              emptyIcon: Icons.photo_library_outlined,
              emptyText: '暂无图片或视频',
              iconOf: (item) => item.kind == 'video'
                  ? Icons.videocam_outlined
                  : Icons.photo_outlined,
              nameOf: _conversationMediaName,
              trailing: Icons.open_in_new_rounded,
              onTap: (item) {
                if (item.kind == 'image') {
                  widget.onOpenImage(item);
                } else if (item.attachments.isNotEmpty) {
                  widget.onOpenMedia(item.attachments.first);
                }
              },
            ),
            _ConversationResourceType.link =>
              links.isEmpty
                  ? const EmptyState(
                      icon: Icons.link_off_rounded,
                      title: '暂无会话链接',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      itemCount: links.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final link = links[index];
                        return ListTile(
                          dense: true,
                          minTileHeight: 54,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: const _ResourceIcon(
                            icon: Icons.link_rounded,
                          ),
                          title: Text(
                            link.uri.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5),
                          ),
                          subtitle: Text(
                            _resourceTime(link.message),
                            style: const TextStyle(fontSize: 10.5),
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                          ),
                          onTap: () => widget.onOpenLink(link.uri),
                        );
                      },
                    ),
          },
        ),
      ],
    );
  }
}

class _ResourceCategoryTab extends StatelessWidget {
  const _ResourceCategoryTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      canRequestFocus: false,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            count == 0 ? label : '$label $count',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.primary : AppColors.secondaryText,
            ),
          ),
          if (selected)
            const Positioned(
              left: 34,
              right: 34,
              bottom: 0,
              child: SizedBox(
                height: 2,
                child: ColoredBox(color: AppColors.primary),
              ),
            ),
        ],
      ),
    ),
  );
}

class _ConversationResourceList extends StatelessWidget {
  const _ConversationResourceList({
    required this.items,
    required this.emptyIcon,
    required this.emptyText,
    required this.iconOf,
    required this.nameOf,
    required this.trailing,
    required this.onTap,
  });

  final List<ImMessage> items;
  final IconData emptyIcon;
  final String emptyText;
  final IconData Function(ImMessage) iconOf;
  final String Function(ImMessage) nameOf;
  final IconData trailing;
  final ValueChanged<ImMessage> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return EmptyState(icon: emptyIcon, title: emptyText);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          dense: true,
          minTileHeight: 54,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: _ResourceIcon(icon: iconOf(item)),
          title: Text(
            nameOf(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            _resourceTime(item),
            style: const TextStyle(fontSize: 10.5),
          ),
          trailing: Icon(trailing, size: 19),
          onTap: () => onTap(item),
        );
      },
    );
  }
}

class _ResourceIcon extends StatelessWidget {
  const _ResourceIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(icon, size: 18, color: AppColors.primary),
  );
}

String _conversationFileName(ImMessage item) {
  final name = item.kind == 'audio' && item.attachments.isNotEmpty
      ? item.attachments.first.fileName
      : item.attachmentName.trim().isEmpty
      ? item.content.replaceFirst(RegExp(r'^附件[：:]\s*'), '')
      : item.attachmentName;
  return name.trim().isEmpty ? '工作附件' : name;
}

String _conversationMediaName(ImMessage item) {
  if (item.kind == 'image') {
    if (item.images.isEmpty) return '会话图片';
    if (item.images.length == 1) return item.images.first.fileName;
    return '${item.images.first.fileName} 等 ${item.images.length} 张图片';
  }
  return item.attachments.isEmpty ? '会话视频' : item.attachments.first.fileName;
}

String _resourceTime(ImMessage item) => item.createdAt == null
    ? '会话资源'
    : DateFormat('yyyy/MM/dd HH:mm').format(item.createdAt!);

class _ConversationImagePreview extends ConsumerWidget {
  const _ConversationImagePreview({required this.message});

  final ImMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = message.images.first;
    final bytes = ref.watch(
      imMessageImageProvider((
        messageId: message.id,
        imageId: image.id,
        sha256: image.sha256,
      )),
    );
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          bytes.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
                size: 42,
              ),
            ),
            data: (data) => InteractiveViewer(
              child: Image.memory(data, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 28,
            right: 12,
            child: IconButton.filledTonal(
              tooltip: '关闭预览',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTasksView extends StatelessWidget {
  const _ConversationTasksView({
    required this.tasks,
    required this.onCreate,
    required this.onViewAll,
  });

  final List<OaTodo> tasks;
  final VoidCallback onCreate;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              '共同任务',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(onPressed: onViewAll, child: const Text('查看全部')),
          const SizedBox(width: 2),
          SizedBox(
            height: 34,
            child: FilledButton.tonalIcon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('新建'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      if (tasks.isEmpty)
        const SizedBox(
          height: 220,
          child: Center(
            child: Text(
              '暂无共同任务',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
        )
      else
        ...tasks.map(
          (task) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MobileSurface(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _taskPriorityColor(task.priority),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (task.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            task.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.secondaryText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    task.dueAt == null
                        ? '未排期'
                        : DateFormat('MM/dd').format(task.dueAt!),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

Color _taskPriorityColor(String priority) => switch (priority) {
  'urgent' => AppColors.error,
  'high' => const Color(0xFFF08C2E),
  'low' => const Color(0xFF22A06B),
  _ => AppColors.primary,
};

String _directPresenceLabel(({bool? online, DateTime? lastSeenAt}) presence) {
  final online = presence.online;
  final lastSeenAt = presence.lastSeenAt;
  if (online == null) {
    return lastSeenAt == null
        ? '状态未知'
        : '最后在线 ${DateFormat('MM-dd HH:mm').format(lastSeenAt)}';
  }
  return online
      ? '在线'
      : lastSeenAt != null
      ? '离线 · ${DateFormat('MM-dd HH:mm').format(lastSeenAt)}'
      : '离线';
}

final class _MentionChoice {
  const _MentionChoice.all() : member = null, mentionAll = true;
  const _MentionChoice.member(ImMember value)
    : member = value,
      mentionAll = false;

  final ImMember? member;
  final bool mentionAll;
}

List<InlineSpan> _messageSpans(ImMessage item, Color color) {
  final labels = item.mentions
      .map(
        (mention) => mention.isMentionAll ? '@全体' : '@${mention.displayName}',
      )
      .toSet()
      .toList();
  if (labels.isEmpty) {
    return [
      TextSpan(
        text: item.content,
        style: TextStyle(color: color),
      ),
    ];
  }
  final spans = <InlineSpan>[];
  final pattern = RegExp(labels.map(RegExp.escape).join('|'));
  var cursor = 0;
  for (final match in pattern.allMatches(item.content)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(
          text: item.content.substring(cursor, match.start),
          style: TextStyle(color: color),
        ),
      );
    }
    spans.add(
      TextSpan(
        text: match.group(0),
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
    cursor = match.end;
  }
  if (cursor < item.content.length) {
    spans.add(
      TextSpan(
        text: item.content.substring(cursor),
        style: TextStyle(color: color),
      ),
    );
  }
  return spans;
}

bool _isEmojiOnlyMessage(String value) {
  final runes = value.trim().runes.toList(growable: false);
  if (runes.isEmpty) return false;
  var hasEmojiBase = false;
  for (var index = 0; index < runes.length; index += 1) {
    final rune = runes[index];
    if (String.fromCharCodes([rune]).trim().isEmpty) continue;
    if (_isKeycapBase(rune)) {
      var suffix = index + 1;
      if (suffix < runes.length && runes[suffix] == 0xFE0F) suffix += 1;
      if (suffix >= runes.length || runes[suffix] != 0x20E3) return false;
      hasEmojiBase = true;
      index = suffix;
      continue;
    }
    if (_isEmojiComponent(rune)) continue;
    if (!_isEmojiBase(rune)) return false;
    hasEmojiBase = true;
  }
  return hasEmojiBase;
}

bool _isKeycapBase(int rune) =>
    rune == 0x23 || rune == 0x2A || (rune >= 0x30 && rune <= 0x39);

bool _isEmojiComponent(int rune) =>
    rune == 0x200D ||
    rune == 0x20E3 ||
    (rune >= 0xFE00 && rune <= 0xFE0F) ||
    (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
    (rune >= 0xE0020 && rune <= 0xE007F);

bool _isEmojiBase(int rune) =>
    (rune >= 0x1F000 && rune <= 0x1FAFF) ||
    (rune >= 0x2190 && rune <= 0x21FF) ||
    (rune >= 0x2300 && rune <= 0x23FF) ||
    (rune >= 0x2600 && rune <= 0x27BF) ||
    (rune >= 0x2B00 && rune <= 0x2BFF) ||
    const {
      0x00A9,
      0x00AE,
      0x203C,
      0x2049,
      0x2122,
      0x2139,
      0x3030,
      0x303D,
      0x3297,
      0x3299,
    }.contains(rune);

String? _groupComposerRestriction({
  required ImConversation? conversation,
  required ImGroupProfile? profile,
  required bool profileLoadFailed,
  required List<ImMember>? members,
  required String currentMemberId,
}) {
  if (conversation?.isGroup != true) return null;
  if (profile == null) {
    return profileLoadFailed ? '群聊状态不可用' : '群聊状态加载中';
  }
  final status = profile.status.trim().toLowerCase();
  if (const {
    'archived',
    'closed',
    'deleted',
    'disabled',
    'dissolved',
    'inactive',
    '已关闭',
    '已解散',
    '已停用',
  }.contains(status)) {
    return '群聊已停用';
  }
  if (!profile.muted) return null;
  final role = profile.currentUserRole.trim().isNotEmpty
      ? profile.currentUserRole.trim().toLowerCase()
      : members
            ?.where((member) => member.id == currentMemberId)
            .firstOrNull
            ?.groupRole
            .trim()
            .toLowerCase();
  if (const {'owner', 'admin', 'administrator', '群主', '管理员'}.contains(role)) {
    return null;
  }
  return '全员禁言中';
}

bool _messagesShareCalendarDay(ImMessage? first, ImMessage? second) {
  final firstAt = first?.createdAt?.toLocal();
  final secondAt = second?.createdAt?.toLocal();
  if (firstAt == null || secondAt == null) return false;
  return firstAt.year == secondAt.year &&
      firstAt.month == secondAt.month &&
      firstAt.day == secondAt.day;
}

bool _messagesShareIdentityGroup(ImMessage? first, ImMessage? second) {
  if (first == null || second == null || first.senderId != second.senderId) {
    return false;
  }
  return _messagesShareCalendarDay(first, second);
}

bool _messagesShareCompactCluster(ImMessage? first, ImMessage? second) {
  if (!_messagesShareIdentityGroup(first, second)) return false;
  final firstAt = first!.createdAt!;
  final secondAt = second!.createdAt!;
  return secondAt.difference(firstAt).abs() <= const Duration(minutes: 5);
}

String _messageDayLabel(DateTime? createdAt) {
  if (createdAt == null) return '今天';
  return DateFormat('MM月dd日').format(createdAt.toLocal());
}

double? _mediaMessageContentWidth(ImMessage message) {
  if (message.recalledAt != null) return null;
  if (message.kind == 'image' && message.images.isNotEmpty) {
    return message.images.length == 1 ? 210 : 240;
  }
  if (message.attachments.isEmpty) return null;
  return switch (message.kind) {
    'video' => 200,
    'audio' => 210,
    _ => null,
  };
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.item,
    required this.mine,
    required this.currentMemberName,
    required this.currentMemberAvatarKey,
    required this.currentMemberAvatarDataUrl,
    required this.sender,
    required this.showSenderName,
    required this.reserveSenderAvatar,
    required this.showSenderAvatar,
    required this.compactWithNext,
    required this.onOpenAttachment,
    required this.audioActive,
    required this.audioLoading,
    required this.audioPlaying,
    required this.audioPosition,
    required this.audioDuration,
    required this.onRetry,
    required this.showReadReceiptAction,
    required this.onOpenReadReceipt,
    required this.onLongPress,
  });

  final ImMessage item;
  final bool mine;
  final String currentMemberName;
  final String currentMemberAvatarKey;
  final String currentMemberAvatarDataUrl;
  final ImMember? sender;
  final bool showSenderName;
  final bool reserveSenderAvatar;
  final bool showSenderAvatar;
  final bool compactWithNext;
  final VoidCallback? onOpenAttachment;
  final bool audioActive;
  final bool audioLoading;
  final bool audioPlaying;
  final Duration audioPosition;
  final Duration? audioDuration;
  final VoidCallback? onRetry;
  final bool showReadReceiptAction;
  final VoidCallback onOpenReadReceipt;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final emojiOnly = item.kind == 'text' && _isEmojiOnlyMessage(item.content);
    const outgoingBubble = Color(0xFFDCEAFF);
    final bubbleColor = mine ? outgoingBubble : Colors.white;
    final contentColor = AppColors.text;
    final metaColor = mine ? const Color(0xFF54709B) : AppColors.weakText;
    final mediaWidth = _mediaMessageContentWidth(item);
    final bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(!mine && showSenderAvatar ? 4 : 14),
      topRight: Radius.circular(mine && showSenderAvatar ? 4 : 14),
      bottomLeft: const Radius.circular(14),
      bottomRight: const Radius.circular(14),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: compactWithNext ? 3 : 9),
      child: Row(
        mainAxisAlignment: mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: showSenderAvatar
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          if (!mine && reserveSenderAvatar) ...[
            SizedBox.square(
              dimension: 30,
              child: showSenderAvatar
                  ? InitialAvatar(
                      key: ValueKey<String>('message-avatar-${item.id}'),
                      name: sender?.displayName ?? item.senderId,
                      radius: 15,
                      avatarKey: sender?.avatarKey ?? '',
                      avatarDataUrl: sender?.avatarDataUrl ?? '',
                    )
                  : null,
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onOpenAttachment,
                  onLongPress: onLongPress,
                  borderRadius: bubbleRadius,
                  child: Container(
                    key: ValueKey<String>('message-bubble-${item.id}'),
                    // Align on the metadata row may expand, but only within
                    // the actual media width plus padding/border. Avoid
                    // intrinsic sizing: image grids are lazy viewports.
                    constraints: BoxConstraints(
                      maxWidth: mediaWidth == null
                          ? 292
                          : mediaWidth + 19 + (mine ? 0 : 2),
                    ),
                    padding: const EdgeInsets.fromLTRB(11, 7, 8, 6),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      border: mine
                          ? null
                          : Border.all(color: const Color(0xFFDDE3EC)),
                      borderRadius: bubbleRadius,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!mine && showSenderName) ...[
                          Text(
                            sender?.displayName ?? '群成员',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (item.recalledAt != null)
                          _MessageTextWithMeta(
                            item: item,
                            mine: mine,
                            contentColor: contentColor,
                            metaColor: metaColor,
                            emojiOnly: false,
                            recalled: true,
                            showReadReceiptAction: showReadReceiptAction,
                            onOpenReadReceipt: onOpenReadReceipt,
                            onRetry: onRetry,
                          )
                        else ...[
                          if (item.replyTo != null)
                            Container(
                              constraints: const BoxConstraints(maxWidth: 250),
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.only(left: 7),
                              decoration: const BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Text(
                                item.replyTo!.recalledAt != null
                                    ? '消息已撤回'
                                    : item.replyTo!.content,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ),
                          if (item.kind == 'text')
                            _MessageTextWithMeta(
                              item: item,
                              mine: mine,
                              contentColor: contentColor,
                              metaColor: metaColor,
                              emojiOnly: emojiOnly,
                              showReadReceiptAction: showReadReceiptAction,
                              onOpenReadReceipt: onOpenReadReceipt,
                              onRetry: onRetry,
                            )
                          else ...[
                            if (item.kind == 'file')
                              _AttachmentContent(item: item)
                            else if (const {
                                  'video',
                                  'audio',
                                }.contains(item.kind) &&
                                item.attachments.isNotEmpty)
                              _MediaMessageContent(
                                message: item,
                                audioActive: audioActive,
                                audioLoading: audioLoading,
                                audioPlaying: audioPlaying,
                                audioPosition: audioPosition,
                                audioDuration: audioDuration,
                              )
                            else if (item.kind == 'image' &&
                                item.images.isNotEmpty)
                              _ImageMessageContent(message: item)
                            else if (item.kind == 'contact' &&
                                item.contactCard != null)
                              _ContactCardContent(card: item.contactCard!)
                            else
                              Text(
                                item.content,
                                style: TextStyle(color: contentColor),
                              ),
                            const SizedBox(height: 3),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _MessageMeta(
                                item: item,
                                mine: mine,
                                color: metaColor,
                                showReadReceiptAction: showReadReceiptAction,
                                onOpenReadReceipt: onOpenReadReceipt,
                                onRetry: onRetry,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (mine && reserveSenderAvatar) ...[
            const SizedBox(width: 7),
            SizedBox.square(
              dimension: 30,
              child: showSenderAvatar
                  ? InitialAvatar(
                      key: ValueKey<String>('message-avatar-${item.id}'),
                      name: currentMemberName.isEmpty
                          ? item.senderId
                          : currentMemberName,
                      radius: 15,
                      avatarKey: currentMemberAvatarKey,
                      avatarDataUrl: currentMemberAvatarDataUrl,
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageTextWithMeta extends StatelessWidget {
  const _MessageTextWithMeta({
    required this.item,
    required this.mine,
    required this.contentColor,
    required this.metaColor,
    required this.emojiOnly,
    required this.showReadReceiptAction,
    required this.onOpenReadReceipt,
    required this.onRetry,
    this.recalled = false,
  });

  final ImMessage item;
  final bool mine;
  final Color contentColor;
  final Color metaColor;
  final bool emojiOnly;
  final bool showReadReceiptAction;
  final VoidCallback onOpenReadReceipt;
  final VoidCallback? onRetry;
  final bool recalled;

  @override
  Widget build(BuildContext context) {
    final largeEmoji = emojiOnly || _isEmojiOnlyMessage(item.content);
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 7,
      runSpacing: 1,
      children: [
        recalled
            ? Text(
                '消息已撤回',
                style: TextStyle(
                  color: contentColor,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              )
            : Text.rich(
                key: ValueKey('message-text-${item.id}'),
                TextSpan(children: _messageSpans(item, contentColor)),
                style: TextStyle(
                  color: contentColor,
                  fontSize: largeEmoji ? 30 : 15,
                  height: largeEmoji ? 1.12 : 1.32,
                ),
              ),
        _MessageMeta(
          item: item,
          mine: mine,
          color: metaColor,
          showReadReceiptAction: showReadReceiptAction,
          onOpenReadReceipt: onOpenReadReceipt,
          onRetry: onRetry,
        ),
      ],
    );
  }
}

/// Never render stored exception strings: older builds may have persisted
/// request addresses or transport details. Only project recognized categories.
String imOutboxStatusText(ImMessage message) {
  final error = message.lastError;
  final operation = RegExp(
    r'(视频上传|音频上传|封面上传|媒体消息提交|图片发送|文件发送|消息发送|消息服务请求)失败（HTTP \d{3}）',
  ).firstMatch(error)?.group(0);
  if (operation != null) return operation;
  final status = RegExp(r'HTTP\s+(\d{3})').firstMatch(error)?.group(1);
  if (status != null) return '消息服务请求失败（HTTP $status）';
  if (error.contains('超时')) return '网络超时，等待自动重试';
  if (error.contains('网络不可用')) return '网络不可用，等待自动重试';
  return message.localStatus == ImLocalMessageStatus.failed
      ? '发送未完成，请重试'
      : '尚未收到发送确认，将自动重试';
}

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.item,
    required this.mine,
    required this.color,
    required this.showReadReceiptAction,
    required this.onOpenReadReceipt,
    required this.onRetry,
  });

  final ImMessage item;
  final bool mine;
  final Color color;
  final bool showReadReceiptAction;
  final VoidCallback onOpenReadReceipt;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final time = item.createdAt == null
        ? ''
        : DateFormat('HH:mm').format(item.createdAt!.toLocal());
    final failed = item.localStatus == ImLocalMessageStatus.failed;
    final pending = item.localStatus == ImLocalMessageStatus.pending;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (time.isNotEmpty)
          Text(
            time,
            key: ValueKey<String>('message-time-${item.id}'),
            style: TextStyle(
              fontSize: 9,
              height: 1,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        if (mine) ...[
          const SizedBox(width: 2),
          if (failed)
            Semantics(
              button: true,
              label: '发送失败，点此重试',
              child: InkWell(
                key: ValueKey<String>('message-retry-${item.id}'),
                onTap: onRetry,
                borderRadius: BorderRadius.circular(8),
                child: const Icon(
                  Icons.error_rounded,
                  size: 13,
                  color: AppColors.error,
                ),
              ),
            )
          else if (pending)
            Semantics(
              label: '发送中，等待确认，长按可重试',
              child: Icon(
                Icons.schedule_rounded,
                key: ValueKey<String>('message-pending-${item.id}'),
                size: 12,
                color: color,
              ),
            )
          else if (showReadReceiptAction)
            Semantics(
              button: true,
              label: item.hasRecipientRead ? '已有接收人已读，查看已读详情' : '已发送，查看已读详情',
              child: InkWell(
                key: ValueKey<String>('message-read-receipt-${item.id}'),
                onTap: onOpenReadReceipt,
                borderRadius: BorderRadius.circular(8),
                child: Icon(
                  item.hasRecipientRead
                      ? Icons.done_all_rounded
                      : Icons.done_rounded,
                  size: 13,
                  color: color,
                ),
              ),
            )
          else
            Icon(Icons.done_rounded, size: 12, color: color),
        ],
      ],
    );
  }
}

class _ImageMessageContent extends ConsumerWidget {
  const _ImageMessageContent({required this.message});

  final ImMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = message.images.take(9).toList();
    return SizedBox(
      width: _mediaMessageContentWidth(message),
      child: GridView.builder(
        // Screen safe-area insets belong to the page, not each image bubble.
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: images.length == 1 ? 1 : 3,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
          mainAxisExtent: images.length == 1 ? 180 : 78,
        ),
        itemCount: images.length,
        itemBuilder: (context, index) {
          final image = images[index];
          final logicalWidth = images.length == 1 ? 210.0 : 78.0;
          final thumbnailCacheWidth =
              (logicalWidth * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(1, 1440);
          final bytes = ref.watch(
            imMessageImageProvider((
              messageId: message.id,
              imageId: image.id,
              sha256: image.sha256,
            )),
          );
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: bytes.when(
              loading: () => const ColoredBox(
                color: Color(0xFFE9EDF3),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, _) => const ColoredBox(
                color: Color(0xFFE9EDF3),
                child: Icon(Icons.broken_image_outlined),
              ),
              data: (data) => InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog.fullscreen(
                    backgroundColor: Colors.black,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          child: Image.memory(data, fit: BoxFit.contain),
                        ),
                        Positioned(
                          top: 28,
                          right: 12,
                          child: IconButton.filledTonal(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: Image.memory(
                  data,
                  key: ValueKey<String>(
                    'message-image-thumbnail:${message.id}:${image.id}',
                  ),
                  fit: BoxFit.cover,
                  cacheWidth: thumbnailCacheWidth,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MediaMessageContent extends ConsumerWidget {
  const _MediaMessageContent({
    required this.message,
    required this.audioActive,
    required this.audioLoading,
    required this.audioPlaying,
    required this.audioPosition,
    required this.audioDuration,
  });

  final ImMessage message;
  final bool audioActive;
  final bool audioLoading;
  final bool audioPlaying;
  final Duration audioPosition;
  final Duration? audioDuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachment = message.attachments.first;
    final video = message.kind == 'video';
    const color = AppColors.primary;
    final preview = video
        ? ref.watch(
            imVideoPreviewProvider((
              attachmentId: attachment.id,
              fileName: attachment.fileName,
              coverObjectId: attachment.coverObjectId,
              sha256: attachment.sha256,
              size: attachment.size,
            )),
          )
        : null;
    final previewSource = preview?.asData?.value;
    final knownAudioDuration = audioActive
        ? audioDuration
        : attachment.durationSeconds == null
        ? null
        : Duration(milliseconds: (attachment.durationSeconds! * 1000).round());
    final audioProgress =
        knownAudioDuration == null || knownAudioDuration.inMilliseconds <= 0
        ? 0.0
        : (audioPosition.inMilliseconds / knownAudioDuration.inMilliseconds)
              .clamp(0.0, 1.0);
    return SizedBox(
      width: _mediaMessageContentWidth(message),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (video && preview != null)
            preview.when(
              loading: () => const _VideoPreviewLoading(),
              error: (_, _) => const SizedBox.shrink(),
              data: (source) => source == null
                  ? const SizedBox.shrink()
                  : _VideoPreview(
                      source: source,
                      fileName: attachment.fileName,
                      durationSeconds: attachment.durationSeconds,
                    ),
            ),
          if (!video)
            Semantics(
              key: ValueKey<String>('message-audio-player-${attachment.id}'),
              button: true,
              label: audioLoading
                  ? '正在加载音频 ${attachment.fileName}'
                  : audioPlaying
                  ? '暂停音频 ${attachment.fileName}'
                  : '播放音频 ${attachment.fileName}',
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 34,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Color(0xFFEAF2FF),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: audioLoading
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                audioPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: color,
                                size: 23,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        ExcludeSemantics(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              key: ValueKey<String>(
                                'message-audio-progress-${attachment.id}',
                              ),
                              value: audioProgress,
                              minHeight: 2.5,
                              backgroundColor: const Color(0xFFD8E3F3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (audioActive)
                              '${_durationLabel(audioPosition)} / ${_durationLabel(knownAudioDuration)}',
                            if (!audioActive && knownAudioDuration != null)
                              _durationLabel(knownAudioDuration),
                            _fileSize(attachment.size),
                          ].join(' · '),
                          style: const TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else if (previewSource == null && preview?.isLoading != true)
            Row(
              children: [
                Icon(Icons.play_circle_outline, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          if (attachment.durationSeconds != null)
                            '${attachment.durationSeconds!.round()} 秒',
                          _fileSize(attachment.size),
                        ].join(' · '),
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new_rounded, color: color, size: 18),
              ],
            ),
          if (!video &&
              message.content.trim().isNotEmpty &&
              message.content.trim() != attachment.fileName.trim()) ...[
            const SizedBox(height: 6),
            Text(message.content, style: TextStyle(color: color)),
          ],
        ],
      ),
    );
  }
}

String _durationLabel(Duration? value) {
  if (value == null) return '--:--';
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({
    required this.source,
    required this.fileName,
    required this.durationSeconds,
  });

  final ImVideoPreviewSource source;
  final String fileName;
  final double? durationSeconds;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '视频预览，$fileName',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        key: const ValueKey('message-video-preview'),
        width: 200,
        height: 112,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (source.bytes case final bytes?)
              Image.memory(
                bytes,
                fit: BoxFit.cover,
                cacheWidth: (200 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                filterQuality: FilterQuality.low,
              )
            else
              Image.file(
                File(source.filePath),
                fit: BoxFit.cover,
                cacheWidth: (200 * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                filterQuality: FilterQuality.low,
              ),
            const ColoredBox(color: Color(0x1F000000)),
            Center(
              child: Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xD9FFFFFF),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
              ),
            ),
            if (durationSeconds != null)
              Positioned(
                right: 7,
                bottom: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x99000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _videoDuration(durationSeconds!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
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

class _VideoPreviewLoading extends StatelessWidget {
  const _VideoPreviewLoading();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 200,
    height: 112,
    child: ColoredBox(
      color: Color(0xFFE9EDF3),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    ),
  );
}

class _AttachmentContent extends StatelessWidget {
  const _AttachmentContent({required this.item});

  final ImMessage item;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.insert_drive_file_rounded, color: AppColors.primary),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.attachmentName.isEmpty ? item.content : item.attachmentName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item.attachmentSize != null)
              Text(
                _fileSize(item.attachmentSize!),
                style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
              ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Icon(Icons.download_rounded, size: 18, color: AppColors.secondaryText),
    ],
  );
}

class _ContactCardContent extends StatelessWidget {
  const _ContactCardContent({required this.card});

  final ImContactCard card;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      InitialAvatar(
        name: card.displayName,
        radius: 20,
        avatarKey: card.avatarKey,
        avatarDataUrl: card.avatarDataUrl,
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              [
                card.departmentName,
                card.username,
              ].where((value) => value.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.secondaryText),
            ),
          ],
        ),
      ),
    ],
  );
}

class _MentionPickerSheet extends ConsumerStatefulWidget {
  const _MentionPickerSheet({
    required this.conversationId,
    required this.members,
    required this.memberTotal,
    required this.allowMentionAll,
  });

  final String conversationId;
  final List<ImMember> members;
  final int memberTotal;
  final bool allowMentionAll;

  @override
  ConsumerState<_MentionPickerSheet> createState() =>
      _MentionPickerSheetState();
}

class _MentionPickerSheetState extends ConsumerState<_MentionPickerSheet> {
  String _query = '';
  String _effectiveQuery = '';
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _updateQuery(String value) {
    final query = value.trim();
    setState(() => _query = query);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _effectiveQuery = query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final usesServerPaging = widget.memberTotal > widget.members.length;
    final remotePage = usesServerPaging
        ? ref.watch(
            conversationMemberPageProvider((
              conversationId: widget.conversationId,
              page: 1,
              pageSize: 50,
              keyword: _effectiveQuery,
            )),
          )
        : null;
    final query = _effectiveQuery.toLowerCase();
    final localMembers = widget.members
        .where(
          (item) =>
              query.isEmpty ||
              item.displayName.toLowerCase().contains(query) ||
              item.username.toLowerCase().contains(query) ||
              item.departmentName.toLowerCase().contains(query),
        )
        .toList(growable: false);
    final members = usesServerPaging
        ? remotePage?.value?.items ??
              (_effectiveQuery.isEmpty ? widget.members : const <ImMember>[])
        : localMembers;
    final resultTotal = usesServerPaging
        ? remotePage?.value?.total ?? widget.memberTotal
        : members.length;
    final searching = _query != _effectiveQuery;
    final loading = searching || (remotePage?.isLoading ?? false);
    final loadFailed = remotePage?.hasError ?? false;
    final hasMore = resultTotal > members.length;
    final offset = widget.allowMentionAll ? 1 : 0;
    return SafeArea(
      child: SizedBox(
        key: const Key('mention-picker-sheet'),
        height: MediaQuery.sizeOf(context).height * .68,
        child: Column(
          children: [
            const SizedBox(height: 8),
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
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '提及成员',
                      style: TextStyle(
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: MobileSearchField(
                key: const Key('mention-picker-search'),
                hintText: '搜索姓名、部门或账号',
                autofocus: false,
                onChanged: _updateQuery,
              ),
            ),
            Expanded(
              child: loading && members.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : loadFailed && members.isEmpty
                  ? const EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: '群成员加载失败',
                    )
                  : members.isEmpty && !widget.allowMentionAll
                  ? const EmptyState(
                      icon: Icons.person_search_outlined,
                      title: '没有匹配的群成员',
                    )
                  : ListView.builder(
                      key: const Key('mention-picker-list'),
                      itemCount: members.length + offset + (hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (widget.allowMentionAll && index == 0) {
                          return SizedBox(
                            key: const Key('mention-picker-all'),
                            height: 50,
                            child: ListTile(
                              dense: true,
                              visualDensity: VisualDensity.compact,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              leading: const CircleAvatar(
                                radius: 17,
                                child: Text('@'),
                              ),
                              title: const Text(
                                '@全体',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                '提醒群内全部成员',
                                style: TextStyle(fontSize: 11),
                              ),
                              onTap: () => Navigator.pop(
                                context,
                                const _MentionChoice.all(),
                              ),
                            ),
                          );
                        }
                        if (index >= members.length + offset) {
                          return const SizedBox(
                            height: 40,
                            child: Center(
                              child: Text(
                                '仅显示前 50 位，请输入姓名或账号继续查找',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ),
                          );
                        }
                        final member = members[index - offset];
                        return SizedBox(
                          key: ValueKey('mention-picker-member-${member.id}'),
                          height: 50,
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            minLeadingWidth: 34,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            leading: Consumer(
                              builder: (context, ref, _) => InitialAvatar(
                                name: member.displayName,
                                radius: 17,
                                online: watchMemberPresence(
                                  ref,
                                  member,
                                  transportAvailable:
                                      ref.watch(
                                        imRealtimeAvailabilityProvider,
                                      ) ==
                                      ImRealtimeAvailability.available,
                                ).online,
                                avatarKey: member.avatarKey,
                                avatarDataUrl: member.avatarDataUrl,
                              ),
                            ),
                            title: Text(
                              member.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              [
                                member.departmentName,
                                member.username,
                              ].where((item) => item.isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.secondaryText,
                              ),
                            ),
                            onTap: () => Navigator.pop(
                              context,
                              _MentionChoice.member(member),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactPickerSheet extends StatefulWidget {
  const _ContactPickerSheet({required this.contacts});

  final List<ImMember> contacts;

  @override
  State<_ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<_ContactPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final contacts = widget.contacts
        .where(
          (item) =>
              query.isEmpty ||
              item.displayName.toLowerCase().contains(query) ||
              item.username.toLowerCase().contains(query) ||
              item.departmentName.toLowerCase().contains(query),
        )
        .toList();
    return SafeArea(
      child: SizedBox(
        key: const Key('chat-contact-picker-sheet'),
        height: MediaQuery.sizeOf(context).height * .68,
        child: Column(
          children: [
            const SizedBox(height: 8),
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
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '分享联系人',
                      style: TextStyle(
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: MobileSearchField(
                key: const Key('chat-contact-picker-search'),
                hintText: '搜索姓名、部门或账号',
                autofocus: false,
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final member = contacts[index];
                  return SizedBox(
                    key: ValueKey('chat-contact-picker-member-${member.id}'),
                    height: 50,
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      minLeadingWidth: 34,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      leading: Consumer(
                        builder: (context, ref, _) => InitialAvatar(
                          name: member.displayName,
                          radius: 17,
                          online: watchMemberPresence(
                            ref,
                            member,
                            transportAvailable:
                                ref.watch(imRealtimeAvailabilityProvider) ==
                                ImRealtimeAvailability.available,
                          ).online,
                          avatarKey: member.avatarKey,
                          avatarDataUrl: member.avatarDataUrl,
                        ),
                      ),
                      title: Text(
                        member.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        [
                          member.departmentName,
                          member.username,
                        ].where((value) => value.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, member),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _contentType(String? extension) => switch (extension?.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'png' => 'image/png',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  'heic' || 'heif' => 'image/heic',
  'bmp' => 'image/bmp',
  'mp4' || 'm4v' => 'video/mp4',
  'webm' => 'video/webm',
  'mov' => 'video/quicktime',
  'mkv' => 'video/x-matroska',
  'mp3' => 'audio/mpeg',
  'm4a' => 'audio/mp4',
  'wav' => 'audio/wav',
  'ogg' || 'oga' => 'audio/ogg',
  'flac' => 'audio/flac',
  'pdf' => 'application/pdf',
  'doc' => 'application/msword',
  'docx' =>
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls' => 'application/vnd.ms-excel',
  'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'zip' => 'application/zip',
  'txt' => 'text/plain',
  _ => 'application/octet-stream',
};

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _videoDuration(double seconds) {
  final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
  final minutes = total ~/ 60;
  final remainder = total % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(8),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.groups_rounded,
      size: size * .62,
      color: AppColors.primary,
    ),
  );
}
