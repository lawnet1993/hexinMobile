import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/workbench/data/managed_sites_repository.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/workbench_page.dart';

void main() {
  const sites = [
    ManagedAccessSite(
      id: 'site-1',
      name: '数据中台',
      category: '数据',
      departmentName: '集团总部',
      primaryDomain: 'data.example.test',
      loginUrl: 'https://data.example.test',
      backupDomains: '',
      backupLoginUrls: [],
    ),
    ManagedAccessSite(
      id: 'site-2',
      name: '华南运营台',
      category: '运营',
      departmentName: '深圳运营部',
      primaryDomain: 'ops.example.test',
      loginUrl: 'https://ops.example.test',
      backupDomains: '',
      backupLoginUrls: [],
    ),
  ];

  testWidgets('工作台分开显示全部站点数量和紧凑刷新操作', (tester) async {
    final router = GoRouter(
      initialLocation: '/workbench',
      routes: [
        GoRoute(path: '/workbench', builder: (_, _) => const WorkbenchPage()),
        GoRoute(path: '/sites', builder: (_, _) => const ManagedSitesPage()),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          oaBootstrapProvider.overrideWith(
            (ref) async => PreviewData.oaBootstrap,
          ),
          oaApplicationCatalogProvider.overrideWith(
            (ref) async => PreviewData.oaCatalog,
          ),
          managedSitesProvider.overrideWith((ref) async => sites),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部站点 2'), findsOneWidget);
    expect(find.byTooltip('刷新授权站点'), findsOneWidget);
    expect(
      tester.getSize(find.byTooltip('刷新授权站点')).height,
      lessThanOrEqualTo(40),
    );

    await tester.tap(find.text('全部站点 2'));
    await tester.pumpAndSettle();

    expect(find.text('全部站点'), findsOneWidget);
    expect(find.text('数据中台'), findsOneWidget);
    expect(find.text('华南运营台'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '深圳');
    await tester.pump();
    expect(find.text('华南运营台'), findsOneWidget);
    expect(find.text('数据中台'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
