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
    final groups = _groupByCategory(entries);
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
          if (entries.isEmpty)
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
              key: const Key('all-app-catalog-surface'),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: Column(
                children: [
                  for (var index = 0; index < groups.length; index++) ...[
                    _AppCategorySection(group: groups[index]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

List<({String category, List<MobileAppEntry> items})> _groupByCategory(
  List<MobileAppEntry> entries,
) {
  final groups = <String, List<MobileAppEntry>>{};
  for (final entry in entries) {
    final category = entry.category.trim().isEmpty ? '其他' : entry.category;
    groups.putIfAbsent(category, () => <MobileAppEntry>[]).add(entry);
  }
  return [
    for (final group in groups.entries)
      (category: group.key, items: group.value),
  ];
}

class _AppCategorySection extends StatelessWidget {
  const _AppCategorySection({required this.group});

  final ({String category, List<MobileAppEntry> items}) group;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 0),
        child: Text(
          group.category,
          key: Key('all-app-category-${group.category}'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      _AppGrid(items: group.items),
    ],
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
      mainAxisExtent: 58,
      mainAxisSpacing: 0,
      crossAxisSpacing: 2,
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
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.05,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
