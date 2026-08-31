import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../domain/app_catalog.dart';

class AllAppsPage extends ConsumerStatefulWidget {
  const AllAppsPage({super.key});

  @override
  ConsumerState<AllAppsPage> createState() => _AllAppsPageState();
}

class _AllAppsPageState extends ConsumerState<AllAppsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(oaApplicationCatalogProvider).value;
    final applications = MobileAppCatalog.fromCatalog(
      catalog?.items ?? const [],
    );
    final entries = applications.where((item) {
      return _query.isEmpty || item.title.contains(_query);
    }).toList();
    final categories = <String, List<MobileAppEntry>>{};
    for (final item in entries) {
      categories.putIfAbsent(item.category, () => []).add(item);
    }
    final categoryEntries = categories.entries.toList(growable: false);
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('全部应用')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
        children: [
          MobileSearchField(
            hintText: '搜索应用',
            onChanged: (value) => setState(() => _query = value.trim()),
          ),
          const SizedBox(height: 6),
          if (categoryEntries.isEmpty)
            const MobileSurface(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(
                  '暂无匹配应用',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            )
          else
            MobileSurface(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < categoryEntries.length;
                    index++
                  ) ...[
                    _AppCategorySection(
                      key: ValueKey(
                        'app-category-${categoryEntries[index].key}',
                      ),
                      title: categoryEntries[index].key,
                      items: categoryEntries[index].value,
                    ),
                    if (index != categoryEntries.length - 1)
                      const SizedBox(height: 2),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AppCategorySection extends StatelessWidget {
  const _AppCategorySection({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<MobileAppEntry> items;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _CategoryTitle(title: title),
      _AppGrid(items: items),
    ],
  );
}

class _CategoryTitle extends StatelessWidget {
  const _CategoryTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _AppGrid extends StatelessWidget {
  const _AppGrid({required this.items});

  final List<MobileAppEntry> items;

  @override
  Widget build(BuildContext context) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 5,
      mainAxisExtent: 56,
    ),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final item = items[index];
      return Opacity(
        opacity: item.route == null ? .42 : 1,
        child: InkResponse(
          onTap: item.route == null ? null : () => context.push(item.route!),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                key: Key(
                  'all-app-icon-${item.applicationKey.isEmpty ? item.title : item.applicationKey}',
                ),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: item.color,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: MobileAppIcon(
                  iconKey: item.iconKey,
                  iconDataUrl: item.iconDataUrl,
                  fallback: item.icon,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: AppColors.text),
              ),
            ],
          ),
        ),
      );
    },
  );
}
