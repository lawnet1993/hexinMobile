import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart'
    show debugPrint, kReleaseMode, kProfileMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/demo/preview_data.dart';
import '../../../core/network/collaboration_client.dart';
import '../../../core/network/mobile_read_retry.dart';
import '../../../core/storage/im_cache_cipher.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/collaboration_models.dart';
import 'im_local_store.dart';
import 'im_message_image_cache.dart';
import 'im_message_window_retention.dart';
import 'im_decoded_message_cache.dart';
import 'im_outbox_file_store.dart';
import 'im_upload_diagnostics.dart';
import 'im_send_timing.dart';
import 'im_read_diagnostics.dart';
import 'im_presence_projection.dart';
import 'im_presence_diagnostics.dart';
import 'im_member_presence.dart';
import 'im_video_thumbnail.dart';
import 'oa_attachment_file_store.dart';
import 'oa_local_store.dart';
import 'oa_sync_timing.dart';

const _demoSession = MobileSession(
  accessToken: 'demo-token',
  deviceId: '00000000-0000-0000-0000-000000000001',
  userId: '00000000-0000-0000-0000-000000000002',
  displayName: '林晨',
  username: 'term.sh01',
  policySignatureKey: '',
  imApiUrl: '',
  oaApiUrl: '',
);

Future<T> _demoValue<T>(T value) async {
  final delay = AppEnvironment.demoDataDelayMilliseconds;
  if (delay > 0) {
    await Future<void>.delayed(Duration(milliseconds: delay));
  }
  return value;
}

final collaborationAccountScopeProvider = Provider<String>((ref) {
  if (AppEnvironment.demoMode) return _demoSession.userId;
  return ref.watch(
    authControllerProvider.select((state) => state.value?.userId ?? ''),
  );
});

// Refreshing credentials must not invalidate already rendered media, but a
// different account or service environment must never reuse its cached bytes.
String imMediaCacheNamespace(MobileSession session) => crypto.sha256
    .convert(
      utf8.encode(
        jsonEncode([
          AppEnvironment.storageNamespace,
          session.userId.trim(),
          session.imApiUrl.trim(),
          session.oaApiUrl.trim(),
        ]),
      ),
    )
    .toString();

final imMediaScopeProvider = Provider((ref) {
  final account = ref.watch(collaborationAccountScopeProvider);
  final endpoints = ref.watch(
    authControllerProvider.select(
      (state) => (state.value?.imApiUrl ?? '', state.value?.oaApiUrl ?? ''),
    ),
  );
  return (account, endpoints);
});

enum ImRealtimeAvailability { connecting, available, unavailable }

enum OaSyncAvailability { connecting, available, unavailable }

final imRealtimeAvailabilityControllerProvider =
    NotifierProvider<ImRealtimeAvailabilityController, ImRealtimeAvailability>(
      ImRealtimeAvailabilityController.new,
    );

final imRealtimeAvailabilityProvider = Provider<ImRealtimeAvailability>((ref) {
  return ref.watch(imRealtimeAvailabilityControllerProvider);
});

class ImRealtimeAvailabilityController
    extends Notifier<ImRealtimeAvailability> {
  @override
  ImRealtimeAvailability build() => ImRealtimeAvailability.connecting;

  void markConnecting() => state = ImRealtimeAvailability.connecting;

  void markAvailable() => state = ImRealtimeAvailability.available;

  void markUnavailable() => state = ImRealtimeAvailability.unavailable;
}

final oaSyncAvailabilityControllerProvider =
    NotifierProvider<OaSyncAvailabilityController, OaSyncAvailability>(
      OaSyncAvailabilityController.new,
    );

final oaSyncAvailabilityProvider = Provider<OaSyncAvailability>((ref) {
  return ref.watch(oaSyncAvailabilityControllerProvider);
});

class OaSyncAvailabilityController extends Notifier<OaSyncAvailability> {
  @override
  OaSyncAvailability build() => OaSyncAvailability.connecting;

  void markConnecting() => state = OaSyncAvailability.connecting;

  void markAvailable() => state = OaSyncAvailability.available;

  void markUnavailable() => state = OaSyncAvailability.unavailable;
}

final oaApprovalRevisionsProvider =
    NotifierProvider<OaApprovalRevisions, Map<String, int>>(
      OaApprovalRevisions.new,
    );

final oaApprovalRevisionProvider = Provider.family<int, String>((ref, id) {
  return ref.watch(
    oaApprovalRevisionsProvider.select((value) => value[id] ?? 0),
  );
});

class OaApprovalRevisions extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    ref.watch(collaborationAccountScopeProvider);
    return const {};
  }

  void changed(Set<String> requestIds) {
    if (requestIds.isEmpty) return;
    state = {...state, for (final id in requestIds) id: (state[id] ?? 0) + 1};
  }
}

final imDecodedMessageCacheProvider = Provider<ImDecodedMessageCache>((ref) {
  final cache = ImDecodedMessageCache();
  ref.onDispose(cache.clear);
  return cache;
});

final imLocalStoreProvider = Provider<ImLocalStore>((ref) {
  final sessionStore = ref.read(secureSessionStoreProvider);
  var decodeSamples = 0;
  final store = ImLocalStore(
    cipher: AesGcmImCacheCipher(sessionStore.readOrCreateImCacheKey),
    decodedMessageCache: ref.read(imDecodedMessageCacheProvider),
    onMessageRead: kProfileMode
        ? (rows, cacheHits, durationMicros) {
            if (decodeSamples++ < 80) {
              debugPrint(
                'MOBILE_IM_ROW_DECODE ${jsonEncode({'rows': rows, 'cacheHits': cacheHits, 'durationMicros': durationMicros})}',
              );
            }
          }
        : null,
  );
  // Repositories retain this store through ref.read, without an active UI
  // listener. A ref.listen would pause with that provider and miss logout.
  // Keep the security cleanup subscription active until the store is disposed.
  final accountSubscription = ref.container.listen<String>(
    collaborationAccountScopeProvider,
    (_, _) => store.clearDecodedMessages(),
  );
  ref.onDispose(accountSubscription.close);
  ref.onDispose(store.close);
  return store;
});

final oaLocalStoreProvider = Provider<OaLocalStore>((ref) {
  final sessionStore = ref.read(secureSessionStoreProvider);
  final store = OaLocalStore(
    cipher: AesGcmImCacheCipher(sessionStore.readOrCreateImCacheKey),
  );
  ref.onDispose(store.close);
  return store;
});

final oaRepositoryProvider = Provider<OaRepository>((ref) {
  return OaRepository(
    ref.read(collaborationClientProvider),
    ref.read(secureSessionStoreProvider),
    ref.read(oaLocalStoreProvider),
  );
});

typedef OaWorkflowPreviewLoader = Future<OaWorkflowPreview> Function({
  required String applicationKey,
  required OaApprovalTemplate template,
  required Map<String, Object?> formData,
});

final oaWorkflowPreviewLoaderProvider = Provider<OaWorkflowPreviewLoader>((
  ref,
) {
  final repository = ref.read(oaRepositoryProvider);
  return repository.previewWorkflow;
});

typedef OaDraftLoader = Future<OaApprovalDraft?> Function(String templateId);
typedef OaApprovalRequestLoader = Future<OaApprovalRequest> Function(String id);
typedef OaAttachmentThumbnailBytesLoader = Future<Uint8List> Function(
  String attachmentId,
);

final oaDraftLoaderProvider = Provider<OaDraftLoader>((ref) {
  final repository = ref.read(oaRepositoryProvider);
  return repository.draftForTemplate;
});

final oaApprovalRequestLoaderProvider = Provider<OaApprovalRequestLoader>((
  ref,
) {
  final repository = ref.read(oaRepositoryProvider);
  return repository.approvalRequestCacheFirst;
});

final oaApprovalRequestRefresherProvider = Provider<OaApprovalRequestLoader>((
  ref,
) {
  return ref.read(oaRepositoryProvider).refreshApprovalRequest;
});

final oaAttachmentThumbnailBytesLoaderProvider =
    Provider<OaAttachmentThumbnailBytesLoader>((ref) {
      final repository = ref.read(oaRepositoryProvider);
      return repository.downloadAttachmentThumbnail;
    });

typedef OaDraftSaver = Future<OaApprovalDraft> Function({
  String? id,
  required String applicationKey,
  required OaApprovalTemplate template,
  required String title,
  required Map<String, Object?> formData,
  required List<OaLocalAttachment> attachments,
});

final oaDraftSaverProvider = Provider<OaDraftSaver>((ref) {
  final repository = ref.read(oaRepositoryProvider);
  return repository.saveDraft;
});

final markApprovalCcReadActionProvider =
    Provider<Future<void> Function(String)>((ref) {
      final repository = ref.read(oaRepositoryProvider);
      return repository.markApprovalCcRead;
    });

final imRepositoryProvider = Provider<ImRepository>((ref) {
  return ImRepository(
    ref.read(collaborationClientProvider),
    ref.read(secureSessionStoreProvider),
    ref.read(imLocalStoreProvider),
    memberPresence: () => ref.mounted
        ? ref.read(imMemberPresenceProjectionProvider.notifier)
        : null,
  );
});

final conversationVisibleReadMarkerProvider =
    Provider<Future<void> Function(String, int)>((ref) {
      return ref.read(imRepositoryProvider).markRead;
    });

final conversationPresenceEnterActionProvider =
    Provider<Future<void> Function(String)>((ref) {
      return ref.read(imRepositoryProvider).enterConversation;
    });

final conversationPresenceLeaveActionProvider =
    Provider<Future<void> Function()>((ref) {
      return ref.read(imRepositoryProvider).leaveActiveConversation;
    });

typedef ImMemberProfileLoader = Future<ImMemberProfile> Function(
  String memberId,
);

final imMemberProfileLoaderProvider = Provider<ImMemberProfileLoader>((ref) {
  return ref.read(imRepositoryProvider).memberProfile;
});

typedef ImGroupManagementCapabilitiesLoader =
    Future<ImGroupManagementCapabilities> Function(String conversationId);
typedef ImGroupMutedMembersPageLoader =
    Future<ImGroupManagementPage<ImMutedGroupMember>> Function(
      String conversationId, {
      int page,
      int pageSize,
    });
typedef ImGroupManagersPageLoader =
    Future<ImGroupManagementPage<ImMember>> Function(
      String conversationId, {
      int page,
      int pageSize,
    });
typedef ImGroupJoinRequestsPageLoader =
    Future<ImGroupManagementPage<ImGroupJoinRequest>> Function(
      String conversationId, {
      int page,
      int pageSize,
    });
typedef ImGroupNoticesPageLoader =
    Future<ImGroupManagementPage<ImGroupNotice>> Function(
      String conversationId, {
      int page,
      int pageSize,
    });
typedef ImGroupProfileRefresher = Future<ImGroupProfile?> Function(
  String conversationId,
);
typedef ImMessageReadReceiptLoader = Future<ImMessageReadReceipt> Function(
  String messageId,
);

final imGroupManagementCapabilitiesLoaderProvider =
    Provider<ImGroupManagementCapabilitiesLoader>((ref) {
      return ref.read(imRepositoryProvider).groupManagementCapabilities;
    });

final imGroupMutedMembersPageLoaderProvider =
    Provider<ImGroupMutedMembersPageLoader>((ref) {
      return ref.read(imRepositoryProvider).groupMutedMembers;
    });

final imGroupManagersPageLoaderProvider = Provider<ImGroupManagersPageLoader>((
  ref,
) {
  return ref.read(imRepositoryProvider).groupManagersPage;
});

final imGroupJoinRequestsPageLoaderProvider =
    Provider<ImGroupJoinRequestsPageLoader>((ref) {
      return ref.read(imRepositoryProvider).groupJoinRequests;
    });

final imGroupNoticesPageLoaderProvider = Provider<ImGroupNoticesPageLoader>((
  ref,
) {
  return ref.read(imRepositoryProvider).groupNotices;
});

final imGroupProfileRefresherProvider = Provider<ImGroupProfileRefresher>((
  ref,
) {
  return ref.read(imRepositoryProvider).refreshGroupProfile;
});

final imMessageReadReceiptLoaderProvider = Provider<ImMessageReadReceiptLoader>(
  (ref) {
    return ref.read(imRepositoryProvider).messageReadReceipts;
  },
);

final oaBootstrapProvider = FutureProvider<OaBootstrap>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return _demoValue(PreviewData.oaBootstrap);
  return ref.read(oaRepositoryProvider).bootstrapCacheFirst();
}, retry: mobileReadRetry);

final oaApplicationCatalogProvider = FutureProvider<OaApplicationCatalog>((
  ref,
) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return PreviewData.oaCatalog;
  return ref.read(oaRepositoryProvider).appCatalogCacheFirst();
}, retry: mobileReadRetry);

final oaApplicationCatalogRefresherProvider =
    Provider<Future<OaApplicationCatalog> Function()>((ref) {
      if (AppEnvironment.demoMode) return () async => PreviewData.oaCatalog;
      return ref.read(oaRepositoryProvider).refreshAppCatalog;
    });

final oaApprovalRequestProvider = FutureProvider.autoDispose
    .family<OaApprovalRequest, String>((ref, id) async {
      _retainForHotReopen(ref);
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) {
        return PreviewData.oaBootstrap.approvalRequests.firstWhere(
          (item) => item.id == id,
          orElse: () => throw StateError('审批申请不存在'),
        );
      }
      return ref.read(oaApprovalRequestLoaderProvider)(id);
    });

final oaNotificationsProvider = FutureProvider<List<OaNotification>>((
  ref,
) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return PreviewData.oaBootstrap.notifications;
  return ref.read(oaRepositoryProvider).notificationsCacheFirst();
}, retry: mobileReadRetry);

final oaNotificationPageProvider =
    FutureProvider.family<
      OaNotificationPage,
      ({String? cursor, bool unreadOnly})
    >((ref, key) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) {
        final items = PreviewData.oaBootstrap.notifications
            .where((item) => !key.unreadOnly || !item.isRead)
            .toList();
        return _demoValue(
          OaNotificationPage(items: items, nextCursor: null, hasMore: false),
        );
      }
      return ref
          .read(oaRepositoryProvider)
          .notificationPageCacheFirst(
            cursor: key.cursor,
            unreadOnly: key.unreadOnly,
          );
    });

typedef OaApprovalRequestsPageKey = ({
  String? cursor,
  String view,
  String search,
  String applicationKey,
  String status,
  DateTime? from,
});

final oaApprovalRequestsPageProvider =
    FutureProvider.family<OaApprovalRequestPage, OaApprovalRequestsPageKey>((
      ref,
      key,
    ) async {
      ref.watch(collaborationAccountScopeProvider);
      return ref
          .read(oaRepositoryProvider)
          .approvalRequestsPage(
            cursor: key.cursor,
            view: key.view,
            search: key.search,
            applicationKey: key.applicationKey,
            status: key.status,
            from: key.from,
          );
    });

final oaAttendanceOverviewProvider = FutureProvider<OaAttendanceOverview>((
  ref,
) async {
  ref.watch(collaborationAccountScopeProvider);
  return ref.read(oaRepositoryProvider).attendanceOverviewCacheFirst();
});

final oaBehaviorDefinitionsProvider =
    FutureProvider<List<OaBehaviorDefinition>>((ref) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) return const [];
      return ref.read(oaRepositoryProvider).behaviorDefinitions();
    });

final oaActiveBehaviorSessionsProvider =
    FutureProvider<List<OaBehaviorSession>>((ref) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) return const [];
      return ref.read(oaRepositoryProvider).activeBehaviorSessions();
    });

final oaBehaviorSessionHistoryProvider =
    FutureProvider<List<OaBehaviorSession>>((ref) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) return const [];
      final now = DateTime.now();
      return ref
          .read(oaRepositoryProvider)
          .behaviorSessionHistory(
            DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(const Duration(days: 30)),
            now,
          );
    });

final oaActiveInspectionsProvider = FutureProvider<List<OaActiveInspection>>((
  ref,
) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return const [];
  return ref.read(oaRepositoryProvider).activeInspections();
});

final oaDraftsProvider = FutureProvider<List<OaApprovalDraft>>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return const [];
  return ref.read(oaRepositoryProvider).drafts();
});

final oaOutboxProvider = FutureProvider<List<OaOutboxItem>>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return const [];
  return ref.read(oaRepositoryProvider).outbox();
});

final oaPendingNotificationReadsProvider = FutureProvider<int>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return 0;
  return ref.read(oaRepositoryProvider).pendingNotificationReadCount();
});

final imBootstrapProvider = FutureProvider<ImBootstrap>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return _demoValue(PreviewData.imBootstrap);
  return ref.read(imRepositoryProvider).bootstrapCacheFirst();
}, retry: mobileReadRetry);

final imDepartmentsProvider = FutureProvider<List<ImDepartment>>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return PreviewData.imDepartments;
  return ref.read(imRepositoryProvider).departmentsCacheFirst();
}, retry: mobileReadRetry);

final pendingFriendApplicationsProvider =
    FutureProvider<List<ImFriendApplication>>((ref) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) return const [];
      return ref.read(imRepositoryProvider).pendingFriendApplications();
    }, retry: mobileReadRetry);

final conversationMessagesProvider =
    FutureProvider.family<List<ImMessage>, String>((ref, id) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) return PreviewData.conversationMessages(id);
      return ref.read(imRepositoryProvider).messagesCacheFirst(id);
    }, retry: mobileReadRetry);

typedef ConversationMessageWindowKey = ({String conversationId, int take});
typedef ConversationAnchoredWindowKey = ({
  String conversationId,
  int take,
  int beforeSequence,
});
typedef ConversationAnchoredWindowLoader = Future<List<ImMessage>> Function(
  String conversationId, {
  required int take,
  required int beforeSequence,
});

final conversationAnchoredWindowLoaderProvider =
    Provider<ConversationAnchoredWindowLoader>((ref) {
      return ref.read(imRepositoryProvider).messagesBeforeCacheFirst;
    });

// An unread anchor must not drag the whole unread backlog into the first frame.
// Keep a bounded initial slice around it, then page in either direction.
final conversationAnchoredWindowProvider = FutureProvider.autoDispose
    .family<List<ImMessage>, ConversationAnchoredWindowKey>((ref, key) async {
      ref.watch(collaborationAccountScopeProvider);
      ref.watch(conversationMessageRevisionProvider(key.conversationId));
      if (AppEnvironment.demoMode) {
        final all = PreviewData.conversationMessages(key.conversationId)
            .where(
              (item) => item.sequence > 0 && item.sequence < key.beforeSequence,
            )
            .toList();
        return all.length <= key.take
            ? all
            : all.sublist(all.length - key.take);
      }
      return ref.read(conversationAnchoredWindowLoaderProvider)(
        key.conversationId,
        take: key.take,
        beforeSequence: key.beforeSequence,
      );
    }, retry: mobileReadRetry);
typedef ConversationMessageWindowLoader = Future<List<ImMessage>> Function(
  String conversationId, {
  int? take,
});

final conversationMessageWindowLoaderProvider =
    Provider<ConversationMessageWindowLoader>((ref) {
      final repository = ref.read(imRepositoryProvider);
      return repository.messagesCacheFirst;
    });

typedef ConversationOlderMessageLoader = Future<List<ImMessage>> Function(
  String conversationId, {
  int? beforeSequence,
});

final conversationOlderMessageLoaderProvider =
    Provider<ConversationOlderMessageLoader>((ref) {
      final repository = ref.read(imRepositoryProvider);
      return repository.loadOlderMessages;
    });

typedef ConversationLatestReconciler = Future<bool> Function(
  String conversationId,
);

final conversationLatestReconcilerProvider =
    Provider<ConversationLatestReconciler>((ref) {
      final repository = ref.read(imRepositoryProvider);
      return repository.reconcileLatestMessages;
    });

final conversationMessageRevisionProvider = Provider.autoDispose
    .family<Object, String>((ref, conversationId) => Object());

final imMessageWindowRetentionProvider = Provider<ImMessageWindowRetention>((
  ref,
) {
  ref.watch(collaborationAccountScopeProvider);
  var diagnosticSamples = 0;
  final retention = ImMessageWindowRetention(
    onChanged: kProfileMode
        ? (windows, messages) {
            if (diagnosticSamples++ < 80) {
              debugPrint(
                'MOBILE_IM_WINDOW_CACHE ${jsonEncode({'windows': windows, 'messages': messages})}',
              );
            }
          }
        : null,
  );
  ref.onDispose(retention.dispose);
  return retention;
});

final conversationMessageWindowProvider = FutureProvider.autoDispose
    .family<List<ImMessage>, ConversationMessageWindowKey>((ref, key) async {
      ref.watch(collaborationAccountScopeProvider);
      ref.watch(conversationMessageRevisionProvider(key.conversationId));
      final keepAlive = ref.keepAlive();
      final lease = ref
          .watch(imMessageWindowRetentionProvider)
          .acquire(key.conversationId, keepAlive.close);
      ref.onCancel(lease.idle);
      ref.onResume(lease.resume);
      ref.onDispose(lease.release);
      try {
        final List<ImMessage> messages;
        if (AppEnvironment.demoMode) {
          final all = PreviewData.conversationMessages(key.conversationId);
          messages = all.length <= key.take
              ? all
              : all.sublist(all.length - key.take);
        } else {
          messages = await ref.read(conversationMessageWindowLoaderProvider)(
            key.conversationId,
            take: key.take,
          );
        }
        lease.loaded(messages.length);
        return messages;
      } catch (_) {
        lease.release();
        rethrow;
      }
    }, retry: mobileReadRetry);

typedef ImMediaCacheAccountLoader = Future<String> Function();
typedef ImMessageImageBytesLoader = Future<Uint8List> Function(
  String messageId,
  String imageId,
);
typedef ImMediaAttachmentBytesLoader = Future<Uint8List> Function(
  String attachmentId, {
  required bool cover,
});

final imMediaCacheAccountLoaderProvider = Provider<ImMediaCacheAccountLoader>((
  ref,
) {
  final store = ref.read(secureSessionStoreProvider);
  return () async {
    final session = await store.readSession();
    final accountId = session?.userId.trim() ?? '';
    if (accountId.isEmpty) throw StateError('登录状态已失效，请重新登录');
    return imMediaCacheNamespace(session!);
  };
});

final imMessageImageBytesLoaderProvider = Provider<ImMessageImageBytesLoader>((
  ref,
) {
  final repository = ref.read(imRepositoryProvider);
  return repository.downloadMessageImage;
});

final imMediaAttachmentBytesLoaderProvider =
    Provider<ImMediaAttachmentBytesLoader>((ref) {
      final repository = ref.read(imRepositoryProvider);
      return repository.downloadMediaAttachment;
    });

final imBinaryMemoryCacheProvider = Provider<ImBinaryMemoryCache>((ref) {
  ref.watch(imMediaScopeProvider);
  final cache = ImBinaryMemoryCache();
  ref.onDispose(cache.clear);
  return cache;
});

final imMessageImageDiskCacheProvider = Provider<ImMessageImageDiskCache>((
  ref,
) {
  return ImMessageImageDiskCache();
});

typedef ImMessageImageDiskCacheReader = Future<Uint8List?> Function({
  required String accountId,
  required String imageId,
  required String sha256Value,
});
typedef ImMessageImageDiskCacheWriter = Future<void> Function({
  required String accountId,
  required String imageId,
  required String sha256Value,
  required Uint8List bytes,
});

final imMessageImageDiskCacheReaderProvider =
    Provider<ImMessageImageDiskCacheReader>((ref) {
      return ref.read(imMessageImageDiskCacheProvider).read;
    });

final imMessageImageDiskCacheWriterProvider =
    Provider<ImMessageImageDiskCacheWriter>((ref) {
      return ref.read(imMessageImageDiskCacheProvider).write;
    });

final imMessageImageProvider = FutureProvider.autoDispose
    .family<Uint8List, ({String messageId, String imageId, String sha256})>((
      ref,
      key,
    ) async {
      ref.watch(imMediaScopeProvider);
      final load = await _MediaLoad.start(ref);
      final accountId = load.accountId;
      final cache = ref.read(imBinaryMemoryCacheProvider);
      final cacheKey =
          'image:${key.messageId}:${key.imageId}'
          '${key.sha256.isEmpty ? '' : ':${key.sha256}'}';
      final cached = cache.read(accountId, cacheKey);
      if (cached != null) return cached;
      if (parseImOutboxSyntheticFileId(key.imageId) != null) {
        final bytes = await ref.read(imMessageImageBytesLoaderProvider)(
          key.messageId,
          key.imageId,
        );
        await load.check();
        cache.write(accountId, cacheKey, bytes);
        return bytes;
      }
      final diskCached = await ref.read(imMessageImageDiskCacheReaderProvider)(
        accountId: accountId,
        imageId: key.imageId,
        sha256Value: key.sha256,
      );
      await load.check();
      if (diskCached != null) {
        cache.write(accountId, cacheKey, diskCached);
        return diskCached;
      }
      final bytes = await ref.read(imMessageImageBytesLoaderProvider)(
        key.messageId,
        key.imageId,
      );
      await load.check();
      cache.write(accountId, cacheKey, bytes);
      await ref.read(imMessageImageDiskCacheWriterProvider)(
        accountId: accountId,
        imageId: key.imageId,
        sha256Value: key.sha256,
        bytes: bytes,
      );
      await load.check();
      return bytes;
    }, retry: mobileReadRetry);

final imMediaAttachmentProvider = FutureProvider.autoDispose
    .family<Uint8List, ({String attachmentId, bool cover})>((ref, key) async {
      ref.watch(imMediaScopeProvider);
      final load = await _MediaLoad.start(ref);
      final accountId = load.accountId;
      final cache = ref.read(imBinaryMemoryCacheProvider);
      final cacheKey = 'media:${key.attachmentId}:${key.cover ? 1 : 0}';
      final cached = cache.read(accountId, cacheKey);
      if (cached != null) return cached;
      final bytes = await ref.read(imMediaAttachmentBytesLoaderProvider)(
        key.attachmentId,
        cover: key.cover,
      );
      await load.check();
      cache.write(accountId, cacheKey, bytes);
      return bytes;
    }, retry: mobileReadRetry);

// An invalidated account provider may still finish its asynchronous download.
// Never let that retired generation mutate the currently active account cache.
void _requireActiveMediaLoad(Ref ref) {
  if (!ref.mounted) throw const SessionChangedException();
}

final class _MediaLoad {
  _MediaLoad(this.ref, this.accountLoader, this.accountId);
  final Ref ref;
  final ImMediaCacheAccountLoader accountLoader;
  final String accountId;

  static Future<_MediaLoad> start(Ref ref) async {
    final loader = ref.read(imMediaCacheAccountLoaderProvider);
    final account = await loader();
    _requireActiveMediaLoad(ref);
    return _MediaLoad(ref, loader, account);
  }

  Future<void> check() async {
    _requireActiveMediaLoad(ref);
    // The secure store can change before auth state notifies the widget tree.
    final current = await accountLoader();
    _requireActiveMediaLoad(ref);
    if (current != accountId) throw const SessionChangedException();
  }
}

final class ImBinaryMemoryCache {
  ImBinaryMemoryCache({this.maxEntries = 48, this.maxBytes = 32 * 1024 * 1024})
    : assert(maxEntries > 0),
      assert(maxBytes > 0);

  final int maxEntries;
  final int maxBytes;
  final LinkedHashMap<String, Uint8List> _entries = LinkedHashMap();
  String _accountId = '';
  int _totalBytes = 0;

  int get entryCount => _entries.length;
  int get totalBytes => _totalBytes;

  Uint8List? read(String accountId, String key) {
    _selectAccount(accountId);
    final value = _entries.remove(key);
    if (value == null) return null;
    _entries[key] = value;
    return value;
  }

  void write(String accountId, String key, Uint8List value) {
    _selectAccount(accountId);
    final previous = _entries.remove(key);
    if (previous != null) _totalBytes -= previous.lengthInBytes;
    if (value.isEmpty || value.lengthInBytes > maxBytes) return;
    _entries[key] = value;
    _totalBytes += value.lengthInBytes;
    while (_entries.length > maxEntries || _totalBytes > maxBytes) {
      final oldestKey = _entries.keys.first;
      final removed = _entries.remove(oldestKey);
      if (removed != null) _totalBytes -= removed.lengthInBytes;
    }
  }

  void clear() {
    _entries.clear();
    _totalBytes = 0;
    _accountId = '';
  }

  void _selectAccount(String accountId) {
    if (_accountId == accountId) return;
    _entries.clear();
    _totalBytes = 0;
    _accountId = accountId;
  }
}

typedef ImVideoPreviewKey = ({
  String attachmentId,
  String fileName,
  String coverObjectId,
  String coverSha256,
  int size,
});

final class ImVideoPreviewSource {
  const ImVideoPreviewSource.file(this.filePath) : bytes = null;

  const ImVideoPreviewSource.memory(this.bytes) : filePath = '';

  final String filePath;
  final Uint8List? bytes;
}

final imVideoPreviewCacheReaderProvider =
    Provider<Future<String?> Function(String)>(
      (ref) => readImVideoPreviewCachePath,
    );
final imVideoPreviewCacheWriterProvider =
    Provider<Future<String?> Function(String, Uint8List)>(
      (ref) => writeImVideoPreviewCache,
    );
final imQueuedMediaPreviewLoaderProvider =
    Provider<Future<Uint8List?> Function(String)>(
      (ref) => ref.read(imRepositoryProvider).readQueuedMediaPreview,
    );
final imVideoPreviewProvider = FutureProvider.autoDispose
    .family<ImVideoPreviewSource?, ImVideoPreviewKey>((ref, key) async {
      _retainForHotReopen(ref);
      ref.watch(imMediaScopeProvider);
      final load = await _MediaLoad.start(ref);
      if (parseImOutboxSyntheticFileId(key.attachmentId) != null) {
        final preview = await ref.read(imQueuedMediaPreviewLoaderProvider)(
          key.attachmentId,
        );
        await load.check();
        return preview == null ? null : ImVideoPreviewSource.memory(preview);
      }
      final mediaKey = imVideoPreviewCacheKey(
        attachmentId: key.attachmentId,
        sha256Value: key.coverSha256,
        coverObjectId: key.coverObjectId,
      );
      final cacheKey = '${load.accountId}:$mediaKey';
      final cachedPath = await ref.read(imVideoPreviewCacheReaderProvider)(
        cacheKey,
      );
      await load.check();
      if (cachedPath != null) return ImVideoPreviewSource.file(cachedPath);
      Uint8List? preview;
      if (key.coverObjectId.isNotEmpty) {
        try {
          preview = await ref.read(imMediaAttachmentBytesLoaderProvider)(
            key.attachmentId,
            cover: true,
          );
        } on SessionChangedException {
          rethrow;
        } catch (_) {
          preview = null;
        }
        await load.check();
      }
      // A missing/failed cover is a placeholder state. Never download the
      // original video merely to build a list thumbnail; the original is only
      // allowed after an explicit play or download action.
      if (preview == null || preview.isEmpty) return null;
      final filePath = await ref.read(imVideoPreviewCacheWriterProvider)(
        cacheKey,
        preview,
      );
      await load.check();
      return filePath == null ? null : ImVideoPreviewSource.file(filePath);
    }, retry: mobileReadRetry);

void _retainForHotReopen(
  Ref ref, {
  Duration retention = const Duration(minutes: 5),
}) {
  final keepAlive = ref.keepAlive();
  Timer? expiry;
  ref.onCancel(() {
    expiry?.cancel();
    expiry = Timer(retention, keepAlive.close);
  });
  ref.onResume(() {
    expiry?.cancel();
    expiry = null;
  });
  ref.onDispose(() => expiry?.cancel());
}

final oaAttachmentThumbnailProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, attachmentId) async {
      ref.watch(imMediaScopeProvider);
      final load = await _MediaLoad.start(ref);
      final accountId = load.accountId;
      final cache = ref.read(imBinaryMemoryCacheProvider);
      final cacheKey = 'oa-thumbnail:$attachmentId';
      final cached = cache.read(accountId, cacheKey);
      if (cached != null) return cached;
      final bytes = await ref.read(oaAttachmentThumbnailBytesLoaderProvider)(
        attachmentId,
      );
      await load.check();
      cache.write(accountId, cacheKey, bytes);
      return bytes;
    }, retry: mobileReadRetry);

final conversationMembersProvider =
    FutureProvider.family<List<ImMember>, String>((ref, id) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) {
        return PreviewData.conversationMembers(id);
      }
      return ref.read(imRepositoryProvider).conversationMembersCacheFirst(id);
    });

final conversationCachedMembersProvider =
    FutureProvider.family<List<ImMember>, String>((ref, id) async {
      final accountId = ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) {
        return PreviewData.conversationMembers(id);
      }
      if (accountId.isEmpty) return const <ImMember>[];
      return ref
          .read(imLocalStoreProvider)
          .readConversationMembers(accountId, id);
    });

final conversationMemberPageProvider =
    FutureProvider.family<
      ImMemberPage,
      ({String conversationId, int page, int pageSize, String keyword})
    >((ref, key) async {
      ref.watch(collaborationAccountScopeProvider);
      ref.watch(
        authControllerProvider.select(
          (value) => (
            value.value?.userId,
            value.value?.deviceId,
            value.value?.accessToken,
          ),
        ),
      );
      if (AppEnvironment.demoMode) {
        final keyword = key.keyword.trim().toLowerCase();
        final members = PreviewData.conversationMembers(key.conversationId)
            .where(
              (member) =>
                  keyword.isEmpty ||
                  member.displayName.toLowerCase().contains(keyword) ||
                  member.username.toLowerCase().contains(keyword),
            )
            .toList(growable: false);
        final page = key.page.clamp(1, 100000);
        final pageSize = key.pageSize.clamp(1, 100);
        final start = (page - 1) * pageSize;
        return ImMemberPage(
          items: start >= members.length
              ? const <ImMember>[]
              : members.skip(start).take(pageSize).toList(growable: false),
          page: page,
          pageSize: pageSize,
          total: members.length,
        );
      }
      return ref
          .read(imRepositoryProvider)
          .conversationMemberPage(
            key.conversationId,
            page: key.page,
            pageSize: key.pageSize,
            keyword: key.keyword,
          );
    });

final imFavoritesProvider = FutureProvider<List<ImFavoriteMessage>>((
  ref,
) async {
  ref.watch(collaborationAccountScopeProvider);
  return (await ref.watch(imFavoritesPageProvider(1).future)).items;
});

final imFavoritesPageProvider =
    FutureProvider.family<ImListPage<ImFavoriteMessage>, int>((
      ref,
      page,
    ) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) {
        return _previewPage(PreviewData.imFavorites, page: page);
      }
      return ref.read(imRepositoryProvider).favoritesPage(page: page);
    });

final imBadgeSummaryProvider = FutureProvider<ImBadgeSummary>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) {
    final bootstrap = PreviewData.imBootstrap;
    return ImBadgeSummary(
      unreadMessages: bootstrap.conversations.fold(
        0,
        (total, item) => total + item.unreadCount,
      ),
      pendingFriendRequests: 0,
    );
  }
  // Visible reads update SQLite even when the server emits no new read event.
  // Refresh the authoritative total on unread changes, not every metadata or
  // presence refresh. Keep the server count: the cached index may be partial.
  ref.watch(
    imBootstrapProvider.select(
      (state) => state.value?.conversations.fold<int>(
        0,
        (total, item) => total + item.unreadCount,
      ),
    ),
  );
  return ref.read(imRepositoryProvider).badgeSummary();
});

final imAssistantTasksProvider = FutureProvider<List<ImAssistantTask>>((
  ref,
) async {
  ref.watch(collaborationAccountScopeProvider);
  return (await ref.watch(imAssistantTasksPageProvider(1).future)).items;
});

bool imUnreadProjectionDiffers(ImBadgeSummary remote, ImBootstrap? local) {
  if (local == null) return true;
  final localUnread = local.conversations.fold<int>(
    0,
    (total, conversation) => total + conversation.unreadCount,
  );
  return localUnread != remote.unreadMessages;
}

final imAssistantTasksPageProvider =
    FutureProvider.family<ImListPage<ImAssistantTask>, int>((ref, page) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) {
        return _previewPage(PreviewData.imAssistantTasks, page: page);
      }
      return ref.read(imRepositoryProvider).assistantTasksPage(page: page);
    });

ImListPage<T> _previewPage<T>(
  List<T> items, {
  required int page,
  int pageSize = 50,
}) {
  final safePage = page < 1 ? 1 : page;
  final start = (safePage - 1) * pageSize;
  return ImListPage<T>(
    items: start >= items.length
        ? const []
        : items.skip(start).take(pageSize).toList(growable: false),
    page: safePage,
    pageSize: pageSize,
    total: items.length,
  );
}

final imDeviceAuthorizationsProvider =
    FutureProvider<List<ImDeviceAuthorization>>((ref) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) {
        return List.unmodifiable(PreviewData.demoDeviceAuthorizations);
      }
      return ref.read(imRepositoryProvider).deviceAuthorizations();
    });

final imPushDeviceProvider = FutureProvider<ImPushDevice?>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return PreviewData.demoPushDevice;
  return ref.read(imRepositoryProvider).pushDevice();
});

final imLanguagePreferenceProvider = FutureProvider<ImLanguagePreference?>((
  ref,
) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return null;
  return ref.read(imRepositoryProvider).languagePreference();
});

final conversationPresenceProvider =
    FutureProvider.family<ImConversationPresence, String>((ref, id) async {
      ref.watch(collaborationAccountScopeProvider);
      ref.watch(
        authControllerProvider.select(
          (value) => (
            value.value?.userId,
            value.value?.deviceId,
            value.value?.accessToken,
          ),
        ),
      );
      if (AppEnvironment.demoMode) {
        final conversation = PreviewData.imBootstrap.conversations
            .where((item) => item.id == id)
            .firstOrNull;
        final members = PreviewData.conversationMembers(id);
        final peer = members
            .where(
              (item) => item.id != PreviewData.imBootstrap.currentMember.id,
            )
            .firstOrNull;
        return ImConversationPresence(
          conversationId: id,
          type: conversation?.type ?? 'direct',
          onlineMemberCount: members.where((item) => item.isOnline).length,
          peerOnline: peer?.isOnline ?? false,
          serverTime: DateTime.now(),
        );
      }
      try {
        final session = await ref
            .read(secureSessionStoreProvider)
            .readSession();
        if (!ref.mounted || session == null) {
          throw const SessionChangedException();
        }
        final presence = await ref
            .read(imRepositoryProvider)
            .conversationPresence(id, forSession: session);
        if (!ref.mounted) throw const SessionChangedException();
        ref
            .read(imPresenceProjectionProvider.notifier)
            .observe(session, presence);
        ref
            .read(imRealtimeAvailabilityControllerProvider.notifier)
            .markAvailable();
        return presence;
      } on SessionChangedException {
        rethrow;
      } catch (_) {
        if (!ref.mounted) rethrow;
        ref
            .read(imRealtimeAvailabilityControllerProvider.notifier)
            .markUnavailable();
        rethrow;
      }
    });

final groupProfileProvider = FutureProvider.family<ImGroupProfile?, String>((
  ref,
  id,
) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return PreviewData.groupProfile(id);
  return ref.read(imRepositoryProvider).groupProfileCacheFirst(id);
});

final groupManagersProvider = FutureProvider.family<List<ImMember>, String>((
  ref,
  id,
) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return PreviewData.groupManagers(id);
  return ref.read(imRepositoryProvider).groupManagers(id);
});

final class OaSubmissionQueuedException implements Exception {
  const OaSubmissionQueuedException(this.item);

  final OaOutboxItem item;

  @override
  String toString() => '申请已保存到待同步队列';
}

final class OaSyncPullResult {
  const OaSyncPullResult({
    required this.changed,
    required this.sequence,
    this.requestIds = const {},
  });

  factory OaSyncPullResult.fromEvents(List<OaSyncEvent> events) {
    final requestIds = <String>{};
    var sequence = 0;
    for (final event in events) {
      if (event.sequence > sequence) sequence = event.sequence;
      try {
        final payload = jsonDecode(event.payloadJson);
        if (payload is! Map) continue;
        final id =
            payload['requestId'] ??
            payload['RequestId'] ??
            payload['approvalRequestId'] ??
            payload['ApprovalRequestId'];
        if (id is String && id.trim().isNotEmpty) requestIds.add(id.trim());
      } on FormatException {
        // A malformed optional payload must not interrupt other updates.
      }
    }
    return OaSyncPullResult(
      changed: events.isNotEmpty,
      sequence: sequence,
      requestIds: Set.unmodifiable(requestIds),
    );
  }

  final bool changed;
  final int sequence;
  final Set<String> requestIds;
}

final class OaRepository {
  OaRepository(
    this._client,
    this._sessionStore,
    this._store, {
    OaAttachmentFileStore? attachmentFileStore,
  }) : _attachmentFiles =
           attachmentFileStore ??
           OaAttachmentFileStore(
             keyLoader: _sessionStore.readOrCreateImCacheKey,
           );

  final CollaborationClient _client;
  final SecureSessionStore _sessionStore;
  final OaLocalStore _store;
  final OaAttachmentFileStore _attachmentFiles;
  final _notificationReadFlushes = <(String, String, String), Future<int>>{};
  final _attachmentStartupCleanup = <String, Future<void>>{};

  Future<MobileSession> _session() async {
    if (AppEnvironment.demoMode) return _demoSession;
    final session = await _sessionStore.readSession();
    if (session == null || session.userId.isEmpty) {
      throw StateError('登录状态已失效，请重新登录');
    }
    await _attachmentStartupCleanup.putIfAbsent(
      session.userId,
      () => _attachmentFiles.deleteIncompleteWrites(session.userId),
    );
    return session;
  }

  Future<OaBootstrap> bootstrapCacheFirst() async {
    final session = await _session();
    final cached = await _sessionStore.withCurrentSession(
      session,
      () => _store.readObject(session.userId, OaLocalStore.bootstrapCacheKey),
    );
    return cached == null
        ? _refreshBootstrapFor(session)
        : OaBootstrap.fromJson(cached);
  }

  Future<OaBootstrap> refreshBootstrap() async {
    final session = await _session();
    return _refreshBootstrapFor(session);
  }

  Future<OaBootstrap> _refreshBootstrapFor(
    MobileSession session, {
    CancelToken? cancelToken,
  }) async {
    final payload = await _fetchBootstrap(
      forSession: session,
      cancelToken: cancelToken,
    );
    return _sessionStore.withCurrentSession(session, () async {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      await _store.writeObject(
        session.userId,
        OaLocalStore.bootstrapCacheKey,
        payload,
      );
      return OaBootstrap.fromJson(
        await _store.projectNotificationObject(
          session.userId,
          OaLocalStore.bootstrapCacheKey,
          payload,
        ),
      );
    });
  }

  Future<OaApplicationCatalog> appCatalogCacheFirst() async {
    final session = await _session();
    final cached = await _sessionStore.withCurrentSession(
      session,
      () => _store.readObject(session.userId, OaLocalStore.catalogCacheKey),
    );
    return cached == null
        ? _refreshAppCatalogFor(session)
        : OaApplicationCatalog.fromJson(cached);
  }

  Future<OaApplicationCatalog> refreshAppCatalog() async {
    final session = await _session();
    return _refreshAppCatalogFor(session);
  }

  Future<OaApplicationCatalog> _refreshAppCatalogFor(
    MobileSession session, {
    CancelToken? cancelToken,
  }) async {
    final payload = await _fetchAppCatalog(
      forSession: session,
      cancelToken: cancelToken,
    );
    return _sessionStore.withCurrentSession(session, () async {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      await _store.writeObject(
        session.userId,
        OaLocalStore.catalogCacheKey,
        payload,
      );
      return OaApplicationCatalog.fromJson(payload);
    });
  }

  Future<OaApprovalRequest> approvalRequestCacheFirst(String requestId) async {
    final session = await _session();
    final cacheKey = 'approval:$requestId';
    final cached = await _sessionStore.withCurrentSession(
      session,
      () => _store.readObject(session.userId, cacheKey),
    );
    if (cached != null) return OaApprovalRequest.fromJson(cached);
    return _refreshApprovalRequestFor(session, requestId);
  }

  Future<OaApprovalRequest> approvalRequestNetworkFirst(
    String requestId,
  ) async {
    final session = await _session();
    try {
      return await _refreshApprovalRequestFor(session, requestId);
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      final cached = await _sessionStore.withCurrentSession(
        session,
        () => _store.readObject(session.userId, 'approval:$requestId'),
      );
      if (cached == null) rethrow;
      return OaApprovalRequest.fromJson(cached);
    }
  }

  Future<OaApprovalRequest> refreshApprovalRequest(String requestId) async {
    final session = await _session();
    return _refreshApprovalRequestFor(session, requestId);
  }

  Future<OaApprovalRequest> _refreshApprovalRequestFor(
    MobileSession session,
    String requestId,
  ) async {
    final payload = await _readOaObject(
      session,
      '/api/oa/approval-requests/${Uri.encodeComponent(requestId)}',
    );
    return _sessionStore.withCurrentSession(session, () async {
      await _store.writeObject(session.userId, 'approval:$requestId', payload);
      return OaApprovalRequest.fromJson(payload);
    });
  }

  Future<OaApprovalRequestPage> approvalRequestsPage({
    String? cursor,
    String view = 'all',
    String search = '',
    String applicationKey = '',
    String status = '',
    DateTime? from,
    DateTime? to,
    int take = 50,
  }) async {
    final session = await _session();
    final payload = await _readOaObject(
      session,
      '/api/oa/approval-requests/page',
      queryParameters: {
        'take': take,
        'view': view,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (applicationKey.isNotEmpty) 'applicationKey': applicationKey,
        if (status.isNotEmpty) 'status': status,
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        if (cursor?.isNotEmpty == true) 'cursor': cursor,
      },
    );
    return OaApprovalRequestPage.fromJson(payload);
  }

  Future<OaApprovalRequest> reviewApproval({
    required String requestId,
    required String taskId,
    required int expectedTaskVersion,
    required String decision,
    required String comment,
    MobileSession? expectedSession,
  }) async {
    if (AppEnvironment.demoMode) {
      return _reviewDemoApproval(
        requestId: requestId,
        taskId: taskId,
        expectedTaskVersion: expectedTaskVersion,
        decision: decision,
        comment: comment,
      );
    }
    final session = expectedSession ?? await _session();
    final payload = await _requestOa<Map<String, Object?>>(
      session,
      '/api/oa/approval-requests/${Uri.encodeComponent(requestId)}/review',
      method: 'PATCH',
      data: {
        'taskId': taskId,
        'expectedTaskVersion': expectedTaskVersion,
        'idempotencyKey': const Uuid().v4(),
        'decision': decision,
        'comment': comment,
      },
    );
    return _commitApprovalAction(session, requestId, payload ?? {});
  }

  Future<OaApprovalRequest> _reviewDemoApproval({
    required String requestId,
    required String taskId,
    required int expectedTaskVersion,
    required String decision,
    required String comment,
  }) async {
    final requests = PreviewData.oaBootstrap.approvalRequests;
    final requestIndex = requests.indexWhere((item) => item.id == requestId);
    if (requestIndex < 0) throw StateError('审批申请不存在');

    final request = requests[requestIndex];
    final taskIndex = request.tasks.indexWhere((item) => item.id == taskId);
    if (taskIndex < 0) throw StateError('审批任务不存在');
    final task = request.tasks[taskIndex];
    if (!task.canOperate || task.status.toLowerCase() != 'pending') {
      throw StateError('该审批任务已处理');
    }
    if (task.version != expectedTaskVersion) {
      throw StateError('审批任务已更新，请刷新后重试');
    }

    final normalizedDecision = decision.trim().toLowerCase();
    if (normalizedDecision != 'approved' && normalizedDecision != 'rejected') {
      throw ArgumentError.value(decision, 'decision', '不支持的审批决定');
    }
    if (normalizedDecision == 'rejected' && comment.trim().isEmpty) {
      throw ArgumentError.value(comment, 'comment', '驳回原因不能为空');
    }

    final now = DateTime.now();
    final tasks = List<OaApprovalTask>.of(request.tasks);
    tasks[taskIndex] = _copyDemoApprovalTask(
      task,
      status: normalizedDecision,
      version: task.version + 1,
      decision: normalizedDecision,
      comment: comment.trim(),
      canOperate: false,
      completedById: PreviewData.oaBootstrap.currentMemberId,
      completedByName: PreviewData.oaBootstrap.displayName,
      completedAt: now,
    );

    var requestStatus = normalizedDecision == 'rejected'
        ? 'rejected'
        : 'approved';
    OaApprovalTask? nextTask;
    if (normalizedDecision == 'approved') {
      for (var index = taskIndex + 1; index < tasks.length; index++) {
        final candidate = tasks[index];
        if (candidate.status.toLowerCase() != 'waiting') continue;
        nextTask = _copyDemoApprovalTask(
          candidate,
          status: 'pending',
          canOperate:
              candidate.assigneeId == PreviewData.oaBootstrap.currentMemberId,
          createdAt: now,
        );
        tasks[index] = nextTask;
        requestStatus = 'submitted';
        break;
      }
    } else {
      for (var index = taskIndex + 1; index < tasks.length; index++) {
        tasks[index] = _copyDemoApprovalTask(
          tasks[index],
          status: 'cancelled',
          canOperate: false,
        );
      }
    }

    final updated = OaApprovalRequest(
      id: request.id,
      requesterId: request.requesterId,
      title: request.title,
      formDataJson: request.formDataJson,
      formSchemaSnapshotJson: request.formSchemaSnapshotJson,
      status: requestStatus,
      createdAt: request.createdAt,
      updatedAt: now,
      requesterName: request.requesterName,
      requesterDepartmentName: request.requesterDepartmentName,
      templateName: request.templateName,
      templateCategory: request.templateCategory,
      applicationKey: request.applicationKey,
      conversationId: request.conversationId,
      allowedActions: requestStatus == 'submitted'
          ? const ['approve', 'reject']
          : const [],
      tasks: tasks,
      actions: [
        ...request.actions,
        OaApprovalAction(
          actorName: PreviewData.oaBootstrap.displayName,
          action: normalizedDecision,
          comment: comment.trim().isEmpty
              ? (normalizedDecision == 'approved' ? '同意' : '驳回')
              : comment.trim(),
          occurredAt: now,
        ),
      ],
      attachments: request.attachments,
      ccs: request.ccs,
    );
    requests[requestIndex] = updated;
    _projectDemoApprovalNotification(updated, nextTask, now);
    return _demoValue(updated);
  }

  OaApprovalTask _copyDemoApprovalTask(
    OaApprovalTask task, {
    String? status,
    int? version,
    String? decision,
    String? comment,
    bool? canOperate,
    String? completedById,
    String? completedByName,
    DateTime? createdAt,
    DateTime? completedAt,
  }) => OaApprovalTask(
    id: task.id,
    nodeId: task.nodeId,
    nodeName: task.nodeName,
    stage: task.stage,
    assigneeId: task.assigneeId,
    assigneeName: task.assigneeName,
    status: status ?? task.status,
    version: version ?? task.version,
    decision: decision ?? task.decision,
    comment: comment ?? task.comment,
    canOperate: canOperate ?? task.canOperate,
    completedById: completedById ?? task.completedById,
    completedByName: completedByName ?? task.completedByName,
    dueAt: task.dueAt,
    timeoutAction: task.timeoutAction,
    timeoutHandledAt: task.timeoutHandledAt,
    timeoutLastError: task.timeoutLastError,
    createdAt: createdAt ?? task.createdAt,
    completedAt: completedAt ?? task.completedAt,
  );

  void _projectDemoApprovalNotification(
    OaApprovalRequest request,
    OaApprovalTask? nextTask,
    DateTime now,
  ) {
    final notifications = PreviewData.oaBootstrap.notifications;
    final index = notifications.indexWhere(
      (item) => item.requestId == request.id,
    );
    if (index < 0) return;
    final current = notifications[index];
    final continues = request.status == 'submitted' && nextTask != null;
    notifications[index] = OaNotification(
      id: current.id,
      requestId: current.requestId,
      category: current.category,
      type: continues ? 'approval.task.created' : 'approval.task.completed',
      title: continues
          ? '${request.templateName}待处理'
          : '${request.templateName}已处理',
      body: continues
          ? '${request.requesterName}的申请已流转到${nextTask.nodeName}'
          : request.status == 'rejected'
          ? '你已驳回${request.requesterName}的申请'
          : '你已完成最后一个审批节点',
      importance: current.importance,
      action: continues ? 'review' : 'detail',
      isRead: !continues,
      readAt: continues ? null : now,
      createdAt: now,
      targetKind: current.targetKind,
      targetId: current.targetId,
    );
  }

  Future<OaApprovalRequest> withdrawApproval({
    required String requestId,
    required String reason,
    MobileSession? expectedSession,
  }) => _postApprovalAction(requestId, 'withdraw', {
    'idempotencyKey': const Uuid().v4(),
    'reason': reason,
  }, expectedSession: expectedSession);

  Future<OaApprovalRequest> transferApproval({
    required String requestId,
    required OaApprovalTask task,
    required String newAssigneeId,
    required String reason,
    MobileSession? expectedSession,
  }) async {
    if (AppEnvironment.demoMode) {
      return _transferDemoApproval(
        requestId: requestId,
        task: task,
        newAssigneeId: newAssigneeId,
        reason: reason,
      );
    }
    return _postApprovalAction(requestId, 'transfer', {
      'taskId': task.id,
      'expectedTaskVersion': task.version,
      'idempotencyKey': const Uuid().v4(),
      'newAssigneeId': newAssigneeId,
      'reason': reason,
    }, expectedSession: expectedSession);
  }

  Future<OaApprovalRequest> _transferDemoApproval({
    required String requestId,
    required OaApprovalTask task,
    required String newAssigneeId,
    required String reason,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', '转交原因不能为空');
    }
    if (newAssigneeId == PreviewData.oaBootstrap.currentMemberId) {
      throw ArgumentError.value(newAssigneeId, 'newAssigneeId', '不能转交给自己');
    }
    final target = PreviewData.imBootstrap.contacts.where(
      (item) => item.id == newAssigneeId,
    );
    if (target.isEmpty) throw StateError('转交人不存在');
    final newAssignee = target.single;

    final requests = PreviewData.oaBootstrap.approvalRequests;
    final requestIndex = requests.indexWhere((item) => item.id == requestId);
    if (requestIndex < 0) throw StateError('审批申请不存在');
    final request = requests[requestIndex];
    final taskIndex = request.tasks.indexWhere((item) => item.id == task.id);
    if (taskIndex < 0) throw StateError('审批任务不存在');
    final currentTask = request.tasks[taskIndex];
    if (!currentTask.canOperate ||
        currentTask.status.toLowerCase() != 'pending') {
      throw StateError('该审批任务已处理');
    }
    if (currentTask.version != task.version) {
      throw StateError('审批任务已更新，请刷新后重试');
    }

    final now = DateTime.now();
    final tasks = List<OaApprovalTask>.of(request.tasks);
    tasks[taskIndex] = _copyDemoApprovalTask(
      currentTask,
      status: 'transferred',
      version: currentTask.version + 1,
      decision: 'transferred',
      comment: normalizedReason,
      canOperate: false,
      completedById: PreviewData.oaBootstrap.currentMemberId,
      completedByName: PreviewData.oaBootstrap.displayName,
      completedAt: now,
    );
    tasks.insert(
      taskIndex + 1,
      OaApprovalTask(
        id: '${currentTask.id}-transfer-${newAssignee.id}',
        nodeId: currentTask.nodeId,
        nodeName: currentTask.nodeName,
        stage: currentTask.stage,
        assigneeId: newAssignee.id,
        assigneeName: newAssignee.displayName,
        status: 'pending',
        version: 1,
        decision: '',
        comment: '',
        canOperate: false,
        createdAt: now,
        completedAt: null,
        dueAt: currentTask.dueAt,
        timeoutAction: currentTask.timeoutAction,
      ),
    );

    final updated = OaApprovalRequest(
      id: request.id,
      requesterId: request.requesterId,
      title: request.title,
      formDataJson: request.formDataJson,
      formSchemaSnapshotJson: request.formSchemaSnapshotJson,
      status: request.status,
      createdAt: request.createdAt,
      updatedAt: now,
      requesterName: request.requesterName,
      requesterDepartmentName: request.requesterDepartmentName,
      templateName: request.templateName,
      templateCategory: request.templateCategory,
      applicationKey: request.applicationKey,
      conversationId: request.conversationId,
      allowedActions: const [],
      tasks: tasks,
      actions: [
        ...request.actions,
        OaApprovalAction(
          actorName: PreviewData.oaBootstrap.displayName,
          action: 'transferred',
          comment: '$normalizedReason · 转交给${newAssignee.displayName}',
          occurredAt: now,
        ),
      ],
      attachments: request.attachments,
      ccs: request.ccs,
    );
    requests[requestIndex] = updated;

    final notifications = PreviewData.oaBootstrap.notifications;
    final notificationIndex = notifications.indexWhere(
      (item) => item.requestId == request.id,
    );
    if (notificationIndex >= 0) {
      final current = notifications[notificationIndex];
      notifications[notificationIndex] = OaNotification(
        id: current.id,
        requestId: current.requestId,
        category: current.category,
        type: 'approval.task.transferred',
        title: '${request.templateName}已转交',
        body: '已转交给${newAssignee.displayName}',
        importance: current.importance,
        action: 'detail',
        isRead: true,
        readAt: now,
        createdAt: now,
        targetKind: current.targetKind,
        targetId: current.targetId,
      );
    }
    return _demoValue(updated);
  }

  Future<OaApprovalRequest> addSignApproval({
    required String requestId,
    required OaApprovalTask task,
    required String addedAssigneeId,
    required String mode,
    required String comment,
    MobileSession? expectedSession,
  }) => _postApprovalAction(requestId, 'add-sign', {
    'taskId': task.id,
    'expectedTaskVersion': task.version,
    'idempotencyKey': const Uuid().v4(),
    'addedAssigneeId': addedAssigneeId,
    'mode': mode,
    'comment': comment,
  }, expectedSession: expectedSession);

  Future<OaApprovalRequest> returnApproval({
    required String requestId,
    required OaApprovalTask task,
    required String reason,
    MobileSession? expectedSession,
  }) => _postApprovalAction(requestId, 'return', {
    'taskId': task.id,
    'expectedTaskVersion': task.version,
    'idempotencyKey': const Uuid().v4(),
    'reason': reason,
  }, expectedSession: expectedSession);

  Future<OaApprovalRequest> remindApproval({
    required String requestId,
    required String comment,
    MobileSession? expectedSession,
  }) => _postApprovalAction(requestId, 'remind', {
    'idempotencyKey': const Uuid().v4(),
    'comment': comment,
  }, expectedSession: expectedSession);

  Future<void> markApprovalCcRead(String requestId) async {
    final session = await _session();
    await _requestOa<void>(
      session,
      '/api/oa/approval-requests/${Uri.encodeComponent(requestId)}/cc/read',
      method: 'POST',
    );
    await _sessionStore.withCurrentSession(
      session,
      () => _store.invalidate(session.userId, [
        OaLocalStore.bootstrapCacheKey,
        OaLocalStore.notificationsCacheKey,
        OaLocalStore.notificationPageCacheKey,
      ]),
    );
  }

  Future<OaWorkflowPreview> previewWorkflow({
    required String applicationKey,
    required OaApprovalTemplate template,
    required Map<String, Object?> formData,
  }) async {
    if (AppEnvironment.demoMode) return PreviewData.workflowPreview(template);
    final session = await _session();
    final payload = await _requestOa<Map<String, Object?>>(
      session,
      '/api/oa/workflow-resolution/preview',
      method: 'POST',
      data: {
        'applicationKey': applicationKey,
        'templateId': template.id,
        'workflowKey': template.workflowKey,
        'formDataJson': jsonEncode(formData),
      },
    );
    return OaWorkflowPreview.fromJson(payload ?? {});
  }

  Future<OaApprovalRequest> _postApprovalAction(
    String requestId,
    String action,
    Map<String, Object?> data, {
    MobileSession? expectedSession,
  }) async {
    final session = expectedSession ?? await _session();
    final payload = await _requestOa<Map<String, Object?>>(
      session,
      '/api/oa/approval-requests/${Uri.encodeComponent(requestId)}/$action',
      method: 'POST',
      data: data,
    );
    return _commitApprovalAction(session, requestId, payload ?? {});
  }

  Future<OaApprovalRequest> _commitApprovalAction(
    MobileSession session,
    String requestId,
    Map<String, Object?> payload,
  ) => _sessionStore.withCurrentSession(session, () async {
    await _store.writeObject(session.userId, 'approval:$requestId', payload);
    await _store.invalidate(session.userId, [
      OaLocalStore.bootstrapCacheKey,
      OaLocalStore.notificationsCacheKey,
      OaLocalStore.notificationPageCacheKey,
    ]);
    return OaApprovalRequest.fromJson(payload);
  });

  Future<OaApprovalRequest> submitApproval({
    required String applicationKey,
    required OaApprovalTemplate template,
    required String title,
    required Map<String, Object?> formData,
    String sourceDraftId = '',
    List<String> attachmentIds = const [],
    List<Map<String, Object?>> attachmentBindings = const [],
    List<OaLocalAttachment> pendingAttachments = const [],
    bool allowOfflineQueue = false,
    void Function(
      int attachmentIndex,
      int attachmentCount,
      int sent,
      int total,
    )?
    onAttachmentUploadProgress,
  }) async {
    if (attachmentIds.length + pendingAttachments.length > 20) {
      throw ArgumentError('单个申请最多上传 20 个附件。');
    }
    if (pendingAttachments.any((item) => item.size > 20 * 1024 * 1024)) {
      throw ArgumentError('单个附件不能超过 20 MB。');
    }
    final session = await _session();
    final fallbackAttachmentFieldId = _firstAttachmentFieldId(
      template.formSchemaJson,
    );
    final clientRequestId = const Uuid().v4();
    final outboxId = const Uuid().v4();
    final persistedPending = await _persistLocalAttachments(
      session: session,
      ownerId: outboxId,
      attachments: pendingAttachments,
    );
    final payload = <String, Object?>{
      'applicationKey': applicationKey,
      'templateId': template.id,
      'workflowKey': template.workflowKey,
      'clientRequestId': clientRequestId,
      'title': title,
      'formDataJson': jsonEncode(formData),
      if (sourceDraftId.trim().isNotEmpty)
        '_sourceDraftId': sourceDraftId.trim(),
      'attachmentIds': attachmentIds,
      if (attachmentBindings.isNotEmpty)
        'attachmentBindings': attachmentBindings,
      'pendingAttachments': persistedPending
          .map(
            (item) => {
              ...item.toJson(),
              if (item.formFieldId.isEmpty &&
                  fallbackAttachmentFieldId.isNotEmpty)
                'formFieldId': fallbackAttachmentFieldId,
            },
          )
          .toList(),
    };
    late OaOutboxItem outboxItem;
    try {
      outboxItem = await _sessionStore.withCurrentSession(
        session,
        () => _store.enqueue(
          session.userId,
          id: outboxId,
          idempotencyKey: clientRequestId,
          commandType: 'submit-approval',
          payload: payload,
        ),
      );
    } catch (_) {
      await _deleteStoredAttachments(session.userId, persistedPending);
      rethrow;
    }
    try {
      final response = await _deliverApprovalOutbox(
        session,
        outboxItem,
        onAttachmentUploadProgress: onAttachmentUploadProgress,
      );
      return await _sessionStore.withCurrentSession(session, () async {
        await _store.removeOutbox(session.userId, outboxId);
        await _deleteDeliveredSourceDraft(session.userId, outboxItem);
        await _deleteStoredAttachments(
          session.userId,
          _localAttachments(outboxItem.payload['pendingAttachments']),
        );
        await _store.invalidate(session.userId, [
          OaLocalStore.bootstrapCacheKey,
          OaLocalStore.notificationsCacheKey,
        ]);
        return OaApprovalRequest.fromJson(response);
      });
    } on DioException catch (error) {
      final sessionFailure = _isOaSessionFailure(error);
      final permanent = !_isTransient(error) && !sessionFailure;
      await _sessionStore.withCurrentSession(session, () async {
        await _store.markOutboxFailed(
          session.userId,
          outboxItem,
          _oaOutboxMessage(error),
          permanent: permanent,
        );
        // Keep the same request id for the restored session. Authentication
        // errors are not business validation failures or network-only queues.
        if (sessionFailure) return;
        if (!permanent && allowOfflineQueue) {
          outboxItem = (await _store.readOutbox(session.userId))
              .firstWhere((item) => item.id == outboxId);
          throw OaSubmissionQueuedException(outboxItem);
        }
        if (!permanent) {
          await _store.removeOutbox(session.userId, outboxId);
          await _deleteStoredAttachments(
            session.userId,
            _localAttachments(outboxItem.payload['pendingAttachments']),
          );
        }
      });
      rethrow;
    }
  }

  Future<OaApprovalAttachment> uploadAttachment({
    required String fileName,
    required List<int> bytes,
    String contentType = 'application/octet-stream',
    MobileSession? forSession,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final dio = await _client.forOa(forSession: forSession);
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/attachments',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
      }),
      onSendProgress: onSendProgress,
    );
    return OaApprovalAttachment.fromJson(response.data ?? <String, Object?>{});
  }

  Future<OaApprovalAttachment> _uploadStoredAttachment({
    required MobileSession session,
    required OaLocalAttachment attachment,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final stored = attachment.storedFile;
    if (stored == null || attachment.storageOwnerId.isEmpty) {
      if (attachment.bytes.isEmpty) {
        throw StateError('本地附件文件已不存在');
      }
      return uploadAttachment(
        fileName: attachment.fileName,
        bytes: attachment.bytes,
        contentType: attachment.contentType,
        forSession: session,
        onSendProgress: onSendProgress,
      );
    }
    await _attachmentFiles.verify(
      accountId: session.userId,
      ownerId: attachment.storageOwnerId,
      file: stored,
    );
    final dio = await _client.forOa(forSession: session);
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/attachments',
      data: FormData.fromMap({
        'file': MultipartFile.fromStream(
          () => _attachmentFiles.openRead(
            accountId: session.userId,
            ownerId: attachment.storageOwnerId,
            file: stored,
          ),
          stored.length,
          filename: attachment.fileName,
          contentType: DioMediaType.parse(attachment.contentType),
        ),
      }),
      onSendProgress: onSendProgress,
    );
    return OaApprovalAttachment.fromJson(response.data ?? <String, Object?>{});
  }

  Future<void> deleteAttachment(String attachmentId) async {
    final dio = await _client.forOa();
    await dio.delete<void>('/api/oa/attachments/$attachmentId');
  }

  Future<Uint8List> downloadAttachment(
    String attachmentId, {
    MobileSession? expectedSession,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) => _downloadOaAttachment(
    attachmentId,
    '',
    expectedSession,
    cancelToken,
    onReceiveProgress,
  );

  Future<void> downloadAttachmentToFile(
    String attachmentId,
    String targetPath, {
    MobileSession? expectedSession,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    final session = expectedSession ?? await _session();
    await _sessionStore.withCurrentSession(session, () async {});
    final target = File(targetPath);
    final partial = File('$targetPath.part');
    await target.parent.create(recursive: true);
    try {
      if (await partial.exists()) await partial.delete();
      final dio = await _client.forOa(forSession: session);
      await dio.download(
        '/api/oa/attachments/${Uri.encodeComponent(attachmentId)}',
        partial.path,
        cancelToken: cancelToken,
        onReceiveProgress: onReceiveProgress,
        deleteOnError: true,
      );
      await _sessionStore.withCurrentSession(session, () async {
        if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
        await partial.rename(target.path);
      });
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Future<Uint8List> downloadAttachmentThumbnail(
    String attachmentId, {
    MobileSession? expectedSession,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) => _downloadOaAttachment(
    attachmentId,
    '/thumbnail',
    expectedSession,
    cancelToken,
    onReceiveProgress,
  );

  Future<Uint8List> downloadAttachmentPreview(
    String attachmentId, {
    MobileSession? expectedSession,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) => _downloadOaAttachment(
    attachmentId,
    '/preview',
    expectedSession,
    cancelToken,
    onReceiveProgress,
  );

  Future<Uint8List> _downloadOaAttachment(
    String attachmentId,
    String suffix,
    MobileSession? expectedSession,
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  ) async {
    final session = expectedSession ?? await _session();
    await _sessionStore.withCurrentSession(session, () async {});
    Dio? dio;
    try {
      dio = await _client.forOa(forSession: session);
      final response = await dio.get<List<int>>(
        '/api/oa/attachments/${Uri.encodeComponent(attachmentId)}$suffix',
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onReceiveProgress,
      );
      return await _sessionStore.withCurrentSession(session, () async {
        if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
        return Uint8List.fromList(response.data ?? const <int>[]);
      });
    } catch (_) {
      await _sessionStore.withCurrentSession(session, () async {});
      rethrow;
    } finally {
      dio?.close(force: true);
    }
  }

  Future<List<OaNotification>> notificationsCacheFirst() async {
    final session = await _session();
    final cached = await _sessionStore.withCurrentSession(
      session,
      () => _store.readList(session.userId, OaLocalStore.notificationsCacheKey),
    );
    return cached == null
        ? (await _refreshNotificationPageFor(session)).items
        : _notificationModels(cached);
  }

  Future<List<OaNotification>> refreshNotifications({
    bool unreadOnly = false,
  }) async {
    final session = await _session();
    return (await _refreshNotificationPageFor(
      session,
      unreadOnly: unreadOnly,
    )).items;
  }

  Future<OaNotificationPage> _refreshNotificationPageFor(
    MobileSession session, {
    bool unreadOnly = false,
    int take = 100,
    CancelToken? cancelToken,
  }) async {
    final page = await _notificationPageFor(
      session,
      unreadOnly: unreadOnly,
      take: take,
      cancelToken: cancelToken,
    );
    return _sessionStore.withCurrentSession(session, () async {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (!unreadOnly) {
        await _store.writeList(
          session.userId,
          OaLocalStore.notificationsCacheKey,
          page.items.map<Object?>((item) => item.toJson()).toList(),
        );
        await _store.writeObject(
          session.userId,
          OaLocalStore.notificationPageCacheKey,
          page.toJson(),
        );
      }
      return page;
    });
  }

  Future<OaNotificationPage> notificationPage({
    String? cursor,
    bool unreadOnly = false,
    int take = 100,
  }) async {
    final session = await _session();
    return _notificationPageFor(
      session,
      cursor: cursor,
      unreadOnly: unreadOnly,
      take: take,
    );
  }

  Future<Map<String, Object?>> _fetchNotificationPage({
    required MobileSession forSession,
    String? cursor,
    bool unreadOnly = false,
    int take = 100,
    CancelToken? cancelToken,
  }) => _readOaObject(
    forSession,
    '/api/oa/notifications/page',
    queryParameters: {
      'take': take.clamp(1, 200),
      'unreadOnly': unreadOnly,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    },
    cancelToken: cancelToken,
  );

  Future<OaNotificationPage> _notificationPageFor(
    MobileSession session, {
    String? cursor,
    bool unreadOnly = false,
    int take = 100,
    CancelToken? cancelToken,
  }) async {
    final payload = await _fetchNotificationPage(
      forSession: session,
      cursor: cursor,
      unreadOnly: unreadOnly,
      take: take,
      cancelToken: cancelToken,
    );
    return _sessionStore.withCurrentSession(session, () async {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      final projected = await _store.projectNotificationObject(
        session.userId,
        OaLocalStore.notificationPageCacheKey,
        payload,
      );
      final page = OaNotificationPage.fromJson(projected);
      return unreadOnly
          ? OaNotificationPage(
              items: page.items.where((item) => !item.isRead).toList(),
              nextCursor: page.nextCursor,
              hasMore: page.hasMore,
            )
          : page;
    });
  }

  Future<OaNotificationPage> notificationPageCacheFirst({
    String? cursor,
    bool unreadOnly = false,
    int take = 100,
  }) async {
    final session = await _session();
    if (cursor != null && cursor.isNotEmpty) {
      return _notificationPageFor(
        session,
        cursor: cursor,
        unreadOnly: unreadOnly,
        take: take,
      );
    }
    final cachedPage = await _sessionStore.withCurrentSession(
      session,
      () => _store.readObject(
        session.userId,
        OaLocalStore.notificationPageCacheKey,
      ),
    );
    if (cachedPage != null) {
      final page = OaNotificationPage.fromJson(cachedPage);
      return unreadOnly
          ? OaNotificationPage(
              items: page.items.where((item) => !item.isRead).toList(),
              nextCursor: page.nextCursor,
              hasMore: page.hasMore,
            )
          : page;
    }
    final legacy = await _sessionStore.withCurrentSession(
      session,
      () => _store.readList(session.userId, OaLocalStore.notificationsCacheKey),
    );
    if (legacy != null) {
      final items = _notificationModels(legacy)
          .where((item) => !unreadOnly || !item.isRead)
          .take(take.clamp(1, 200))
          .toList();
      return OaNotificationPage(items: items, nextCursor: null, hasMore: false);
    }
    return _refreshNotificationPageFor(
      session,
      unreadOnly: unreadOnly,
      take: take,
    );
  }

  Future<void> markNotificationRead(String notificationId) async {
    if (AppEnvironment.demoMode) {
      final notifications = PreviewData.oaBootstrap.notifications;
      final index = notifications.indexWhere(
        (item) => item.id == notificationId,
      );
      if (index < 0 || notifications[index].isRead) return;
      final item = notifications[index];
      notifications[index] = OaNotification(
        id: item.id,
        requestId: item.requestId,
        category: item.category,
        type: item.type,
        title: item.title,
        body: item.body,
        importance: item.importance,
        action: item.action,
        isRead: true,
        readAt: DateTime.now(),
        createdAt: item.createdAt,
        targetKind: item.targetKind,
        targetId: item.targetId,
      );
      return;
    }
    final session = await _session();
    // Commit the local read intent before any network work. Separate from
    // approval submissions: opening a notice must not create a pending OA form.
    await _sessionStore.withCurrentSession(
      session,
      () => _store.enqueueNotificationRead(session.userId, notificationId),
    );
  }

  Future<int> pendingNotificationReadCount() async {
    final session = await _session();
    return _sessionStore.withCurrentSession(
      session,
      () => _store.pendingNotificationReadCount(session.userId),
    );
  }

  Future<int> flushNotificationReads({bool retryNow = false}) async {
    if (AppEnvironment.demoMode) return 0;
    final session = await _session();
    if (retryNow) {
      await _sessionStore.withCurrentSession(
        session,
        () => _store.retryNotificationReads(session.userId),
      );
    }
    // Coalesce within one login, not across accounts or renewed credentials.
    // The key is memory-only and must never be logged.
    final key = (session.userId, session.deviceId, session.accessToken);
    return _notificationReadFlushes.putIfAbsent(
      key,
      () => _flushNotificationReads(session).whenComplete(() {
        _notificationReadFlushes.remove(key);
      }),
    );
  }

  Future<int> _flushNotificationReads(MobileSession session) async {
    final items = await _sessionStore.withCurrentSession(
      session,
      () => _store.dueNotificationReads(session.userId),
    );
    if (items.isEmpty) return 0;
    var delivered = 0;
    for (final item in items) {
      final id = item['notification_id'] as String;
      try {
        try {
          await _requestOa<void>(
            session,
            '/api/oa/notifications/${Uri.encodeComponent(id)}/read',
            method: 'POST',
          );
          await _sessionStore.withCurrentSession(
            session,
            () => _store.confirmNotificationRead(session.userId, id),
          );
          delivered++;
        } on DioException catch (error) {
          final sessionFailure = _isOaSessionFailure(error);
          await _sessionStore.withCurrentSession(
            session,
            () => _store.failNotificationRead(
              session.userId,
              id,
              item['attempts'] as int,
              permanent: !_isTransient(error) && !sessionFailure,
            ),
          );
          // A shared network/session failure should not cause N doomed calls.
          if (_isTransient(error) || sessionFailure) break;
        }
      } on SessionChangedException {
        // The original read intent remains pending for its own restored login.
        break;
      }
    }
    return delivered;
  }

  Future<void> markAllNotificationsRead() async {
    if (AppEnvironment.demoMode) {
      final notifications = PreviewData.oaBootstrap.notifications;
      final now = DateTime.now();
      for (var index = 0; index < notifications.length; index++) {
        final item = notifications[index];
        if (item.isRead) continue;
        notifications[index] = OaNotification(
          id: item.id,
          requestId: item.requestId,
          category: item.category,
          type: item.type,
          title: item.title,
          body: item.body,
          importance: item.importance,
          action: item.action,
          isRead: true,
          readAt: now,
          createdAt: item.createdAt,
          targetKind: item.targetKind,
          targetId: item.targetId,
        );
      }
      return;
    }
    final session = await _session();
    await _requestOa<void>(
      session,
      '/api/oa/notifications/read-all',
      method: 'POST',
    );
    await _sessionStore.withCurrentSession(
      session,
      () => _updateCachedNotificationReadState(session.userId),
    );
  }

  Future<void> _updateCachedNotificationReadState(
    String accountId, {
    String? notificationId,
  }) async {
    final readAt = DateTime.now().toUtc().toIso8601String();

    Object? updateItem(Object? value) {
      if (value is! Map) return value;
      final item = Map<String, Object?>.from(value.cast<String, Object?>());
      if (notificationId == null || item['id']?.toString() == notificationId) {
        item['isRead'] = true;
        item['readAt'] = readAt;
      }
      return item;
    }

    final cached = await _store.readList(
      accountId,
      OaLocalStore.notificationsCacheKey,
    );
    if (cached != null) {
      await _store.writeList(
        accountId,
        OaLocalStore.notificationsCacheKey,
        cached.map(updateItem).toList(),
      );
    }

    final page = await _store.readObject(
      accountId,
      OaLocalStore.notificationPageCacheKey,
    );
    if (page != null && page['items'] is List) {
      page['items'] = (page['items'] as List).map(updateItem).toList();
      await _store.writeObject(
        accountId,
        OaLocalStore.notificationPageCacheKey,
        page,
      );
    }

    final bootstrap = await _store.readObject(
      accountId,
      OaLocalStore.bootstrapCacheKey,
    );
    if (bootstrap != null && bootstrap['notifications'] is List) {
      bootstrap['notifications'] = (bootstrap['notifications'] as List)
          .map(updateItem)
          .toList();
      await _store.writeObject(
        accountId,
        OaLocalStore.bootstrapCacheKey,
        bootstrap,
      );
    }
  }

  Future<OaAttendanceOverview> attendanceOverviewCacheFirst() async {
    final session = await _session();
    final cached = await _sessionStore.withCurrentSession(
      session,
      () => _store.readObject(session.userId, OaLocalStore.attendanceCacheKey),
    );
    return cached == null
        ? _refreshAttendanceOverviewFor(session)
        : OaAttendanceOverview.fromJson(cached);
  }

  Future<OaAttendanceOverview> refreshAttendanceOverview() async {
    final session = await _session();
    return _refreshAttendanceOverviewFor(session);
  }

  Future<OaAttendanceOverview> _refreshAttendanceOverviewFor(
    MobileSession session,
  ) async {
    final payload = await _fetchAttendanceOverview(forSession: session);
    return _sessionStore.withCurrentSession(session, () async {
      await _store.writeObject(
        session.userId,
        OaLocalStore.attendanceCacheKey,
        payload,
      );
      return OaAttendanceOverview.fromJson(payload);
    });
  }

  Future<Map<String, Object?>> _fetchAttendanceOverview({
    required MobileSession forSession,
    CancelToken? cancelToken,
  }) => _readOaObject(
    forSession,
    '/api/oa/attendance/overview',
    cancelToken: cancelToken,
  );

  Future<OaAttendanceRecord> punchAttendance() async {
    final session = await _session();
    final dio = await _client.forOa();
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/attendance/punches',
    );
    await _store.invalidate(session.userId, [
      OaLocalStore.bootstrapCacheKey,
      OaLocalStore.attendanceCacheKey,
    ]);
    return OaAttendanceRecord.fromJson(response.data ?? <String, Object?>{});
  }

  Future<List<OaBehaviorDefinition>> behaviorDefinitions() async {
    final dio = await _client.forOa();
    final response = await dio.get<List<Object?>>('/api/oa/behaviors');
    return (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (item) => OaBehaviorDefinition.fromJson(item.cast<String, Object?>()),
        )
        .where((item) => item.isEnabled)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<List<OaBehaviorSession>> activeBehaviorSessions() async {
    final dio = await _client.forOa();
    final response = await dio.get<List<Object?>>(
      '/api/oa/behavior-sessions/active',
    );
    return (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => OaBehaviorSession.fromJson(item.cast<String, Object?>()))
        .toList();
  }

  Future<List<OaBehaviorSession>> behaviorSessionHistory(
    DateTime from,
    DateTime to, {
    int take = 200,
  }) async {
    final dio = await _client.forOa();
    final response = await dio.get<List<Object?>>(
      '/api/oa/behavior-sessions',
      queryParameters: {
        'from': DateFormat('yyyy-MM-dd').format(from),
        'to': DateFormat('yyyy-MM-dd').format(to),
        'take': take,
      },
    );
    return (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => OaBehaviorSession.fromJson(item.cast<String, Object?>()))
        .toList()
      ..sort(
        (a, b) =>
            (b.startedAt ?? DateTime(0)).compareTo(a.startedAt ?? DateTime(0)),
      );
  }

  Future<OaBehaviorSession> startBehavior(String definitionId) async {
    final dio = await _client.forOa();
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/behavior-sessions',
      data: {
        'behaviorDefinitionId': definitionId,
        'clientRequestId': const Uuid().v4(),
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return OaBehaviorSession.fromJson(response.data ?? <String, Object?>{});
  }

  Future<OaBehaviorSession> finishBehavior(String sessionId) async {
    final dio = await _client.forOa();
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/behavior-sessions/$sessionId/finish',
    );
    return OaBehaviorSession.fromJson(response.data ?? <String, Object?>{});
  }

  Future<void> returnToPosition() async {
    final dio = await _client.forOa();
    await dio.post<void>('/api/oa/behavior-sessions/return');
  }

  Future<List<OaActiveInspection>> activeInspections() async {
    final dio = await _client.forOa();
    final response = await dio.get<List<Object?>>('/api/oa/inspections/active');
    return (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (item) => OaActiveInspection.fromJson(item.cast<String, Object?>()),
        )
        .where((item) => item.inspectionId.isNotEmpty)
        .toList();
  }

  Future<void> markInspectionOpened(String inspectionId) async {
    final dio = await _client.forOa();
    await dio.post<void>('/api/oa/inspections/$inspectionId/opened');
  }

  Future<void> respondInspection(String inspectionId, String status) async {
    final dio = await _client.forOa();
    await dio.post<void>(
      '/api/oa/inspections/$inspectionId/respond',
      data: {'status': status, 'text': ''},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<void> correctAttendance({
    required String exceptionId,
    required DateTime correctionAt,
    required String reason,
  }) async {
    final session = await _session();
    final dio = await _client.forOa();
    await dio.post<Object?>(
      '/api/oa/attendance/corrections',
      data: {
        'exceptionId': exceptionId,
        'correctionAt': correctionAt.toUtc().toIso8601String(),
        'reason': reason,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    await _store.invalidate(session.userId, [
      OaLocalStore.bootstrapCacheKey,
      OaLocalStore.notificationsCacheKey,
      OaLocalStore.attendanceCacheKey,
    ]);
  }

  Future<OaTodo> createTodo({
    required String title,
    String description = '',
    String priority = 'normal',
    DateTime? dueAt,
    String? conversationId,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) throw ArgumentError('待办标题不能为空');
    if (AppEnvironment.demoMode) {
      final now = DateTime.now();
      final todo = OaTodo(
        id: 'demo-todo-${now.microsecondsSinceEpoch}',
        title: normalizedTitle,
        description: description.trim(),
        status: 'todo',
        priority: priority,
        dueAt: dueAt,
        createdById: PreviewData.oaBootstrap.currentMemberId,
        conversationId: conversationId?.trim() ?? '',
        createdAt: now,
        updatedAt: now,
      );
      PreviewData.oaBootstrap.todos.insert(0, todo);
      return todo;
    }
    final dio = await _client.forOa();
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/todos',
      data: {
        'title': normalizedTitle,
        'description': description.trim(),
        'priority': priority,
        if (conversationId?.trim().isNotEmpty == true)
          'conversationId': conversationId!.trim(),
        if (dueAt != null) 'dueAt': dueAt.toUtc().toIso8601String(),
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    await refreshBootstrap();
    return OaTodo.fromJson(response.data ?? <String, Object?>{});
  }

  Future<OaTodo> updateTodo(
    String todoId, {
    String? title,
    String? description,
    String? status,
    String? priority,
    DateTime? dueAt,
  }) async {
    if (AppEnvironment.demoMode) {
      final items = PreviewData.oaBootstrap.todos;
      final index = items.indexWhere((item) => item.id == todoId);
      if (index < 0) throw StateError('待办不存在');
      final current = items[index];
      final updated = OaTodo(
        id: current.id,
        title: title?.trim() ?? current.title,
        description: description?.trim() ?? current.description,
        status: status ?? current.status,
        priority: priority ?? current.priority,
        dueAt: dueAt ?? current.dueAt,
        createdById: current.createdById,
        conversationId: current.conversationId,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      items[index] = updated;
      return updated;
    }
    final dio = await _client.forOa();
    final data = <String, Object?>{};
    if (title != null) data['title'] = title.trim();
    if (description != null) data['description'] = description.trim();
    if (status != null) data['status'] = status;
    if (priority != null) data['priority'] = priority;
    if (dueAt != null) data['dueAt'] = dueAt.toUtc().toIso8601String();
    final response = await dio.patch<Map<String, Object?>>(
      '/api/oa/todos/$todoId',
      data: data,
      options: Options(contentType: Headers.jsonContentType),
    );
    await refreshBootstrap();
    return OaTodo.fromJson(response.data ?? <String, Object?>{});
  }

  Future<List<OaApprovalDraft>> drafts() async {
    final session = await _session();
    final drafts = await _store.readDrafts(session.userId);
    final migrated = <OaApprovalDraft>[];
    for (final draft in drafts) {
      migrated.add(await _migrateDraftAttachments(session, draft));
    }
    return List.unmodifiable(migrated);
  }

  Future<OaApprovalDraft?> draftForTemplate(String templateId) async {
    final session = await _session();
    final draft = await _store.readDraftForTemplate(session.userId, templateId);
    return draft == null ? null : _migrateDraftAttachments(session, draft);
  }

  Future<OaApprovalDraft> _migrateDraftAttachments(
    MobileSession session,
    OaApprovalDraft draft,
  ) async {
    if (!draft.attachments.any((item) => item.storedFile == null)) return draft;
    final previousTokens = <String>{
      for (final item in draft.attachments)
        if (item.storedFile case final file?) file.token,
      for (final item in draft.attachments)
        if (item.storedPreviewFile case final preview?) preview.token,
    };
    final persisted = await _persistLocalAttachments(
      session: session,
      ownerId: draft.id,
      attachments: draft.attachments,
    );
    final migrated = OaApprovalDraft(
      id: draft.id,
      applicationKey: draft.applicationKey,
      templateId: draft.templateId,
      workflowKey: draft.workflowKey,
      title: draft.title,
      formData: draft.formData,
      updatedAt: draft.updatedAt,
      attachments: persisted,
    );
    try {
      return await _store.saveDraft(session.userId, migrated);
    } catch (_) {
      await _deleteStoredFiles(session.userId, [
        for (final item in persisted)
          for (final file in [item.storedFile, item.storedPreviewFile])
            if (file != null && !previousTokens.contains(file.token)) file,
      ]);
      rethrow;
    }
  }

  Future<OaApprovalDraft> saveDraft({
    String? id,
    required String applicationKey,
    required OaApprovalTemplate template,
    required String title,
    required Map<String, Object?> formData,
    List<OaLocalAttachment> attachments = const [],
  }) async {
    final session = await _session();
    final draftId = id ?? const Uuid().v4();
    final previous = await _store.readDraft(session.userId, draftId);
    final persistedAttachments = await _persistLocalAttachments(
      session: session,
      ownerId: draftId,
      attachments: attachments,
    );
    final draft = OaApprovalDraft(
      id: draftId,
      applicationKey: applicationKey,
      templateId: template.id,
      workflowKey: template.workflowKey,
      title: title,
      formData: Map<String, Object?>.from(formData),
      attachments: persistedAttachments,
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      final saved = await _store.saveDraft(session.userId, draft);
      final retainedTokens = <String>{
        for (final item in persistedAttachments)
          if (item.storedFile case final file?) file.token,
        for (final item in persistedAttachments)
          if (item.storedPreviewFile case final preview?) preview.token,
      };
      await _deleteStoredFiles(session.userId, [
        for (final item in previous?.attachments ?? const <OaLocalAttachment>[])
          for (final file in [item.storedFile, item.storedPreviewFile])
            if (file != null && !retainedTokens.contains(file.token)) file,
      ]);
      return saved;
    } catch (_) {
      final previousTokens = <String>{
        for (final item in previous?.attachments ?? const <OaLocalAttachment>[])
          if (item.storedFile case final file?) file.token,
        for (final item in previous?.attachments ?? const <OaLocalAttachment>[])
          if (item.storedPreviewFile case final preview?) preview.token,
      };
      await _deleteStoredFiles(session.userId, [
        for (final item in persistedAttachments)
          for (final file in [item.storedFile, item.storedPreviewFile])
            if (file != null && !previousTokens.contains(file.token)) file,
      ]);
      rethrow;
    }
  }

  /// Copies a picker-provided stream directly into the encrypted OA attachment
  /// store. This is the mobile equivalent of the desktop client's file-path
  /// based multipart flow and avoids materializing ordinary files in Dart heap.
  Future<OaLocalAttachment> stageLocalAttachmentStream({
    required String id,
    required String ownerId,
    required String fileName,
    required String contentType,
    required int length,
    required String formFieldId,
    required Stream<List<int>> Function() openRead,
  }) async {
    if (id.trim().isEmpty || ownerId.trim().isEmpty || length <= 0) {
      throw ArgumentError('本地附件信息不完整');
    }
    final session = await _session();
    OaStoredAttachment? stored;
    try {
      stored = await _attachmentFiles.writeStream(
        accountId: session.userId,
        ownerId: ownerId,
        fileName: fileName,
        contentType: contentType,
        clearLength: length,
        source: openRead(),
      );
      await _sessionStore.withCurrentSession(session, () async {});
    } catch (_) {
      if (stored case final file?) {
        await _attachmentFiles.deleteAll(session.userId, [file]);
      }
      rethrow;
    }
    return OaLocalAttachment(
      id: id,
      fileName: fileName,
      contentType: contentType,
      bytes: const [],
      formFieldId: formFieldId,
      storedFile: stored,
      storageOwnerId: ownerId,
    );
  }

  /// Removes page-owned staged files that were never retained by a draft or
  /// outbox item. Callers must not use this for attachments still referenced
  /// by either durable record.
  Future<void> discardLocalAttachments(
    Iterable<OaLocalAttachment> attachments,
  ) async {
    final session = await _session();
    await _deleteStoredAttachments(session.userId, attachments);
  }

  Future<void> deleteDraft(String draftId) async {
    final session = await _session();
    final draft = await _store.readDraft(session.userId, draftId);
    await _store.deleteDraft(session.userId, draftId);
    await _deleteStoredAttachments(
      session.userId,
      draft?.attachments ?? const <OaLocalAttachment>[],
    );
  }

  Future<Uint8List> readLocalAttachmentBytes(
    OaLocalAttachment attachment,
  ) async {
    if (attachment.bytes.isNotEmpty) {
      return Uint8List.fromList(attachment.bytes);
    }
    final stored = attachment.storedFile;
    if (stored == null || attachment.storageOwnerId.isEmpty) {
      throw StateError('本地附件文件已不存在');
    }
    final session = await _session();
    return _sessionStore.withCurrentSession(
      session,
      () => _attachmentFiles.readBytes(
        accountId: session.userId,
        ownerId: attachment.storageOwnerId,
        file: stored,
      ),
    );
  }

  /// Decrypts an attachment as bounded chunks for external file viewers.
  /// Image previews may still request bytes explicitly because Flutter image
  /// codecs require them, while generic files stay off the Dart heap.
  Stream<List<int>> readLocalAttachmentStream(
    OaLocalAttachment attachment,
  ) async* {
    if (attachment.bytes.isNotEmpty) {
      yield Uint8List.fromList(attachment.bytes);
      return;
    }
    final stored = attachment.storedFile;
    if (stored == null || attachment.storageOwnerId.isEmpty) {
      throw StateError('本地附件文件已不存在');
    }
    final session = await _session();
    await for (final chunk in _attachmentFiles.openRead(
      accountId: session.userId,
      ownerId: attachment.storageOwnerId,
      file: stored,
    )) {
      yield chunk;
    }
    await _sessionStore.withCurrentSession(session, () async {});
  }

  Future<Uint8List?> readLocalAttachmentPreviewBytes(
    OaLocalAttachment attachment,
  ) async {
    if (attachment.previewBytes.isNotEmpty) {
      return Uint8List.fromList(attachment.previewBytes);
    }
    final stored = attachment.storedPreviewFile;
    if (stored == null || attachment.storageOwnerId.isEmpty) return null;
    final session = await _session();
    return _sessionStore.withCurrentSession(
      session,
      () => _attachmentFiles.readBytes(
        accountId: session.userId,
        ownerId: attachment.storageOwnerId,
        file: stored,
      ),
    );
  }

  Future<List<OaOutboxItem>> outbox() async {
    final session = await _session();
    return _store.readOutbox(session.userId);
  }

  Future<int> retryOutbox(String itemId) async {
    final session = await _session();
    await _store.retryOutbox(session.userId, itemId);
    return flushOutbox();
  }

  Future<void> discardOutbox(String itemId) async {
    final session = await _session();
    final matches = (await _store.readOutbox(session.userId))
        .where((item) => item.id == itemId);
    await _store.removeOutbox(session.userId, itemId);
    if (matches.isNotEmpty) {
      await _deleteStoredAttachments(
        session.userId,
        _localAttachments(matches.first.payload['pendingAttachments']),
      );
    }
  }

  Future<int> flushOutbox() async {
    final session = await _session();
    final readReceiptsDelivered = await flushNotificationReads();
    final items = await _store.dueOutbox(session.userId);
    var delivered = 0;
    for (final item in items) {
      if (item.commandType != 'submit-approval') continue;
      try {
        await _deliverApprovalOutbox(session, item);
        await _sessionStore.withCurrentSession(session, () async {
          await _store.removeOutbox(session.userId, item.id);
          await _deleteDeliveredSourceDraft(session.userId, item);
          await _deleteStoredAttachments(
            session.userId,
            _localAttachments(item.payload['pendingAttachments']),
          );
        });
        delivered++;
      } on SessionChangedException {
        // Keep the original account's stable request id retryable. An already
        // accepted POST may be replayed after login and must be deduplicated.
        break;
      } on DioException catch (error) {
        try {
          await _sessionStore.withCurrentSession(
            session,
            () => _store.markOutboxFailed(
              session.userId,
              item,
              _oaOutboxMessage(error),
              permanent: !_isTransient(error) && !_isOaSessionFailure(error),
            ),
          );
          if (_isOaSessionFailure(error)) break;
        } on SessionChangedException {
          break;
        }
      } catch (error) {
        try {
          await _sessionStore.withCurrentSession(
            session,
            () => _store.markOutboxFailed(
              session.userId,
              item,
              error.toString(),
              permanent: true,
            ),
          );
        } on SessionChangedException {
          break;
        }
      }
    }
    if (delivered > 0) {
      await _store.invalidate(session.userId, [
        OaLocalStore.bootstrapCacheKey,
        OaLocalStore.notificationsCacheKey,
      ]);
    }
    return delivered + readReceiptsDelivered;
  }

  Future<void> _deleteDeliveredSourceDraft(
    String accountId,
    OaOutboxItem item,
  ) async {
    final draftId = item.payload['_sourceDraftId']?.toString().trim() ?? '';
    if (draftId.isEmpty) return;
    final draft = await _store.readDraft(accountId, draftId);
    await _store.deleteDraft(accountId, draftId);
    await _deleteStoredAttachments(
      accountId,
      draft?.attachments ?? const <OaLocalAttachment>[],
    );
  }

  Future<OaSyncPullResult> pullEvents({
    CancelToken? cancelToken,
    int waitSeconds = 20,
  }) async {
    final session = await _session();
    final cursor = await _sessionStore.withCurrentSession(
      session,
      () => _store.lastEventSequence(session.userId),
    );
    final requestTimer = Stopwatch()..start();
    final body = await _readOaObject(
      session,
      '/api/oa/sync/events',
      queryParameters: {
        'afterSequence': cursor,
        'waitSeconds': waitSeconds.clamp(0, 20),
        'take': 200,
      },
      cancelToken: cancelToken,
    );
    requestTimer.stop();
    final events = (body['events'] is List ? body['events'] as List : const [])
        .whereType<Map>()
        .map((item) => OaSyncEvent.fromJson(item.cast<String, Object?>()))
        .where((event) => event.sequence > cursor)
        .toList();
    if (events.isEmpty) {
      return OaSyncPullResult(changed: false, sequence: cursor);
    }

    final projectionTimer = Stopwatch()..start();
    final notificationsPage = OaNotificationPage.fromJson(
      await _fetchNotificationPage(
        forSession: session,
        cancelToken: cancelToken,
      ),
    );
    final caches = <String, String>{
      OaLocalStore.bootstrapCacheKey: jsonEncode(
        await _fetchBootstrap(forSession: session, cancelToken: cancelToken),
      ),
      OaLocalStore.notificationsCacheKey: jsonEncode(
        notificationsPage.items.map((item) => item.toJson()).toList(),
      ),
      OaLocalStore.notificationPageCacheKey: jsonEncode(
        notificationsPage.toJson(),
      ),
    };
    if (events.any((event) => event.type == 'oa.app-catalog.changed')) {
      caches[OaLocalStore.catalogCacheKey] = jsonEncode(
        await _fetchAppCatalog(forSession: session, cancelToken: cancelToken),
      );
    }
    if (events.any((event) => event.type.contains('attendance'))) {
      caches[OaLocalStore.attendanceCacheKey] = jsonEncode(
        await _fetchAttendanceOverview(
          forSession: session,
          cancelToken: cancelToken,
        ),
      );
    }
    if (cancelToken?.isCancelled == true) {
      throw cancelToken!.cancelError!;
    }
    projectionTimer.stop();
    final commitTimer = Stopwatch()..start();
    final result = await _sessionStore.withCurrentSession(session, () async {
      await _store.applySyncBatch(
        accountId: session.userId,
        events: events,
        refreshedCaches: caches,
      );
      return OaSyncPullResult.fromEvents(events);
    });
    commitTimer.stop();
    recordOaSyncTiming(
      eventCount: events.length,
      waitSeconds: waitSeconds.clamp(0, 20),
      requestMilliseconds: requestTimer.elapsedMilliseconds,
      projectionMilliseconds: projectionTimer.elapsedMilliseconds,
      commitMilliseconds: commitTimer.elapsedMilliseconds,
    );
    return result;
  }

  Future<void> refreshWorkspace({CancelToken? cancelToken}) async {
    final session = await _session();
    await Future.wait([
      _refreshBootstrapFor(session, cancelToken: cancelToken),
      _refreshAppCatalogFor(session, cancelToken: cancelToken),
      _refreshNotificationPageFor(session, cancelToken: cancelToken),
    ], eagerError: true);
  }

  Future<Map<String, Object?>> _fetchBootstrap({
    required MobileSession forSession,
    CancelToken? cancelToken,
  }) =>
      _readOaObject(forSession, '/api/oa/bootstrap', cancelToken: cancelToken);

  Future<Map<String, Object?>> _fetchAppCatalog({
    required MobileSession forSession,
    CancelToken? cancelToken,
  }) => _readOaObject(
    forSession,
    '/api/oa/app-catalog',
    cancelToken: cancelToken,
  );

  // Network stages always retain the caller's identity. The session lock is
  // held only for local checks/commits, never while waiting for the network.
  Future<Map<String, Object?>> _readOaObject(
    MobileSession session,
    String path, {
    Map<String, Object?>? queryParameters,
    CancelToken? cancelToken,
  }) async =>
      await _requestOa<Map<String, Object?>>(
        session,
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      ) ??
      {};

  Future<T?> _requestOa<T>(
    MobileSession session,
    String path, {
    String method = 'GET',
    Map<String, Object?>? queryParameters,
    Object? data,
    CancelToken? cancelToken,
  }) async {
    await _sessionStore.withCurrentSession(session, () async {});
    if (cancelToken?.isCancelled == true) {
      throw cancelToken!.cancelError!;
    }
    final dio = await _client.forOa(forSession: session);
    try {
      // Recheck after client construction, which itself may await secure storage.
      await _sessionStore.withCurrentSession(session, () async {});
      final response = await dio.request<T>(
        path,
        queryParameters: queryParameters,
        data: data,
        options: Options(method: method, contentType: Headers.jsonContentType),
        cancelToken: cancelToken,
      );
      return await _sessionStore.withCurrentSession(
        session,
        () async => response.data,
      );
    } on DioException {
      // A late failure must not be presented as a failure of the new login.
      await _sessionStore.withCurrentSession(session, () async {});
      rethrow;
    } finally {
      dio.close();
    }
  }

  Future<Map<String, Object?>> _sendApprovalPayload(
    Map<String, Object?> payload,
    MobileSession session,
  ) async {
    final dio = await _client.forOa(forSession: session);
    final requestPayload = Map<String, Object?>.from(payload)
      ..remove('pendingAttachments')
      ..remove('_sourceDraftId');
    if (requestPayload['attachmentBindings'] is List &&
        (requestPayload['attachmentBindings'] as List).isNotEmpty) {
      requestPayload.remove('attachmentIds');
    }
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/approval-requests',
      data: requestPayload,
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.data ?? <String, Object?>{};
  }

  Future<List<OaLocalAttachment>> _persistLocalAttachments({
    required MobileSession session,
    required String ownerId,
    required List<OaLocalAttachment> attachments,
  }) async {
    if (attachments.isEmpty) return const [];
    final persisted = <OaLocalAttachment>[];
    final created = <OaStoredAttachment>[];
    try {
      for (final attachment in attachments) {
        final existing = attachment.storedFile;
        late final OaStoredAttachment stored;
        if (existing != null && attachment.storageOwnerId == ownerId) {
          stored = existing;
        } else if (existing != null && attachment.storageOwnerId.isNotEmpty) {
          stored = await _attachmentFiles.writeStream(
            accountId: session.userId,
            ownerId: ownerId,
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            clearLength: existing.length,
            source: _attachmentFiles.openRead(
              accountId: session.userId,
              ownerId: attachment.storageOwnerId,
              file: existing,
            ),
          );
        } else {
          if (attachment.bytes.isEmpty) {
            throw StateError('本地附件文件已不存在');
          }
          stored = await _attachmentFiles.writeBytes(
            accountId: session.userId,
            ownerId: ownerId,
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            bytes: Uint8List.fromList(attachment.bytes),
          );
        }
        if (stored.token != existing?.token) created.add(stored);

        final existingPreview = attachment.storedPreviewFile;
        OaStoredAttachment? storedPreview;
        if (existingPreview != null && attachment.storageOwnerId == ownerId) {
          storedPreview = existingPreview;
        } else if (existingPreview != null &&
            attachment.storageOwnerId.isNotEmpty) {
          storedPreview = await _attachmentFiles.writeStream(
            accountId: session.userId,
            ownerId: ownerId,
            fileName: '${attachment.fileName}.preview',
            contentType: existingPreview.contentType,
            clearLength: existingPreview.length,
            source: _attachmentFiles.openRead(
              accountId: session.userId,
              ownerId: attachment.storageOwnerId,
              file: existingPreview,
            ),
          );
        } else if (attachment.previewBytes.isNotEmpty) {
          storedPreview = await _attachmentFiles.writeBytes(
            accountId: session.userId,
            ownerId: ownerId,
            fileName: '${attachment.fileName}.preview',
            contentType: 'image/webp',
            bytes: Uint8List.fromList(attachment.previewBytes),
          );
        }
        if (storedPreview != null &&
            storedPreview.token != existingPreview?.token) {
          created.add(storedPreview);
        }
        persisted.add(
          attachment.copyWith(
            bytes: const [],
            storedFile: stored,
            storedPreviewFile: storedPreview,
            storageOwnerId: ownerId,
          ),
        );
      }
      return List.unmodifiable(persisted);
    } catch (_) {
      await _attachmentFiles.deleteAll(session.userId, created);
      rethrow;
    }
  }

  Future<void> _deleteStoredAttachments(
    String accountId,
    Iterable<OaLocalAttachment> attachments,
  ) async {
    await _deleteStoredFiles(accountId, [
      for (final attachment in attachments)
        for (final file in [
          ?attachment.storedFile,
          ?attachment.storedPreviewFile,
        ])
          file,
    ]);
  }

  Future<void> _deleteStoredFiles(
    String accountId,
    Iterable<OaStoredAttachment> candidates,
  ) async {
    final seen = <String>{};
    final files = candidates.where((file) => seen.add(file.token)).toList();
    if (files.isNotEmpty) await _attachmentFiles.deleteAll(accountId, files);
  }

  Future<Map<String, Object?>> _deliverApprovalOutbox(
    MobileSession session,
    OaOutboxItem item, {
    void Function(
      int attachmentIndex,
      int attachmentCount,
      int sent,
      int total,
    )?
    onAttachmentUploadProgress,
  }) async {
    await _sessionStore.withCurrentSession(session, () async {});
    final accountId = session.userId;
    final payload = Map<String, Object?>.from(item.payload);
    final attachmentIds =
        (payload['attachmentIds'] is List
                ? payload['attachmentIds'] as List
                : const <Object?>[])
            .map((value) => value.toString())
            .toList();
    var pending = _localAttachments(payload['pendingAttachments']);
    if (pending.any((attachment) => attachment.storedFile == null)) {
      final previousTokens = <String>{
        for (final item in pending)
          if (item.storedFile case final file?) file.token,
        for (final item in pending)
          if (item.storedPreviewFile case final preview?) preview.token,
      };
      final migrated = await _persistLocalAttachments(
        session: session,
        ownerId: item.id,
        attachments: pending,
      );
      payload['pendingAttachments'] = migrated
          .map((attachment) => attachment.toJson())
          .toList();
      try {
        await _sessionStore.withCurrentSession(
          session,
          () => _store.updateOutboxPayload(accountId, item.id, payload),
        );
        pending = migrated;
      } catch (_) {
        await _deleteStoredFiles(accountId, [
          for (final attachment in migrated)
            for (final file in [
              attachment.storedFile,
              attachment.storedPreviewFile,
            ])
              if (file != null && !previousTokens.contains(file.token)) file,
        ]);
        rethrow;
      }
    }
    final formData = _jsonObject(payload['formDataJson']);
    final attachmentBindings =
        (payload['attachmentBindings'] is List
                ? payload['attachmentBindings'] as List
                : const <Object?>[])
            .whereType<Map>()
            .map(
              (item) =>
                  item.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList();

    final attachmentCount = pending.length;
    var attachmentIndex = 0;
    while (pending.isNotEmpty) {
      await _sessionStore.withCurrentSession(session, () async {});
      final local = pending.first;
      final uploaded = await _uploadStoredAttachment(
        session: session,
        attachment: local,
        onSendProgress: onAttachmentUploadProgress == null
            ? null
            : (sent, total) => onAttachmentUploadProgress(
                attachmentIndex,
                attachmentCount,
                sent,
                total,
              ),
      );
      attachmentIds.add(uploaded.id);
      final fieldId = local.formFieldId.trim();
      if (fieldId.isNotEmpty) {
        final fieldAttachments = formData[fieldId] is List
            ? List<Object?>.from(formData[fieldId] as List)
            : <Object?>[];
        final displayOrder = fieldAttachments.length;
        fieldAttachments.add(uploaded.toJson());
        formData[fieldId] = fieldAttachments;
        attachmentBindings.add({
          'attachmentId': uploaded.id,
          'formFieldId': fieldId,
          'displayOrder': displayOrder,
        });
      }
      pending.removeAt(0);
      payload['attachmentIds'] = attachmentIds;
      payload['attachmentBindings'] = attachmentBindings;
      payload['formDataJson'] = jsonEncode(formData);
      payload['pendingAttachments'] = pending
          .map((attachment) => attachment.toJson())
          .toList();
      await _sessionStore.withCurrentSession(
        session,
        () => _store.updateOutboxPayload(accountId, item.id, payload),
      );
      await _deleteStoredAttachments(accountId, [local]);
      attachmentIndex++;
    }

    await _sessionStore.withCurrentSession(session, () async {});
    final response = await _sendApprovalPayload(payload, session);
    return _sessionStore.withCurrentSession(session, () async => response);
  }
}

Map<String, Object?> _jsonObject(Object? value) {
  try {
    final decoded = value is String ? jsonDecode(value) : value;
    return decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : <String, Object?>{};
  } on FormatException {
    return <String, Object?>{};
  }
}

String _firstAttachmentFieldId(String schemaJson) {
  final schema = _jsonObject(schemaJson);
  final fields = schema['fields'];
  if (fields is! List) return '';
  for (final field in fields.whereType<Map>()) {
    final type = field['type']?.toString();
    if (type == 'attachment' || type == 'file') {
      return field['id']?.toString().trim() ?? '';
    }
  }
  return '';
}

List<OaNotification> _notificationModels(List<Object?> payload) => payload
    .whereType<Map>()
    .map((item) => OaNotification.fromJson(item.cast<String, Object?>()))
    .toList();

List<OaLocalAttachment> _localAttachments(Object? payload) =>
    (payload is List ? payload : const <Object?>[])
        .whereType<Map>()
        .map((item) => OaLocalAttachment.fromJson(item.cast<String, Object?>()))
        .toList();

bool _isOaSessionFailure(DioException error) {
  if (error.response?.statusCode == 401) return true;
  final body = error.response?.data;
  final code = body is Map
      ? (body['code'] ?? body['Code'])?.toString().trim().toLowerCase()
      : null;
  return error.response?.statusCode == 409 && code == 'session_replaced';
}

bool _isTransient(DioException error) {
  if (error.response == null) return true;
  final status = error.response!.statusCode ?? 0;
  return status == 408 || status == 429 || status >= 500;
}

String _oaOutboxMessage(DioException error) {
  if (!_isTransient(error)) return _dioMessage(error);
  final operation = error.requestOptions.path == '/api/oa/attachments'
      ? '附件上传'
      : '申请提交';
  final status = error.response?.statusCode;
  // Persist a safe diagnosis instead of a proxy body, token-bearing URL, or
  // transport exception. Keep the HTTP status so support can distinguish 5xx
  // from an offline device without exposing the actual request.
  return status == null
      ? '$operation暂未完成，网络恢复后自动重试'
      : '$operation暂未完成（HTTP $status），将自动重试';
}

String _dioMessage(DioException error) {
  final data = error.response?.data;
  if (data is Map) {
    final directValidationMessages = _validationMessages(
      data['errors'] ?? data['validationErrors'],
    );
    if (directValidationMessages.isNotEmpty) {
      final summary = data['message']?.toString().trim() ?? '';
      return {
        if (summary.isNotEmpty) summary,
        ...directValidationMessages,
      }.join('\n');
    }
    final nestedError = data['error'];
    if (nestedError is Map) {
      final nestedValidationMessages = _validationMessages(
        nestedError['errors'] ?? nestedError['validationErrors'],
      );
      if (nestedValidationMessages.isNotEmpty) {
        return nestedValidationMessages.join('\n');
      }
      for (final key in const ['details', 'message']) {
        final message = nestedError[key]?.toString().trim();
        if (message != null && message.isNotEmpty) return message;
      }
    }
    for (final key in const ['detail', 'message']) {
      final message = data[key]?.toString().trim();
      if (message != null && message.isNotEmpty) return message;
    }
  }
  return error.message ?? error.toString();
}

List<String> _validationMessages(Object? payload) {
  if (payload is! List) return const [];
  return payload
      .whereType<Map>()
      .map((item) => item['message']?.toString().trim() ?? '')
      .where((message) => message.isNotEmpty)
      .toSet()
      .toList(growable: false);
}

final class CollaborationOperationException implements Exception {
  const CollaborationOperationException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ImRepository {
  ImRepository(
    this._client,
    this._sessionStore,
    this._store, {
    ImOutboxFileStore? outboxFileStore,
    DateTime Function()? conversationIndexClock,
    this.beforeEventAck,
    this.memberPresence,
  }) : _conversationIndexClock = conversationIndexClock ?? DateTime.now,
       _outboxFiles =
           outboxFileStore ??
           ImOutboxFileStore(keyLoader: _sessionStore.readOrCreateImCacheKey);

  final CollaborationClient _client;
  final SecureSessionStore _sessionStore;
  final ImLocalStore _store;
  final ImOutboxFileStore _outboxFiles;
  final _outboxStartupCleanup = <String, Future<void>>{};
  final ImReadDiagnostics _readDiagnostics = ImReadDiagnostics();
  final ImMemberPresenceProjection? Function()? memberPresence;
  // Fault-injection seam for tests; normal application construction leaves null.
  final Future<void> Function(int sequence, List<ImSyncEvent> events)?
  beforeEventAck;
  final Map<String, DateTime> _historyRetryAfter = {};
  final DateTime Function() _conversationIndexClock;
  ({MobileSession session, DateTime at})? _lastConversationIndexAttempt;
  ({MobileSession session, Future<bool> request})? _conversationIndexInFlight;

  Future<MobileSession> _session() async {
    if (AppEnvironment.demoMode) return _demoSession;
    final session = await _sessionStore.readSession();
    if (session == null || session.userId.isEmpty) {
      throw StateError('登录状态已失效，请重新登录');
    }
    await _outboxStartupCleanup.putIfAbsent(
      session.userId,
      () => _outboxFiles.deleteIncompleteWrites(session.userId),
    );
    return session;
  }

  Future<ImBootstrap> bootstrapCacheFirst() async {
    final session = await _session();
    final cached = await _sessionStore.withCurrentSession(
      session,
      () => _store.readBootstrap(session.userId),
    );
    return cached ?? _refreshBootstrapFor(session);
  }

  Future<ImBootstrap> refreshBootstrap() async {
    final session = await _session();
    return _refreshBootstrapFor(session);
  }

  Future<ImBootstrap> _refreshBootstrapFor(MobileSession session) async {
    await _sessionStore.withCurrentSession(session, () async {});
    try {
      final result = await _fetchBootstrap(forSession: session);
      return await _sessionStore.withCurrentSession(session, () async {
        await _store.replaceBootstrap(session.userId, result);
        return result;
      });
    } catch (_) {
      // An old session's failed refresh is not the current account's error.
      await _sessionStore.withCurrentSession(session, () async {});
      rethrow;
    }
  }

  /// Compare conversation sequence/metadata even when unread totals do not
  /// change (e.g. same-account desktop sends). No directory reload is required.
  Future<bool> reconcileConversationIndex({
    bool force = false,
    CancelToken? cancelToken,
  }) async {
    final session = await _session();
    final inFlight = _conversationIndexInFlight;
    if (inFlight != null && inFlight.session.isSameSession(session)) {
      return inFlight.request;
    }
    final now = _conversationIndexClock();
    final previous = _lastConversationIndexAttempt;
    if (!force && previous != null && previous.session.isSameSession(session)) {
      final elapsed = now.difference(previous.at);
      if (!elapsed.isNegative && elapsed < const Duration(seconds: 25)) {
        return false;
      }
    }
    _lastConversationIndexAttempt = (session: session, at: now);
    final request = _fetchAndMergeConversationIndex(session, cancelToken);
    _conversationIndexInFlight = (session: session, request: request);
    try {
      return await request;
    } finally {
      if (identical(_conversationIndexInFlight?.request, request)) {
        _conversationIndexInFlight = null;
      }
    }
  }

  Future<bool> _fetchAndMergeConversationIndex(
    MobileSession session,
    CancelToken? cancelToken,
  ) async {
    final dio = await _client.forIm(forSession: session);
    final response = await dio.get<List<Object?>>(
      '/api/im/conversations',
      cancelToken: cancelToken,
    );
    if ((await _sessionStore.readSession())?.isSameSession(session) != true) {
      return false;
    }
    if (response.data == null) {
      throw const FormatException('Conversation index missing');
    }
    final ids = <String>{};
    final values = response.data!.map((raw) {
      if (raw is! Map) {
        throw const FormatException('Invalid conversation index');
      }
      final value = ImConversation.fromJson(raw.cast<String, Object?>());
      if (value.id.isEmpty || !value.isSupported || !ids.add(value.id)) {
        throw const FormatException('Invalid conversation identity');
      }
      return value;
    }).toList();
    final changed = await _store.mergeConversationIndex(session.userId, values);
    _readDiagnostics.snapshot(
      'conversation_index',
      response.statusCode,
      values,
    );
    if (!kReleaseMode) {
      // Whitelisted transport metadata only: no identities, headers or body.
      debugPrint(
        'MOBILE_IM_INDEX ${jsonEncode({'status': response.statusCode, 'received': values.length, 'changed': changed})}',
      );
    }
    return changed;
  }

  Future<ImBootstrap> _fetchBootstrap({MobileSession? forSession}) async {
    final session = forSession ?? await _session();
    final presence = memberPresence?.call();
    final request = presence?.beginRequest();
    final dio = await _client.forIm(forSession: session);
    final response = await dio.get<Map<String, Object?>>('/api/im/bootstrap');
    final bootstrap = ImBootstrap.fromJson(
      response.data ?? <String, Object?>{},
    );
    _readDiagnostics.snapshot(
      'bootstrap',
      response.statusCode,
      bootstrap.conversations,
    );
    imPresenceDiagnostics.memberResponse(
      [bootstrap.currentMember, ...bootstrap.contacts],
      source: 'bootstrap',
      status: response.statusCode,
    );
    if (presence != null && request != null) {
      try {
        await _sessionStore.withCurrentSession(session, () async {
          presence.observe(session, request, [
            bootstrap.currentMember,
            ...bootstrap.contacts,
          ]);
        });
      } on SessionChangedException {
        // Cache/event callers keep their existing late-session rejection path.
      }
    }
    return bootstrap;
  }

  /// Repairs announced message ranges without inventing event ACKs or reads.
  /// Small page budgets let event polling and outgoing messages keep running.
  Future<({Set<String> changed, bool progressed})> repairAnnouncedMessageGaps({
    int pageBudget = 3,
    CancelToken? cancelToken,
  }) async {
    final session = await _session();
    final jobs = await _store.pendingHistoryCatchups(session.userId);
    final changed = <String>{};
    var progressed = false;
    var attempted = 0;
    for (final job in jobs) {
      if (cancelToken?.isCancelled ?? false) break;
      final key = '${session.userId}:${job.conversationId}';
      if ((_historyRetryAfter[key]?.isAfter(DateTime.now()) ?? false)) continue;
      if (attempted++ >= pageBudget) break;
      if ((await _sessionStore.readSession())?.isSameSession(session) != true) {
        break;
      }
      try {
        if (await _store.historyCatchupAlreadyCached(session.userId, job)) {
          progressed =
              await _store.commitHistoryCatchupPage(
                session.userId,
                job,
                const [],
                nextBeforeSequence: job.beforeSequence,
                complete: true,
              ) ||
              progressed;
          continue;
        }
        final dio = await _client.forIm(forSession: session);
        final response = await dio.get<List<Object?>>(
          '/api/im/conversations/${job.conversationId}/messages',
          queryParameters: {'beforeSequence': job.beforeSequence, 'take': 50},
          cancelToken: cancelToken,
        );
        if ((await _sessionStore.readSession())?.isSameSession(session) !=
            true) {
          break;
        }
        final messages = (response.data ?? const []).map((raw) {
          if (raw is! Map) throw const FormatException('Invalid history entry');
          final message = ImMessage.fromJson(raw.cast<String, Object?>());
          if (message.id.isEmpty ||
              message.conversationId != job.conversationId ||
              message.sequence <= 0 ||
              message.sequence >= job.beforeSequence) {
            throw const FormatException('Invalid history identity or range');
          }
          return message;
        }).toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
        if (messages.isEmpty && job.beforeSequence == job.targetSequence + 1) {
          // A stale empty page is not proof that the announced message exists.
          _historyRetryAfter[key] = DateTime.now().add(
            const Duration(seconds: 30),
          );
          continue;
        }
        final next = messages.isEmpty
            ? job.afterSequence + 1
            : messages.first.sequence;
        final committed = await _store.commitHistoryCatchupPage(
          session.userId,
          job,
          messages,
          nextBeforeSequence: next,
          complete: next <= job.afterSequence + 1,
        );
        if (committed) {
          if (messages.isNotEmpty) changed.add(job.conversationId);
          progressed = true;
          _historyRetryAfter.remove(key);
        }
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status == 401 || status == 409 || CancelToken.isCancel(error)) {
          rethrow;
        }
        _historyRetryAfter[key] = DateTime.now().add(
          const Duration(seconds: 30),
        );
      } on FormatException {
        _historyRetryAfter[key] = DateTime.now().add(
          const Duration(seconds: 30),
        );
      }
    }
    return (changed: changed, progressed: progressed);
  }

  Future<List<ImDepartment>> departmentsCacheFirst() async {
    final session = await _session();
    final cached = await _store.readDepartments(session.userId);
    if (cached.isNotEmpty) return cached;
    return refreshDepartments();
  }

  Future<List<ImDepartment>> refreshDepartments() async {
    final session = await _session();
    final dio = await _client.forIm();
    final response = await dio.get<List<Object?>>('/api/im/departments');
    final result = (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => ImDepartment.fromJson(item.cast<String, Object?>()))
        .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
        .toList();
    await _store.writeDepartments(session.userId, result);
    return result;
  }

  Future<ImMemberProfile> memberProfile(String memberId) async {
    if (AppEnvironment.demoMode) {
      final member = PreviewData.imBootstrap.contacts.firstWhere(
        (item) => item.id == memberId,
      );
      return ImMemberProfile(
        id: member.id,
        displayName: member.displayName,
        username: member.username,
        departmentName: member.departmentName,
        remark: PreviewData.demoFriendRemarks[member.id] ?? '',
      );
    }
    final session = await _session();
    final body = await _imReadRequest<Map<String, Object?>>(
      session,
      '/api/im/members/$memberId/profile',
    );
    return ImMemberProfile.fromJson(body ?? <String, Object?>{});
  }

  Future<ImMemberProfile> updateProfile({
    required String nickname,
    required String signature,
    MobileSession? expectedSession,
  }) async {
    final normalizedNickname = nickname.trim();
    final normalizedSignature = signature.trim();
    if (normalizedNickname.length > 128 || normalizedSignature.length > 280) {
      throw ArgumentError('昵称或签名超出长度限制');
    }
    final session = expectedSession ?? await _session();
    final body = await _imReadRequest<Map<String, Object?>>(
      session,
      '/api/im/profile',
      method: 'PUT',
      data: {'nickname': normalizedNickname, 'signature': normalizedSignature},
    );
    await _refreshBootstrapFor(session);
    return ImMemberProfile.fromJson(body ?? <String, Object?>{});
  }

  Future<void> updateAvatar({
    required String avatarKey,
    String? avatarDataUrl,
    MobileSession? expectedSession,
  }) async {
    final key = avatarKey.trim().toLowerCase();
    const allowed = {
      'person',
      'work',
      'badge',
      'support',
      'security',
      'custom',
    };
    if (!allowed.contains(key)) throw ArgumentError('头像类型无效');
    if (key == 'custom' &&
        (avatarDataUrl == null ||
            avatarDataUrl.isEmpty ||
            avatarDataUrl.length > 400000)) {
      throw ArgumentError('头像文件过大或格式无效');
    }
    final session = expectedSession ?? await _session();
    await _imReadRequest<void>(
      session,
      '/api/im/profile/avatar',
      method: 'PUT',
      data: {'avatarKey': key, 'avatarDataUrl': avatarDataUrl},
    );
    await _refreshBootstrapFor(session);
  }

  Future<void> updateFriendRemark(String memberId, String remark) async {
    final normalized = remark.trim();
    if (normalized.length > 128) throw ArgumentError('备注超出长度限制');
    if (AppEnvironment.demoMode) {
      PreviewData.demoFriendRemarks[memberId] = normalized;
      return;
    }
    final dio = await _client.forIm();
    await dio.put<void>(
      '/api/im/friends/$memberId/remark',
      data: {'remark': normalized},
    );
    await refreshBootstrap();
  }

  Future<List<ImMessage>> messagesCacheFirst(
    String conversationId, {
    int? take,
  }) async {
    final session = await _session();
    final cached = await _readMessageCache(
      session,
      () => _store.readMessages(session.userId, conversationId, limit: take),
    );
    return cached.isNotEmpty
        ? cached
        : _refreshMessagesFor(session, conversationId);
  }

  Future<List<ImMessage>> messagesBeforeCacheFirst(
    String conversationId, {
    required int take,
    required int beforeSequence,
  }) async {
    if (take < 1 || beforeSequence < 1) {
      throw ArgumentError('Invalid message slice');
    }
    final session = await _session();
    if (beforeSequence == 1) return const [];
    // Continuity includes deletion tombstones: an arbitrary old cached row is
    // not proof that the unread anchor is present. Only the newest page needs
    // this check; earlier pages are explicitly loaded by the scroll actions.
    final pageSize = take.clamp(1, 80);
    final covered = await _readMessageCache(
      session,
      () => _store.historyCatchupAlreadyCached(
        session.userId,
        ImHistoryCatchup(
          conversationId: conversationId,
          afterSequence: (beforeSequence - pageSize - 1).clamp(
            0,
            beforeSequence,
          ),
          beforeSequence: beforeSequence,
          targetSequence: beforeSequence - 1,
        ),
      ),
    );
    if (!covered) {
      final data = await _imReadRequest<List<Object?>>(
        session,
        '/api/im/conversations/$conversationId/messages',
        queryParameters: {'beforeSequence': beforeSequence, 'take': pageSize},
      );
      final page = (data ?? const <Object?>[])
          .whereType<Map>()
          .map((item) => ImMessage.fromJson(item.cast<String, Object?>()))
          .toList();
      if (page.any(
        (item) =>
            item.conversationId != conversationId ||
            item.sequence <= 0 ||
            item.sequence >= beforeSequence,
      )) {
        throw StateError(
          'Message slice is outside the requested conversation or range',
        );
      }
      await _sessionStore.withCurrentSession(
        session,
        () => _store.mergeMessages(session.userId, conversationId, page),
      );
    }
    return _readMessageCache(
      session,
      () => _store.readMessages(
        session.userId,
        conversationId,
        limit: take,
        beforeSequence: beforeSequence,
      ),
    );
  }

  Future<List<ImMember>> conversationMembersCacheFirst(
    String conversationId,
  ) async {
    final session = await _session();
    final cached = await _store.readConversationMembers(
      session.userId,
      conversationId,
    );
    return cached.isNotEmpty
        ? cached
        : refreshConversationMembers(conversationId);
  }

  Future<List<ImMember>> refreshConversationMembers(
    String conversationId,
  ) async {
    final session = await _session();
    final presence = memberPresence?.call();
    final request = presence?.beginRequest();
    final dio = await _client.forIm(forSession: session);
    final response = await dio.get<List<Object?>>(
      '/api/im/conversations/$conversationId/members',
    );
    final members = (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => ImMember.fromJson(item.cast<String, Object?>()))
        .toList();
    return _sessionStore.withCurrentSession(session, () async {
      await _store.replaceConversationMembers(
        session.userId,
        conversationId,
        members,
      );
      if (presence != null && request != null) {
        presence.observe(session, request, members);
      }
      return members;
    });
  }

  Future<ImMemberPage> conversationMemberPage(
    String conversationId, {
    int page = 1,
    int pageSize = 50,
    String keyword = '',
  }) async {
    final session = await _session();
    final presence = memberPresence?.call();
    final request = presence?.beginRequest();
    final dio = await _client.forIm(forSession: session);
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/conversations/$conversationId/members/page',
      queryParameters: {
        'page': page.clamp(1, 100000),
        'pageSize': pageSize.clamp(1, 100),
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
    final result = ImMemberPage.fromJson(
      response.data ?? const <String, Object?>{},
    );
    return _sessionStore.withCurrentSession(session, () async {
      await _store.mergeConversationMembers(
        session.userId,
        conversationId,
        result.items,
        positionOffset: (result.page - 1) * result.pageSize,
      );
      if (presence != null && request != null) {
        presence.observe(session, request, result.items);
      }
      return result;
    });
  }

  Future<ImGroupProfile?> groupProfileCacheFirst(String conversationId) async {
    final session = await _session();
    final cached = await _store.readGroupProfile(
      session.userId,
      conversationId,
    );
    return cached ?? refreshGroupProfile(conversationId);
  }

  Future<ImGroupProfile?> refreshGroupProfile(String conversationId) async {
    if (AppEnvironment.demoMode) {
      return PreviewData.groupProfile(conversationId);
    }
    final session = await _session();
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/groups/$conversationId',
    );
    final data = response.data;
    if (data == null || data.isEmpty) return null;
    final profile = ImGroupProfile.fromJson(data);
    await _store.writeGroupProfile(session.userId, profile);
    return profile;
  }

  Future<List<ImMessage>> refreshMessages(String conversationId) async {
    final session = await _session();
    return _refreshMessagesFor(session, conversationId);
  }

  Future<List<ImMessage>> _refreshMessagesFor(
    MobileSession session,
    String conversationId,
  ) async {
    final messages = await _fetchLatestMessages(session, conversationId);
    return _sessionStore.withCurrentSession(session, () async {
      await _store.mergeMessages(session.userId, conversationId, messages);
      return _store.readMessages(session.userId, conversationId);
    });
  }

  /// Reconciles the visible conversation with the latest server window.
  ///
  /// Normal IM events remain the real-time path. This bounded fallback covers
  /// same-account multi-device sends for deployments that do not echo a
  /// message-created event back to every device owned by the sender. Cached
  /// content is only written and the UI is only invalidated when the server
  /// window actually differs, so reopening an unchanged chat does not rebuild
  /// its message list.
  Future<bool> reconcileLatestMessages(String conversationId) async {
    final session = await _session();
    final latest = await _fetchLatestMessages(session, conversationId);
    if (latest.isEmpty) return false;
    final cached = await _readMessageCache(
      session,
      () => _store.readMessages(
        session.userId,
        conversationId,
        limit: latest.length.clamp(1, 50),
      ),
    );
    if (!imMessageSnapshotsDiffer(cached, latest)) return false;
    return _sessionStore.withCurrentSession(session, () async {
      await _store.mergeMessages(session.userId, conversationId, latest);
      return true;
    });
  }

  Future<List<ImMessage>> _fetchLatestMessages(
    MobileSession session,
    String conversationId,
  ) async {
    final data = await _imReadRequest<List<Object?>>(
      session,
      '/api/im/conversations/$conversationId/messages',
      queryParameters: const {'take': 50},
    );
    return (data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => ImMessage.fromJson(item.cast<String, Object?>()))
        .toList()
      ..sort((left, right) => left.sequence.compareTo(right.sequence));
  }

  Future<List<ImMessage>> loadOlderMessages(
    String conversationId, {
    int? beforeSequence,
  }) async {
    final session = await _session();
    var cursor = beforeSequence;
    if (cursor == null) {
      final cached = await _readMessageCache(
        session,
        () => _store.readMessages(session.userId, conversationId, limit: 80),
      );
      final sequenced = cached
          .where((message) => message.sequence > 0)
          .toList();
      if (sequenced.isEmpty) return const [];
      cursor = sequenced
          .map((message) => message.sequence)
          .reduce((left, right) => left < right ? left : right);
    }
    if (cursor <= 1) return const [];
    final cachedOlder = await _readMessageCache(
      session,
      () => _store.readAdjacentOlderMessages(
        session.userId,
        conversationId,
        beforeSequence: cursor!,
      ),
    );
    if (cachedOlder.isNotEmpty) return cachedOlder;
    final data = await _imReadRequest<List<Object?>>(
      session,
      '/api/im/conversations/$conversationId/messages',
      queryParameters: {'beforeSequence': cursor, 'take': 80},
    );
    final older =
        (data ?? const <Object?>[])
            .whereType<Map>()
            .map((item) => ImMessage.fromJson(item.cast<String, Object?>()))
            .where(
              (message) => message.sequence > 0 && message.sequence < cursor!,
            )
            .toList()
          ..sort((left, right) => left.sequence.compareTo(right.sequence));
    return _sessionStore.withCurrentSession(session, () async {
      if (older.isNotEmpty) {
        await _store.mergeMessages(session.userId, conversationId, older);
      }
      return older;
    });
  }

  // Local decoding may yield just like HTTP. Do not hold the login lock while
  // reading/decrypting, but do not return old data (or old errors) to a new login.
  Future<T> _readMessageCache<T>(
    MobileSession session,
    Future<T> Function() read,
  ) async {
    await _sessionStore.withCurrentSession(session, () async {});
    try {
      final result = await read();
      return await _sessionStore.withCurrentSession(
        session,
        () async => result,
      );
    } catch (_) {
      await _sessionStore.withCurrentSession(session, () async {});
      rethrow;
    }
  }

  Future<ImMessage?> retryMessage(
    String conversationId,
    String clientMessageId,
  ) async {
    if (clientMessageId.isEmpty) return null;
    final session = await _session();
    await _store.retryOutboxNow(session.userId, clientMessageId);
    final messages = await _store.readMessages(session.userId, conversationId);
    return messages
        .where((message) => message.clientMessageId == clientMessageId)
        .firstOrNull;
  }

  Future<ImListPage<ImFavoriteMessage>> favoritesPage({
    int page = 1,
    int pageSize = 50,
  }) async {
    if (AppEnvironment.demoMode) {
      return _previewPage(
        PreviewData.imFavorites,
        page: page,
        pageSize: pageSize,
      );
    }
    final dio = await _client.forIm();
    final response = await dio.get<Object?>(
      '/api/im/favorites',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    final body = response.data;
    final nested = body is Map && body.containsKey('data')
        ? body['data']
        : body;
    final payload = nested is Map
        ? nested.cast<String, Object?>()
        : <String, Object?>{'items': nested};
    return ImListPage<ImFavoriteMessage>.fromJson(
      payload,
      ImFavoriteMessage.fromJson,
      fallbackPage: page,
      fallbackPageSize: pageSize,
    );
  }

  Future<List<ImFavoriteMessage>> favorites({int page = 1}) async =>
      (await favoritesPage(page: page)).items;

  Future<void> addFavorite(String messageId, {String note = ''}) async {
    final dio = await _client.forIm();
    await dio.post<void>(
      '/api/im/favorites',
      data: {'messageId': messageId, 'note': note.trim()},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<void> deleteFavorite(String messageId) async {
    if (AppEnvironment.demoMode) {
      PreviewData.imFavorites.removeWhere(
        (item) => item.messageId == messageId,
      );
      return;
    }
    final dio = await _client.forIm();
    await dio.delete<void>('/api/im/favorites/$messageId');
  }

  Future<ImListPage<ImAssistantTask>> assistantTasksPage({
    int page = 1,
    int pageSize = 50,
  }) async {
    if (AppEnvironment.demoMode) {
      return _previewPage(
        PreviewData.imAssistantTasks,
        page: page,
        pageSize: pageSize,
      );
    }
    final dio = await _client.forIm();
    final response = await dio.get<Object?>(
      '/api/im/assistant/tasks',
      queryParameters: {'page': page, 'pageSize': pageSize},
    );
    final body = response.data;
    final nested = body is Map && body.containsKey('data')
        ? body['data']
        : body;
    final payload = nested is Map
        ? nested.cast<String, Object?>()
        : <String, Object?>{'items': nested};
    return ImListPage<ImAssistantTask>.fromJson(
      payload,
      ImAssistantTask.fromJson,
      fallbackPage: page,
      fallbackPageSize: pageSize,
    );
  }

  Future<List<ImAssistantTask>> assistantTasks({int page = 1}) async =>
      (await assistantTasksPage(page: page)).items;

  Future<ImAssistantTask> createAssistantTask({
    required List<String> receiverMemberIds,
    required String content,
  }) async {
    final normalizedContent = content.trim();
    final receivers = receiverMemberIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    if (receivers.isEmpty || normalizedContent.isEmpty) {
      throw ArgumentError('请选择接收人并输入消息');
    }
    if (AppEnvironment.demoMode) {
      final now = DateTime.now();
      final task = ImAssistantTask(
        id: 'demo-assistant-${now.microsecondsSinceEpoch}',
        messageKind: 'text',
        content: normalizedContent,
        attachmentJson: '',
        status: 'queued',
        receiverCount: receivers.length,
        successCount: 0,
        failureCount: 0,
        createdAt: now,
        updatedAt: now,
      );
      PreviewData.imAssistantTasks.insert(0, task);
      return task;
    }
    final dio = await _client.forIm();
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/assistant/tasks',
      data: {
        'receiverMemberIds': receivers,
        'messageKind': 'text',
        'content': normalizedContent,
        'attachmentJson': '',
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return ImAssistantTask.fromJson(response.data ?? <String, Object?>{});
  }

  Future<void> cancelAssistantTask(String taskId) async {
    if (taskId.trim().isEmpty) return;
    if (AppEnvironment.demoMode) {
      final index = PreviewData.imAssistantTasks.indexWhere(
        (item) => item.id == taskId,
      );
      if (index < 0) return;
      final current = PreviewData.imAssistantTasks[index];
      PreviewData.imAssistantTasks[index] = ImAssistantTask(
        id: current.id,
        messageKind: current.messageKind,
        content: current.content,
        attachmentJson: current.attachmentJson,
        status: 'cancelled',
        receiverCount: current.receiverCount,
        successCount: current.successCount,
        failureCount: current.failureCount,
        createdAt: current.createdAt,
        updatedAt: DateTime.now(),
      );
      return;
    }
    final dio = await _client.forIm();
    await dio.delete<void>('/api/im/assistant/tasks/$taskId');
  }

  Future<List<ImDeviceAuthorization>> deviceAuthorizations() async {
    if (AppEnvironment.demoMode) {
      return List.unmodifiable(PreviewData.demoDeviceAuthorizations);
    }
    final dio = await _client.forIm();
    final response = await dio.get<List<Object?>>(
      '/api/im/devices/authorizations',
    );
    return (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map(
          (item) =>
              ImDeviceAuthorization.fromJson(item.cast<String, Object?>()),
        )
        .toList()
      ..sort((left, right) {
        if (left.isAuthorized != right.isAuthorized) {
          return left.isAuthorized ? -1 : 1;
        }
        return (right.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(
              left.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            );
      });
  }

  Future<ImDeviceAuthorization> registerDeviceAuthorization({
    required String deviceName,
    String platform = 'android',
  }) async {
    if (AppEnvironment.demoMode) {
      final now = DateTime.now();
      final devices = PreviewData.demoDeviceAuthorizations;
      final index = devices.indexWhere(
        (item) => item.deviceId == PreviewData.demoDeviceId,
      );
      final current = index < 0 ? null : devices[index];
      final device = ImDeviceAuthorization(
        deviceId: PreviewData.demoDeviceId,
        deviceName: deviceName.trim().isEmpty
            ? 'Android 移动端'
            : deviceName.trim(),
        platform: platform,
        isAuthorized: true,
        authorizedAt: current?.authorizedAt ?? now,
        lastSeenAt: now,
        revokedAt: null,
      );
      if (index < 0) {
        devices.insert(0, device);
      } else {
        devices[index] = device;
      }
      return device;
    }
    final dio = await _client.forIm();
    final response = await dio.put<Map<String, Object?>>(
      '/api/im/devices/authorizations/current',
      data: {'deviceName': deviceName.trim(), 'platform': platform},
      options: Options(contentType: Headers.jsonContentType),
    );
    return ImDeviceAuthorization.fromJson(
      response.data ?? const <String, Object?>{},
    );
  }

  Future<void> revokeDeviceAuthorization(String deviceId) async {
    if (AppEnvironment.demoMode) {
      final devices = PreviewData.demoDeviceAuthorizations;
      final index = devices.indexWhere((item) => item.deviceId == deviceId);
      if (index < 0 || deviceId == PreviewData.demoDeviceId) return;
      final current = devices[index];
      devices[index] = ImDeviceAuthorization(
        deviceId: current.deviceId,
        deviceName: current.deviceName,
        platform: current.platform,
        isAuthorized: false,
        authorizedAt: current.authorizedAt,
        lastSeenAt: current.lastSeenAt,
        revokedAt: DateTime.now(),
      );
      return;
    }
    final dio = await _client.forIm();
    await dio.delete<void>('/api/im/devices/authorizations/$deviceId');
  }

  Future<ImPushDevice?> pushDevice() async {
    if (AppEnvironment.demoMode) return PreviewData.demoPushDevice;
    final dio = await _client.forIm();
    try {
      final response = await dio.get<Map<String, Object?>>(
        '/api/im/push/devices/current',
      );
      final data = response.data;
      return data == null || data.isEmpty ? null : ImPushDevice.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<ImLanguagePreference?> languagePreference() async {
    final dio = await _client.forIm();
    try {
      final response = await dio.get<Map<String, Object?>>(
        '/api/im/preferences/language',
      );
      final data = response.data;
      return data == null || data.isEmpty
          ? null
          : ImLanguagePreference.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<ImLanguagePreference> updateLanguage(String language) async {
    const supported = {'zh-CN', 'zh-TW', 'en-US'};
    final normalized = language.trim();
    if (!supported.contains(normalized)) {
      throw ArgumentError.value(language, 'language', '不支持的账号语言');
    }
    final dio = await _client.forIm();
    final response = await dio.put<Map<String, Object?>>(
      '/api/im/preferences/language',
      data: {'language': normalized},
      options: Options(contentType: Headers.jsonContentType),
    );
    return ImLanguagePreference.fromJson(
      response.data ?? <String, Object?>{'language': normalized},
    );
  }

  Future<ImMessage> send(
    String conversationId,
    String content, {
    List<String> mentionedMemberIds = const [],
    bool mentionAll = false,
    String? replyToMessageId,
    ImMessageReply? replyTo,
    String? clientMessageId,
    String? expectedAccountId,
  }) async {
    final session = await _session();
    if (expectedAccountId != null && session.userId != expectedAccountId) {
      throw const SessionChangedException();
    }
    final messageId = clientMessageId ?? const Uuid().v4();
    Future<ImMessage> enqueue() => _store.enqueueText(
      accountId: session.userId,
      senderId: session.userId,
      conversationId: conversationId,
      clientMessageId: messageId,
      content: content,
      mentionedMemberIds: mentionedMemberIds,
      mentionAll: mentionAll,
      replyToMessageId: replyToMessageId ?? replyTo?.messageId,
      replyTo: replyTo,
    );
    if (AppEnvironment.demoMode) return enqueue();
    return _sessionStore.withCurrentSession(session, enqueue);
  }

  Future<ImConversation> createDirect(String memberId) async {
    if (AppEnvironment.demoMode) {
      final bootstrap = PreviewData.imBootstrap;
      final peer = bootstrap.contacts
          .where((item) => item.id == memberId)
          .firstOrNull;
      if (peer == null) throw StateError('未找到演示联系人');
      for (final conversation in bootstrap.conversations) {
        if (conversation.isDirect &&
            conversation.title.trim() == peer.displayName.trim()) {
          return conversation;
        }
      }
      return ImConversation(
        id: 'demo-direct-$memberId',
        type: 'direct',
        title: peer.displayName,
        preview: '',
        updatedAt: DateTime.now(),
        unreadCount: 0,
      );
    }
    final dio = await _client.forIm();
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/direct',
      data: {'memberId': memberId},
      options: Options(contentType: Headers.jsonContentType),
    );
    final conversation = ImConversation.fromJson(
      response.data ?? <String, Object?>{},
    );
    if (!conversation.isDirect) {
      throw StateError('单聊接口返回了非单聊会话，已拒绝打开');
    }
    return conversation;
  }

  Future<ImConversation> createGroup(
    String title,
    List<String> memberIds,
  ) async {
    if (AppEnvironment.demoMode) {
      for (final conversation in PreviewData.imBootstrap.conversations) {
        if (conversation.isGroup && conversation.title.trim() == title.trim()) {
          return conversation;
        }
      }
      return ImConversation(
        id: 'demo-group-${DateTime.now().millisecondsSinceEpoch}',
        type: 'group',
        title: title.trim(),
        preview: '',
        updatedAt: DateTime.now(),
        unreadCount: 0,
      );
    }
    final dio = await _client.forIm();
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/groups',
      data: {'title': title.trim(), 'memberIds': memberIds},
      options: Options(contentType: Headers.jsonContentType),
    );
    final conversation = ImConversation.fromJson(
      response.data ?? <String, Object?>{},
    );
    if (!conversation.isGroup) {
      throw StateError('群聊接口返回了非群聊会话，已拒绝打开');
    }
    return conversation;
  }

  Future<ImMessage> sendAttachment({
    required String conversationId,
    required String fileName,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
  }) async {
    if (bytes.isEmpty || bytes.length > 536870912) {
      throw ArgumentError('文件必须非空且不超过 512 MB');
    }
    final session = await _session();
    final clientMessageId = const Uuid().v4();
    final stored = <ImOutboxStoredFile>[];
    try {
      final file = await _outboxFiles.writeBytes(
        accountId: session.userId,
        clientMessageId: clientMessageId,
        role: 'file',
        fileName: fileName,
        contentType: contentType,
        bytes: bytes,
      );
      stored.add(file);
      return await _store.enqueueAttachment(
        accountId: session.userId,
        senderId: session.userId,
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        file: file,
      );
    } catch (_) {
      await _outboxFiles.deleteAll(session.userId, stored);
      rethrow;
    }
  }

  Future<ImMessage> sendAttachmentStream({
    required String conversationId,
    required String fileName,
    required int length,
    required Stream<List<int>> Function() openRead,
    String contentType = 'application/octet-stream',
  }) async {
    if (length <= 0 || length > 536870912) {
      throw ArgumentError('文件必须非空且不超过 512 MB');
    }
    final session = await _session();
    final clientMessageId = const Uuid().v4();
    final stored = <ImOutboxStoredFile>[];
    try {
      final file = await _outboxFiles.writeStream(
        accountId: session.userId,
        clientMessageId: clientMessageId,
        role: 'file',
        fileName: fileName,
        contentType: contentType,
        clearLength: length,
        source: openRead(),
      );
      stored.add(file);
      return await _store.enqueueAttachment(
        accountId: session.userId,
        senderId: session.userId,
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        file: file,
      );
    } catch (_) {
      await _outboxFiles.deleteAll(session.userId, stored);
      rethrow;
    }
  }

  Future<ImMessage> sendImages({
    required String conversationId,
    required List<({String fileName, Uint8List bytes, String contentType})>
    files,
    String caption = '',
  }) => sendPreparedImages(
    conversationId: conversationId,
    count: files.length,
    prepare: (index) async => files[index],
    caption: caption,
  );

  /// Prepares and encrypts one image at a time so a nine-photo batch never
  /// retains every compressed byte buffer in the presentation layer.
  Future<ImMessage> sendPreparedImages({
    required String conversationId,
    required int count,
    required Future<({String fileName, Uint8List bytes, String contentType})>
    Function(int index)
    prepare,
    String caption = '',
  }) async {
    if (count < 1 || count > 9) {
      throw ArgumentError('请选择 1–9 张图片');
    }
    final session = await _session();
    final clientMessageId = const Uuid().v4();
    final stored = <ImOutboxStoredFile>[];
    try {
      for (var index = 0; index < count; index++) {
        final file = await prepare(index);
        if (file.bytes.isEmpty || file.bytes.length > 52428800) {
          throw ArgumentError('图片必须非空且不超过 50 MB');
        }
        stored.add(
          await _outboxFiles.writeBytes(
            accountId: session.userId,
            clientMessageId: clientMessageId,
            role: 'image',
            fileName: file.fileName,
            contentType: file.contentType,
            bytes: file.bytes,
          ),
        );
      }
      return await _store.enqueueImages(
        accountId: session.userId,
        senderId: session.userId,
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        files: stored,
        caption: caption,
      );
    } catch (_) {
      await _outboxFiles.deleteAll(session.userId, stored);
      rethrow;
    }
  }

  /// Encrypts one image stream at a time into a single image message. This is
  /// used for animated/vector images that must keep their original bytes and
  /// must not be retained as one large Dart heap buffer.
  Future<ImMessage> sendPreparedImageStreams({
    required String conversationId,
    required int count,
    required Future<
      ({
        String fileName,
        int length,
        String contentType,
        Stream<List<int>> Function() openRead,
      })
    >
    Function(int index)
    prepare,
    String caption = '',
  }) async {
    if (count < 1 || count > 9) {
      throw ArgumentError('请选择 1–9 张图片');
    }
    final session = await _session();
    final clientMessageId = const Uuid().v4();
    final stored = <ImOutboxStoredFile>[];
    try {
      for (var index = 0; index < count; index++) {
        final file = await prepare(index);
        if (file.length <= 0 || file.length > 52428800) {
          throw ArgumentError('图片必须非空且不超过 50 MB');
        }
        stored.add(
          await _outboxFiles.writeStream(
            accountId: session.userId,
            clientMessageId: clientMessageId,
            role: 'image',
            fileName: file.fileName,
            contentType: file.contentType,
            clearLength: file.length,
            source: file.openRead(),
          ),
        );
      }
      return await _store.enqueueImages(
        accountId: session.userId,
        senderId: session.userId,
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        files: stored,
        caption: caption,
      );
    } catch (_) {
      await _outboxFiles.deleteAll(session.userId, stored);
      rethrow;
    }
  }

  Future<Uint8List> downloadMessageImage(
    String messageId,
    String imageId,
  ) async {
    final local = parseImOutboxSyntheticFileId(imageId);
    if (local != null) {
      return _readQueuedFile(local.clientMessageId, local.token);
    }
    final dio = await _client.forIm();
    final response = await dio.get<List<int>>(
      '/api/im/messages/$messageId/images/$imageId',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<ImMessage> sendMedia({
    required String conversationId,
    required String kind,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
    Uint8List? coverBytes,
    int? coverWidth,
    int? coverHeight,
    String caption = '',
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    if (!const {'video', 'audio'}.contains(normalizedKind)) {
      throw ArgumentError('仅支持视频或音频消息');
    }
    if (bytes.isEmpty || bytes.length > 536870912) {
      throw ArgumentError('媒体文件必须非空且不超过 512 MB');
    }
    final session = await _session();
    final clientMessageId = const Uuid().v4();
    final stored = <ImOutboxStoredFile>[];
    try {
      final mediaFile = await _outboxFiles.writeBytes(
        accountId: session.userId,
        clientMessageId: clientMessageId,
        role: 'media',
        fileName: fileName,
        contentType: contentType,
        bytes: bytes,
      );
      stored.add(mediaFile);
      ImOutboxStoredFile? coverFile;
      if (normalizedKind == 'video' &&
          coverBytes != null &&
          coverBytes.isNotEmpty) {
        coverFile = await _outboxFiles.writeBytes(
          accountId: session.userId,
          clientMessageId: clientMessageId,
          role: 'cover',
          fileName: '${path.basenameWithoutExtension(fileName)}-cover.jpg',
          contentType: 'image/jpeg',
          bytes: coverBytes,
          width: coverWidth,
          height: coverHeight,
        );
        stored.add(coverFile);
      }
      return await _store.enqueueMedia(
        accountId: session.userId,
        senderId: session.userId,
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        kind: normalizedKind,
        mediaFile: mediaFile,
        coverFile: coverFile,
        caption: caption,
      );
    } catch (_) {
      await _outboxFiles.deleteAll(session.userId, stored);
      rethrow;
    }
  }

  Future<ImMessage> sendMediaStream({
    required String conversationId,
    required String kind,
    required String fileName,
    required int length,
    required Stream<List<int>> Function() openRead,
    required String contentType,
    Uint8List? coverBytes,
    int? coverWidth,
    int? coverHeight,
    String caption = '',
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    if (!const {'video', 'audio'}.contains(normalizedKind)) {
      throw ArgumentError('仅支持视频或音频消息');
    }
    if (length <= 0 || length > 536870912) {
      throw ArgumentError('媒体文件必须非空且不超过 512 MB');
    }
    final session = await _session();
    final clientMessageId = const Uuid().v4();
    final stored = <ImOutboxStoredFile>[];
    try {
      final mediaFile = await _outboxFiles.writeStream(
        accountId: session.userId,
        clientMessageId: clientMessageId,
        role: 'media',
        fileName: fileName,
        contentType: contentType,
        clearLength: length,
        source: openRead(),
      );
      stored.add(mediaFile);
      ImOutboxStoredFile? coverFile;
      if (normalizedKind == 'video' &&
          coverBytes != null &&
          coverBytes.isNotEmpty) {
        coverFile = await _outboxFiles.writeBytes(
          accountId: session.userId,
          clientMessageId: clientMessageId,
          role: 'cover',
          fileName: '${path.basenameWithoutExtension(fileName)}-cover.jpg',
          contentType: 'image/jpeg',
          bytes: coverBytes,
          width: coverWidth,
          height: coverHeight,
        );
        stored.add(coverFile);
      }
      return await _store.enqueueMedia(
        accountId: session.userId,
        senderId: session.userId,
        conversationId: conversationId,
        clientMessageId: clientMessageId,
        kind: normalizedKind,
        mediaFile: mediaFile,
        coverFile: coverFile,
        caption: caption,
      );
    } catch (_) {
      await _outboxFiles.deleteAll(session.userId, stored);
      rethrow;
    }
  }

  Future<Uint8List?> readQueuedMediaPreview(String attachmentId) async {
    final local = parseImOutboxSyntheticFileId(attachmentId);
    if (local == null) return null;
    final session = await _session();
    final item = await _store.outboxItem(session.userId, local.clientMessageId);
    if (item == null) return null;
    final covers = item.mediaFiles.where((file) => file.role == 'cover');
    if (covers.isEmpty) return null;
    return _outboxFiles.readBytes(
      accountId: session.userId,
      clientMessageId: local.clientMessageId,
      file: covers.first,
    );
  }

  Future<Uint8List> _readQueuedFile(
    String clientMessageId,
    String token,
  ) async {
    final session = await _session();
    final item = await _store.outboxItem(session.userId, clientMessageId);
    if (item == null) throw StateError('排队中的媒体记录已不存在');
    final matches = item.mediaFiles.where((file) => file.token == token);
    if (matches.isEmpty) throw StateError('排队中的媒体文件已不存在');
    return _outboxFiles.readBytes(
      accountId: session.userId,
      clientMessageId: clientMessageId,
      file: matches.first,
    );
  }

  Future<Uint8List> downloadMediaAttachment(
    String attachmentId, {
    bool cover = false,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    if (attachmentId.trim().isEmpty) throw StateError('媒体附件无效');
    final local = parseImOutboxSyntheticFileId(attachmentId);
    if (local != null) {
      final bytes = await _readQueuedFile(local.clientMessageId, local.token);
      onReceiveProgress?.call(bytes.length, bytes.length);
      return bytes;
    }
    final dio = await _client.forIm();
    final response = await dio.get<List<int>>(
      '/api/im/media-attachments/$attachmentId',
      queryParameters: {'cover': cover},
      options: Options(responseType: ResponseType.bytes),
      onReceiveProgress: onReceiveProgress,
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<void> downloadMediaAttachmentToFile(
    String attachmentId,
    String targetPath, {
    bool cover = false,
    void Function(int received, int total)? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    if (attachmentId.trim().isEmpty) throw StateError('媒体附件无效');
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    final local = parseImOutboxSyntheticFileId(attachmentId);
    if (local != null) {
      final bytes = await _readQueuedFile(local.clientMessageId, local.token);
      await target.writeAsBytes(bytes, flush: true);
      onReceiveProgress?.call(bytes.length, bytes.length);
      return;
    }
    final dio = await _client.forIm();
    await dio.download(
      '/api/im/media-attachments/$attachmentId',
      target.path,
      queryParameters: {'cover': cover},
      onReceiveProgress: onReceiveProgress,
      deleteOnError: true,
      cancelToken: cancelToken,
    );
  }

  Future<ImMessage> sendContactCard(
    String conversationId,
    String memberId,
  ) async {
    final session = await _session();
    final clientMessageId = const Uuid().v4();
    final local = await _store.enqueueContactCard(
      accountId: session.userId,
      senderId: session.userId,
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      memberId: memberId,
    );
    return local;
  }

  Future<ImDownloadedAttachment> downloadAttachment(ImMessage message) async {
    if (message.id.isEmpty) throw StateError('附件消息无效');
    if (message.clientMessageId.trim().isNotEmpty) {
      final session = await _session();
      final item = await _store.outboxItem(
        session.userId,
        message.clientMessageId,
      );
      final files = item?.mediaFiles.where((file) => file.role == 'file');
      if (item != null && files != null && files.length == 1) {
        return ImDownloadedAttachment(
          fileName: files.single.fileName,
          bytes: await _outboxFiles.readBytes(
            accountId: session.userId,
            clientMessageId: item.clientMessageId,
            file: files.single,
          ),
          contentType: files.single.contentType,
        );
      }
    }
    final dio = await _client.forIm();
    final response = await dio.get<List<int>>(
      '/api/im/messages/${message.id}/attachment',
      options: Options(responseType: ResponseType.bytes),
    );
    return ImDownloadedAttachment(
      fileName: message.attachmentName.isEmpty
          ? 'attachment-${message.id}'
          : message.attachmentName,
      bytes: Uint8List.fromList(response.data ?? const <int>[]),
      contentType: message.attachmentContentType,
    );
  }

  Future<ImDownloadedAttachmentFile> downloadAttachmentToFile(
    ImMessage message,
    String targetPath, {
    CancelToken? cancelToken,
    void Function(int received, int total)? onReceiveProgress,
  }) async {
    if (message.id.isEmpty) throw StateError('附件消息无效');
    final session = await _session();
    final target = File(targetPath);
    final partial = File('$targetPath.part');
    await target.parent.create(recursive: true);

    ImOutboxStoredFile? localFile;
    if (message.clientMessageId.trim().isNotEmpty) {
      final item = await _store.outboxItem(
        session.userId,
        message.clientMessageId,
      );
      final files = item?.mediaFiles.where((file) => file.role == 'file');
      if (item != null && files != null && files.length == 1) {
        localFile = files.single;
      }
    }

    final expectedLength = message.attachmentSize ?? localFile?.length ?? 0;
    if (await target.exists()) {
      final length = await target.length();
      if (expectedLength <= 0 || length == expectedLength) {
        onReceiveProgress?.call(length, length);
        return ImDownloadedAttachmentFile(
          fileName: message.attachmentName.isEmpty
              ? localFile?.fileName ?? 'attachment-${message.id}'
              : message.attachmentName,
          path: target.path,
          contentType: message.attachmentContentType.isEmpty
              ? localFile?.contentType ?? 'application/octet-stream'
              : message.attachmentContentType,
        );
      }
      await target.delete();
    }

    try {
      if (await partial.exists()) await partial.delete();
      if (localFile != null) {
        final item = await _store.outboxItem(
          session.userId,
          message.clientMessageId,
        );
        if (item == null) throw StateError('附件缓存已失效');
        var received = 0;
        final sink = partial.openWrite();
        try {
          await for (final chunk in _outboxFiles.openRead(
            accountId: session.userId,
            clientMessageId: item.clientMessageId,
            file: localFile,
          )) {
            if (cancelToken?.isCancelled == true) {
              throw cancelToken!.cancelError!;
            }
            sink.add(chunk);
            received += chunk.length;
            onReceiveProgress?.call(received, localFile.length);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
      } else {
        final dio = await _client.forIm(forSession: session);
        await dio.download(
          '/api/im/messages/${Uri.encodeComponent(message.id)}/attachment',
          partial.path,
          cancelToken: cancelToken,
          onReceiveProgress: onReceiveProgress,
          deleteOnError: true,
        );
      }
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      final length = await partial.length();
      if (expectedLength > 0 && length != expectedLength) {
        throw StateError('附件文件不完整');
      }
      await _sessionStore.withCurrentSession(session, () async {
        if (await target.exists()) await target.delete();
        await partial.rename(target.path);
      });
      return ImDownloadedAttachmentFile(
        fileName: message.attachmentName.isEmpty
            ? localFile?.fileName ?? 'attachment-${message.id}'
            : message.attachmentName,
        path: target.path,
        contentType: message.attachmentContentType.isEmpty
            ? localFile?.contentType ?? 'application/octet-stream'
            : message.attachmentContentType,
      );
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  Future<List<ImMember>> groupManagers(String conversationId) async {
    final session = await _session();
    final presence = memberPresence?.call();
    final request = presence?.beginRequest();
    final dio = await _client.forIm(forSession: session);
    final response = await dio.get<List<Object?>>(
      '/api/im/groups/$conversationId/managers',
    );
    final members = (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => ImMember.fromJson(item.cast<String, Object?>()))
        .toList();
    return _sessionStore.withCurrentSession(session, () async {
      if (presence != null && request != null) {
        presence.observe(session, request, members);
      }
      return members;
    });
  }

  Future<List<ImMember>> addGroupMembers(
    String conversationId,
    List<String> memberIds,
  ) async {
    final dio = await _client.forIm();
    final response = await dio.post<List<Object?>>(
      '/api/im/conversations/$conversationId/members',
      data: {'memberIds': memberIds},
      options: Options(contentType: Headers.jsonContentType),
    );
    final members = (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => ImMember.fromJson(item.cast<String, Object?>()))
        .toList();
    final session = await _session();
    await _store.replaceConversationMembers(
      session.userId,
      conversationId,
      members,
    );
    return members;
  }

  Future<ImGroupProfile> updateGroupProfile(
    String conversationId,
    Map<String, Object?> changes,
  ) async {
    final dio = await _client.forIm();
    final response = await dio.put<Map<String, Object?>>(
      '/api/im/conversations/$conversationId/group-profile',
      data: changes,
      options: Options(contentType: Headers.jsonContentType),
    );
    final profile = ImGroupProfile.fromJson(
      response.data ?? <String, Object?>{},
    );
    final session = await _session();
    await _store.writeGroupProfile(session.userId, profile);
    return profile;
  }

  Future<void> updateGroupMemberRole(
    String conversationId,
    String memberId,
    String role,
  ) async {
    final dio = await _client.forIm();
    await dio.patch<void>(
      '/api/im/conversations/$conversationId/members/role',
      data: {'memberId': memberId, 'role': role},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<ImGroupManagementCapabilities> groupManagementCapabilities(
    String conversationId,
  ) async {
    if (AppEnvironment.demoMode) {
      return PreviewData.groupManagementCapabilities(conversationId);
    }
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/groups/$conversationId/management/capabilities',
    );
    return ImGroupManagementCapabilities.fromJson(
      response.data ?? <String, Object?>{},
    );
  }

  Future<ImGroupManagementPage<ImMutedGroupMember>> groupMutedMembers(
    String conversationId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    if (AppEnvironment.demoMode) {
      return PreviewData.groupMutedMembers(conversationId);
    }
    final session = await _session();
    final presence = memberPresence?.call();
    final request = presence?.beginRequest();
    final dio = await _client.forIm(forSession: session);
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/groups/$conversationId/management/muted-members',
      queryParameters: {
        'page': page < 1 ? 1 : page,
        'pageSize': pageSize.clamp(1, 100),
      },
    );
    final result = ImGroupManagementPage<ImMutedGroupMember>.fromJson(
      response.data ?? const <String, Object?>{},
      ImMutedGroupMember.fromJson,
    );
    return _sessionStore.withCurrentSession(session, () async {
      if (presence != null && request != null) {
        presence.observe(
          session,
          request,
          result.items.map((item) => item.member),
        );
      }
      return result;
    });
  }

  Future<ImGroupManagementPage<ImMember>> groupManagersPage(
    String conversationId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    if (AppEnvironment.demoMode) {
      return PreviewData.groupManagersPage(conversationId);
    }
    final session = await _session();
    final presence = memberPresence?.call();
    final request = presence?.beginRequest();
    final dio = await _client.forIm(forSession: session);
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/groups/$conversationId/management/managers',
      queryParameters: {
        'page': page < 1 ? 1 : page,
        'pageSize': pageSize.clamp(1, 100),
      },
    );
    final result = ImGroupManagementPage<ImMember>.fromJson(
      response.data ?? const <String, Object?>{},
      ImMember.fromJson,
    );
    return _sessionStore.withCurrentSession(session, () async {
      if (presence != null && request != null) {
        presence.observe(session, request, result.items);
      }
      return result;
    });
  }

  Future<ImGroupManagementPage<ImGroupJoinRequest>> groupJoinRequests(
    String conversationId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    if (AppEnvironment.demoMode) {
      return PreviewData.groupJoinRequests(conversationId);
    }
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/groups/$conversationId/management/join-requests',
      queryParameters: {
        'status': 'pending',
        'page': page < 1 ? 1 : page,
        'pageSize': pageSize.clamp(1, 100),
      },
    );
    return ImGroupManagementPage<ImGroupJoinRequest>.fromJson(
      response.data ?? const <String, Object?>{},
      ImGroupJoinRequest.fromJson,
    );
  }

  Future<ImGroupManagementPage<ImGroupNotice>> groupNotices(
    String conversationId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    if (AppEnvironment.demoMode) {
      return PreviewData.groupNotices(conversationId);
    }
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/groups/$conversationId/notices',
      queryParameters: {
        'page': page < 1 ? 1 : page,
        'pageSize': pageSize.clamp(1, 100),
      },
    );
    return ImGroupManagementPage<ImGroupNotice>.fromJson(
      response.data ?? const <String, Object?>{},
      ImGroupNotice.fromJson,
    );
  }

  Future<void> updateGroupMemberMute(
    String conversationId,
    String memberId,
    DateTime? mutedUntil,
  ) async {
    if (AppEnvironment.demoMode) {
      if (mutedUntil == null) {
        PreviewData.demoGroupMutedMembers.removeWhere(
          (item) => item.member.id == memberId,
        );
      }
      return;
    }
    final dio = await _client.forIm();
    await dio.post<void>(
      '/api/im/groups/$conversationId/muted-members',
      data: {
        'memberId': memberId,
        'mutedUntil': mutedUntil?.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> handleGroupJoinRequest(
    String conversationId,
    String applicationId,
    bool accept,
  ) async {
    if (AppEnvironment.demoMode) {
      PreviewData.demoGroupJoinRequests.removeWhere(
        (item) => item.id == applicationId,
      );
      return;
    }
    final dio = await _client.forIm();
    await dio.post<Map<String, Object?>>(
      '/api/im/groups/$conversationId/join-requests/$applicationId/deal',
      data: {'accept': accept},
    );
  }

  Future<void> removeGroupMember(String conversationId, String memberId) async {
    final dio = await _client.forIm();
    try {
      await dio.delete<void>(
        '/api/im/conversations/$conversationId/members/$memberId',
      );
    } on DioException catch (error) {
      try {
        final members = await refreshConversationMembers(conversationId);
        if (members.every((member) => member.id != memberId)) return;
      } catch (_) {
        // Preserve the mutation error when reconciliation is unavailable.
      }
      throw CollaborationOperationException(_dioMessage(error));
    }
  }

  Future<void> transferGroupOwner(
    String conversationId,
    String memberId,
  ) async {
    final dio = await _client.forIm();
    await dio.post<void>(
      '/api/im/conversations/$conversationId/owner-transfer',
      data: {'newOwnerMemberId': memberId},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<ImConversation> updateConversationPreference(
    String conversationId, {
    bool? pinned,
    bool? muted,
  }) async {
    final dio = await _client.forIm();
    final endpoint = pinned != null ? 'pin' : 'mute';
    final enabled = pinned ?? muted ?? false;
    final response = await dio.put<Map<String, Object?>>(
      '/api/im/conversations/$conversationId/$endpoint',
      data: {'enabled': enabled},
      options: Options(contentType: Headers.jsonContentType),
    );
    final conversation = ImConversation.fromJson(
      response.data ?? <String, Object?>{},
    );
    await refreshBootstrap();
    return conversation;
  }

  Future<void> clearConversation(String conversationId) async {
    final session = await _session();
    final dio = await _client.forIm();
    await dio.post<void>('/api/im/conversations/$conversationId/empty');
    await _store.clearConversationMessages(session.userId, conversationId);
  }

  Future<void> deleteDirectConversation(String conversationId) async {
    final session = await _session();
    final dio = await _client.forIm();
    await dio.delete<void>('/api/im/direct-conversations/$conversationId');
    await _store.clearConversationMessages(session.userId, conversationId);
    await refreshBootstrap();
  }

  Future<void> leaveGroup(String conversationId) async {
    final dio = await _client.forIm();
    await dio.post<void>('/api/im/groups/$conversationId/leave');
    await refreshBootstrap();
  }

  Future<void> dissolveGroup(String conversationId) async {
    final dio = await _client.forIm();
    await dio.delete<void>('/api/im/conversations/$conversationId');
    await refreshBootstrap();
  }

  Future<ImGroupHistoryDeletionJob> deleteAllGroupHistory(
    String conversationId, {
    required String confirmation,
    required String reason,
  }) async {
    if (AppEnvironment.demoMode) {
      final now = DateTime.now();
      return ImGroupHistoryDeletionJob(
        id: 'demo-history-${now.microsecondsSinceEpoch}',
        conversationId: conversationId,
        status: 'completed',
        deletedMessageCount: PreviewData.conversationMessages(conversationId)
            .length,
        errorMessage: '',
        createdAt: now,
        updatedAt: now,
        completedAt: now,
      );
    }
    final session = await _session();
    final dio = await _client.forIm();
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/groups/$conversationId/history-deletion-jobs',
      data: {'confirmation': confirmation.trim(), 'reason': reason.trim()},
    );
    var job = ImGroupHistoryDeletionJob.fromJson(
      response.data ?? const <String, Object?>{},
    );
    for (var attempt = 0; attempt < 60; attempt++) {
      if (job.isCompleted || job.isFailed) break;
      await Future<void>.delayed(const Duration(seconds: 1));
      final status = await dio.get<Map<String, Object?>>(
        '/api/im/groups/$conversationId/history-deletion-jobs/${job.id}',
      );
      job = ImGroupHistoryDeletionJob.fromJson(
        status.data ?? const <String, Object?>{},
      );
    }
    if (job.isCompleted) {
      await _store.clearConversationMessages(session.userId, conversationId);
    }
    return job;
  }

  Future<ImConversation> copyGroup(String conversationId) async {
    final dio = await _client.forIm();
    late final Response<Map<String, Object?>> response;
    try {
      response = await dio.post<Map<String, Object?>>(
        '/api/im/groups/$conversationId/copy',
        data: const {'includeMembers': true, 'copyProfile': true},
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (error) {
      throw CollaborationOperationException(_dioMessage(error));
    }
    final conversation = ImConversation.fromJson(
      response.data ?? <String, Object?>{},
    );
    if (!conversation.isGroup) {
      throw StateError('服务端未返回有效群聊');
    }
    await refreshBootstrap();
    return conversation;
  }

  Future<List<ImSearchResult>> searchMembers(String keyword) async {
    final session = await _session();
    final presence = memberPresence?.call();
    final request = presence?.beginRequest();
    final dio = await _client.forIm(forSession: session);
    late final Response<Map<String, Object?>> response;
    try {
      response = await dio.post<Map<String, Object?>>(
        '/api/im/members/search',
        data: {'userName': keyword.trim()},
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return const <ImSearchResult>[];
      }
      throw CollaborationOperationException(_dioMessage(error));
    }
    final body = response.data ?? <String, Object?>{};
    final member = body['data'] is Map
        ? (body['data'] as Map).cast<String, Object?>()
        : body;
    if ((member['id'] ?? member['Id'])?.toString().trim().isEmpty ?? true) {
      return const <ImSearchResult>[];
    }
    return _sessionStore.withCurrentSession(session, () async {
      if (presence != null && request != null) {
        presence.observe(session, request, [ImMember.fromJson(member)]);
      }
      return [
        ImSearchResult.fromJson(<String, Object?>{...member, 'type': 'member'}),
      ];
    });
  }

  Future<ImConversationPresence> conversationPresence(
    String conversationId, {
    MobileSession? forSession,
    CancelToken? cancelToken,
  }) async {
    final session = forSession ?? await _session();
    final presence = memberPresence?.call();
    final request = presence?.beginRequest();
    final dio = await _client.forIm(forSession: session);
    final startedAt = DateTime.now();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/conversations/$conversationId/presence',
      cancelToken: cancelToken,
    );
    final result = ImConversationPresence.fromJson(
      response.data ?? <String, Object?>{},
    );
    if (result.conversationId != conversationId ||
        (result.type != 'direct' && result.type != 'group')) {
      throw const FormatException('Invalid conversation presence response');
    }
    imPresenceDiagnostics.response(
      result,
      status: response.statusCode,
      host: response.realUri.host,
      startedAt: startedAt,
    );
    return _sessionStore.withCurrentSession(session, () async {
      if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
      if (presence != null && request != null && result.type == 'direct') {
        final selfId =
            await _store.readCurrentMemberId(session.userId) ?? session.userId;
        final members = await _store.readConversationMembers(
          session.userId,
          conversationId,
        );
        if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
        final peers = members
            .where(
              (member) => member.id != selfId && member.id != session.userId,
            )
            .toList();
        // Only a known, unambiguous direct-member identity may update a person.
        // A group total or a title match is never a peer presence observation.
        if (peers.length == 1 &&
            members.any(
              (member) => member.id == selfId || member.id == session.userId,
            )) {
          presence.observe(session, request, [
            ImMember(
              id: peers.single.id,
              username: peers.single.username,
              displayName: peers.single.displayName,
              isOnline: result.peerOnline,
              presenceKnown: result.peerPresenceKnown,
              lastSeenAt: result.peerLastSeenAt,
            ),
          ]);
        }
      }
      return result;
    });
  }

  Future<void> enterConversation(String conversationId) async {
    final dio = await _client.forIm();
    _readDiagnostics.action('active_enter_request', conversationId);
    await dio.put<void>('/api/im/conversations/$conversationId/active');
  }

  Future<void> leaveActiveConversation() async {
    final dio = await _client.forIm();
    _readDiagnostics.action('active_leave_request', '');
    await dio.delete<void>('/api/im/conversations/active');
    _readDiagnostics.action('active_leave_confirmed', '');
  }

  Future<void> requestFriend(String memberId, String greeting) async {
    final dio = await _client.forIm();
    try {
      await dio.post<void>(
        '/api/im/friends/applications',
        data: {'targetMemberId': memberId, 'greeting': greeting.trim()},
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (error) {
      throw CollaborationOperationException(_dioMessage(error));
    }
    // The mutation has already succeeded. A temporary bootstrap refresh failure
    // must not invite the user to submit the same friend request again.
    try {
      await refreshBootstrap();
    } catch (_) {}
  }

  Future<List<ImFriendApplication>> pendingFriendApplications() async {
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/friends/applications/page',
      queryParameters: const {
        'page': 1,
        'pageSize': 100,
        'pendingIncomingOnly': true,
      },
    );
    final body = response.data ?? <String, Object?>{};
    final nested = body['data'] is Map
        ? (body['data'] as Map).cast<String, Object?>()
        : body;
    final items = nested['items'];
    return items is List
        ? items
              .whereType<Map>()
              .map(
                (item) =>
                    ImFriendApplication.fromJson(item.cast<String, Object?>()),
              )
              .where(
                (item) =>
                    item.direction == 'incoming' && item.status == 'pending',
              )
              .toList()
        : const [];
  }

  Future<ImFriendApplicationBatchResult> acceptPendingFriendApplications({
    int batchSize = 500,
  }) async {
    if (batchSize < 1 || batchSize > 500) {
      throw ArgumentError.value(batchSize, 'batchSize', '必须在 1 到 500 之间');
    }
    final dio = await _client.forIm();
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/friends/applications/pending/accept-all',
      queryParameters: {'batchSize': batchSize},
      data: const <String, Object?>{},
      options: Options(contentType: Headers.jsonContentType),
    );
    final result = ImFriendApplicationBatchResult.fromJson(
      response.data ?? const <String, Object?>{},
    );
    await refreshBootstrap();
    return result;
  }

  Future<ImBadgeSummary> badgeSummary() async {
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>('/api/im/badges');
    return ImBadgeSummary.fromJson(response.data ?? const <String, Object?>{});
  }

  Future<void> handleFriendApplication(String id, bool accept) async {
    final dio = await _client.forIm();
    await dio.post<void>(
      '/api/im/friends/applications/$id/deal',
      data: {'accept': accept},
      options: Options(contentType: Headers.jsonContentType),
    );
    await refreshBootstrap();
  }

  Future<ImMessage> editMessage(String messageId, String content) async {
    final session = await _session();
    final dio = await _client.forIm();
    final response = await dio.put<Map<String, Object?>>(
      '/api/im/messages/$messageId',
      data: {'content': content.trim()},
      options: Options(contentType: Headers.jsonContentType),
    );
    final message = ImMessage.fromJson(response.data ?? <String, Object?>{});
    await _store.mergeMessages(session.userId, message.conversationId, [
      message,
    ]);
    return message;
  }

  Future<void> revokeMessage(String conversationId, String messageId) async {
    final dio = await _client.forIm();
    await dio.post<void>('/api/im/messages/$messageId/revoke');
    await refreshMessages(conversationId);
  }

  Future<void> deleteMessage(String messageId) async {
    final session = await _session();
    final dio = await _client.forIm();
    await dio.post<void>(
      '/api/im/messages/delete',
      data: {
        'messageIds': [messageId],
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    await _store.deleteMessage(session.userId, messageId);
  }

  Future<void> forwardMessage(
    String messageId,
    String targetConversationId,
  ) async {
    final dio = await _client.forIm();
    await dio.post<void>(
      '/api/im/messages/forward',
      data: {
        'clientBatchId': const Uuid().v4(),
        'messageIds': [messageId],
        'targetConversationIds': [targetConversationId],
      },
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<void> pinMessage(String messageId) async {
    final dio = await _client.forIm();
    await dio.post<void>(
      '/api/im/messages/$messageId/pin',
      data: const {'pinned': true},
      options: Options(contentType: Headers.jsonContentType),
    );
  }

  Future<ImMessageReadReceipt> messageReadReceipts(String messageId) async {
    final session = await _session();
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/messages/$messageId/read-receipts',
    );
    final receipt = ImMessageReadReceipt.fromJson(
      response.data ?? const <String, Object?>{},
    );
    if (receipt.messageId != messageId) {
      throw const FormatException('Message receipt identity mismatch');
    }
    await _store.recordMessageReadReceipt(session.userId, receipt);
    return receipt;
  }

  Future<int> flushOutbox() async =>
      (await flushOutboxDetailed()).deliveredCount;

  Future<int> resumeNetworkOutbox() async {
    final session = await _session();
    return _store.resumeNetworkOutbox(session.userId);
  }

  Future<ImOutboxFlushResult> flushOutboxDetailed() async {
    final session = await _session();
    final items = await _store.dueOutbox(session.userId);
    var delivered = 0;
    final conversationIds = <String>{};
    final waitingConversations = <String>{};
    for (final item in items) {
      if (waitingConversations.contains(item.conversationId)) continue;
      final sendStartedAt = DateTime.now();
      final enqueuedAt = item.enqueuedAt;
      final queueMs = enqueuedAt == null
          ? 0
          : sendStartedAt.difference(enqueuedAt).inMilliseconds;
      final totalTimer = Stopwatch()..start();
      final requestTimer = Stopwatch();
      var commitMs = 0;
      try {
        try {
          await _requireOutboxSession(session);
          requestTimer.start();
          final message = await _postMessage(session, item);
          requestTimer.stop();
          final commitTimer = Stopwatch()..start();
          await _sessionStore.withCurrentSession(
            session,
            () => _store.markOutboxSent(
              session.userId,
              item.clientMessageId,
              message,
            ),
          );
          commitTimer.stop();
          commitMs = commitTimer.elapsedMilliseconds;
          await _outboxFiles.deleteAll(session.userId, item.mediaFiles);
          totalTimer.stop();
          imSendTiming.success(
            kind: item.kind,
            attempts: item.attempts,
            queueMs: queueMs,
            requestMs: requestTimer.elapsedMilliseconds,
            commitMs: commitMs,
            totalMs: totalTimer.elapsedMilliseconds,
          );
          delivered += 1;
          conversationIds.add(item.conversationId);
        } catch (error) {
          if (requestTimer.isRunning) requestTimer.stop();
          if (totalTimer.isRunning) totalTimer.stop();
          await _requireOutboxSession(session);
          if (error is SessionChangedException ||
              _isOutboxSessionFailure(error)) {
            rethrow;
          }
          imUploadDiagnostics.failure(error);
          final retryScheduled = isTransientImOutboxFailure(error);
          await _sessionStore.withCurrentSession(
            session,
            () => _store.markOutboxFailed(
              session.userId,
              item,
              imOutboxFailureText(error),
              retryScheduled: retryScheduled,
              retryOnConnectionChange: isTransportImOutboxFailure(error),
            ),
          );
          conversationIds.add(item.conversationId);
          if (retryScheduled) {
            waitingConversations.add(item.conversationId);
            // Endpoint failures must not stall other chats; a transport outage
            // stops the batch to avoid one timeout per queued conversation.
            if (error is DioException && error.response == null) break;
          }
        }
      } on SessionChangedException {
        // Keep the stable IDs and encrypted files for the original login to
        // replay. Never publish an old batch's conversation IDs to a new login.
        return ImOutboxFlushResult(deliveredCount: 0, conversationIds: {});
      }
    }
    if ((await _sessionStore.readSession())?.isSameSession(session) != true) {
      return ImOutboxFlushResult(deliveredCount: 0, conversationIds: {});
    }
    return ImOutboxFlushResult(
      deliveredCount: delivered,
      conversationIds: conversationIds,
    );
  }

  Future<void> _requireOutboxSession(MobileSession session) =>
      _sessionStore.withCurrentSession(session, () async {});

  bool _isOutboxSessionFailure(Object error) {
    if (error is! DioException) return false;
    final response = error.response;
    final data = response?.data;
    final code = data is Map
        ? (data['code'] ?? data['Code'])?.toString().trim().toLowerCase()
        : null;
    return response?.statusCode == 401 ||
        (response?.statusCode == 409 && code == 'session_replaced');
  }

  Future<ImMessage> _postMessage(
    MobileSession session,
    ImOutboxItem item,
  ) async {
    return switch (item.kind) {
      'file' => _postAttachmentMessage(session, item),
      'contact' => _postContactCardMessage(session, item),
      'image' => _postImageMessage(session, item),
      'video' || 'audio' => _postMediaMessage(session, item),
      _ => _postTextMessage(session, item),
    };
  }

  Future<ImMessage> _postTextMessage(
    MobileSession session,
    ImOutboxItem item,
  ) async {
    final dio = await _client.forIm(forSession: session);
    await _requireOutboxSession(session);
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/${item.conversationId}/messages',
      data: <String, Object?>{
        'clientMessageId': item.clientMessageId,
        'content': item.content,
        'mentionedMemberIds': item.mentionedMemberIds,
        'mentionAll': item.mentionAll,
        'replyToMessageId': item.replyToMessageId,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return ImMessage.fromJson(response.data ?? <String, Object?>{});
  }

  Future<ImMessage> _postAttachmentMessage(
    MobileSession session,
    ImOutboxItem item,
  ) async {
    final protectedFiles = item.mediaFiles.where((file) => file.role == 'file');
    if (protectedFiles.length > 1) {
      throw StateError('排队中的文件记录不完整');
    }
    final upload = protectedFiles.isEmpty
        ? MultipartFile.fromBytes(
            item.attachmentBytes,
            filename: item.attachmentName,
            contentType: DioMediaType.parse(item.attachmentContentType),
          )
        : await _storedMultipart(session.userId, item, protectedFiles.single);
    final dio = await _client.forIm(forSession: session);
    await _requireOutboxSession(session);
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/${item.conversationId}/attachments',
      data: FormData.fromMap({
        'clientMessageId': item.clientMessageId,
        'file': upload,
      }),
    );
    return ImMessage.fromJson(response.data ?? <String, Object?>{});
  }

  Future<ImMessage> _postImageMessage(
    MobileSession session,
    ImOutboxItem item,
  ) async {
    final images = item.mediaFiles
        .where((file) => file.role == 'image')
        .toList();
    if (images.isEmpty || images.length > 9) {
      throw StateError('排队中的图片记录不完整');
    }
    final files = <MultipartFile>[];
    for (final image in images) {
      files.add(await _storedMultipart(session.userId, item, image));
    }
    final dio = await _client.forIm(forSession: session);
    await _requireOutboxSession(session);
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/${item.conversationId}/images',
      data: FormData.fromMap({
        'clientMessageId': item.clientMessageId,
        'caption': item.content.trim(),
        'files': files,
      }),
    );
    return ImMessage.fromJson(response.data ?? <String, Object?>{});
  }

  Future<ImMessage> _postMediaMessage(
    MobileSession session,
    ImOutboxItem item,
  ) async {
    final media = item.mediaFiles.where((file) => file.role == 'media');
    if (media.length != 1) throw StateError('排队中的媒体记录不完整');
    final mediaFile = media.single;
    final dio = await _client.forIm(forSession: session);
    final upload = await _storedMultipart(session.userId, item, mediaFile);
    await _requireOutboxSession(session);
    final uploadResponse = await dio.post<Map<String, Object?>>(
      '/api/im/upload/${item.kind}',
      data: FormData.fromMap({'file': upload}),
    );
    await _requireOutboxSession(session);
    final uploaded = uploadResponse.data ?? <String, Object?>{};
    final objectId = uploaded['objectId']?.toString() ?? '';
    if (objectId.isEmpty) throw StateError('媒体上传未返回对象标识');

    Map<String, Object?> cover = const {};
    final covers = item.mediaFiles.where((file) => file.role == 'cover');
    if (item.kind == 'video' && covers.isNotEmpty) {
      try {
        final coverUpload = await _storedMultipart(
          session.userId,
          item,
          covers.first,
        );
        await _requireOutboxSession(session);
        final coverResponse = await dio.post<Map<String, Object?>>(
          '/api/im/upload/picture',
          data: FormData.fromMap({'file': coverUpload}),
        );
        cover = coverResponse.data ?? const {};
      } catch (error) {
        await _requireOutboxSession(session);
        if (error is SessionChangedException ||
            _isOutboxSessionFailure(error)) {
          rethrow;
        }
        imUploadDiagnostics.failure(error);
        // A cover is optional and must not discard an uploaded video.
      }
    }

    final attachment = <String, Object?>{
      'objectId': objectId,
      'fileName': uploaded['fileName']?.toString() ?? mediaFile.fileName,
      'contentType':
          uploaded['contentType']?.toString() ?? mediaFile.contentType,
      'size': uploaded['size'] ?? mediaFile.length,
      'sha256': uploaded['sha256']?.toString() ?? '',
      'width': uploaded['width'],
      'height': uploaded['height'],
      'durationSeconds': uploaded['durationSeconds'],
    };
    final coverObjectId = cover['objectId']?.toString().trim() ?? '';
    final coverContentType = cover['contentType']?.toString().trim() ?? '';
    final coverSha256 = cover['sha256']?.toString().trim() ?? '';
    final coverSize = cover['size'];
    if (coverObjectId.isNotEmpty &&
        coverContentType.startsWith('image/') &&
        coverSha256.isNotEmpty &&
        coverSize is num &&
        coverSize.toInt() > 0) {
      attachment.addAll({
        'coverObjectId': coverObjectId,
        'coverContentType': coverContentType,
        'coverSize': coverSize.toInt(),
        'coverSha256': coverSha256,
        'coverWidth': covers.isEmpty
            ? cover['width']
            : covers.first.width ?? cover['width'],
        'coverHeight': covers.isEmpty
            ? cover['height']
            : covers.first.height ?? cover['height'],
      });
    }

    await _requireOutboxSession(session);
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/${item.conversationId}/media-messages',
      data: {
        'clientMessageId': item.clientMessageId,
        'kind': item.kind,
        'caption': item.content.trim(),
        'attachments': [attachment],
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return ImMessage.fromJson(response.data ?? <String, Object?>{});
  }

  Future<MultipartFile> _storedMultipart(
    String accountId,
    ImOutboxItem item,
    ImOutboxStoredFile file,
  ) async {
    await _outboxFiles.verify(
      accountId: accountId,
      clientMessageId: item.clientMessageId,
      file: file,
    );
    return MultipartFile.fromStream(
      () => _outboxFiles.openRead(
        accountId: accountId,
        clientMessageId: item.clientMessageId,
        file: file,
      ),
      file.length,
      filename: file.fileName,
      contentType: DioMediaType.parse(file.contentType),
    );
  }

  Future<ImMessage> _postContactCardMessage(
    MobileSession session,
    ImOutboxItem item,
  ) async {
    final dio = await _client.forIm(forSession: session);
    await _requireOutboxSession(session);
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/${item.conversationId}/contact-cards',
      data: {
        'clientMessageId': item.clientMessageId,
        'memberId': item.contactMemberId,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return ImMessage.fromJson(response.data ?? <String, Object?>{});
  }

  Future<ImSyncPullResult> pullEvents({
    int waitSeconds = 25,
    CancelToken? cancelToken,
    void Function(ImSyncPullResult result)? onCommitted,
  }) async {
    final totalTimer = kProfileMode ? (Stopwatch()..start()) : null;
    final session = await _session();
    final syncDeviceId = session.syncDeviceId;
    final cursor = await _store.lastEventSequence(session.userId, syncDeviceId);
    final dio = await _client.forIm(forSession: session);
    final acked = await _store.lastAckedEventSequence(
      session.userId,
      syncDeviceId,
    );
    if (cursor > acked) {
      await _ackEvents(dio, cursor, cancelToken: cancelToken);
      await _store.markEventsAcked(session.userId, syncDeviceId, cursor);
    }
    if ((await _sessionStore.readSession())?.isSameSession(session) != true) {
      return ImSyncPullResult.empty(cursor);
    }
    final requestTimer = kProfileMode ? (Stopwatch()..start()) : null;
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/sync/events',
      queryParameters: {
        'afterSequence': cursor,
        'waitSeconds': waitSeconds,
        'take': 500,
      },
      cancelToken: cancelToken,
    );
    requestTimer?.stop();
    if ((await _sessionStore.readSession())?.isSameSession(session) != true) {
      return ImSyncPullResult.empty(cursor);
    }
    final body = response.data ?? <String, Object?>{};
    final rawEvents = body['events'];
    final events = rawEvents is List
        ? rawEvents
              .whereType<Map>()
              .map(
                (value) => ImSyncEvent.fromJson(value.cast<String, Object?>()),
              )
              .where((event) => event.sequence > 0 && event.id.isNotEmpty)
              .toList()
        : <ImSyncEvent>[];
    final receivedAtUtc = DateTime.now().toUtc();
    final eventTimes = events
        .map((event) => event.createdAt?.toUtc())
        .whereType<DateTime>()
        .toList();
    final firstEventSequence = events.isEmpty
        ? null
        : events
              .map((event) => event.sequence)
              .reduce((left, right) => left < right ? left : right);
    final lastEventSequence = events.isEmpty
        ? null
        : events
              .map((event) => event.sequence)
              .reduce((left, right) => left > right ? left : right);
    final oldestEventAgeMs = eventTimes.isEmpty
        ? null
        : receivedAtUtc
              .difference(
                eventTimes.reduce(
                  (left, right) => left.isBefore(right) ? left : right,
                ),
              )
              .inMilliseconds;
    final newestEventAgeMs = eventTimes.isEmpty
        ? null
        : receivedAtUtc
              .difference(
                eventTimes.reduce(
                  (left, right) => left.isAfter(right) ? left : right,
                ),
              )
              .inMilliseconds;
    if (events.isEmpty) {
      totalTimer?.stop();
      _recordImSyncStage(
        waitSeconds: waitSeconds,
        eventCount: 0,
        requestMs: requestTimer?.elapsedMilliseconds,
        totalMs: totalTimer?.elapsedMilliseconds,
      );
      return ImSyncPullResult.empty(cursor);
    }

    final bootstrapTimer = kProfileMode ? (Stopwatch()..start()) : null;
    // start() refreshes and persists bootstrap before the event loop. Reusing
    // that account-scoped snapshot avoids one network round trip for every
    // small live-event batch while retaining the network fallback for direct
    // repository callers and first-run recovery.
    final cachedBootstrap = await _store.readBootstrap(session.userId);
    final bootstrap =
        cachedBootstrap ?? await _fetchBootstrap(forSession: session);
    bootstrapTimer?.stop();
    if ((await _sessionStore.readSession())?.isSameSession(session) != true) {
      return ImSyncPullResult.empty(cursor);
    }
    _readDiagnostics.events(events, bootstrap.currentMember.id, session.userId);
    final commitTimer = kProfileMode ? (Stopwatch()..start()) : null;
    await _store.applySyncBatch(
      accountId: session.userId,
      deviceId: syncDeviceId,
      events: events,
      bootstrap: bootstrap,
      replaceBootstrap: cachedBootstrap == null,
    );
    commitTimer?.stop();
    final latestSequence = events.fold<int>(
      cursor,
      (latest, event) => event.sequence > latest ? event.sequence : latest,
    );
    final result = ImSyncPullResult.fromEvents(
      latestSequence: latestSequence,
      events: events.where((event) => event.sequence > cursor).toList(),
    );
    if ((await _sessionStore.readSession())?.isSameSession(session) != true) {
      return ImSyncPullResult.empty(latestSequence);
    }
    // Durable content is already available to the UI. A slow/failed ACK must
    // not hide it until a later reconciliation; ACK errors still propagate to
    // the coordinator for retry/auth handling, without advancing acked state.
    if (result.changed) onCommitted?.call(result);
    await beforeEventAck?.call(latestSequence, events);
    if ((await _sessionStore.readSession())?.isSameSession(session) != true) {
      return ImSyncPullResult.empty(latestSequence);
    }
    final ackTimer = kProfileMode ? (Stopwatch()..start()) : null;
    await _ackEvents(dio, latestSequence, cancelToken: cancelToken);
    await _store.markEventsAcked(session.userId, syncDeviceId, latestSequence);
    ackTimer?.stop();
    totalTimer?.stop();
    _recordImSyncStage(
      waitSeconds: waitSeconds,
      eventCount: events.length,
      firstEventSequence: firstEventSequence,
      lastEventSequence: lastEventSequence,
      oldestEventAgeMs: oldestEventAgeMs,
      newestEventAgeMs: newestEventAgeMs,
      requestMs: requestTimer?.elapsedMilliseconds,
      bootstrapMs: bootstrapTimer?.elapsedMilliseconds,
      commitMs: commitTimer?.elapsedMilliseconds,
      ackMs: ackTimer?.elapsedMilliseconds,
      totalMs: totalTimer?.elapsedMilliseconds,
    );
    return result;
  }

  void _recordImSyncStage({
    required int waitSeconds,
    required int eventCount,
    int? firstEventSequence,
    int? lastEventSequence,
    int? oldestEventAgeMs,
    int? newestEventAgeMs,
    int? requestMs,
    int? bootstrapMs,
    int? commitMs,
    int? ackMs,
    int? totalMs,
  }) {
    if (!kProfileMode) return;
    debugPrint(
      'MOBILE_IM_SYNC_STAGE ${jsonEncode({'waitSeconds': waitSeconds, 'eventCount': eventCount, 'firstEventSequence': firstEventSequence, 'lastEventSequence': lastEventSequence, 'oldestEventAgeMs': oldestEventAgeMs, 'newestEventAgeMs': newestEventAgeMs, 'requestMs': requestMs, 'bootstrapMs': bootstrapMs, 'commitMs': commitMs, 'ackMs': ackMs, 'totalMs': totalMs})}',
    );
  }

  Future<void> _ackEvents(Dio dio, int sequence, {CancelToken? cancelToken}) =>
      dio.post<void>(
        '/api/im/sync/ack',
        data: {'eventSequence': sequence},
        cancelToken: cancelToken,
        options: Options(contentType: Headers.jsonContentType),
      );

  Future<void> markRead(String conversationId, int sequence) async {
    if (sequence <= 0) return;
    final session = await _session();
    _readDiagnostics.action(
      'visible_read_request',
      conversationId,
      sequence: sequence,
    );
    await _imReadRequest<void>(
      session,
      '/api/im/conversations/$conversationId/read',
      method: 'POST',
      data: {'sequence': sequence},
    );
    await _sessionStore.withCurrentSession(
      session,
      () =>
          _store.markConversationRead(session.userId, conversationId, sequence),
    );
    _readDiagnostics.action(
      'visible_read_confirmed',
      conversationId,
      sequence: sequence,
    );
    try {
      final mentions = await unreadMentions(
        conversationId: conversationId,
        forSession: session,
      );
      final visibleIds = mentions
          .where((item) => (item['sequence'] as int) <= sequence)
          .map((item) => item['messageId'] as String)
          .where((id) => id.isNotEmpty)
          .toList();
      if (visibleIds.isNotEmpty) {
        await markMentionsRead(visibleIds, forSession: session);
      }
    } on DioException {
      // Conversation read state is authoritative even when the mention
      // projection is temporarily unavailable; foreground sync retries it.
    }
  }

  Future<List<Map<String, Object>>> unreadMentions({
    String? conversationId,
    int afterSequence = 0,
    int take = 100,
    MobileSession? forSession,
  }) async {
    final session = forSession ?? await _session();
    final items = await _imReadRequest<List<Object?>>(
      session,
      '/api/im/mentions/unread',
      queryParameters: {
        'afterSequence': afterSequence < 0 ? 0 : afterSequence,
        'take': take.clamp(1, 500),
        if (conversationId?.isNotEmpty == true)
          'conversationId': conversationId,
      },
    );
    return (items ?? const <Object?>[]).whereType<Map>().map((item) {
      final value = item.cast<String, Object?>();
      return <String, Object>{
        'messageId': value['messageId']?.toString() ?? '',
        'conversationId': value['conversationId']?.toString() ?? '',
        'sequence': switch (value['sequence']) {
          int number => number,
          num number => number.toInt(),
          final value => int.tryParse(value?.toString() ?? '') ?? 0,
        },
      };
    }).toList();
  }

  Future<int> markMentionsRead(
    List<String> messageIds, {
    MobileSession? forSession,
  }) async {
    if (messageIds.isEmpty || messageIds.length > 500) {
      throw ArgumentError('一次需处理 1 到 500 条 @ 消息');
    }
    final session = forSession ?? await _session();
    final result = await _imReadRequest<Map<String, Object?>>(
      session,
      '/api/im/mentions/read',
      method: 'POST',
      data: {'messageIds': messageIds},
    );
    final affected = result?['affected'];
    return affected is num ? affected.toInt() : 0;
  }

  // History, profile and visible-read/mention chains retain their original login. Never
  // hold the session lock over a network wait, and discard late failures too.
  Future<T?> _imReadRequest<T>(
    MobileSession session,
    String path, {
    String method = 'GET',
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    await _sessionStore.withCurrentSession(session, () async {});
    final dio = await _client.forIm(forSession: session);
    try {
      await _sessionStore.withCurrentSession(session, () async {});
      final response = await dio.request<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        options: Options(method: method, contentType: Headers.jsonContentType),
      );
      return await _sessionStore.withCurrentSession(
        session,
        () async => response.data,
      );
    } on DioException {
      await _sessionStore.withCurrentSession(session, () async {});
      rethrow;
    } finally {
      dio.close();
    }
  }

  Future<void> registerPushDevice({
    required String platform,
    required String provider,
    required String token,
    String privacyMode = 'summary',
    MobileSession? forSession,
  }) async {
    if (AppEnvironment.demoMode) {
      final current = PreviewData.demoPushDevice;
      PreviewData.demoPushDevice = ImPushDevice(
        deviceId: PreviewData.demoDeviceId,
        platform: platform,
        provider: provider,
        privacyMode: privacyMode,
        isEnabled: true,
        lastPushEventSequence: current?.lastPushEventSequence ?? 0,
        updatedAt: DateTime.now(),
      );
      return;
    }
    final session = forSession ?? await _sessionStore.readSession();
    if (session == null) throw const SessionChangedException();
    await _requireOutboxSession(session);
    final dio = await _client.forIm(forSession: session);
    await dio.put<void>(
      '/api/im/push/devices/current',
      data: {
        'platform': platform,
        'provider': provider,
        'token': token,
        'privacyMode': privacyMode,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    await _requireOutboxSession(session);
  }

  Future<void> unregisterPushDevice({MobileSession? forSession}) async {
    if (AppEnvironment.demoMode) {
      final current = PreviewData.demoPushDevice;
      if (current != null) {
        PreviewData.demoPushDevice = ImPushDevice(
          deviceId: current.deviceId,
          platform: current.platform,
          provider: current.provider,
          privacyMode: current.privacyMode,
          isEnabled: false,
          lastPushEventSequence: current.lastPushEventSequence,
          updatedAt: DateTime.now(),
        );
      }
      return;
    }
    final session = forSession ?? await _sessionStore.readSession();
    if (session == null) throw const SessionChangedException();
    await _requireOutboxSession(session);
    final dio = await _client.forIm(forSession: session);
    await dio.delete<void>('/api/im/push/devices/current');
  }
}

String imOutboxFailureText(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null) {
      // Return a fixed operation label, never the request URL, headers or body.
      final route = Uri.tryParse(error.requestOptions.path)?.path ?? '';
      final operation = switch (route) {
        '/api/im/upload/video' => '视频上传',
        '/api/im/upload/audio' => '音频上传',
        '/api/im/upload/picture' => '封面上传',
        final value when value.endsWith('/media-messages') => '媒体消息提交',
        final value when value.endsWith('/images') => '图片发送',
        final value when value.endsWith('/attachments') => '文件发送',
        final value when value.endsWith('/messages') => '消息发送',
        _ => '消息服务请求',
      };
      return '$operation失败（HTTP $status）';
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => '网络超时，等待自动重试',
      DioExceptionType.connectionError => '网络不可用，等待自动重试',
      _ => '消息发送失败，等待自动重试',
    };
  }
  return '消息发送失败，等待自动重试';
}

bool isTransientImOutboxFailure(Object error) {
  if (error is! DioException) return true;
  final status = error.response?.statusCode;
  if (status != null) return status >= 500 || status == 408 || status == 429;
  return true;
}

bool isTransportImOutboxFailure(Object error) {
  if (error is! DioException || error.response != null) return false;
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.connectionError => true,
    _ => false,
  };
}

final class ImDownloadedAttachment {
  const ImDownloadedAttachment({
    required this.fileName,
    required this.bytes,
    required this.contentType,
  });

  final String fileName;
  final Uint8List bytes;
  final String contentType;
}

final class ImDownloadedAttachmentFile {
  const ImDownloadedAttachmentFile({
    required this.fileName,
    required this.path,
    required this.contentType,
  });

  final String fileName;
  final String path;
  final String contentType;
}

final class ImSyncPullResult {
  const ImSyncPullResult({
    required this.changed,
    required this.latestSequence,
    required this.conversationIds,
    required this.messageConversationIds,
    required this.memberConversationIds,
    required this.groupProfileConversationIds,
    required this.eventCount,
  });

  factory ImSyncPullResult.fromEvents({
    required int latestSequence,
    required List<ImSyncEvent> events,
  }) {
    final conversationIds = <String>{};
    final messageConversationIds = <String>{};
    final memberConversationIds = <String>{};
    final groupProfileConversationIds = <String>{};
    for (final event in events) {
      String conversationId;
      try {
        final payload = (jsonDecode(event.payloadJson) as Map)
            .cast<String, Object?>();
        conversationId =
            (payload['conversationId'] ?? payload['ConversationId'])
                ?.toString()
                .trim() ??
            '';
      } catch (_) {
        continue;
      }
      if (conversationId.isEmpty) continue;
      conversationIds.add(conversationId);
      final type = event.type.trim().toLowerCase();
      if (type.startsWith('message.') || type == 'conversation.read') {
        messageConversationIds.add(conversationId);
      }
      if (type.contains('.member.') ||
          type.endsWith('.members.updated') ||
          type.startsWith('member.')) {
        memberConversationIds.add(conversationId);
      }
      if (type.startsWith('group.') &&
          !type.startsWith('group.member.') &&
          !type.startsWith('group.message.')) {
        groupProfileConversationIds.add(conversationId);
      }
    }
    return ImSyncPullResult(
      changed: events.isNotEmpty,
      latestSequence: latestSequence,
      conversationIds: conversationIds,
      messageConversationIds: messageConversationIds,
      memberConversationIds: memberConversationIds,
      groupProfileConversationIds: groupProfileConversationIds,
      eventCount: events.length,
    );
  }

  factory ImSyncPullResult.empty(int sequence) => ImSyncPullResult(
    changed: false,
    latestSequence: sequence,
    conversationIds: const <String>{},
    messageConversationIds: const <String>{},
    memberConversationIds: const <String>{},
    groupProfileConversationIds: const <String>{},
    eventCount: 0,
  );

  final bool changed;
  final int latestSequence;
  final Set<String> conversationIds;
  final Set<String> messageConversationIds;
  final Set<String> memberConversationIds;
  final Set<String> groupProfileConversationIds;
  final int eventCount;
}

final class ImOutboxFlushResult {
  const ImOutboxFlushResult({
    required this.deliveredCount,
    required this.conversationIds,
  });

  final int deliveredCount;
  final Set<String> conversationIds;
}

bool imMessageSnapshotsDiffer(
  Iterable<ImMessage> cached,
  Iterable<ImMessage> latest,
) {
  final cachedById = <String, ImMessage>{
    for (final message in cached)
      if (message.id.isNotEmpty) message.id: message,
  };
  for (final message in latest) {
    final current = cachedById[message.id];
    if (current == null || !_sameServerMessageSnapshot(current, message)) {
      return true;
    }
  }
  return false;
}

bool _sameServerMessageSnapshot(ImMessage left, ImMessage right) {
  if (left.id != right.id ||
      left.sequence != right.sequence ||
      left.senderId != right.senderId ||
      left.clientMessageId != right.clientMessageId ||
      left.content != right.content ||
      left.kind != right.kind ||
      left.attachmentName != right.attachmentName ||
      left.attachmentSize != right.attachmentSize ||
      left.attachmentContentType != right.attachmentContentType ||
      left.attachmentSha256 != right.attachmentSha256 ||
      left.recalledAt?.toUtc() != right.recalledAt?.toUtc() ||
      left.images.length != right.images.length ||
      left.attachments.length != right.attachments.length ||
      left.mentions.length != right.mentions.length) {
    return false;
  }
  for (var index = 0; index < left.images.length; index += 1) {
    final a = left.images[index];
    final b = right.images[index];
    if (a.id != b.id || a.fileName != b.fileName || a.sha256 != b.sha256) {
      return false;
    }
  }
  for (var index = 0; index < left.attachments.length; index += 1) {
    final a = left.attachments[index];
    final b = right.attachments[index];
    if (a.id != b.id ||
        a.type != b.type ||
        a.fileName != b.fileName ||
        a.size != b.size ||
        a.sha256 != b.sha256 ||
        a.coverObjectId != b.coverObjectId ||
        a.coverContentType != b.coverContentType ||
        a.coverSize != b.coverSize ||
        a.coverSha256 != b.coverSha256 ||
        a.coverWidth != b.coverWidth ||
        a.coverHeight != b.coverHeight ||
        a.durationSeconds != b.durationSeconds) {
      return false;
    }
  }
  for (var index = 0; index < left.mentions.length; index += 1) {
    final a = left.mentions[index];
    final b = right.mentions[index];
    if (a.mentionedMemberId != b.mentionedMemberId ||
        a.displayName != b.displayName) {
      return false;
    }
  }
  return true;
}
