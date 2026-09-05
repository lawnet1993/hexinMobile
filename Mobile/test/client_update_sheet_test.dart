import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/updates/client_update_repository.dart';
import 'package:hexing_terminal_mobile/core/updates/client_update_sheet.dart';

void main() {
  for (final size in [const Size(320, 640), const Size(640, 320)]) {
    testWidgets(
      'mandatory dialog handles $size with large text and long notes',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showClientUpdateSheet(
                    context,
                    info: ClientUpdateInfo(
                      hasPublishedVersion: true,
                      updateAvailable: true,
                      isMandatory: true,
                      releaseId: 'layout-fixture',
                      latestVersion: '1.0.91',
                      packageUrl: 'https://example.test/mobile.apk',
                      packageSize: 105706291,
                      releaseNotes: List.filled(
                        30,
                        '更新说明，保持文案可滚动阅读。',
                      ).join('\n'),
                    ),
                    onDownload: () async {},
                  ),
                  child: const Text('打开更新'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开更新'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final download = find.byKey(const Key('client-update-download'));
        await tester.ensureVisible(download);
        await tester.pumpAndSettle();
        expect(download.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'mandatory update uses a compact non-dismissible centered dialog',
    (tester) async {
      const info = ClientUpdateInfo(
        hasPublishedVersion: true,
        updateAvailable: true,
        isMandatory: true,
        releaseId: 'release-mandatory',
        latestVersion: '1.0.81',
        packageUrl: 'https://example.test/mobile.apk',
        packageSize: 105706291,
        releaseNotes: '修复通知分页与会话恢复。',
      );
      var downloadCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showClientUpdateSheet(
                  context,
                  info: info,
                  onDownload: () async => downloadCount += 1,
                ),
                child: const Text('打开更新'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开更新'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('client-update-sheet')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsOneWidget);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor, Colors.white);
      expect(dialog.surfaceTintColor, Colors.transparent);
      expect(dialog.elevation, 0);
      final dialogShape = dialog.shape! as RoundedRectangleBorder;
      expect(dialogShape.borderRadius, BorderRadius.circular(16));
      expect(dialogShape.side, BorderSide.none);
      final barrier = tester.widget<ModalBarrier>(
        find
            .byWidgetPredicate(
              (widget) => widget is ModalBarrier && widget.color != null,
            )
            .last,
      );
      expect(barrier.color, const Color(0x5C000000));
      final notes = tester.widget<ConstrainedBox>(
        find.byKey(const Key('client-update-release-notes')),
      );
      expect(notes.constraints.maxHeight, 132);
      final surface = find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first;
      expect(tester.getSize(surface).width, 360);
      expect(tester.getCenter(surface), const Offset(400, 300));
      expect(find.text('必须更新客户端'), findsOneWidget);
      expect(find.text('强制更新'), findsOneWidget);
      expect(find.text('版本 v1.0.81'), findsOneWidget);
      expect(find.text('大小 100.81 MB'), findsOneWidget);
      expect(find.byKey(const Key('client-update-close')), findsNothing);
      expect(find.byKey(const Key('client-update-later')), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('client-update-download'))).height,
        40,
      );
      expect(downloadCount, 0);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('client-update-sheet')), findsOneWidget);
      expect(downloadCount, 0);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('client-update-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('client-update-download')));
      await tester.pumpAndSettle();
      expect(downloadCount, 1);
      expect(find.byKey(const Key('client-update-dialog')), findsOneWidget);
    },
  );

  testWidgets('optional update can be postponed without a dialog', (
    tester,
  ) async {
    const info = ClientUpdateInfo(
      hasPublishedVersion: true,
      updateAvailable: true,
      isMandatory: false,
      releaseId: 'release-optional',
      latestVersion: '1.0.82',
      packageUrl: 'https://example.test/mobile.apk',
      packageSize: 1024,
      releaseNotes: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showClientUpdateSheet(
                context,
                info: info,
                onDownload: () async {},
              ),
              child: const Text('打开更新'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开更新'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.byKey(const Key('client-update-close')), findsOneWidget);
    expect(find.byKey(const Key('client-update-later')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.byKey(const Key('client-update-later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-update-sheet')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
