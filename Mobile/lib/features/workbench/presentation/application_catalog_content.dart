import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/mobile_read_retry.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';
import '../domain/app_catalog.dart';

/// Shared state handling for home shortcuts and the searchable app directory.
/// Keeps only data accepted for this account, never a previous account's
/// AsyncValue retained by Riverpod while a dependency is being reloaded.
class ApplicationCatalogContent extends ConsumerStatefulWidget {
  const ApplicationCatalogContent({
    super.key,
    this.query = '',
    required this.builder,
  });

  final String query;
  final Widget Function(List<MobileAppEntry>) builder;

  @override
  ConsumerState<ApplicationCatalogContent> createState() =>
      _ApplicationCatalogContentState();
}

class _ApplicationCatalogContentState
    extends ConsumerState<ApplicationCatalogContent> {
  String? _account;
  OaApplicationCatalog? _catalog;
  Object? _retryError;
  bool _retrying = false;
  int _request = 0;
  int _recovery = 0;
  int _consumedRecovery = 0;

  Future<void> _retry() async {
    if (_retrying) return;
    final request = ++_request;
    final account = ref.read(collaborationAccountScopeProvider);
    final refresh = ref.read(oaApplicationCatalogRefresherProvider);
    setState(() {
      _retrying = true;
      _retryError = null;
    });
    try {
      // Force a real network read; invalidating cache-first alone would simply
      // re-display SQLite and incorrectly look like a successful retry.
      await refresh();
      if (!mounted ||
          request != _request ||
          ref.read(collaborationAccountScopeProvider) != account) {
        return;
      }
      ref.invalidate(oaApplicationCatalogProvider);
    } catch (error) {
      if (!mounted ||
          request != _request ||
          ref.read(collaborationAccountScopeProvider) != account) {
        return;
      }
      _retryError = error;
    } finally {
      if (mounted &&
          request == _request &&
          ref.read(collaborationAccountScopeProvider) == account) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(collaborationAccountScopeProvider);
    if (_account != account) {
      _account = account;
      _catalog = null;
      _retryError = null;
      _retrying = false;
      _request++;
      _recovery = _consumedRecovery = 0;
    }
    final value = ref.watch(oaApplicationCatalogProvider);
    final availability = ref.watch(oaSyncAvailabilityProvider);
    ref.listen(oaSyncAvailabilityProvider, (previous, next) {
      if (previous != null &&
          previous != OaSyncAvailability.available &&
          next == OaSyncAvailability.available) {
        setState(() => _recovery++);
      }
    });
    if (!value.isLoading && value.asData != null) {
      if (!identical(_catalog, value.asData!.value)) _retryError = null;
      _catalog = value.asData!.value;
    }
    final error = _retryError ?? value.error;
    if (!_retrying &&
        !value.isLoading &&
        error != null &&
        _recovery > _consumedRecovery &&
        availability == OaSyncAvailability.available &&
        mobileReadRetry(0, error) != null) {
      _consumedRecovery = _recovery;
      final request = _request;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            request == _request &&
            ref.read(oaSyncAvailabilityProvider) ==
                OaSyncAvailability.available) {
          _retry();
        }
      });
    }

    if (_catalog == null) {
      if (_retrying || value.isLoading) {
        return const ModuleLoadingState(label: '应用加载中');
      }
      return _CatalogNotice(
        title: '应用加载失败',
        detail: error == null ? null : mobileErrorText(error),
        onRetry: _retry,
      );
    }

    final applications = MobileAppCatalog.fromCatalog(_catalog!.items);
    final query = widget.query.trim();
    final entries = applications
        .where((item) => query.isEmpty || item.title.contains(query))
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_retrying)
          const _CatalogNotice(title: '正在更新应用', pending: true)
        else if (availability == OaSyncAvailability.unavailable)
          _CatalogNotice(title: '连接暂不可用，显示缓存应用', onRetry: _retry)
        else if (error != null)
          _CatalogNotice(title: '应用更新失败，显示缓存应用', onRetry: _retry),
        if (applications.isEmpty)
          const _CatalogNotice(title: '暂无可用应用')
        else if (entries.isEmpty)
          const _CatalogNotice(title: '暂无匹配应用')
        else
          widget.builder(entries),
      ],
    );
  }
}

class _CatalogNotice extends StatelessWidget {
  const _CatalogNotice({
    required this.title,
    this.detail,
    this.onRetry,
    this.pending = false,
  });

  final String title;
  final String? detail;
  final VoidCallback? onRetry;
  final bool pending;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('application-catalog-status'),
    liveRegion: true,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            if (pending) ...[
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      detail!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('重试', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    ),
  );
}
