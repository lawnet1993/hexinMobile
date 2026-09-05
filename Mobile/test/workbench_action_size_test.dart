import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/workbench_page.dart';

void main() {
  testWidgets('workbench brand header expands for device font metrics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          oaBootstrapProvider.overrideWith(
            (_) async => PreviewData.oaBootstrap,
          ),
          oaApplicationCatalogProvider.overrideWith(
            (_) async => PreviewData.oaCatalog,
          ),
          oaSyncAvailabilityProvider.overrideWithValue(
            OaSyncAvailability.available,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const WorkbenchPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const Key('workbench-brand-header'))).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'workbench action stays compact while the whole row opens request',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = '';
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const WorkbenchPage()),
          GoRoute(
            path: '/approval/:id',
            builder: (_, state) {
              opened = state.pathParameters['id']!;
              return const Scaffold(body: Text('详情测试页'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaBootstrapProvider.overrideWith(
              (_) async => PreviewData.oaBootstrap,
            ),
            oaApplicationCatalogProvider.overrideWith(
              (_) async => PreviewData.oaCatalog,
            ),
            oaSyncAvailabilityProvider.overrideWithValue(
              OaSyncAvailability.available,
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.light,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('workbench-approval-action-1'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      expect(tester.getSize(action), const Size(52, 28));
      expect(find.text('去处理'), findsNothing);
      final semanticsLabel = tester.getSemantics(action).label;
      expect(semanticsLabel, contains('处理'));
      expect(semanticsLabel, isNot(contains('去处理')));
      await tester.tapAt(tester.getCenter(action));
      await tester.pumpAndSettle();
      expect(opened, '1');
      expect(find.text('详情测试页'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
