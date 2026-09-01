import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

class MessageFavoritesPage extends ConsumerStatefulWidget {
  const MessageFavoritesPage({super.key});

  @override
  ConsumerState<MessageFavoritesPage> createState() =>
      _MessageFavoritesPageState();
}

class _MessageFavoritesPageState extends ConsumerState<MessageFavoritesPage> {
  final _additionalItems = <ImFavoriteMessage>[];
  final _scrollController = ScrollController();
  var _nextPage = 2;
  var _loadingMore = false;
  var _hasMore = false;
  var _autoLoadScheduled = false;
  var _autoLoadRetryBlocked = false;
  var _pagingExhausted = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _resetPages() {
    if (!mounted) return;
    setState(() {
      _additionalItems.clear();
      _nextPage = 2;
      _loadingMore = false;
      _hasMore = false;
      _autoLoadRetryBlocked = false;
      _pagingExhausted = false;
    });
    ref.invalidate(imFavoritesPageProvider);
    ref.invalidate(imFavoritesProvider);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _autoLoadRetryBlocked) return;
    final pageNumber = _nextPage;
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(imFavoritesPageProvider(pageNumber).future);
      if (!mounted) return;
      final knownIds = _additionalItems.map((item) => item.messageId).toSet();
      setState(() {
        _additionalItems.addAll(
          page.items.where((item) => knownIds.add(item.messageId)),
        );
        _nextPage = page.page + 1;
        _autoLoadRetryBlocked = false;
        _pagingExhausted = page.items.isEmpty;
      });
    } catch (error) {
      _autoLoadRetryBlocked = true;
      ref.invalidate(imFavoritesPageProvider(pageNumber));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载更多失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (_autoLoadRetryBlocked ||
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter > 240) {
      return;
    }
    unawaited(_loadMore());
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _autoLoadRetryBlocked = false;
    }
    return false;
  }

  void _scheduleAutoLoad() {
    if (!_hasMore ||
        _loadingMore ||
        _autoLoadScheduled ||
        _autoLoadRetryBlocked) {
      return;
    }
    _autoLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLoadScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.position.extentAfter <= 240) {
        unawaited(_loadMore());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(imFavoritesPageProvider(1));
    final bootstrap = ref.watch(imBootstrapProvider).value;
    final memberNames = {
      for (final member in [
        ...?bootstrap?.contacts,
        bootstrap?.currentMember,
      ].nonNulls)
        member.id: member.displayName,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: favorites.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: '收藏加载失败',
          description: error.toString(),
          onRetry: _resetPages,
        ),
        data: (page) {
          final knownIds = <String>{};
          final items = <ImFavoriteMessage>[
            ...page.items.where((item) => knownIds.add(item.messageId)),
            ..._additionalItems.where((item) => knownIds.add(item.messageId)),
          ];
          final hasMore = !_pagingExhausted && items.length < page.total;
          _hasMore = hasMore;
          _scheduleAutoLoad();
          return items.isEmpty
              ? const EmptyState(
                  icon: Icons.bookmark_border_rounded,
                  title: '暂无收藏',
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() {
                      _additionalItems.clear();
                      _nextPage = 2;
                      _hasMore = false;
                      _autoLoadRetryBlocked = false;
                      _pagingExhausted = false;
                    });
                    final _ = await ref.refresh(
                      imFavoritesPageProvider(1).future,
                    );
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleScrollNotification,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: items.length + (hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == items.length) {
                          return SizedBox(
                            key: const Key('favorite-page-footer'),
                            height: 40,
                            child: Center(
                              child: _loadingMore
                                  ? const SizedBox.square(
                                      dimension: 17,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      '继续上滑 · ${items.length}/${page.total}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFFB0B7C3),
                                      ),
                                    ),
                            ),
                          );
                        }
                        final favorite = items[index];
                        final sender =
                            memberNames[favorite.message.senderId] ?? '聊天消息';
                        final conversationId = favorite.message.conversationId;
                        return ListTile(
                          dense: true,
                          leading: InitialAvatar(name: sender, radius: 19),
                          title: Text(
                            favorite.message.content.isEmpty
                                ? favorite.message.attachmentName.isEmpty
                                      ? '附件消息'
                                      : favorite.message.attachmentName
                                : favorite.message.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              sender,
                              if (favorite.note.isNotEmpty) favorite.note,
                              if (favorite.createdAt != null)
                                DateFormat('MM-dd HH:mm')
                                    .format(favorite.createdAt!.toLocal()),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '打开会话',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 36,
                                  height: 36,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: conversationId.isEmpty
                                    ? null
                                    : () =>
                                          context.push('/chat/$conversationId'),
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                ),
                              ),
                              IconButton(
                                tooltip: '取消收藏',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 36,
                                  height: 36,
                                ),
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.bookmark_remove_outlined,
                                  size: 19,
                                ),
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(imRepositoryProvider)
                                        .deleteFavorite(favorite.messageId);
                                    _resetPages();
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text('取消收藏失败：$error'),
                                            ),
                                          );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                          onTap: conversationId.isEmpty
                              ? null
                              : () => context.push('/chat/$conversationId'),
                        );
                      },
                    ),
                  ),
                );
        },
      ),
    );
  }
}
