import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_filex/open_filex.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_detail_page.dart';

void main() {
  testWidgets('unknown attachment stays downloadable on desktop only', (
    tester,
  ) async {
    final f = await _Fixture.create(tester);
    addTearDown(f.close);
    f
      ..withAttachment = true
      ..imageAttachment = false
      ..attachmentFileName = 'AI-UAT-proof.bin';
    f.current = f.request();
    await f.pump(tester);

    expect(find.textContaining('· 请在桌面端查看'), findsOneWidget);
    expect(find.byIcon(Icons.desktop_windows_outlined), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    final row = find
        .ancestor(
          of: find.text('AI-UAT-proof.bin'),
          matching: find.byType(InkWell),
        )
        .first;
    tester.widget<InkWell>(row).onTap!();
    await tester.pump();

    expect(find.text('暂不支持在移动端打开此格式，请在桌面端查看'), findsOneWidget);
    expect(f.openedPaths, isEmpty);
    expect(f.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final change in ['same', 'account', 'disposed', 'open-error']) {
    testWidgets('external attachment handoff guards $change', (tester) async {
      final f = await _Fixture.create(tester);
      addTearDown(f.close);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('oa-file-guard-'),
      ))!;
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      f.withAttachment = true;
      f.imageAttachment = false;
      f.current = f.request();
      f.tempGate = Completer<Directory>();
      f.openResult = change == 'open-error'
          ? ResultType.error
          : ResultType.done;
      await f.pump(tester);
      final row = find
          .ancestor(
            of: find.text('AI-UAT-proof.txt'),
            matching: find.byType(InkWell),
          )
          .first;
      tester.widget<InkWell>(row).onTap!();
      for (var i = 0; i < 100 && !f.tempRequested; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(f.tempRequested, isTrue);
      if (change == 'account') await f.changeSession('other');
      if (change == 'disposed') await tester.pumpWidget(const SizedBox());
      f.tempGate!.complete(directory);
      await f.finishDialog(tester);
      final allowed = change == 'same' || change == 'open-error';
      if (allowed) {
        for (var i = 0; i < 100 && f.openedPaths.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
        }
        if (change == 'open-error') {
          await tester.pump();
          expect(find.text('附件打开失败，请稍后重试'), findsOneWidget);
          expect(find.text('fixture'), findsNothing);
        }
      }
      await tester.pump(const Duration(seconds: 4));
      expect(f.openedPaths.length, allowed ? 1 : 0);
      if (allowed) {
        expect(f.openedPaths.single, contains('oa-attachments'));
        expect(f.openedPaths.single.endsWith('AI-UAT-proof.txt'), isTrue);
        if (change == 'open-error') {
          // File deletion runs in the async finally block after the external
          // opener returns. Advancing the widget clock does not wait for real
          // filesystem I/O, so observe the bounded cleanup instead of racing it.
          for (var i = 0; i < 100; i++) {
            final exists = await tester.runAsync(
              () => File(f.openedPaths.single).exists(),
            );
            if (exists != true) break;
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
          }
        }
        expect(
          await tester.runAsync(() => File(f.openedPaths.single).exists()),
          change == 'same',
        );
        expect(f.openedWithBytes, [true]);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('external attachment streams to disk and shows progress', (
    tester,
  ) async {
    final f = await _Fixture.create(tester);
    addTearDown(f.close);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('oa-file-progress-'),
    ))!;
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    f
      ..withAttachment = true
      ..imageAttachment = false
      ..chunkedAttachment = true
      ..expectedOpenedLength = _streamChunk.length * 2
      ..attachmentGate = Completer<void>()
      ..tempGate = (Completer<Directory>()..complete(directory));
    f.current = f.request();
    await f.pump(tester);

    final row = find
        .ancestor(
          of: find.text('AI-UAT-proof.txt'),
          matching: find.byType(InkWell),
        )
        .first;
    tester.widget<InkWell>(row).onTap!();
    await tester.pump();
    expect(
      find.byKey(const Key('oa-attachment-download-progress-proof')),
      findsOneWidget,
    );
    expect(find.textContaining('下载'), findsOneWidget);
    for (var i = 0; i < 150 && !f.attachmentFirstChunk.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    expect(f.attachmentFirstChunk.isCompleted, isTrue);
    await tester.pump();

    expect(
      find.byKey(const Key('oa-attachment-download-progress-proof')),
      findsOneWidget,
    );

    f.attachmentGate!.complete();
    for (var i = 0; i < 150 && f.openedPaths.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(seconds: 4));
    expect(f.openedWithBytes, [true]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('completed external attachment is reused without redownload', (
    tester,
  ) async {
    final f = await _Fixture.create(tester);
    addTearDown(f.close);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('oa-file-cache-'),
    ))!;
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    f
      ..withAttachment = true
      ..imageAttachment = false
      ..tempGate = (Completer<Directory>()..complete(directory));
    f.current = f.request();
    await f.pump(tester);

    final row = find
        .ancestor(
          of: find.text('AI-UAT-proof.txt'),
          matching: find.byType(InkWell),
        )
        .first;
    tester.widget<InkWell>(row).onTap!();
    // Full-suite parallelism can briefly starve the filesystem isolate on
    // Windows. Keep this an eventual cache assertion instead of a 2 s timing
    // assertion; dedicated latency coverage lives in the manager tests.
    for (var i = 0; i < 300 && f.openedPaths.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    tester.widget<InkWell>(row).onTap!();
    for (var i = 0; i < 300 && f.openedPaths.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(seconds: 4));

    expect(f.openedPaths.length, 2);
    expect(f.openedPaths.toSet().length, 1);
    expect(
      f.writes.where((path) => path == '/api/oa/attachments/proof'),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('same-size corrupt external attachment is downloaded again', (
    tester,
  ) async {
    final f = await _Fixture.create(tester);
    addTearDown(f.close);
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('oa-file-integrity-'),
    ))!;
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    f
      ..withAttachment = true
      ..imageAttachment = false
      ..tempGate = (Completer<Directory>()..complete(directory));
    f.current = f.request();
    await f.pump(tester);

    final row = find
        .ancestor(
          of: find.text('AI-UAT-proof.txt'),
          matching: find.byType(InkWell),
        )
        .first;
    tester.widget<InkWell>(row).onTap!();
    for (var i = 0; i < 100 && f.openedPaths.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.runAsync(
      () => File(
        f.openedPaths.single,
      ).writeAsBytes(List<int>.filled(f.expectedOpenedLength, 0), flush: true),
    );
    tester.widget<InkWell>(row).onTap!();
    for (var i = 0; i < 100 && f.openedPaths.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump(const Duration(seconds: 4));

    expect(f.openedPaths, hasLength(2));
    expect(
      f.writes.where((path) => path == '/api/oa/attachments/proof'),
      hasLength(2),
    );
    expect(f.openedWithBytes, [true, true]);
    expect(tester.takeException(), isNull);
  });
  for (final change in [
    'double',
    'account',
    'logout',
    'relogin',
    'covered',
    'disposed',
    'open-then-account',
  ]) {
    testWidgets('attachment open guards $change', (tester) async {
      final f = await _Fixture.create(tester);
      addTearDown(f.close);
      f.withAttachment = true;
      f.current = f.request();
      f.attachmentGate = Completer<void>();
      await f.pump(tester);
      final row = find
          .ancestor(
            of: find.text('AI-UAT-proof.png'),
            matching: find.byType(InkWell),
          )
          .first;
      final tap = tester.widget<InkWell>(row).onTap!;
      expect(f.container.read(authControllerProvider).value?.userId, 'self');
      tap();
      if (change == 'double') tap();
      // Session persistence uses the widget zone; alternate frame pumping with
      // real socket progress instead of blocking that zone on the server gate.
      for (var i = 0; i < 100 && !f.attachmentStarted.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(f.attachmentStarted.isCompleted, isTrue);
      if (change == 'account' || change == 'relogin') {
        await f.changeSession(change == 'account' ? 'other' : 'self');
      } else if (change == 'logout') {
        await f.sessions.clearSession();
        (f.container.read(authControllerProvider.notifier) as _Auth).replace(
          null,
        );
      } else if (change == 'covered') {
        Navigator.of(tester.element(row)).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('另一页面')),
          ),
        );
        await tester.pumpAndSettle();
      } else if (change == 'disposed') {
        await tester.pumpWidget(const SizedBox());
      }
      f.attachmentGate!.complete();
      await f.finishDialog(tester);
      await tester.pumpAndSettle();
      expect(f.writes, ['/api/oa/attachments/proof/preview']);
      expect(
        find.byType(InteractiveViewer),
        change == 'double' || change == 'open-then-account'
            ? findsOneWidget
            : findsNothing,
      );
      if (change == 'open-then-account') {
        await f.changeSession('other');
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsNothing);
        expect(find.text('登录状态已变化，请重新打开附件'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final action in [
    'approve',
    'reject',
    'withdraw',
    'transfer',
    'add_sign',
    'return',
    'remind',
  ]) {
    for (final change in ['account', 'relogin', 'logout', 'offline', 'task']) {
      testWidgets('$action dialog rejects $change before sending', (
        tester,
      ) async {
        final f = await _Fixture.create(tester);
        addTearDown(f.close);
        await f.pump(tester);
        await f.openReason(tester, action);
        if (change == 'account' || change == 'relogin') {
          await f.changeSession(change == 'account' ? 'other' : 'self');
        } else if (change == 'logout') {
          await f.sessions.clearSession();
          (f.container.read(authControllerProvider.notifier) as _Auth).replace(
            null,
          );
        } else if (change == 'offline') {
          f.container
              .read(oaSyncAvailabilityControllerProvider.notifier)
              .markUnavailable();
        } else {
          f.current = f.request(ended: true);
          f.container.invalidate(oaApprovalRequestProvider('request'));
        }
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('mobile-text-input-field')),
          'AI-UAT-guard',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('mobile-text-input-submit')));
        await f.finishDialog(tester);
        await tester.pumpAndSettle();
        expect(
          f.writes,
          isEmpty,
          reason: 'A stale dialog must not use the next session or task.',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final action in ['approve', 'more']) {
    testWidgets('$action rapid double tap opens only one interaction', (
      tester,
    ) async {
      final f = await _Fixture.create(tester);
      addTearDown(f.close);
      await f.pump(tester);
      final ButtonStyleButton button = action == 'approve'
          ? tester.widget<FilledButton>(find.widgetWithText(FilledButton, '同意'))
          : tester.widget<OutlinedButton>(
              find.byKey(const Key('approval-more-actions')),
            );
      button.onPressed!();
      button.onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      final context = tester.element(find.byType(BottomSheet));
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      expect(f.writes, isEmpty);
      final ButtonStyleButton restored = action == 'approve'
          ? tester.widget<FilledButton>(find.widgetWithText(FilledButton, '同意'))
          : tester.widget<OutlinedButton>(
              find.byKey(const Key('approval-more-actions')),
            );
      expect(restored.onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  for (final stage in ['menu', 'member', 'mode']) {
    testWidgets('session change at $stage stops the next approval drawer', (
      tester,
    ) async {
      final f = await _Fixture.create(tester);
      addTearDown(f.close);
      await f.pump(tester);
      await tester.tap(find.byKey(const Key('approval-more-actions')));
      await tester.pumpAndSettle();
      if (stage != 'menu') {
        await tester.tap(find.text('加签'));
        await tester.pumpAndSettle();
        if (stage == 'mode') {
          await tester.tap(
            find.text(PreviewData.imBootstrap.contacts.first.displayName),
          );
          await tester.pumpAndSettle();
        }
      }
      await f.changeSession('other');
      await tester.pump();
      await tester.tap(
        find.text(
          stage == 'menu'
              ? '加签'
              : stage == 'member'
              ? PreviewData.imBootstrap.contacts.first.displayName
              : '前加签',
        ),
      );
      await f.finishDialog(tester);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(f.writes, isEmpty);
      expect(find.text('登录状态已更新，请重新打开审批'), findsOneWidget);
    });
  }

  testWidgets('changed pending task version requires another confirmation', (
    tester,
  ) async {
    final f = await _Fixture.create(tester);
    addTearDown(f.close);
    await f.pump(tester);
    await f.openReason(tester, 'approve');
    f.current = f.request(version: 2);
    f.container.invalidate(oaApprovalRequestProvider('request'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mobile-text-input-submit')));
    await f.finishDialog(tester);
    await tester.pumpAndSettle();
    expect(f.writes, isEmpty);
    expect(find.text('审批状态已更新，请重新确认'), findsOneWidget);
  });

  testWidgets('same current dialog still dispatches one unchanged command', (
    tester,
  ) async {
    final f = await _Fixture.create(tester);
    addTearDown(f.close);
    await f.pump(tester);
    await f.openReason(tester, 'withdraw');
    await tester.enterText(
      find.byKey(const Key('mobile-text-input-field')),
      'AI-UAT-valid',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('mobile-text-input-submit')));
    await f.finishDialog(tester);
    expect(find.byKey(const Key('mobile-text-input-sheet')), findsNothing);
    await tester.runAsync(() async {
      await f.received.future.timeout(const Duration(seconds: 3));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(f.writes, ['/api/oa/approval-requests/request/withdraw']);
    expect(f.correctIdentity, [true]);
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  _Fixture(this.server);
  final HttpServer server;
  final sessions = SecureSessionStore();
  late final ProviderContainer container;
  late OaApprovalRequest current = request();
  final writes = <String>[];
  final correctIdentity = <bool>[];
  final received = Completer<void>();
  bool withAttachment = false;
  bool imageAttachment = true;
  String? attachmentFileName;
  Completer<Directory>? tempGate;
  bool tempRequested = false;
  final openedPaths = <String>[];
  final openedWithBytes = <bool>[];
  bool chunkedAttachment = false;
  int expectedOpenedLength = _pixel.length;
  ResultType openResult = ResultType.done;
  Completer<void>? attachmentGate;
  final attachmentStarted = Completer<void>();
  final attachmentFirstChunk = Completer<void>();

  MobileSession session(String account, String token) => MobileSession(
    accessToken: token,
    deviceId: 'fixture-device',
    userId: account,
    displayName: account,
    username: account,
    policySignatureKey: '',
    imApiUrl: '',
    oaApiUrl: 'http://127.0.0.1:${server.port}',
  );

  OaApprovalRequest request({bool ended = false, int version = 1}) =>
      OaApprovalRequest.fromJson({
        'id': 'request',
        'requesterId': 'self',
        'requesterName': 'Self',
        'title': 'AI-UAT-dialog-guard',
        'status': ended ? 'withdrawn' : 'submitted',
        if (withAttachment)
          'attachments': [
            {
              'id': 'proof',
              'fileName':
                  attachmentFileName ??
                  (imageAttachment ? 'AI-UAT-proof.png' : 'AI-UAT-proof.txt'),
              'contentType': imageAttachment ? 'image/png' : 'text/plain',
              'isPreviewableImage': imageAttachment,
              'size': expectedOpenedLength,
              'sha256': sha256
                  .convert(
                    chunkedAttachment
                        ? [..._streamChunk, ..._streamChunk]
                        : _pixel,
                  )
                  .toString(),
            },
          ],
        'allowedActions': ended
            ? <String>[]
            : [
                'approve',
                'reject',
                'withdraw',
                'transfer',
                'add_sign',
                'return',
                'remind',
              ],
        'tasks': [
          {
            'id': 'task',
            'assigneeId': 'self',
            'assigneeName': 'Self',
            'nodeName': '部门负责人审批',
            'status': ended ? 'canceled' : 'pending',
            'version': ended ? 2 : version,
            'canOperate': !ended,
          },
        ],
      });

  static Future<_Fixture> create(WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    HttpOverrides.global = _RealHttp();
    final server = (await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    ))!;
    final f = _Fixture(server);
    await f.sessions.saveSession(f.session('self', 'fixture-old'));
    await tester.runAsync(() async {
      server.listen((request) async {
        f.writes.add(request.uri.path);
        f.correctIdentity.add(
          request.headers.value('authorization') == 'Bearer fixture-old',
        );
        await request.drain<void>();
        if (request.uri.path == '/api/oa/attachments/proof/preview' ||
            request.uri.path == '/api/oa/attachments/proof') {
          if (!f.attachmentStarted.isCompleted) f.attachmentStarted.complete();
          try {
            request.response.headers.contentType = ContentType('image', 'png');
            if (f.chunkedAttachment) {
              request.response.contentLength = f.expectedOpenedLength;
              request.response.add(_streamChunk);
              await request.response.flush();
              if (!f.attachmentFirstChunk.isCompleted) {
                f.attachmentFirstChunk.complete();
              }
              await f.attachmentGate?.future;
              request.response.add(_streamChunk);
            } else {
              await f.attachmentGate?.future;
              request.response.add(_pixel);
            }
            await request.response.close();
          } catch (_) {
            /* The detail can cancel the held download. */
          }
          return;
        }
        // No database writes: this test asserts dispatch, not a synthetic approval success.
        request.response.statusCode = 500;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"message":"AI-UAT-fixture-response"}');
        await request.response.close();
        if (!f.received.isCompleted) f.received.complete();
      });
    });
    f.container = ProviderContainer(
      overrides: [
        secureSessionStoreProvider.overrideWithValue(f.sessions),
        authControllerProvider.overrideWith(
          () => _Auth(f.session('self', 'fixture-old')),
        ),
        approvalDetailAutoRefreshProvider.overrideWithValue(false),
        approvalAttachmentTempDirectoryProvider.overrideWithValue(() {
          f.tempRequested = true;
          return f.tempGate!.future;
        }),
        approvalAttachmentExternalOpenerProvider.overrideWithValue((
          file,
        ) async {
          f.openedPaths.add(file);
          f.openedWithBytes.add(
            File(file).lengthSync() == f.expectedOpenedLength,
          );
          return OpenResult(type: f.openResult, message: 'fixture');
        }),
        oaAttachmentThumbnailProvider('proof')
            .overrideWith((_) async => _pixel),
        oaRepositoryProvider.overrideWithValue(
          OaRepository(
            CollaborationClient(f.sessions),
            f.sessions,
            OaLocalStore(factory: databaseFactoryFfi),
          ),
        ),
        oaApprovalRequestProvider('request')
            .overrideWith((ref) async => f.current),
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
      ],
    );
    await f.container.read(authControllerProvider.future);
    f.container
        .read(oaSyncAvailabilityControllerProvider.notifier)
        .markAvailable();
    return f;
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ApprovalDetailPage(approvalId: 'request'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> changeSession(String account) async {
    final next = session(account, 'fixture-new');
    await sessions.saveSession(next);
    (container.read(authControllerProvider.notifier) as _Auth).replace(next);
  }

  Future<void> finishDialog(WidgetTester tester) async {
    // Advance route disposal without fast-forwarding a real socket's timeout.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
  }

  Future<void> openReason(WidgetTester tester, String action) async {
    if (action == 'approve' || action == 'reject') {
      await tester.tap(
        find.widgetWithText(
          action == 'approve' ? FilledButton : OutlinedButton,
          action == 'approve' ? '同意' : '驳回',
        ),
      );
    } else {
      await tester.tap(find.byKey(const Key('approval-more-actions')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          {
            'withdraw': '撤回',
            'transfer': '转交',
            'add_sign': '加签',
            'return': '退回',
            'remind': '催办',
          }[action]!,
        ),
      );
    }
    await tester.pumpAndSettle();
    if (action == 'transfer' || action == 'add_sign') {
      await tester.tap(
        find.text(PreviewData.imBootstrap.contacts.first.displayName),
      );
      await tester.pumpAndSettle();
      if (action == 'add_sign') {
        await tester.tap(find.text('前加签'));
        await tester.pumpAndSettle();
      }
    }
    expect(find.byKey(const Key('mobile-text-input-sheet')), findsOneWidget);
  }

  Future<void> close() async {
    if (attachmentGate != null && !attachmentGate!.isCompleted) {
      attachmentGate!.complete();
    }
    container.dispose();
    await server.close(force: true);
    HttpOverrides.global = null;
  }
}

class _Auth extends AuthController {
  _Auth(this.initial);
  final MobileSession initial;
  @override
  Future<MobileSession?> build() async => initial;
  void replace(MobileSession? next) => state = AsyncData(next);
}

class _RealHttp extends HttpOverrides {}

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
);
final _streamChunk = List<int>.filled(64 * 1024, 0x41);
