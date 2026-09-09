import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/workbench_page.dart';

void main() {
  testWidgets('移动工作台不暴露站点列表，独立页只提示桌面端使用', (tester) async {
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
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('常用站点'), findsNothing);
    expect(find.text('站点访问'), findsNothing);
    expect(find.text('数据中台'), findsNothing);
    expect(find.text('华南运营台'), findsNothing);

    router.go('/sites');
    await tester.pumpAndSettle();

    expect(find.text('站点访问'), findsOneWidget);
    expect(find.text('请在桌面端访问授权站点'), findsOneWidget);
    expect(find.textContaining('移动端不建立站点隧道'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
