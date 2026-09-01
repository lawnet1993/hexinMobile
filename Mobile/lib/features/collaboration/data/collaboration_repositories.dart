import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/demo/preview_data.dart';
import '../../../core/network/collaboration_client.dart';
import '../../../core/storage/im_cache_cipher.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/collaboration_models.dart';
import 'im_local_store.dart';
import 'im_message_image_cache.dart';
import 'im_video_thumbnail.dart';
import 'oa_local_store.dart';

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

final imLocalStoreProvider = Provider<ImLocalStore>((ref) {
  final sessionStore = ref.read(secureSessionStoreProvider);
  final store = ImLocalStore(
    cipher: AesGcmImCacheCipher(sessionStore.readOrCreateImCacheKey),
  );
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
  return repository.approvalRequestNetworkFirst;
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
  );
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
});

final oaApplicationCatalogProvider = FutureProvider<OaApplicationCatalog>((
  ref,
) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return PreviewData.oaCatalog;
  return ref.read(oaRepositoryProvider).appCatalogCacheFirst();
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
});

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

final imBootstrapProvider = FutureProvider<ImBootstrap>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return _demoValue(PreviewData.imBootstrap);
  return ref.read(imRepositoryProvider).bootstrapCacheFirst();
});

final imDepartmentsProvider = FutureProvider<List<ImDepartment>>((ref) async {
  ref.watch(collaborationAccountScopeProvider);
  if (AppEnvironment.demoMode) return PreviewData.imDepartments;
  return ref.read(imRepositoryProvider).departmentsCacheFirst();
});

final pendingFriendApplicationsProvider =
    FutureProvider<List<ImFriendApplication>>((ref) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) return const [];
      return ref.read(imRepositoryProvider).pendingFriendApplications();
    });

final conversationMessagesProvider =
    FutureProvider.family<List<ImMessage>, String>((ref, id) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) return PreviewData.conversationMessages(id);
      return ref.read(imRepositoryProvider).messagesCacheFirst(id);
    });

typedef ConversationMessageWindowKey = ({String conversationId, int take});
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

final conversationMessageWindowProvider = FutureProvider.autoDispose
    .family<List<ImMessage>, ConversationMessageWindowKey>((ref, key) async {
      _retainForHotReopen(ref);
      ref.watch(collaborationAccountScopeProvider);
      ref.watch(conversationMessageRevisionProvider(key.conversationId));
      if (AppEnvironment.demoMode) {
        final messages = PreviewData.conversationMessages(key.conversationId);
        return messages.length <= key.take
            ? messages
            : messages.sublist(messages.length - key.take);
      }
      return ref.read(conversationMessageWindowLoaderProvider)(
        key.conversationId,
        take: key.take,
      );
    });

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
    return accountId;
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
      ref.watch(collaborationAccountScopeProvider);
      final accountId = await ref.read(imMediaCacheAccountLoaderProvider)();
      final cache = ref.read(imBinaryMemoryCacheProvider);
      final cacheKey = 'image:${key.messageId}:${key.imageId}';
      final cached = cache.read(accountId, cacheKey);
      if (cached != null) return cached;
      final diskCached = await ref.read(imMessageImageDiskCacheReaderProvider)(
        accountId: accountId,
        imageId: key.imageId,
        sha256Value: key.sha256,
      );
      if (diskCached != null) {
        cache.write(accountId, cacheKey, diskCached);
        return diskCached;
      }
      final bytes = await ref.read(imMessageImageBytesLoaderProvider)(
        key.messageId,
        key.imageId,
      );
      cache.write(accountId, cacheKey, bytes);
      await ref.read(imMessageImageDiskCacheWriterProvider)(
        accountId: accountId,
        imageId: key.imageId,
        sha256Value: key.sha256,
        bytes: bytes,
      );
      return bytes;
    });

final imMediaAttachmentProvider = FutureProvider.autoDispose
    .family<Uint8List, ({String attachmentId, bool cover})>((ref, key) async {
      ref.watch(collaborationAccountScopeProvider);
      final accountId = await ref.read(imMediaCacheAccountLoaderProvider)();
      final cache = ref.read(imBinaryMemoryCacheProvider);
      final cacheKey = 'media:${key.attachmentId}:${key.cover ? 1 : 0}';
      final cached = cache.read(accountId, cacheKey);
      if (cached != null) return cached;
      final bytes = await ref.read(imMediaAttachmentBytesLoaderProvider)(
        key.attachmentId,
        cover: key.cover,
      );
      cache.write(accountId, cacheKey, bytes);
      return bytes;
    });

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
  String sha256,
  int size,
});

final class ImVideoPreviewSource {
  const ImVideoPreviewSource.file(this.filePath) : bytes = null;

  const ImVideoPreviewSource.memory(this.bytes) : filePath = '';

  final String filePath;
  final Uint8List? bytes;
}

final imVideoPreviewProvider = FutureProvider.autoDispose
    .family<ImVideoPreviewSource?, ImVideoPreviewKey>((ref, key) async {
      _retainForHotReopen(ref);
      ref.watch(collaborationAccountScopeProvider);
      final repository = ref.read(imRepositoryProvider);
      final cacheKey = imVideoPreviewCacheKey(
        attachmentId: key.attachmentId,
        sha256Value: key.sha256,
        coverObjectId: key.coverObjectId,
      );
      final cachedPath = await readImVideoPreviewCachePath(cacheKey);
      if (cachedPath != null) return ImVideoPreviewSource.file(cachedPath);
      Uint8List? preview;
      if (key.coverObjectId.isNotEmpty) {
        try {
          preview = await repository.downloadMediaAttachment(
            key.attachmentId,
            cover: true,
          );
        } catch (_) {
          preview = null;
        }
      }
      if ((preview == null || preview.isEmpty) &&
          !AppEnvironment.demoMode &&
          key.size <= 32 * 1024 * 1024) {
        final videoBytes = await repository.downloadMediaAttachment(
          key.attachmentId,
        );
        preview = (await createImVideoThumbnail(
          videoBytes: videoBytes,
          fileName: key.fileName,
        ))?.bytes;
      }
      if (preview == null || preview.isEmpty) return null;
      final filePath = await writeImVideoPreviewCache(cacheKey, preview);
      return filePath == null ? null : ImVideoPreviewSource.file(filePath);
    });

void _retainForHotReopen(Ref ref) {
  final keepAlive = ref.keepAlive();
  Timer? expiry;
  ref.onCancel(() {
    expiry?.cancel();
    expiry = Timer(const Duration(minutes: 5), keepAlive.close);
  });
  ref.onResume(() {
    expiry?.cancel();
    expiry = null;
  });
  ref.onDispose(() => expiry?.cancel());
}

final oaAttachmentThumbnailProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, attachmentId) async {
      ref.watch(collaborationAccountScopeProvider);
      final accountId = await ref.read(imMediaCacheAccountLoaderProvider)();
      final cache = ref.read(imBinaryMemoryCacheProvider);
      final cacheKey = 'oa-thumbnail:$attachmentId';
      final cached = cache.read(accountId, cacheKey);
      if (cached != null) return cached;
      final bytes = await ref.read(oaAttachmentThumbnailBytesLoaderProvider)(
        attachmentId,
      );
      cache.write(accountId, cacheKey, bytes);
      return bytes;
    });

final conversationMembersProvider =
    FutureProvider.family<List<ImMember>, String>((ref, id) async {
      ref.watch(collaborationAccountScopeProvider);
      if (AppEnvironment.demoMode) {
        return PreviewData.conversationMembers(id);
      }
      return ref.read(imRepositoryProvider).conversationMembersCacheFirst(id);
    });

final conversationMemberPageProvider =
    FutureProvider.family<
      ImMemberPage,
      ({String conversationId, int page, int pageSize, String keyword})
    >((ref, key) async {
      ref.watch(collaborationAccountScopeProvider);
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
  return ref.read(imRepositoryProvider).badgeSummary();
});

final imAssistantTasksProvider = FutureProvider<List<ImAssistantTask>>((
  ref,
) async {
  ref.watch(collaborationAccountScopeProvider);
  return (await ref.watch(imAssistantTasksPageProvider(1).future)).items;
});

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
      return ref.read(imRepositoryProvider).conversationPresence(id);
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
  const OaSyncPullResult({required this.changed, required this.sequence});

  final bool changed;
  final int sequence;
}

final class OaRepository {
  OaRepository(this._client, this._sessionStore, this._store);

  final CollaborationClient _client;
  final SecureSessionStore _sessionStore;
  final OaLocalStore _store;

  Future<MobileSession> _session() async {
    if (AppEnvironment.demoMode) return _demoSession;
    final session = await _sessionStore.readSession();
    if (session == null || session.userId.isEmpty) {
      throw StateError('登录状态已失效，请重新登录');
    }
    return session;
  }

  Future<OaBootstrap> bootstrapCacheFirst() async {
    final session = await _session();
    final cached = await _store.readObject(
      session.userId,
      OaLocalStore.bootstrapCacheKey,
    );
    return cached == null ? refreshBootstrap() : OaBootstrap.fromJson(cached);
  }

  Future<OaBootstrap> refreshBootstrap() async {
    final session = await _session();
    final payload = await _fetchBootstrap();
    await _store.writeObject(
      session.userId,
      OaLocalStore.bootstrapCacheKey,
      payload,
    );
    return OaBootstrap.fromJson(payload);
  }

  Future<OaApplicationCatalog> appCatalogCacheFirst() async {
    final session = await _session();
    final cached = await _store.readObject(
      session.userId,
      OaLocalStore.catalogCacheKey,
    );
    return cached == null
        ? refreshAppCatalog()
        : OaApplicationCatalog.fromJson(cached);
  }

  Future<OaApplicationCatalog> refreshAppCatalog() async {
    final session = await _session();
    final payload = await _fetchAppCatalog();
    await _store.writeObject(
      session.userId,
      OaLocalStore.catalogCacheKey,
      payload,
    );
    return OaApplicationCatalog.fromJson(payload);
  }

  Future<OaApprovalRequest> approvalRequestCacheFirst(String requestId) async {
    final session = await _session();
    final cacheKey = 'approval:$requestId';
    final cached = await _store.readObject(session.userId, cacheKey);
    if (cached != null) return OaApprovalRequest.fromJson(cached);
    return refreshApprovalRequest(requestId);
  }

  Future<OaApprovalRequest> approvalRequestNetworkFirst(
    String requestId,
  ) async {
    try {
      return await refreshApprovalRequest(requestId);
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      final session = await _session();
      final cached = await _store.readObject(
        session.userId,
        'approval:$requestId',
      );
      if (cached == null) rethrow;
      return OaApprovalRequest.fromJson(cached);
    }
  }

  Future<OaApprovalRequest> refreshApprovalRequest(String requestId) async {
    final session = await _session();
    final dio = await _client.forOa();
    final response = await dio.get<Map<String, Object?>>(
      '/api/oa/approval-requests/$requestId',
    );
    final payload = response.data ?? <String, Object?>{};
    await _store.writeObject(session.userId, 'approval:$requestId', payload);
    return OaApprovalRequest.fromJson(payload);
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
    final dio = await _client.forOa();
    final response = await dio.get<Map<String, Object?>>(
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
    return OaApprovalRequestPage.fromJson(
      response.data ?? const <String, Object?>{},
    );
  }

  Future<OaApprovalRequest> reviewApproval({
    required String requestId,
    required String taskId,
    required int expectedTaskVersion,
    required String decision,
    required String comment,
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
    final session = await _session();
    final dio = await _client.forOa();
    final response = await dio.patch<Map<String, Object?>>(
      '/api/oa/approval-requests/$requestId/review',
      data: {
        'taskId': taskId,
        'expectedTaskVersion': expectedTaskVersion,
        'idempotencyKey': const Uuid().v4(),
        'decision': decision,
        'comment': comment,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    final payload = response.data ?? <String, Object?>{};
    await _store.writeObject(session.userId, 'approval:$requestId', payload);
    await _store.invalidate(session.userId, [
      OaLocalStore.bootstrapCacheKey,
      OaLocalStore.notificationsCacheKey,
    ]);
    return OaApprovalRequest.fromJson(payload);
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
  }) => _postApprovalAction(requestId, 'withdraw', {
    'idempotencyKey': const Uuid().v4(),
    'reason': reason,
  });

  Future<OaApprovalRequest> transferApproval({
    required String requestId,
    required OaApprovalTask task,
    required String newAssigneeId,
    required String reason,
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
    });
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
  }) => _postApprovalAction(requestId, 'add-sign', {
    'taskId': task.id,
    'expectedTaskVersion': task.version,
    'idempotencyKey': const Uuid().v4(),
    'addedAssigneeId': addedAssigneeId,
    'mode': mode,
    'comment': comment,
  });

  Future<OaApprovalRequest> returnApproval({
    required String requestId,
    required OaApprovalTask task,
    required String reason,
  }) => _postApprovalAction(requestId, 'return', {
    'taskId': task.id,
    'expectedTaskVersion': task.version,
    'idempotencyKey': const Uuid().v4(),
    'reason': reason,
  });

  Future<OaApprovalRequest> remindApproval({
    required String requestId,
    required String comment,
  }) => _postApprovalAction(requestId, 'remind', {
    'idempotencyKey': const Uuid().v4(),
    'comment': comment,
  });

  Future<void> markApprovalCcRead(String requestId) async {
    final session = await _session();
    final dio = await _client.forOa();
    await dio.post<void>('/api/oa/approval-requests/$requestId/cc/read');
    await _store.invalidate(session.userId, [
      OaLocalStore.bootstrapCacheKey,
      OaLocalStore.notificationsCacheKey,
    ]);
  }

  Future<OaWorkflowPreview> previewWorkflow({
    required String applicationKey,
    required OaApprovalTemplate template,
    required Map<String, Object?> formData,
  }) async {
    if (AppEnvironment.demoMode) return PreviewData.workflowPreview(template);
    final dio = await _client.forOa();
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/workflow-resolution/preview',
      data: {
        'applicationKey': applicationKey,
        'templateId': template.id,
        'workflowKey': template.workflowKey,
        'formDataJson': jsonEncode(formData),
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    return OaWorkflowPreview.fromJson(
      response.data ?? const <String, Object?>{},
    );
  }

  Future<OaApprovalRequest> _postApprovalAction(
    String requestId,
    String action,
    Map<String, Object?> data,
  ) async {
    final session = await _session();
    final dio = await _client.forOa();
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/approval-requests/$requestId/$action',
      data: data,
      options: Options(contentType: Headers.jsonContentType),
    );
    final payload = response.data ?? <String, Object?>{};
    await _store.writeObject(session.userId, 'approval:$requestId', payload);
    await _store.invalidate(session.userId, [
      OaLocalStore.bootstrapCacheKey,
      OaLocalStore.notificationsCacheKey,
    ]);
    return OaApprovalRequest.fromJson(payload);
  }

  Future<OaApprovalRequest> submitApproval({
    required String applicationKey,
    required OaApprovalTemplate template,
    required String title,
    required Map<String, Object?> formData,
    List<String> attachmentIds = const [],
    List<Map<String, Object?>> attachmentBindings = const [],
    List<OaLocalAttachment> pendingAttachments = const [],
    bool allowOfflineQueue = false,
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
    final payload = <String, Object?>{
      'applicationKey': applicationKey,
      'templateId': template.id,
      'workflowKey': template.workflowKey,
      'clientRequestId': clientRequestId,
      'title': title,
      'formDataJson': jsonEncode(formData),
      'attachmentIds': attachmentIds,
      if (attachmentBindings.isNotEmpty)
        'attachmentBindings': attachmentBindings,
      'pendingAttachments': pendingAttachments
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
    var outboxItem = await _store.enqueue(
      session.userId,
      id: outboxId,
      idempotencyKey: clientRequestId,
      commandType: 'submit-approval',
      payload: payload,
    );
    try {
      final response = await _deliverApprovalOutbox(session.userId, outboxItem);
      await _store.removeOutbox(session.userId, outboxId);
      await _store.invalidate(session.userId, [
        OaLocalStore.bootstrapCacheKey,
        OaLocalStore.notificationsCacheKey,
      ]);
      return OaApprovalRequest.fromJson(response);
    } on DioException catch (error) {
      final permanent = !_isTransient(error);
      await _store.markOutboxFailed(
        session.userId,
        outboxItem,
        _dioMessage(error),
        permanent: permanent,
      );
      if (!permanent && allowOfflineQueue) {
        outboxItem = (await _store.readOutbox(session.userId))
            .firstWhere((item) => item.id == outboxId);
        throw OaSubmissionQueuedException(outboxItem);
      }
      if (!permanent) await _store.removeOutbox(session.userId, outboxId);
      rethrow;
    }
  }

  Future<OaApprovalAttachment> uploadAttachment({
    required String fileName,
    required List<int> bytes,
    String contentType = 'application/octet-stream',
  }) async {
    final dio = await _client.forOa();
    final response = await dio.post<Map<String, Object?>>(
      '/api/oa/attachments',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
      }),
    );
    return OaApprovalAttachment.fromJson(response.data ?? <String, Object?>{});
  }

  Future<void> deleteAttachment(String attachmentId) async {
    final dio = await _client.forOa();
    await dio.delete<void>('/api/oa/attachments/$attachmentId');
  }

  Future<Uint8List> downloadAttachment(String attachmentId) async {
    final dio = await _client.forOa();
    final response = await dio.get<List<int>>(
      '/api/oa/attachments/$attachmentId',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<Uint8List> downloadAttachmentThumbnail(String attachmentId) async {
    final dio = await _client.forOa();
    final response = await dio.get<List<int>>(
      '/api/oa/attachments/$attachmentId/thumbnail',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<Uint8List> downloadAttachmentPreview(String attachmentId) async {
    final dio = await _client.forOa();
    final response = await dio.get<List<int>>(
      '/api/oa/attachments/$attachmentId/preview',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
  }

  Future<List<OaNotification>> notificationsCacheFirst() async {
    final session = await _session();
    final cached = await _store.readList(
      session.userId,
      OaLocalStore.notificationsCacheKey,
    );
    return cached == null
        ? refreshNotifications()
        : _notificationModels(cached);
  }

  Future<List<OaNotification>> refreshNotifications({
    bool unreadOnly = false,
  }) async {
    final session = await _session();
    final page = await notificationPage(unreadOnly: unreadOnly);
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
    return page.items;
  }

  Future<OaNotificationPage> notificationPage({
    String? cursor,
    bool unreadOnly = false,
    int take = 100,
  }) async {
    final dio = await _client.forOa();
    final response = await dio.get<Map<String, Object?>>(
      '/api/oa/notifications/page',
      queryParameters: {
        'take': take.clamp(1, 200),
        'unreadOnly': unreadOnly,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    return OaNotificationPage.fromJson(
      response.data ?? const <String, Object?>{},
    );
  }

  Future<OaNotificationPage> notificationPageCacheFirst({
    String? cursor,
    bool unreadOnly = false,
    int take = 100,
  }) async {
    if (cursor != null && cursor.isNotEmpty) {
      return notificationPage(
        cursor: cursor,
        unreadOnly: unreadOnly,
        take: take,
      );
    }
    final session = await _session();
    final cachedPage = await _store.readObject(
      session.userId,
      OaLocalStore.notificationPageCacheKey,
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
    final legacy = await _store.readList(
      session.userId,
      OaLocalStore.notificationsCacheKey,
    );
    if (legacy != null) {
      final items = _notificationModels(legacy)
          .where((item) => !unreadOnly || !item.isRead)
          .take(take.clamp(1, 200))
          .toList();
      return OaNotificationPage(items: items, nextCursor: null, hasMore: false);
    }
    final page = await notificationPage(unreadOnly: unreadOnly, take: take);
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
    final dio = await _client.forOa();
    await dio.post<void>('/api/oa/notifications/$notificationId/read');
    await _updateCachedNotificationReadState(
      session.userId,
      notificationId: notificationId,
    );
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
    final dio = await _client.forOa();
    await dio.post<void>('/api/oa/notifications/read-all');
    await _updateCachedNotificationReadState(session.userId);
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
    final cached = await _store.readObject(
      session.userId,
      OaLocalStore.attendanceCacheKey,
    );
    return cached == null
        ? refreshAttendanceOverview()
        : OaAttendanceOverview.fromJson(cached);
  }

  Future<OaAttendanceOverview> refreshAttendanceOverview() async {
    final session = await _session();
    final payload = await _fetchAttendanceOverview();
    await _store.writeObject(
      session.userId,
      OaLocalStore.attendanceCacheKey,
      payload,
    );
    return OaAttendanceOverview.fromJson(payload);
  }

  Future<Map<String, Object?>> _fetchAttendanceOverview() async {
    final dio = await _client.forOa();
    final response = await dio.get<Map<String, Object?>>(
      '/api/oa/attendance/overview',
    );
    return response.data ?? <String, Object?>{};
  }

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
    return _store.readDrafts(session.userId);
  }

  Future<OaApprovalDraft?> draftForTemplate(String templateId) async {
    final session = await _session();
    return _store.readDraftForTemplate(session.userId, templateId);
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
    final draft = OaApprovalDraft(
      id: id ?? const Uuid().v4(),
      applicationKey: applicationKey,
      templateId: template.id,
      workflowKey: template.workflowKey,
      title: title,
      formData: Map<String, Object?>.from(formData),
      attachments: List<OaLocalAttachment>.from(attachments),
      updatedAt: DateTime.now().toUtc(),
    );
    return _store.saveDraft(session.userId, draft);
  }

  Future<void> deleteDraft(String draftId) async {
    final session = await _session();
    await _store.deleteDraft(session.userId, draftId);
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
    await _store.removeOutbox(session.userId, itemId);
  }

  Future<int> flushOutbox() async {
    final session = await _session();
    final items = await _store.dueOutbox(session.userId);
    var delivered = 0;
    for (final item in items) {
      if (item.commandType != 'submit-approval') continue;
      try {
        await _deliverApprovalOutbox(session.userId, item);
        await _store.removeOutbox(session.userId, item.id);
        delivered++;
      } on DioException catch (error) {
        await _store.markOutboxFailed(
          session.userId,
          item,
          _dioMessage(error),
          permanent: !_isTransient(error),
        );
      } catch (error) {
        await _store.markOutboxFailed(
          session.userId,
          item,
          error.toString(),
          permanent: true,
        );
      }
    }
    if (delivered > 0) {
      await _store.invalidate(session.userId, [
        OaLocalStore.bootstrapCacheKey,
        OaLocalStore.notificationsCacheKey,
      ]);
    }
    return delivered;
  }

  Future<OaSyncPullResult> pullEvents({CancelToken? cancelToken}) async {
    final session = await _session();
    final cursor = await _store.lastEventSequence(session.userId);
    final dio = await _client.forOa();
    final response = await dio.get<Map<String, Object?>>(
      '/api/oa/sync/events',
      queryParameters: {
        'afterSequence': cursor,
        'waitSeconds': 20,
        'take': 200,
      },
      cancelToken: cancelToken,
    );
    final body = response.data ?? <String, Object?>{};
    final events = (body['events'] is List ? body['events'] as List : const [])
        .whereType<Map>()
        .map((item) => OaSyncEvent.fromJson(item.cast<String, Object?>()))
        .where((event) => event.sequence > cursor)
        .toList();
    if (events.isEmpty) {
      return OaSyncPullResult(changed: false, sequence: cursor);
    }

    final notificationsPage = await notificationPage();
    final caches = <String, String>{
      OaLocalStore.bootstrapCacheKey: jsonEncode(await _fetchBootstrap()),
      OaLocalStore.notificationsCacheKey: jsonEncode(
        notificationsPage.items.map((item) => item.toJson()).toList(),
      ),
      OaLocalStore.notificationPageCacheKey: jsonEncode(
        notificationsPage.toJson(),
      ),
    };
    if (events.any((event) => event.type == 'oa.app-catalog.changed')) {
      caches[OaLocalStore.catalogCacheKey] = jsonEncode(
        await _fetchAppCatalog(),
      );
    }
    if (events.any((event) => event.type.contains('attendance'))) {
      caches[OaLocalStore.attendanceCacheKey] = jsonEncode(
        await _fetchAttendanceOverview(),
      );
    }
    await _store.applySyncBatch(
      accountId: session.userId,
      events: events,
      refreshedCaches: caches,
    );
    return OaSyncPullResult(changed: true, sequence: events.last.sequence);
  }

  Future<void> refreshWorkspace() async {
    await Future.wait([
      refreshBootstrap(),
      refreshAppCatalog(),
      refreshNotifications(),
    ]);
  }

  Future<Map<String, Object?>> _fetchBootstrap() async {
    final dio = await _client.forOa();
    final response = await dio.get<Map<String, Object?>>('/api/oa/bootstrap');
    return response.data ?? <String, Object?>{};
  }

  Future<Map<String, Object?>> _fetchAppCatalog() async {
    final dio = await _client.forOa();
    final response = await dio.get<Map<String, Object?>>('/api/oa/app-catalog');
    return response.data ?? <String, Object?>{};
  }

  Future<Map<String, Object?>> _sendApprovalPayload(
    Map<String, Object?> payload,
  ) async {
    final dio = await _client.forOa();
    final requestPayload = Map<String, Object?>.from(payload)
      ..remove('pendingAttachments');
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

  Future<Map<String, Object?>> _deliverApprovalOutbox(
    String accountId,
    OaOutboxItem item,
  ) async {
    final payload = Map<String, Object?>.from(item.payload);
    final attachmentIds =
        (payload['attachmentIds'] is List
                ? payload['attachmentIds'] as List
                : const <Object?>[])
            .map((value) => value.toString())
            .toList();
    final pending = _localAttachments(payload['pendingAttachments']);
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

    while (pending.isNotEmpty) {
      final local = pending.first;
      final uploaded = await uploadAttachment(
        fileName: local.fileName,
        bytes: local.bytes,
        contentType: local.contentType,
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
      await _store.updateOutboxPayload(accountId, item.id, payload);
    }

    return _sendApprovalPayload(payload);
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

bool _isTransient(DioException error) {
  if (error.response == null) return true;
  final status = error.response!.statusCode ?? 0;
  return status == 408 || status == 429 || status >= 500;
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
  ImRepository(this._client, this._sessionStore, this._store);

  final CollaborationClient _client;
  final SecureSessionStore _sessionStore;
  final ImLocalStore _store;

  Future<MobileSession> _session() async {
    if (AppEnvironment.demoMode) return _demoSession;
    final session = await _sessionStore.readSession();
    if (session == null || session.userId.isEmpty) {
      throw StateError('登录状态已失效，请重新登录');
    }
    return session;
  }

  Future<ImBootstrap> bootstrapCacheFirst() async {
    final session = await _session();
    final cached = await _store.readBootstrap(session.userId);
    return cached ?? refreshBootstrap();
  }

  Future<ImBootstrap> refreshBootstrap() async {
    final session = await _session();
    final result = await _fetchBootstrap();
    await _store.replaceBootstrap(session.userId, result);
    return result;
  }

  Future<ImBootstrap> _fetchBootstrap() async {
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>('/api/im/bootstrap');
    return ImBootstrap.fromJson(response.data ?? <String, Object?>{});
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
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/members/$memberId/profile',
    );
    return ImMemberProfile.fromJson(response.data ?? <String, Object?>{});
  }

  Future<ImMemberProfile> updateProfile({
    required String nickname,
    required String signature,
  }) async {
    final normalizedNickname = nickname.trim();
    final normalizedSignature = signature.trim();
    if (normalizedNickname.length > 128 || normalizedSignature.length > 280) {
      throw ArgumentError('昵称或签名超出长度限制');
    }
    final dio = await _client.forIm();
    final response = await dio.put<Map<String, Object?>>(
      '/api/im/profile',
      data: {'nickname': normalizedNickname, 'signature': normalizedSignature},
    );
    await refreshBootstrap();
    return ImMemberProfile.fromJson(response.data ?? <String, Object?>{});
  }

  Future<void> updateAvatar({
    required String avatarKey,
    String? avatarDataUrl,
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
    final dio = await _client.forIm();
    await dio.put<void>(
      '/api/im/profile/avatar',
      data: {'avatarKey': key, 'avatarDataUrl': avatarDataUrl},
      options: Options(contentType: Headers.jsonContentType),
    );
    await refreshBootstrap();
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
    final cached = await _store.readMessages(
      session.userId,
      conversationId,
      limit: take,
    );
    return cached.isNotEmpty ? cached : refreshMessages(conversationId);
  }

  Future<List<ImMember>> conversationMembersCacheFirst(
    String conversationId,
  ) async {
    final session = await _session();
    final cached = await _store.readConversationMembers(
      session.userId,
      conversationId,
    );
    try {
      return await refreshConversationMembers(conversationId);
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<ImMember>> refreshConversationMembers(
    String conversationId,
  ) async {
    final session = await _session();
    final dio = await _client.forIm();
    final response = await dio.get<List<Object?>>(
      '/api/im/conversations/$conversationId/members',
    );
    final members = (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => ImMember.fromJson(item.cast<String, Object?>()))
        .toList();
    await _store.replaceConversationMembers(
      session.userId,
      conversationId,
      members,
    );
    return members;
  }

  Future<ImMemberPage> conversationMemberPage(
    String conversationId, {
    int page = 1,
    int pageSize = 50,
    String keyword = '',
  }) async {
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/conversations/$conversationId/members/page',
      queryParameters: {
        'page': page.clamp(1, 100000),
        'pageSize': pageSize.clamp(1, 100),
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
      },
    );
    return ImMemberPage.fromJson(response.data ?? const <String, Object?>{});
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
    final messages = await _fetchLatestMessages(conversationId);
    await _store.mergeMessages(session.userId, conversationId, messages);
    return _store.readMessages(session.userId, conversationId);
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
    final latest = await _fetchLatestMessages(conversationId);
    if (latest.isEmpty) return false;
    final cached = await _store.readMessages(
      session.userId,
      conversationId,
      limit: latest.length.clamp(1, 50),
    );
    if (!imMessageSnapshotsDiffer(cached, latest)) return false;
    await _store.mergeMessages(session.userId, conversationId, latest);
    return true;
  }

  Future<List<ImMessage>> _fetchLatestMessages(String conversationId) async {
    final dio = await _client.forIm();
    final response = await dio.get<List<Object?>>(
      '/api/im/conversations/$conversationId/messages',
      queryParameters: const {'take': 50},
    );
    return (response.data ?? const <Object?>[])
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
      final cached = await _store.readMessages(
        session.userId,
        conversationId,
        limit: 80,
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
    final dio = await _client.forIm();
    final response = await dio.get<List<Object?>>(
      '/api/im/conversations/$conversationId/messages',
      queryParameters: {'beforeSequence': cursor, 'take': 80},
    );
    final older =
        (response.data ?? const <Object?>[])
            .whereType<Map>()
            .map((item) => ImMessage.fromJson(item.cast<String, Object?>()))
            .where(
              (message) => message.sequence > 0 && message.sequence < cursor!,
            )
            .toList()
          ..sort((left, right) => left.sequence.compareTo(right.sequence));
    if (older.isNotEmpty) {
      await _store.mergeMessages(session.userId, conversationId, older);
    }
    return older;
  }

  Future<ImMessage?> retryMessage(
    String conversationId,
    String clientMessageId,
  ) async {
    if (clientMessageId.isEmpty) return null;
    final session = await _session();
    await _store.retryOutboxNow(session.userId, clientMessageId);
    await flushOutbox();
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
  }) async {
    final session = await _session();
    final clientMessageId = const Uuid().v4();
    final local = await _store.enqueueText(
      accountId: session.userId,
      senderId: session.userId,
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      content: content,
      mentionedMemberIds: mentionedMemberIds,
      mentionAll: mentionAll,
      replyToMessageId: replyToMessageId ?? replyTo?.messageId,
      replyTo: replyTo,
    );
    await flushOutbox();
    final messages = await _store.readMessages(session.userId, conversationId);
    return messages.firstWhere(
      (message) => message.clientMessageId == clientMessageId,
      orElse: () => local,
    );
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
    await refreshBootstrap();
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
    await refreshBootstrap();
    return conversation;
  }

  Future<ImMessage> sendAttachment({
    required String conversationId,
    required String fileName,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
  }) async {
    final session = await _session();
    final clientMessageId = const Uuid().v4();
    final local = await _store.enqueueAttachment(
      accountId: session.userId,
      senderId: session.userId,
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      fileName: fileName,
      bytes: bytes,
      contentType: contentType,
    );
    await flushOutbox();
    final messages = await _store.readMessages(session.userId, conversationId);
    return messages.firstWhere(
      (message) => message.clientMessageId == clientMessageId,
      orElse: () => local,
    );
  }

  Future<ImMessage> sendImages({
    required String conversationId,
    required List<({String fileName, Uint8List bytes, String contentType})>
    files,
    String caption = '',
  }) async {
    if (files.isEmpty || files.length > 9) {
      throw ArgumentError('请选择 1–9 张图片');
    }
    if (files.any(
      (file) => file.bytes.isEmpty || file.bytes.length > 52428800,
    )) {
      throw ArgumentError('图片必须非空且不超过 50 MB');
    }
    final session = await _session();
    final dio = await _client.forIm();
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/$conversationId/images',
      data: FormData.fromMap({
        'clientMessageId': const Uuid().v4(),
        'caption': caption.trim(),
        'files': files
            .map(
              (file) => MultipartFile.fromBytes(
                file.bytes,
                filename: file.fileName,
                contentType: DioMediaType.parse(file.contentType),
              ),
            )
            .toList(),
      }),
    );
    final message = ImMessage.fromJson(response.data ?? <String, Object?>{});
    await _store.mergeMessages(session.userId, conversationId, [message]);
    await refreshBootstrap();
    return message;
  }

  Future<Uint8List> downloadMessageImage(
    String messageId,
    String imageId,
  ) async {
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
    final dio = await _client.forIm();
    final uploadResponse = await dio.post<Map<String, Object?>>(
      '/api/im/upload/$normalizedKind',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
      }),
    );
    final uploaded = uploadResponse.data ?? <String, Object?>{};
    final objectId = uploaded['objectId']?.toString() ?? '';
    if (objectId.isEmpty) throw StateError('媒体上传未返回对象标识');
    Map<String, Object?> cover = const {};
    if (normalizedKind == 'video' &&
        coverBytes != null &&
        coverBytes.isNotEmpty) {
      try {
        final coverResponse = await dio.post<Map<String, Object?>>(
          '/api/im/upload/picture',
          data: FormData.fromMap({
            'file': MultipartFile.fromBytes(
              coverBytes,
              filename: '${path.basenameWithoutExtension(fileName)}-cover.jpg',
              contentType: DioMediaType.parse('image/jpeg'),
            ),
          }),
        );
        cover = coverResponse.data ?? const {};
      } catch (_) {
        // A missing cover must not discard a successfully uploaded video.
      }
    }
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/$conversationId/media-messages',
      data: {
        'clientMessageId': const Uuid().v4(),
        'kind': normalizedKind,
        'caption': caption.trim(),
        'attachments': [
          {
            'objectId': objectId,
            'fileName': uploaded['fileName']?.toString() ?? fileName,
            'contentType': uploaded['contentType']?.toString() ?? contentType,
            'size': uploaded['size'] ?? bytes.length,
            'sha256': uploaded['sha256']?.toString() ?? '',
            'width': uploaded['width'],
            'height': uploaded['height'],
            'coverObjectId': cover['objectId']?.toString() ?? '',
            'coverWidth': coverWidth ?? cover['width'],
            'coverHeight': coverHeight ?? cover['height'],
            'durationSeconds': uploaded['durationSeconds'],
          },
        ],
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    final message = ImMessage.fromJson(response.data ?? <String, Object?>{});
    if (normalizedKind == 'video' &&
        coverBytes != null &&
        coverBytes.isNotEmpty &&
        message.attachments.isNotEmpty) {
      final attachment = message.attachments.first;
      await writeImVideoPreviewCache(
        imVideoPreviewCacheKey(
          attachmentId: attachment.id,
          sha256Value: attachment.sha256,
          coverObjectId: attachment.coverObjectId,
        ),
        coverBytes,
      );
    }
    await _store.mergeMessages(session.userId, conversationId, [message]);
    await refreshBootstrap();
    return message;
  }

  Future<Uint8List> downloadMediaAttachment(
    String attachmentId, {
    bool cover = false,
  }) async {
    if (attachmentId.trim().isEmpty) throw StateError('媒体附件无效');
    final dio = await _client.forIm();
    final response = await dio.get<List<int>>(
      '/api/im/media-attachments/$attachmentId',
      queryParameters: {'cover': cover},
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(response.data ?? const <int>[]);
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
    await flushOutbox();
    final messages = await _store.readMessages(session.userId, conversationId);
    return messages.firstWhere(
      (message) => message.clientMessageId == clientMessageId,
      orElse: () => local,
    );
  }

  Future<ImDownloadedAttachment> downloadAttachment(ImMessage message) async {
    if (message.id.isEmpty) throw StateError('附件消息无效');
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

  Future<List<ImMember>> groupManagers(String conversationId) async {
    final dio = await _client.forIm();
    final response = await dio.get<List<Object?>>(
      '/api/im/groups/$conversationId/managers',
    );
    return (response.data ?? const <Object?>[])
        .whereType<Map>()
        .map((item) => ImMember.fromJson(item.cast<String, Object?>()))
        .toList();
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
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/groups/$conversationId/management/muted-members',
      queryParameters: {
        'page': page < 1 ? 1 : page,
        'pageSize': pageSize.clamp(1, 100),
      },
    );
    return ImGroupManagementPage<ImMutedGroupMember>.fromJson(
      response.data ?? const <String, Object?>{},
      ImMutedGroupMember.fromJson,
    );
  }

  Future<ImGroupManagementPage<ImMember>> groupManagersPage(
    String conversationId, {
    int page = 1,
    int pageSize = 50,
  }) async {
    if (AppEnvironment.demoMode) {
      return PreviewData.groupManagersPage(conversationId);
    }
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/groups/$conversationId/management/managers',
      queryParameters: {
        'page': page < 1 ? 1 : page,
        'pageSize': pageSize.clamp(1, 100),
      },
    );
    return ImGroupManagementPage<ImMember>.fromJson(
      response.data ?? const <String, Object?>{},
      ImMember.fromJson,
    );
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
    final dio = await _client.forIm();
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
    return [
      ImSearchResult.fromJson(<String, Object?>{...member, 'type': 'member'}),
    ];
  }

  Future<ImConversationPresence> conversationPresence(
    String conversationId,
  ) async {
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/conversations/$conversationId/presence',
    );
    return ImConversationPresence.fromJson(
      response.data ?? <String, Object?>{},
    );
  }

  Future<void> enterConversation(String conversationId) async {
    final dio = await _client.forIm();
    await dio.put<void>('/api/im/conversations/$conversationId/active');
  }

  Future<void> leaveActiveConversation() async {
    final dio = await _client.forIm();
    await dio.delete<void>('/api/im/conversations/active');
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
    final dio = await _client.forIm();
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/messages/$messageId/read-receipts',
    );
    return ImMessageReadReceipt.fromJson(
      response.data ?? const <String, Object?>{},
    );
  }

  Future<int> flushOutbox() async =>
      (await flushOutboxDetailed()).deliveredCount;

  Future<ImOutboxFlushResult> flushOutboxDetailed() async {
    final session = await _session();
    final items = await _store.dueOutbox(session.userId);
    var delivered = 0;
    final conversationIds = <String>{};
    for (final item in items) {
      try {
        final message = await _postMessage(item);
        await _store.markOutboxSent(
          session.userId,
          item.clientMessageId,
          message,
        );
        delivered += 1;
        conversationIds.add(item.conversationId);
      } catch (error) {
        await _store.markOutboxFailed(
          session.userId,
          item,
          _compactError(error),
        );
        conversationIds.add(item.conversationId);
        if (_isTransientOutboxFailure(error)) break;
      }
    }
    return ImOutboxFlushResult(
      deliveredCount: delivered,
      conversationIds: conversationIds,
    );
  }

  Future<ImMessage> _postMessage(ImOutboxItem item) async {
    return switch (item.kind) {
      'file' => _postAttachmentMessage(item),
      'contact' => _postContactCardMessage(item),
      _ => _postTextMessage(item),
    };
  }

  Future<ImMessage> _postTextMessage(ImOutboxItem item) async {
    final dio = await _client.forIm();
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

  Future<ImMessage> _postAttachmentMessage(ImOutboxItem item) async {
    final dio = await _client.forIm();
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/conversations/${item.conversationId}/attachments',
      data: FormData.fromMap({
        'clientMessageId': item.clientMessageId,
        'file': MultipartFile.fromBytes(
          item.attachmentBytes,
          filename: item.attachmentName,
          contentType: DioMediaType.parse(item.attachmentContentType),
        ),
      }),
    );
    return ImMessage.fromJson(response.data ?? <String, Object?>{});
  }

  Future<ImMessage> _postContactCardMessage(ImOutboxItem item) async {
    final dio = await _client.forIm();
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
  }) async {
    final session = await _session();
    final syncDeviceId = session.syncDeviceId;
    final cursor = await _store.lastEventSequence(session.userId, syncDeviceId);
    final dio = await _client.forIm();
    final acked = await _store.lastAckedEventSequence(
      session.userId,
      syncDeviceId,
    );
    if (cursor > acked) {
      await _ackEvents(dio, cursor, cancelToken: cancelToken);
      await _store.markEventsAcked(session.userId, syncDeviceId, cursor);
    }
    final response = await dio.get<Map<String, Object?>>(
      '/api/im/sync/events',
      queryParameters: {
        'afterSequence': cursor,
        'waitSeconds': waitSeconds,
        'take': 500,
      },
      cancelToken: cancelToken,
    );
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
    if (events.isEmpty) {
      return ImSyncPullResult.empty(cursor);
    }

    final bootstrap = await _fetchBootstrap();
    await _store.applySyncBatch(
      accountId: session.userId,
      deviceId: syncDeviceId,
      events: events,
      bootstrap: bootstrap,
    );
    final latestSequence = events.fold<int>(
      cursor,
      (latest, event) => event.sequence > latest ? event.sequence : latest,
    );
    await _ackEvents(dio, latestSequence, cancelToken: cancelToken);
    await _store.markEventsAcked(session.userId, syncDeviceId, latestSequence);
    return ImSyncPullResult.fromEvents(
      latestSequence: latestSequence,
      events: events.where((event) => event.sequence > cursor).toList(),
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
    final dio = await _client.forIm();
    await dio.post<void>(
      '/api/im/conversations/$conversationId/read',
      data: {'sequence': sequence},
      options: Options(contentType: Headers.jsonContentType),
    );
    await _store.markConversationRead(session.userId, conversationId, sequence);
    try {
      final mentions = await unreadMentions(conversationId: conversationId);
      final visibleIds = mentions
          .where((item) => (item['sequence'] as int) <= sequence)
          .map((item) => item['messageId'] as String)
          .where((id) => id.isNotEmpty)
          .toList();
      if (visibleIds.isNotEmpty) await markMentionsRead(visibleIds);
    } on DioException {
      // Conversation read state is authoritative even when the mention
      // projection is temporarily unavailable; foreground sync retries it.
    }
  }

  Future<List<Map<String, Object>>> unreadMentions({
    String? conversationId,
    int afterSequence = 0,
    int take = 100,
  }) async {
    final dio = await _client.forIm();
    final response = await dio.get<List<Object?>>(
      '/api/im/mentions/unread',
      queryParameters: {
        'afterSequence': afterSequence < 0 ? 0 : afterSequence,
        'take': take.clamp(1, 500),
        if (conversationId?.isNotEmpty == true)
          'conversationId': conversationId,
      },
    );
    return (response.data ?? const <Object?>[]).whereType<Map>().map((item) {
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

  Future<int> markMentionsRead(List<String> messageIds) async {
    if (messageIds.isEmpty || messageIds.length > 500) {
      throw ArgumentError('一次需处理 1 到 500 条 @ 消息');
    }
    final dio = await _client.forIm();
    final response = await dio.post<Map<String, Object?>>(
      '/api/im/mentions/read',
      data: {'messageIds': messageIds},
      options: Options(contentType: Headers.jsonContentType),
    );
    final affected = response.data?['affected'];
    return affected is num ? affected.toInt() : 0;
  }

  Future<void> registerPushDevice({
    required String platform,
    required String provider,
    required String token,
    String privacyMode = 'summary',
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
    final dio = await _client.forIm();
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
  }

  Future<void> unregisterPushDevice() async {
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
    final dio = await _client.forIm();
    await dio.delete<void>('/api/im/push/devices/current');
  }

  static String _compactError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null) return '消息服务请求失败（HTTP $status）';
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

  static bool _isTransientOutboxFailure(Object error) {
    if (error is! DioException) return true;
    final status = error.response?.statusCode;
    if (status != null) return status >= 500 || status == 408 || status == 429;
    return true;
  }
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
