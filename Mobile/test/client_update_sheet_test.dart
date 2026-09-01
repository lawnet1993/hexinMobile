import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/updates/client_update_repository.dart';
import 'package:hexing_terminal_mobile/core/updates/client_update_sheet.dart';

void main() {
  testWidgets('mandatory update uses a compact non-dismissible bottom sheet', (
    tester,
  ) async {
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
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).enableDrag,
      false,
    );
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
  });

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
